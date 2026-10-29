package com.nuvio.app.core.ui

import kotlin.test.Test
import kotlin.test.assertEquals

class PlatformOpenLogsDirectoryTest {
    @Test fun macosOpensFinderWithTheWholePathAsOneArgument() {
        val path = "/Users/Antonio/Library/Application Support/NuvioHTPC/logs"
        assertEquals(listOf("/usr/bin/open", path), logsDirectoryOpenCommand("Mac OS X", path))
    }

    @Test fun windowsUsesExplorer() {
        val path = "C:\\Users\\Antonio\\AppData\\Local\\NuvioHTPC\\logs"
        assertEquals(listOf("explorer.exe", path), logsDirectoryOpenCommand("Windows 11", path))
    }

    @Test fun linuxUsesTheDesktopOpener() {
        assertEquals(listOf("xdg-open", "/tmp/logs"), logsDirectoryOpenCommand("Linux", "/tmp/logs"))
    }
}
