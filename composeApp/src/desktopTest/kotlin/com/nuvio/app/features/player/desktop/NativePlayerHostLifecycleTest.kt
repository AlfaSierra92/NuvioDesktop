package com.nuvio.app.features.player.desktop

import java.awt.image.BufferedImage
import javax.swing.SwingUtilities
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

class NativePlayerHostLifecycleTest {
    @Test
    fun lateSubscriberReceivesTheAlreadyPaintedSurface() = SwingUtilities.invokeAndWait {
        val host = NativePlayerHost().apply { setSize(640, 360) }
        paint(host)
        var paints = 0
        var fullSizePaints = 0
        host.onFirstPaint = { paints++ }
        host.onFirstFullSizePaint = { fullSizePaints++ }
        assertEquals(1, paints)
        assertEquals(1, fullSizePaints)
        paint(host)
        assertEquals(1, paints)
        assertEquals(1, fullSizePaints)
    }

    @Test
    fun temporaryPeerRemovalPreservesListenersAndRearmsReadiness() = SwingUtilities.invokeAndWait {
        val host = NativePlayerHost().apply { setSize(640, 360) }
        var paints = 0
        var fullSizePaints = 0
        val ready: () -> Unit = {}
        host.onPeerReady = ready
        host.onFirstPaint = { paints++ }
        host.onFirstFullSizePaint = { fullSizePaints++ }
        paint(host)
        host.removeNotify()
        assertSame(ready, host.onPeerReady)
        paint(host)
        assertEquals(2, paints)
        assertEquals(2, fullSizePaints)
    }

    private fun paint(host: NativePlayerHost) {
        val graphics = BufferedImage(640, 360, BufferedImage.TYPE_INT_RGB).createGraphics()
        try { host.paint(graphics) } finally { graphics.dispose() }
    }
}
