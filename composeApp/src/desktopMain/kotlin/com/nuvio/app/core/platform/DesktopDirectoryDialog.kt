package com.nuvio.app.core.platform

import java.awt.Dialog
import java.awt.FileDialog
import java.awt.Frame
import java.awt.KeyboardFocusManager
import java.io.File
import javax.swing.JFileChooser
import javax.swing.SwingUtilities

internal val usesMacosNativeFileDialogs: Boolean
    get() = System.getProperty("os.name").contains("mac", ignoreCase = true)

/** Call on the EDT. macOS's native panel grants access to the selected folder via Powerbox. */
internal fun chooseDesktopDirectory(title: String, initialDirectory: String? = null): String? {
    check(SwingUtilities.isEventDispatchThread())
    if (!usesMacosNativeFileDialogs) {
        val chooser = JFileChooser(initialDirectory).apply {
            fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
            dialogTitle = title
            isMultiSelectionEnabled = false
        }
        return if (chooser.showOpenDialog(null) == JFileChooser.APPROVE_OPTION) {
            chooser.selectedFile?.absolutePath
        } else null
    }

    return showMacosFileDialog(title, FileDialog.LOAD, initialDirectory?.let(::File), true, emptySet())?.absolutePath
}

/** Native open/save panels let macOS authorize access to the resource the user selects. */
internal fun chooseMacosFile(
    title: String,
    save: Boolean = false,
    initialFile: File? = null,
    extensions: Set<String> = emptySet(),
): File? {
    check(usesMacosNativeFileDialogs)
    var selected: File? = null
    val show = Runnable {
        selected = showMacosFileDialog(title, if (save) FileDialog.SAVE else FileDialog.LOAD,
            initialFile, false, extensions)
    }
    if (SwingUtilities.isEventDispatchThread()) show.run() else SwingUtilities.invokeAndWait(show)
    return selected
}

private fun showMacosFileDialog(
    title: String,
    mode: Int,
    initialFile: File?,
    directoriesOnly: Boolean,
    extensions: Set<String>,
): File? {
    // Restore this process-wide flag even on cancellation/failure, so folder selection
    // cannot change a subsequent open/save panel into another folder picker.
    val property = "apple.awt.fileDialogForDirectories"
    val previous = System.getProperty(property)
    val packagesProperty = "apple.awt.use-file-dialog-packages"
    val previousPackages = System.getProperty(packagesProperty)
    System.setProperty(property, directoriesOnly.toString())
    // AWT otherwise navigates into .app bundles instead of letting the user select one.
    if (!directoriesOnly) System.setProperty(packagesProperty, "true")
    var dialog: FileDialog? = null
    return try {
        val owner = KeyboardFocusManager.getCurrentKeyboardFocusManager().activeWindow
        val panel = when (owner) {
            is Frame -> FileDialog(owner, title, mode)
            is Dialog -> FileDialog(owner, title, mode)
            else -> FileDialog(null as Frame?, title, mode)
        }
        dialog = panel
        val initialIsDirectory = initialFile?.isDirectory == true && !initialFile.extension.equals("app", true)
        panel.directory = if (initialIsDirectory) initialFile?.absolutePath else initialFile?.parent
        if (!directoriesOnly && !initialIsDirectory) panel.file = initialFile?.name
        // FileDialog keeps directories navigable itself. Avoid reading resources from a
        // filter callback, before the user has selected and authorized them.
        if (extensions.isNotEmpty()) panel.setFilenameFilter { _, name ->
            extensions.any { name.endsWith(".$it", ignoreCase = true) }
        }
        panel.isMultipleMode = false
        panel.isVisible = true
        panel.files.firstOrNull()
    } finally {
        dialog?.dispose()
        if (previous == null) System.clearProperty(property) else System.setProperty(property, previous)
        if (previousPackages == null) System.clearProperty(packagesProperty)
        else System.setProperty(packagesProperty, previousPackages)
    }
}
