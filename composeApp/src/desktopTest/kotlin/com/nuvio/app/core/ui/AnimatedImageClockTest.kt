package com.nuvio.app.core.ui

import androidx.compose.ui.graphics.ImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AnimatedImageClockTest {
    private fun painter(clock: AnimatedImageClock, frameCount: Int = 2) = SkiaAnimatedPainter(
        SkiaAnimatedImage(
            width = 4,
            height = 4,
            frames = List(frameCount) { ImageBitmap(4, 4) },
            frameDurationsMs = IntArray(frameCount) { 100 },
        ),
        clock,
    )

    @Test
    fun `clock runs only while an animated painter is mounted and can restart`() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val clock = AnimatedImageClock(scope)
            val first = painter(clock)
            val second = painter(clock)
            assertFalse(clock.isRunning, "constructing cached painters must not start a timer")
            first.onRemembered()
            first.onRemembered() // Repeated lifecycle delivery must not leak a subscription.
            second.onRemembered()
            assertTrue(clock.isRunning)
            first.onForgotten()
            first.onAbandoned()
            assertTrue(clock.isRunning, "another mounted painter still needs ticks")
            second.onForgotten()
            assertFalse(clock.isRunning, "the last painter must stop the timer")
            first.onRemembered()
            assertTrue(clock.isRunning, "retained artwork must be able to resume")
            first.onForgotten()
            assertFalse(clock.isRunning)
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `still and abandoned painters never start the clock`() {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val clock = AnimatedImageClock(scope)
            val still = painter(clock, frameCount = 1)
            still.onRemembered()
            still.onForgotten()
            painter(clock).onAbandoned()
            assertFalse(clock.isRunning)
        } finally {
            scope.cancel()
        }
    }
}
