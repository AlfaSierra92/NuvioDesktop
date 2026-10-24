package com.nuvio.app.features.screensaver

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ScreensaverIdlePolicyTest {
    private val settings = ScreensaverSettings(
        enabled = true, dimDelayMinutes = 1, shutdownEnabled = true, shutdownDelayMinutes = 2,
        activeDuringPlayback = true, playbackDimDelayMinutes = 5, playbackShutdownDelayMinutes = 10,
    )

    private fun decide(
        idle: Long = 120_000, now: Long = 120_000, start: Long? = null,
        foreground: Boolean = true, showing: Boolean = true, available: Boolean = true,
        player: Boolean = false, config: ScreensaverSettings = settings,
    ) = screensaverIdleDecision(config, player, showing, foreground, available, idle, now, start)

    @Test fun `dimming and shutdown have separate delays and a full countdown`() {
        assertFalse(decide(idle = 59_999).dim)
        assertTrue(decide(idle = 60_000).dim)
        assertNull(decide(idle = 119_999).countdownStartedAtMs)
        val start = decide()
        assertEquals(30, start.countdownRemainingSeconds)
        assertFalse(decide(now = 149_999, start = start.countdownStartedAtMs).shutdownDue)
        assertTrue(decide(now = 150_000, start = start.countdownStartedAtMs).shutdownDue)
    }

    @Test fun `input focus loss hiding and missing system idle cancel a running countdown`() {
        for (decision in listOf(
            decide(idle = 0, now = 150_000, start = 120_000),
            decide(now = 150_000, start = 120_000, foreground = false),
            decide(now = 150_000, start = 120_000, showing = false),
            decide(now = 150_000, start = 120_000, available = false),
            decide(now = 150_000, start = 120_000, config = settings.copy(shutdownEnabled = false)),
        )) {
            assertNull(decision.countdownStartedAtMs)
            assertFalse(decision.shutdownDue)
        }
        // Returning to Nuvio must start a new full countdown, even after a long absence.
        assertEquals(30, decide(now = 900_000).countdownRemainingSeconds)
    }

    @Test fun `playback uses longer delays and can suppress both actions`() {
        assertFalse(decide(player = true).dim)
        assertNull(decide(player = true).countdownRemainingSeconds)
        assertEquals(30, decide(player = true, idle = 600_000).countdownRemainingSeconds)
        val disabled = decide(player = true, idle = 600_000,
            config = settings.copy(activeDuringPlayback = false))
        assertFalse(disabled.dim)
        assertNull(disabled.countdownRemainingSeconds)
    }
}
