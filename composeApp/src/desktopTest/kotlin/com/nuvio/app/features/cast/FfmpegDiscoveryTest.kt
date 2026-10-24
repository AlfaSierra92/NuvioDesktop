package com.nuvio.app.features.cast

import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FfmpegDiscoveryTest {
    @Test
    fun macosFindsNativeBinariesAndProbesLocalMedia() {
        if (!System.getProperty("os.name").contains("mac", ignoreCase = true)) return
        if (!File("/opt/homebrew/bin/ffprobe").isFile && !File("/usr/local/bin/ffprobe").isFile) return
        assertTrue(Ffmpeg.available)
        assertEquals("ffmpeg", Ffmpeg.ffmpeg!!.name)
        assertEquals("ffprobe", Ffmpeg.ffprobe!!.name)
        val source = Files.createTempFile("nuvio-cast-probe", ".wav").toFile()
        try {
            val bytes = ByteBuffer.allocate(44 + 32000).order(ByteOrder.LITTLE_ENDIAN)
            bytes.put("RIFF".toByteArray()).putInt(32036).put("WAVEfmt ".toByteArray()).putInt(16)
                .putShort(1).putShort(1).putInt(16000).putInt(32000).putShort(2).putShort(16)
                .put("data".toByteArray()).putInt(32000)
            source.writeBytes(bytes.array())
            assertEquals(1.0, Ffmpeg.probeDurationS(source.path, emptyMap()))
        } finally { source.delete() }
    }
}
