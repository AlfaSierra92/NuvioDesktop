package com.nuvio.app.features.player.desktop

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class NativePlaybackDiagnosticsTest {
    @Test
    fun `native audio diagnostics preserve device messages and redact stream credentials`() {
        assertEquals(
            "[ao/coreaudio] Cannot open <url> using <url>",
            nativePlaybackWarningText("mpvWarning:[ao/coreaudio] Cannot open https://user:secret@server/video?token=private\nusing HTTP://other/video?key=secret\n"),
        )
    }

    @Test
    fun `diagnostics do not consume lifecycle events or playback errors`() {
        assertNull(nativePlaybackWarningText("fileLoaded"))
        assertNull(nativePlaybackWarningText("mpvPlaybackError:Failed to open audio output"))
    }
}
