package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals

class DesktopStartupBufferSettingsTest {
    @Test
    fun `startup buffer selection is published and survives settings reload`() {
        val before = PlayerSettingsStorage.loadDesktopStartupBuffer()
        try {
            PlayerSettingsRepository.setDesktopStartupBuffer(DesktopStartupBuffer.FiveSeconds)
            assertEquals(DesktopStartupBuffer.FiveSeconds, PlayerSettingsRepository.uiState.value.desktopStartupBuffer)
            assertEquals("FiveSeconds", PlayerSettingsStorage.loadDesktopStartupBuffer())
            PlayerSettingsRepository.clearLocalState()
            PlayerSettingsRepository.ensureLoaded()
            assertEquals(DesktopStartupBuffer.FiveSeconds, PlayerSettingsRepository.uiState.value.desktopStartupBuffer)
        } finally {
            PlayerSettingsStorage.saveDesktopStartupBuffer(before ?: "QuarterSecond")
            PlayerSettingsRepository.clearLocalState()
            PlayerSettingsRepository.ensureLoaded()
        }
    }

    @Test
    fun `unknown saved startup buffer falls back to the existing quarter second default`() {
        val before = PlayerSettingsStorage.loadDesktopStartupBuffer()
        try {
            PlayerSettingsStorage.saveDesktopStartupBuffer("UnknownFutureValue")
            PlayerSettingsRepository.clearLocalState()
            PlayerSettingsRepository.ensureLoaded()
            assertEquals(DesktopStartupBuffer.QuarterSecond, PlayerSettingsRepository.uiState.value.desktopStartupBuffer)
        } finally {
            PlayerSettingsStorage.saveDesktopStartupBuffer(before ?: "QuarterSecond")
            PlayerSettingsRepository.clearLocalState()
            PlayerSettingsRepository.ensureLoaded()
        }
    }
}
