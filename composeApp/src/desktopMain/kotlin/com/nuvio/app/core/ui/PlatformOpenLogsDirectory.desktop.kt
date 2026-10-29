package com.nuvio.app.core.ui

import com.nuvio.app.core.storage.DesktopStorage
import java.awt.Desktop
import java.nio.file.Files

actual fun platformOpenLogsDirectory() {
    runCatching {
        val logsDir = DesktopStorage.rootDir.resolve("logs")
        // Fresh installs may not have logged anything yet; Explorer errors on missing paths.
        Files.createDirectories(logsDir)
        val opened = runCatching {
            ProcessBuilder(logsDirectoryOpenCommand(System.getProperty("os.name").orEmpty(), logsDir.toAbsolutePath().toString())).start()
        }.isSuccess
        if (!opened) {
            Desktop.getDesktop().open(logsDir.toFile())
        }
    }
}

internal fun logsDirectoryOpenCommand(osName: String, directory: String): List<String> = when {
    osName.contains("mac", ignoreCase = true) -> listOf("/usr/bin/open", directory)
    osName.startsWith("Windows", ignoreCase = true) -> listOf("explorer.exe", directory)
    else -> listOf("xdg-open", directory)
}
