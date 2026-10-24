package com.nuvio.app

import java.nio.file.Files
import java.nio.file.Path
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DesktopRelaunchTest {
    @Test
    fun invalidPackagedLauncherReturnsFailureWithoutExiting() {
        val previous = System.getProperty("jpackage.app-path")
        try {
            System.setProperty("jpackage.app-path", "invalid\u0000launcher")
            assertFalse(relaunchAfterExit("test-import.bat"))
        } finally {
            if (previous == null) System.clearProperty("jpackage.app-path")
            else System.setProperty("jpackage.app-path", previous)
        }
    }

    @Test
    fun macosRestartsTheBundleThroughLaunchServices() {
        val bundle = Path.of("/Applications/Nuvio d'Antonio è qui.app")
        assertEquals(
            listOf("/usr/bin/open", "-n", bundle.toString()),
            desktopRelaunchCommand(bundle.resolve("Contents/MacOS/Nuvio HTPC"), "Mac OS X"),
        )
        assertNull(desktopRelaunchCommand(Path.of("/tmp/gradle/launcher"), "Mac OS X"))
        val exe = Path.of("/install/Nuvio.exe")
        assertEquals(listOf(exe.toString()), desktopRelaunchCommand(exe, "Windows 11"))
    }

    @Test
    fun helperWaitsForParentAndChildrenAndPreservesLiteralArguments() {
        if (System.getProperty("os.name").startsWith("Windows")) return
        val root = Files.createTempDirectory("nuvio-relaunch-test")
        val parent = ProcessBuilder("/bin/sleep", "30").start()
        val child = ProcessBuilder("/bin/sleep", "30").start()
        var helper: Process? = null
        try {
            val receiver = root.resolve("ricevi d'Antonio è qui.sh")
            Files.writeString(receiver, "printf '%s' \"\$1\" > \"\$2\"\n")
            val output = root.resolve("restart result.txt")
            val argument = "è 'quoted' \"double\" ${'$'}(touch ${root.resolve("injected")}) `false`"
            val script = root.resolve("restart helper.sh")
            Files.writeString(script, posixRelaunchScript(
                parent.pid(), listOf(child.pid()), listOf("/bin/sh", receiver.toString(), argument, output.toString()),
            ))
            helper = ProcessBuilder("/bin/sh", script.toString()).redirectErrorStream(true).start()
            Thread.sleep(150)
            assertFalse(Files.exists(output), "must not restart while the old app is running")
            parent.destroyForcibly().waitFor()
            Thread.sleep(1_200)
            assertFalse(Files.exists(output), "must wait for the old app's children too")
            child.destroyForcibly().waitFor()
            assertTrue(helper.waitFor(5, TimeUnit.SECONDS), "restart helper did not finish")
            assertEquals(0, helper.exitValue(), helper.inputStream.bufferedReader().readText())
            assertEquals(argument, Files.readString(output))
            assertFalse(Files.exists(root.resolve("injected")), "paths and arguments must not execute shell code")
            assertFalse(Files.exists(script), "helper must delete itself")
        } finally {
            parent.destroyForcibly().waitFor()
            child.destroyForcibly().waitFor()
            helper?.destroyForcibly()?.waitFor()
            Files.walk(root).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach(Files::deleteIfExists) }
        }
    }
}
