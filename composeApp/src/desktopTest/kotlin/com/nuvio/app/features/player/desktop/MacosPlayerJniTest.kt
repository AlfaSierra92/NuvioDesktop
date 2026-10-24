package com.nuvio.app.features.player.desktop

import java.lang.reflect.Modifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MacosPlayerJniTest {
    @Test
    fun `shared player methods resolve against the real macOS JNI library`() {
        if (DesktopHostOs.current != DesktopHostOs.MACOS) return
        // Calling with a disposed handle must be safe, but still makes the JVM resolve each
        // native symbol and its return type. This catches missing exports before packaging.
        val windowsOnly = setOf(
            "initializeAppIdentity", "beginVideoProfile", "endVideoProfile", "completeSvpStartupProfile",
            "applyWindowChrome", "setBorderlessFullscreen", "setBorderlessFullscreenSuspended",
            "setCompactPlayerWindow", "beginCompactPlayerWindowMove", "beginCompactPlayerWindowResize",
            "updateCompactPlayerWindowInteraction", "endCompactPlayerWindowInteraction", "pollGamepads",
            "setWindowsDisplaySleepInhibited", "isWindowDisplayHdr",
            "decodeSpeechSpot", "speechSourceBytesPerSecond",
        )
        val tested = mutableSetOf<String>()
        NativePlayerBridge::class.java.declaredMethods
            .filter { Modifier.isNative(it.modifiers) && it.name != "create" && it.name !in windowsOnly }
            .forEach { method ->
                val arguments = method.parameterTypes.map<Class<*>, Any> { type ->
                    when (type) {
                        java.lang.Long.TYPE -> 0L
                        java.lang.Integer.TYPE -> 0
                        java.lang.Float.TYPE -> 0f
                        java.lang.Double.TYPE -> 0.0
                        java.lang.Boolean.TYPE -> false
                        String::class.java -> ""
                        else -> error("Add a JNI test argument for $type in ${method.name}")
                    }
                }.toTypedArray()
                method.invoke(NativePlayerBridge, *arguments)
                tested += method.name
            }
        assertTrue("systemIdleMs" in tested)
        assertTrue("isForegroundProcess" in tested)
        assertTrue("requestMacosShutdown" in tested)
        assertFalse(NativePlayerBridge.requestMacosShutdown(confirmed = false))
        assertTrue(NativePlayerBridge.systemIdleMs() >= 0L)
        assertTrue("setMpvProperty" in tested)
        assertTrue("runJavaScript" in tested)
        assertEquals(100f, NativePlayerBridge.volume(0))
        assertFalse(NativePlayerBridge.isMuted(0))
        assertFalse(NativePlayerBridge.selectAudioTrack(0, 1))
        assertFalse(NativePlayerBridge.selectSubtitleTrack(0, 1))
    }
}
