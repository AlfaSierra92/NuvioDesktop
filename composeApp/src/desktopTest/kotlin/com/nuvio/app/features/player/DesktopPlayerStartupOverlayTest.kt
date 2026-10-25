package com.nuvio.app.features.player

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.runComposeUiTest
import com.nuvio.app.core.ui.NuvioTheme
import java.awt.Canvas
import java.awt.Window
import javax.swing.JDialog
import javax.swing.JFrame
import javax.swing.SwingUtilities
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

@OptIn(ExperimentalTestApi::class)
class DesktopPlayerStartupOverlayTest {
    @Test
    fun `startup covers the native host, updates status, follows resizing and disposes on handoff`() {
        val host = Canvas()
        lateinit var owner: JFrame
        SwingUtilities.invokeAndWait {
            owner = JFrame().apply {
                focusableWindowState = false
                isAutoRequestFocus = false
                contentPane.add(host)
                setBounds(150, 150, 640, 360)
                isVisible = true
            }
        }
        try {
            runComposeUiTest {
                val visible = mutableStateOf(true)
                val status = mutableStateOf("Verifica del collegamento video…")
                setContent {
                    NuvioTheme(darkTheme = true) {
                        if (visible.value) {
                            DesktopPlayerStartupOverlay(
                                host = host,
                                controls = PlayerControlsState(
                                    openingTitle = "Startup test",
                                    openingMessage = status.value,
                                ),
                                onBack = {},
                            )
                        }
                    }
                }
                fun cover(): JDialog? = Window.getWindows()
                    .filterIsInstance<JDialog>()
                    .firstOrNull { it.owner === owner && it.isShowing }
                waitUntil { cover() != null }
                onNodeWithText(status.value, useUnmergedTree = true).assertExists()
                SwingUtilities.invokeAndWait {
                    val dialog = requireNotNull(cover())
                    assertFalse(dialog.isModal)
                    assertFalse(dialog.focusableWindowState)
                    assertEquals(owner.contentPane.locationOnScreen, dialog.location)
                    assertEquals(owner.contentPane.size, dialog.size)
                    owner.setBounds(200, 180, 800, 450)
                }
                waitUntil {
                    cover()?.let { it.size == owner.contentPane.size && it.location == owner.contentPane.locationOnScreen } == true
                }
                runOnIdle { status.value = "Avvio del player…" }
                // The separate native window has its own frame clock; wait for its crossfade.
                waitUntil(timeoutMillis = 5_000) {
                    runCatching {
                        onNodeWithText("Avvio del player…", useUnmergedTree = true).fetchSemanticsNode()
                    }.isSuccess
                }
                val dialog = requireNotNull(cover())
                runOnIdle { visible.value = false }
                waitUntil { !dialog.isDisplayable }
            }
        } finally {
            SwingUtilities.invokeAndWait { owner.dispose() }
        }
    }
}
