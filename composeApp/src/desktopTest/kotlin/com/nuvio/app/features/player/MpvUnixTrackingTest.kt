package com.nuvio.app.features.player

import com.nuvio.app.core.network.UnixIpcConnection
import java.net.StandardProtocolFamily
import java.net.UnixDomainSocketAddress
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.ServerSocketChannel
import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import java.io.IOException

class MpvUnixTrackingTest {
    @Test
    fun realMpvReportsDurationSeekAndPauseOverUnixSocket() {
        if (System.getProperty("os.name").startsWith("Windows")) return
        val mpv = listOf("/opt/homebrew/bin/mpv", "/usr/local/bin/mpv").map(Path::of).firstOrNull(Files::isExecutable)
            ?: return
        val root = Files.createTempDirectory(Path.of("/tmp"), "nuvio-mpv-test-")
        val socket = root.resolve("ipc")
        val source = root.resolve("audio.wav")
        val rate = 16000
        val size = 20 * rate * 2
        val header = ByteBuffer.allocate(44 + size).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(36 + size).put("WAVEfmt ".toByteArray())
            .putInt(16).putShort(1).putShort(1).putInt(rate).putInt(rate * 2).putShort(2).putShort(16)
            .put("data".toByteArray()).putInt(size)
        Files.write(source, header.array())
        val process = ProcessBuilder(mpv.toString(), "--no-config", "--vo=null", "--ao=null", "--pause=yes",
            "--input-ipc-server=$socket", source.toString()).redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD).start()
        val reader = MpvIpcReader(socket.toString())
        try {
            var sample: ExternalPlaybackSample? = null
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(8)
            while (sample == null && System.nanoTime() < deadline) {
                sample = runCatching { reader.read() }.getOrNull()
                if (sample == null) Thread.sleep(50)
            }
            assertTrue(sample != null, "mpv did not answer on its Unix socket")
            assertEquals(20000L, sample.durationMs)
            assertTrue(sample.isPaused)
            UnixIpcConnection(socket.toString()).use { control ->
                control.write("{\"command\":[\"seek\",5,\"absolute+exact\"]}\n".toByteArray())
                control.readLine()
            }
            Thread.sleep(100)
            val afterSeek = reader.read()!!
            assertTrue(afterSeek.positionMs in 4900..5100, "seek was not reflected: $afterSeek")
        } finally {
            reader.close()
            process.destroyForcibly().waitFor()
            root.toFile().deleteRecursively()
        }
    }

    @Test
    fun unresponsiveUnixPeerTimesOutInsteadOfPinningTheMonitor() {
        if (System.getProperty("os.name").startsWith("Windows")) return
        val root = Files.createTempDirectory(Path.of("/tmp"), "nuvio-ipc-test-")
        ServerSocketChannel.open(StandardProtocolFamily.UNIX).use { server ->
            val path = root.resolve("ipc")
            server.bind(UnixDomainSocketAddress.of(path))
            UnixIpcConnection(path.toString(), 100).use { connection ->
                server.accept().use { assertFailsWith<IOException> { connection.readLine() } }
            }
        }
        root.toFile().deleteRecursively()
    }
}
