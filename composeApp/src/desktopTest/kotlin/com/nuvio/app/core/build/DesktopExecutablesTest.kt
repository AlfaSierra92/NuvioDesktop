package com.nuvio.app.core.build

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopExecutablesTest {
    @Test
    fun finderPathIncludesHomebrewAndBundlesResolveToTheRealExecutable() {
        val dirs = desktopExecutableDirectories("Mac OS X") { if (it == "PATH") "/usr/bin:/bin" else null }
        assertTrue(dirs.any { it.path == "/opt/homebrew/bin" })
        assertTrue(dirs.any { it.path == "/usr/local/bin" })
        val root = Files.createTempDirectory("nuvio-player-bundle").toFile()
        try {
            val bundle = root.resolve("VLC è qui.app")
            val executable = bundle.resolve("Contents/MacOS/VLC").apply {
                parentFile.mkdirs(); writeText("#!/bin/sh\nexit 0\n"); setExecutable(true)
            }
            assertEquals(executable, applicationBundleExecutable(bundle, listOf("VLC", "vlc")))
        } finally { root.deleteRecursively() }
    }
}
