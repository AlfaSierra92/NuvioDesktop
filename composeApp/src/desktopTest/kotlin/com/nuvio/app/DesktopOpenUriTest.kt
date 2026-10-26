package com.nuvio.app

import java.net.URI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DesktopOpenUriTest {
    @Test
    fun acceptedLinksAreQueuedBeforeRestoringAHiddenWindow() {
        val events = mutableListOf<String>()
        val url = "nuviohtpc://meta?type=series&id=tt0944947"
        assertTrue(dispatchDesktopOpenUri(URI(url), { events += it }, { events += "activate" }))
        assertEquals(listOf(url, "activate"), events)
        assertFalse(dispatchDesktopOpenUri(URI("nuvio://downloads"), { error("upstream link") }, { error("wrong activation") }))
        assertFalse(dispatchDesktopOpenUri(URI("https://example.test"), { error("wrong scheme") }, { error("wrong activation") }))
    }
}
