package com.nuvio.app.features.player

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.ComposeDialog
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindow
import java.awt.Color
import java.awt.Component
import java.awt.Dialog
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import javax.swing.SwingUtilities

/** Covers the native Canvas until its own loading UI has received and drawn the controls state. */
@Composable
internal fun DesktopPlayerStartupOverlay(
    host: Component,
    controls: PlayerControlsState,
    onBack: () -> Unit,
) {
    DialogWindow(
        visible = true,
        create = {
            ComposeDialog(SwingUtilities.getWindowAncestor(host), Dialog.ModalityType.MODELESS).apply {
                isUndecorated = true
                isResizable = false
                focusableWindowState = false
                isAutoRequestFocus = false
                background = Color.BLACK
                syncStartupBounds(host)
            }
        },
        dispose = { it.dispose() },
    ) {
        // Track the host rather than the screen: this also works in fullscreen, with display
        // scaling, and when the window is moved/resized during a slow source resolution.
        DisposableEffect(window, host) {
            val owner = SwingUtilities.getWindowAncestor(host)
            val listener = object : ComponentAdapter() {
                override fun componentMoved(e: ComponentEvent) = window.syncStartupBounds(host)
                override fun componentResized(e: ComponentEvent) = window.syncStartupBounds(host)
            }
            host.addComponentListener(listener)
            owner?.addComponentListener(listener)
            window.syncStartupBounds(host)
            onDispose {
                host.removeComponentListener(listener)
                owner?.removeComponentListener(listener)
            }
        }
        OpeningOverlay(
            artwork = controls.openingArtwork,
            logo = controls.openingLogo,
            title = controls.openingTitle,
            onBack = onBack,
            horizontalSafePadding = 0.dp,
            modifier = Modifier.fillMaxSize(),
            message = controls.openingMessage,
            progress = controls.openingProgress,
        )
    }
}

private fun ComposeDialog.syncStartupBounds(host: Component) {
    if (!host.isShowing) return
    // The Canvas starts at 1x1 while creating its peer; cover the entire content area even then.
    val owner = SwingUtilities.getWindowAncestor(host) as? javax.swing.RootPaneContainer ?: return
    val content = owner.contentPane
    if (!content.isShowing) return
    setLocation(content.locationOnScreen)
    setSize(content.size)
}
