package com.nuvio.app.core.network

import java.io.Closeable
import java.io.EOFException
import java.io.IOException
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.nio.channels.SocketChannel
import java.util.concurrent.TimeUnit

internal class UnixIpcConnection(path: String, private val timeoutMs: Long = 5_000) : Closeable {
    private val channel = SocketChannel.open(StandardProtocolFamily.UNIX)
    private val selector = Selector.open()

    init {
        try {
            channel.configureBlocking(false)
            channel.register(selector, SelectionKey.OP_CONNECT)
            channel.connect(UnixDomainSocketAddress.of(path))
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
            while (!channel.finishConnect()) await(SelectionKey.OP_CONNECT, deadline)
        } catch (error: Exception) {
            close()
            throw error
        }
    }

    fun write(bytes: ByteArray) = transfer(ByteBuffer.wrap(bytes), writing = true)
    fun readFully(bytes: ByteArray) = transfer(ByteBuffer.wrap(bytes), writing = false)

    fun readLine(): String {
        val output = java.io.ByteArrayOutputStream()
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        val one = ByteBuffer.allocate(1)
        while (output.size() < 65536) {
            one.clear()
            transfer(one, false, deadline)
            val value = one.array()[0].toInt() and 255
            if (value == 10) return output.toString(Charsets.UTF_8)
            output.write(value)
        }
        throw IOException("IPC line exceeds 64 KiB")
    }

    private fun transfer(buffer: ByteBuffer, writing: Boolean,
        deadline: Long = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)) {
        while (buffer.hasRemaining()) {
            val count = if (writing) channel.write(buffer) else channel.read(buffer)
            if (count < 0) throw EOFException("Local peer closed the IPC socket")
            if (count == 0) await(if (writing) SelectionKey.OP_WRITE else SelectionKey.OP_READ, deadline)
        }
    }

    private fun await(operation: Int, deadline: Long) {
        val remaining = deadline - System.nanoTime()
        if (remaining <= 0) throw IOException("Local IPC timed out")
        channel.keyFor(selector).interestOps(operation)
        selector.select(TimeUnit.NANOSECONDS.toMillis(remaining).coerceAtLeast(1))
        selector.selectedKeys().clear()
    }

    override fun close() {
        try { channel.close() } finally { selector.close() }
    }
}
