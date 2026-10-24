package com.nuvio.app.features.player.desktop

import java.awt.Window
import java.awt.MouseInfo
import java.awt.Point
import java.awt.Rectangle
import javax.swing.SwingUtilities

private const val NuvioWindowBackgroundRgb = 0x0D0D0D
private const val NuvioWindowTextRgb = 0xF5F7F8

/**
 * Publishes the process AppUserModelID and a "Nuvio HTPC" Start Menu shortcut carrying it, so the
 * Windows media flyout shows the app name and icon instead of "Unknown app". The shortcut is
 * rewritten only when its target, AUMID or icon drifts, which lets a moved portable copy heal
 * itself on the next launch and undoes the official Nuvio Desktop's icon picker, which re-icons
 * any "Nuvio.lnk" it finds regardless of what the shortcut launches.
 */
internal fun registerDesktopAppIdentity() {
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS) return
    runCatching { NativePlayerBridge.initializeAppIdentity() }
}

internal fun applyNativeDesktopWindowChrome(window: Window) {
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || !window.isDisplayable) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.applyWindowChrome(
            windowHwnd = hwnd,
            darkMode = true,
            captionColorRgb = NuvioWindowBackgroundRgb,
            borderColorRgb = NuvioWindowBackgroundRgb,
            textColorRgb = NuvioWindowTextRgb,
        )
    }
}

internal fun applyNativeBorderlessFullscreen(window: Window, enabled: Boolean) {
    // isShowing (not just isDisplayable): restyling a created-but-not-yet-shown window
    // desyncs AWT's show/bounds bookkeeping and breaks activation and keyboard focus.
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || !window.isShowing) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.setBorderlessFullscreen(hwnd, enabled)
    }
    // The style change above is invisible to AWT, which keeps laying the content out inside the
    // decorated window's frame insets until something corrects it.
    DesktopBorderlessRootPaneFix.setActive(window, enabled)
}

internal fun applyNativeCompactPlayerWindow(window: Window, enabled: Boolean) {
    if (DesktopHostOs.current !in setOf(DesktopHostOs.WINDOWS, DesktopHostOs.MACOS) || !window.isShowing) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.setCompactPlayerWindow(hwnd, enabled)
    }
}

internal fun suspendNativeBorderlessFullscreen(window: Window, suspended: Boolean) {
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || !window.isShowing) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.setBorderlessFullscreenSuspended(hwnd, suspended)
    }
    DesktopBorderlessRootPaneFix.setActive(window, !suspended)
}

internal fun beginNativeCompactPlayerWindowMove(window: Window?) {
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || window?.isShowing != true) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.beginCompactPlayerWindowMove(hwnd)
    }
}

internal fun beginNativeCompactPlayerWindowResize(window: Window?, edge: Int) {
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || window?.isShowing != true || edge !in 1..8) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.beginCompactPlayerWindowResize(hwnd, edge)
    }
}

internal fun beginNativeCompactPlayerWindowInteraction(window: Window?, mode: Int) {
    if (DesktopHostOs.current == DesktopHostOs.MACOS && !SwingUtilities.isEventDispatchThread()) {
        SwingUtilities.invokeLater { beginNativeCompactPlayerWindowInteraction(window, mode) }
        return
    }
    if (DesktopHostOs.current == DesktopHostOs.MACOS && window?.isShowing == true && mode in 1..9) {
        val pointer = MouseInfo.getPointerInfo()?.location ?: return
        compactInteraction = CompactInteraction(window, mode, pointer, Rectangle(window.bounds))
        return
    }
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || window?.isShowing != true || mode !in 1..9) return
    if (mode == 1) {
        beginNativeCompactPlayerWindowMove(window)
    } else {
        beginNativeCompactPlayerWindowResize(window, mode - 1)
    }
}

internal fun updateNativeCompactPlayerWindowInteraction(window: Window?) {
    if (DesktopHostOs.current == DesktopHostOs.MACOS && !SwingUtilities.isEventDispatchThread()) {
        SwingUtilities.invokeLater { updateNativeCompactPlayerWindowInteraction(window) }
        return
    }
    if (DesktopHostOs.current == DesktopHostOs.MACOS) {
        val interaction = compactInteraction?.takeIf { it.window === window } ?: return
        val pointer = MouseInfo.getPointerInfo()?.location ?: return
        window?.bounds = compactInteractionBounds(interaction.bounds, interaction.mode,
            pointer.x - interaction.pointer.x, pointer.y - interaction.pointer.y)
        return
    }
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || window?.isShowing != true) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.updateCompactPlayerWindowInteraction(hwnd)
    }
}

internal fun endNativeCompactPlayerWindowInteraction(window: Window?) {
    if (DesktopHostOs.current == DesktopHostOs.MACOS && !SwingUtilities.isEventDispatchThread()) {
        SwingUtilities.invokeLater { endNativeCompactPlayerWindowInteraction(window) }
        return
    }
    if (DesktopHostOs.current == DesktopHostOs.MACOS) {
        updateNativeCompactPlayerWindowInteraction(window)
        compactInteraction = null
        return
    }
    if (DesktopHostOs.current != DesktopHostOs.WINDOWS || window?.isShowing != true) return

    runCatching {
        val hwnd = AwtNativeViewResolver.resolveNativeViewPointer(window)
        NativePlayerBridge.endCompactPlayerWindowInteraction(hwnd)
    }
}

private data class CompactInteraction(val window: Window, val mode: Int, val pointer: Point, val bounds: Rectangle)
private var compactInteraction: CompactInteraction? = null

internal fun compactInteractionBounds(bounds: Rectangle, mode: Int, dx: Int, dy: Int): Rectangle {
    if (mode == 1) return Rectangle(bounds.x + dx, bounds.y + dy, bounds.width, bounds.height)
    val edge = mode - 1
    val left = edge in setOf(1, 4, 7)
    val right = edge in setOf(2, 5, 8)
    val top = edge in setOf(3, 4, 5)
    val bottom = edge in setOf(6, 7, 8)
    val width = (bounds.width + if (left) -dx else if (right) dx else 0).coerceAtLeast(240)
    val height = (bounds.height + if (top) -dy else if (bottom) dy else 0).coerceAtLeast(135)
    return Rectangle(if (left) bounds.x + bounds.width - width else bounds.x,
        if (top) bounds.y + bounds.height - height else bounds.y, width, height)
}
