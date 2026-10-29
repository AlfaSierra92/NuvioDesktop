package com.nuvio.app.features.settings

import com.nuvio.app.features.input.gamepadSupported
import com.nuvio.app.isWindows
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SettingsSearchPlatformTest {
    @Test fun searchExposesSupportedControllerAndVideoSettings() = runBlocking {
        val entries = buildSettingsSearchEntries(
            pluginsEnabled = false, downloadsEnabled = true, notificationsEnabled = false,
            liquidGlassNativeTabBarSupported = false, switchProfileAvailable = false,
            checkForUpdatesAvailable = true,
        )
        assertEquals(gamepadSupported(), entries.any { it.key.endsWith("gamepad-control") })
        for (key in listOf("desktop-renderer", "hdr-ui-compensation", "nvidia-rtx-hdr-anime")) {
            assertEquals(isWindows, entries.any { it.key.endsWith(key) }, key)
        }
        assertTrue(entries.any { it.key.endsWith("desktop-buffer-preset") })
    }
}
