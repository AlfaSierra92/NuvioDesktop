package com.nuvio.app.features.locallibrary

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.nuvio.app.core.platform.chooseDesktopDirectory
import javax.swing.SwingUtilities
import javax.swing.UIManager

internal actual object LocalDirectoryPicker {

    actual suspend fun pick(): String? = withContext(Dispatchers.IO) {
        val holder = arrayOfNulls<String>(1)
        val run = Runnable {
            runCatching { UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName()) }
            holder[0] = chooseDesktopDirectory("Choose a media folder")
        }
        if (SwingUtilities.isEventDispatchThread()) run.run() else SwingUtilities.invokeAndWait(run)
        holder[0]
    }
}
