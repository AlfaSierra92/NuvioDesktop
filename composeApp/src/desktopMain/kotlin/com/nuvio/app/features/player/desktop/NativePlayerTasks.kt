package com.nuvio.app.features.player.desktop

import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Tracks native workers so process exit cannot interrupt an in-flight create or stream teardown. */
internal class NativePlayerTaskTracker {
    private val monitor = Object()
    private var pending = 0

    fun launch(name: String, task: () -> Unit): Thread {
        synchronized(monitor) { pending++ }
        return try {
            thread(isDaemon = true, name = name) {
                try {
                    task()
                } finally {
                    taskFinished()
                }
            }
        } catch (error: Throwable) {
            taskFinished()
            throw error
        }
    }

    private fun taskFinished() = synchronized(monitor) {
        pending--
        monitor.notifyAll()
    }

    /** Called after Compose disposes the players, off the EDT so native UI cleanup can still run. */
    fun awaitIdle(timeoutMs: Long): Boolean {
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs.coerceAtLeast(0L))
        synchronized(monitor) {
            while (pending > 0) {
                val remaining = deadline - System.nanoTime()
                if (remaining <= 0L) return false
                TimeUnit.NANOSECONDS.timedWait(monitor, remaining)
            }
            return true
        }
    }
}

internal val nativePlayerTasks = NativePlayerTaskTracker()
