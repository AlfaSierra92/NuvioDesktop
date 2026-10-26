package com.nuvio.app.features.player.desktop

import java.lang.reflect.Modifier
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MacosPlayerJniTest {
    @Test
    fun `playback holds and releases real macOS display and system sleep assertions`() {
        if (DesktopHostOs.current != DesktopHostOs.MACOS) return
        fun playbackAssertions(): List<String> {
            val process = ProcessBuilder("/usr/bin/pmset", "-g", "assertions")
                .redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            assertEquals(0, process.waitFor(), output)
            return output.lineSequence().filter { "Nuvio video playback" in it }.toList()
        }
        assertTrue(NativePlayerBridge.setDisplaySleepInhibited(false))
        assertTrue(playbackAssertions().isEmpty())
        try {
            // Repeated acquire must not leak extra assertions on playback state changes.
            repeat(2) { assertTrue(NativePlayerBridge.setDisplaySleepInhibited(true)) }
            val assertions = playbackAssertions()
            assertEquals(2, assertions.size, assertions.joinToString("\n"))
            assertTrue(assertions.any { "PreventUserIdleDisplaySleep" in it && "playback display" in it })
            assertTrue(assertions.any { "PreventUserIdleSystemSleep" in it && "playback system" in it })
        } finally {
            assertTrue(NativePlayerBridge.setDisplaySleepInhibited(false))
        }
        assertTrue(NativePlayerBridge.setDisplaySleepInhibited(false))
        assertTrue(playbackAssertions().isEmpty())
    }

    @Test
    fun `shared player methods resolve against the real macOS JNI library`() {
        if (DesktopHostOs.current != DesktopHostOs.MACOS) return
        // Calling with a disposed handle must be safe, but still makes the JVM resolve each
        // native symbol and its return type. This catches missing exports before packaging.
        val windowsOnly = setOf(
            "initializeAppIdentity", "beginVideoProfile", "endVideoProfile", "completeSvpStartupProfile",
            "applyWindowChrome", "setBorderlessFullscreen", "setBorderlessFullscreenSuspended",
            "beginCompactPlayerWindowMove", "beginCompactPlayerWindowResize",
            "updateCompactPlayerWindowInteraction", "endCompactPlayerWindowInteraction",
            "isWindowDisplayHdr",
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
                        IntArray::class.java -> IntArray(0)
                        String::class.java -> ""
                        else -> error("Add a JNI test argument for $type in ${method.name}")
                    }
                }.toTypedArray()
                method.invoke(NativePlayerBridge, *arguments)
                tested += method.name
            }
        assertTrue("setDisplaySleepInhibited" in tested)
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
