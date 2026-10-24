package com.nuvio.app.features.discord

import java.io.Closeable
import java.io.EOFException
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SelectionKey
import java.nio.channels.Selector
import java.nio.channels.SocketChannel
import java.util.concurrent.TimeUnit

internal fun discordIpcCandidates(osName: String, env: Map<String, String>, tempDir: String?): List<String> {
    if (osName.startsWith("Windows", ignoreCase = true)) return (0..9).map { "\\\\.\\pipe\\discord-ipc-$it" }
    val roots = listOfNotNull(env["XDG_RUNTIME_DIR"], env["TMPDIR"], env["TMP"], env["TEMP"], tempDir, "/tmp")
        .filter { it.isNotBlank() }.distinct()
    return roots.flatMap { root -> (0..9).map { File(root, "discord-ipc-$it").path } }.distinct()
}

internal interface DiscordIpcTransport : Closeable {
    fun write(bytes: ByteArray)
    fun readFully(bytes: ByteArray)
}

internal fun openDiscordIpcTransport(path: String): DiscordIpcTransport {
    if (System.getProperty("os.name").orEmpty().startsWith("Windows", ignoreCase = true)) {
        val file = RandomAccessFile(path, "rw")
        return object : DiscordIpcTransport {
            override fun write(bytes: ByteArray) = file.write(bytes)
            override fun readFully(bytes: ByteArray) = file.readFully(bytes)
            override fun close() = file.close()
        }
    }
    return UnixDiscordIpcTransport(path)
}

/** Bounded reads and writes keep an unresponsive local Discord client from pinning the worker. */
internal class UnixDiscordIpcTransport(path: String, private val timeoutMs: Long = 5_000) : DiscordIpcTransport {
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

    override fun write(bytes: ByteArray) = transfer(ByteBuffer.wrap(bytes), writing = true)
    override fun readFully(bytes: ByteArray) = transfer(ByteBuffer.wrap(bytes), writing = false)

    private fun transfer(buffer: ByteBuffer, writing: Boolean) {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
        while (buffer.hasRemaining()) {
            val count = if (writing) channel.write(buffer) else channel.read(buffer)
            if (count < 0) throw EOFException("Discord closed the IPC socket")
            if (count == 0) await(if (writing) SelectionKey.OP_WRITE else SelectionKey.OP_READ, deadline)
        }
    }

    private fun await(operation: Int, deadline: Long) {
        val remaining = deadline - System.nanoTime()
        if (remaining <= 0) throw IOException("Discord IPC timed out")
        channel.keyFor(selector).interestOps(operation)
        selector.select(TimeUnit.NANOSECONDS.toMillis(remaining).coerceAtLeast(1))
        selector.selectedKeys().clear()
    }

    override fun close() {
        try { channel.close() } finally { selector.close() }
    }
}
