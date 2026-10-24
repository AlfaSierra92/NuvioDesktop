package com.nuvio.app.features.player.desktop

import java.awt.Rectangle
import kotlin.test.Test
import kotlin.test.assertEquals

class MacosPictureInPictureTest {
    @Test
    fun resizingKeepsTheOppositeEdgeFixedAndEnforcesMinimumSize() {
        val original = Rectangle(100, 200, 640, 360)
        assertEquals(Rectangle(140, 220, 640, 360), compactInteractionBounds(original, 1, 40, 20))
        assertEquals(Rectangle(500, 200, 240, 360), compactInteractionBounds(original, 2, 1000, 0))
        assertEquals(Rectangle(100, 425, 640, 135), compactInteractionBounds(original, 4, 0, 1000))
        assertEquals(Rectangle(100, 200, 740, 460), compactInteractionBounds(original, 9, 100, 100))
    }
}
