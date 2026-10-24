package com.nuvio.app.features.discord

import java.io.IOException
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.ServerSocketChannel
import java.nio.channels.SocketChannel
import java.nio.file.Files
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class DiscordIpcTransportTest {
    @Test fun `discovers macOS socket directories and keeps Windows pipe paths`() {
        val paths = discordIpcCandidates("Mac OS X", mapOf("TMPDIR" to "/var/tmp/user", "XDG_RUNTIME_DIR" to "/run/user"), "/tmp")
        assertEquals("/run/user/discord-ipc-0", paths.first())
        assertTrue("/var/tmp/user/discord-ipc-9" in paths)
        assertTrue("/tmp/discord-ipc-0" in paths)
        assertEquals(10, discordIpcCandidates("Windows 11", emptyMap(), null).size)
        assertTrue(discordIpcCandidates("Windows 11", emptyMap(), null).first().startsWith("\\\\.\\pipe\\"))
    }

    @Test fun `real Unix socket handles handshake fragmented frames ping and activity`() {
        if (System.getProperty("os.name").startsWith("Windows")) return
        val dir = Files.createTempDirectory(java.nio.file.Path.of("/tmp"), "nuvio-rpc-")
        val socket = dir.resolve("ipc")
        val worker = Executors.newSingleThreadExecutor()
        try {
            ServerSocketChannel.open(StandardProtocolFamily.UNIX).use { server ->
                server.bind(UnixDomainSocketAddress.of(socket))
                val peer = worker.submit {
                    server.accept().use { channel ->
                        val handshake = receive(channel)
                        assertEquals(0, handshake.first)
                        assertEquals("test-client", handshake.second["client_id"]!!.jsonPrimitive.content)
                        frame(channel, 1, buildJsonObject { put("evt", "READY") })
                        val activity = receive(channel)
                        assertEquals("SET_ACTIVITY", activity.second["cmd"]!!.jsonPrimitive.content)
                        frame(channel, 3, buildJsonObject { put("ping", true) })
                        assertEquals(4, receive(channel).first)
                        frame(channel, 1, buildJsonObject { put("nonce", activity.second["nonce"]!!.jsonPrimitive.content) })
                    }
                }
                DiscordIpcConnection(UnixDiscordIpcTransport(socket.toString())).let { client ->
                    try {
                        client.handshake("test-client")
                        client.setActivity(buildJsonObject { put("details", "Test playback") })
                    } finally { client.close() }
                }
                peer.get(10, TimeUnit.SECONDS)
            }
        } finally {
            worker.shutdownNow()
            Files.deleteIfExists(socket)
            Files.deleteIfExists(dir)
        }
    }

    @Test fun `an unresponsive peer cannot block reads indefinitely`() {
        if (System.getProperty("os.name").startsWith("Windows")) return
        val dir = Files.createTempDirectory(java.nio.file.Path.of("/tmp"), "nuvio-rpc-")
        val socket = dir.resolve("ipc")
        try {
            ServerSocketChannel.open(StandardProtocolFamily.UNIX).use { server ->
                server.bind(UnixDomainSocketAddress.of(socket))
                UnixDiscordIpcTransport(socket.toString(), timeoutMs = 50).use { client ->
                    server.accept().use {
                        assertFailsWith<IOException> { client.readFully(ByteArray(8)) }
                    }
                }
            }
        } finally { Files.deleteIfExists(socket); Files.deleteIfExists(dir) }
    }

    private fun receive(channel: SocketChannel): Pair<Int, JsonObject> {
        fun read(size: Int): ByteArray {
            val buffer = ByteBuffer.allocate(size)
            while (buffer.hasRemaining()) check(channel.read(buffer) >= 0)
            return buffer.array()
        }
        val header = ByteBuffer.wrap(read(8)).order(ByteOrder.LITTLE_ENDIAN)
        val opcode = header.int
        return opcode to Json.parseToJsonElement(String(read(header.int), Charsets.UTF_8)).jsonObject
    }

    private fun frame(channel: SocketChannel, opcode: Int, value: JsonObject) {
        val payload = value.toString().toByteArray()
        val bytes = ByteBuffer.allocate(8 + payload.size).order(ByteOrder.LITTLE_ENDIAN)
            .putInt(opcode).putInt(payload.size).put(payload).array()
        // Deliberately fragment even the header: the client must read complete frames.
        bytes.forEach { byte ->
            val buffer = ByteBuffer.wrap(byteArrayOf(byte))
            while (buffer.hasRemaining()) channel.write(buffer)
        }
    }
}
