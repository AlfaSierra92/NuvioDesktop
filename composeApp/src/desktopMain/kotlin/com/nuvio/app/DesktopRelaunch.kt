package com.nuvio.app

import com.nuvio.app.core.storage.macosAppBundle
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import javax.swing.SwingUtilities
import kotlin.system.exitProcess

/**
 * Starts a fresh Nuvio once this process has exited, so the new copy wins the single-instance
 * claim and starts from what this one staged (a settings import, another account's folder), then
 * exits this one. False on a dev run, which has no launcher to start; nothing is exited then.
 */
internal fun relaunchAfterExit(scriptName: String): Boolean {
    val appPath = System.getProperty("jpackage.app-path")?.takeIf(String::isNotBlank) ?: return false
    var script: Path? = null
    val started = runCatching {
        val launcher = Path.of(appPath).toAbsolutePath().normalize()
        if (!Files.isRegularFile(launcher)) return false
        val osName = System.getProperty("os.name").orEmpty()
        val windows = osName.startsWith("Windows", ignoreCase = true)
        val command = desktopRelaunchCommand(launcher, osName) ?: return false
        val pid = ProcessHandle.current().pid()
        // Capture children before starting the helper, which must never wait on itself.
        val children = ProcessHandle.current().descendants().use { processes -> processes.map { it.pid() }.toList() }
        val helper = Files.createTempFile("nuvio-$pid-${scriptName.substringBeforeLast('.')}-", if (windows) ".cmd" else ".sh")
        script = helper
        val process = if (windows) {
            Files.writeString(helper, windowsRelaunchScript(launcher, pid, children), Charsets.US_ASCII)
            ProcessBuilder("cmd.exe", "/c", "start", "Nuvio Restart", "/min", "cmd.exe", "/c", helper.toString())
        } else {
            Files.writeString(helper, posixRelaunchScript(pid, children, command), Charsets.UTF_8)
            ProcessBuilder("/usr/bin/nohup", "/bin/sh", helper.toString())
                .redirectInput(File("/dev/null"))
        }
        process.directory(helper.parent.toFile())
            .redirectOutput(ProcessBuilder.Redirect.DISCARD)
            .redirectError(ProcessBuilder.Redirect.DISCARD)
            .start()
        true
    }.getOrElse { error ->
        script?.let { runCatching { Files.deleteIfExists(it) } }
        System.err.println("Warn: (Relaunch) could not schedule restart: $error")
        false
    }
    // Never leave the current process until the helper has actually been started. Callers can
    // handle false (e.g. staged import requiring a manual restart) without an uncaught IOException.
    if (started) exitSoon()
    return started
}

internal fun desktopRelaunchCommand(launcher: Path, osName: String): List<String>? =
    if (osName.contains("mac", ignoreCase = true)) {
        macosAppBundle(launcher)?.let { listOf("/usr/bin/open", "-n", it.toString()) }
    } else {
        listOf(launcher.toString())
    }

/** All paths are data, including apostrophes, dollar signs, backticks and non-ASCII names. */
internal fun posixRelaunchScript(pid: Long, childPids: List<Long>, command: List<String>): String {
    require(pid > 0 && childPids.all { it > 0 })
    require(command.isNotEmpty())
    fun quote(value: String) = "'" + value.replace("'", "'\"'\"'") + "'"
    return buildString {
        appendLine("#!/bin/sh")
        appendLine("trap 'rm -f -- \"\$0\"' EXIT")
        appendLine("while kill -0 $pid 2>/dev/null; do sleep 1; done")
        childPids.forEach { child ->
            appendLine("tries=0")
            appendLine("while kill -0 $child 2>/dev/null && [ \"\$tries\" -lt 15 ]; do")
            appendLine("  sleep 1")
            appendLine("  tries=\$((tries + 1))")
            appendLine("done")
        }
        appendLine(command.joinToString(" ", transform = ::quote))
    }
}

private fun windowsRelaunchScript(launcher: Path, pid: Long, childPids: List<Long>): String {
    // Children too (TorrServer, WebView2): a portable switch copies the data folder at the next
    // startup, and TorrServer holds a lock on its database until it has really gone. Captured
    // before the helper below is started, so the helper never waits on itself.
    val installDir = launcher.parent
    // Neither the script nor anyone's working directory may sit in the data folder: Windows won't
    // rename a folder that is some process's current directory or holds an open file, and a
    // portable switch renames it (`data` -> `data.old`) at the very next startup.
    val lines = buildList {
        add("@echo off")
        add("setlocal enableextensions")
        add("set \"PID=$pid\"")
        add("set \"EXE=$launcher\"")
        add(":waitloop")
        add("tasklist /fi \"PID eq %PID%\" /nh 2>nul | findstr \"%PID%\" >nul")
        add("if not errorlevel 1 (")
        add("  timeout /t 1 /nobreak >nul")
        add("  goto waitloop")
        add(")")
        // Children get a bounded wait each: an orphan that refuses to die must not stop the
        // restart altogether.
        childPids.forEachIndexed { index, child ->
            add("set /a TRIES=0")
            add(":child$index")
            add("tasklist /fi \"PID eq $child\" /nh 2>nul | findstr \"$child\" >nul")
            add("if not errorlevel 1 if %TRIES% lss 15 (")
            add("  set /a TRIES+=1")
            add("  timeout /t 1 /nobreak >nul")
            add("  goto child$index")
            add(")")
        }
        add("start \"\" /D \"$installDir\" \"%EXE%\"")
        add("(goto) 2>nul & del \"%~f0\"")
        add("")
    }
    return lines.joinToString("\r\n")
}

/**
 * Closes Nuvio through the window's normal exit (so stores flush and the player shuts down),
 * forcing it if that has not finished within 15 seconds.
 */
internal fun exitSoon() {
    Thread {
        runCatching { Thread.sleep(800) }
        val requested = runCatching {
            var accepted = false
            SwingUtilities.invokeAndWait { accepted = DesktopApplicationExit.request() }
            accepted
        }.getOrDefault(false)
        if (requested) runCatching { Thread.sleep(15_000) }
        exitProcess(0)
    }.apply {
        isDaemon = true
        name = "nuvio-restart-exit"
    }.start()
}
