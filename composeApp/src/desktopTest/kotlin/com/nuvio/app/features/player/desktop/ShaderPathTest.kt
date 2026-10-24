package com.nuvio.app.features.player.desktop

import com.nuvio.app.features.player.DesktopAnimeMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ShaderPathTest {
    @Test fun `mpv path lists use the host separator and escape filenames`() {
        assertEquals(":", mpvShaderPathSeparator(DesktopHostOs.MACOS))
        assertEquals(";", mpvShaderPathSeparator(DesktopHostOs.WINDOWS))
        assertEquals("/Media/a\\:b.glsl", escapeMpvShaderPath("/Media/a:b.glsl", DesktopHostOs.MACOS))
        assertEquals("a\\;b.glsl", escapeMpvShaderPath("a;b.glsl", DesktopHostOs.WINDOWS))
    }

    @Test fun `exported anime chain and sharpen use matching separators`() {
        val chain = DesktopAnimeShaders.shaderChain(DesktopAnimeMode.Optimized)
        assertTrue(chain.isNotBlank())
        val separator = mpvShaderPathSeparator()
        assertTrue(chain.split(separator).size > 1)
        val sharpened = desktopShaderChainWithSharpen(chain, "0.4").first
        assertTrue(sharpened.startsWith(chain + separator))
        assertTrue(sharpened.endsWith("Nuvio_CAS_Sharpen.glsl"))
    }
}
