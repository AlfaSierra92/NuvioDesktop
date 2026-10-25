package com.nuvio.app.features.player.desktop

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlin.test.assertFalse

class NativePlayerTaskTrackerTest {
    @Test
    fun `exit waits for cleanup launched by an in-flight player creation`() {
        val tasks = NativePlayerTaskTracker()
        val createReturned = CountDownLatch(1)
        val cleanupStarted = CountDownLatch(1)
        val releaseCleanup = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        try {
            tasks.launch("test-player-create") {
                createReturned.await()
                tasks.launch("test-player-dispose") {
                    cleanupStarted.countDown()
                    releaseCleanup.await()
                }
            }
            val exit = executor.submit<Boolean> { tasks.awaitIdle(5_000L) }
            createReturned.countDown()
            assertTrue(cleanupStarted.await(5, TimeUnit.SECONDS))
            assertFailsWith<TimeoutException> { exit.get(50, TimeUnit.MILLISECONDS) }
            releaseCleanup.countDown()
            assertTrue(exit.get(5, TimeUnit.SECONDS))
        } finally {
            createReturned.countDown()
            releaseCleanup.countDown()
            executor.shutdownNow()
        }
    }

    @Test
    fun `a stuck native cleanup cannot block application exit indefinitely`() {
        val tasks = NativePlayerTaskTracker()
        val releaseCleanup = CountDownLatch(1)
        try {
            tasks.launch("test-stuck-player") { releaseCleanup.await() }
            assertFalse(tasks.awaitIdle(25L))
        } finally {
            releaseCleanup.countDown()
        }
        assertTrue(tasks.awaitIdle(5_000L))
    }

    @Test
    fun `a failed native teardown still releases the exit wait`() {
        val tasks = NativePlayerTaskTracker()
        val failed = CountDownLatch(1)
        tasks.launch("test-failed-player") {
            Thread.currentThread().uncaughtExceptionHandler = Thread.UncaughtExceptionHandler { _, _ ->
                failed.countDown()
            }
            error("Native cleanup failed")
        }
        assertTrue(failed.await(5, TimeUnit.SECONDS))
        assertTrue(tasks.awaitIdle(5_000L))
    }
}
