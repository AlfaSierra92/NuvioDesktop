package com.nuvio.app.features.plugins

import co.touchlab.kermit.Logger
import java.io.File

/**
 * Points quickjs-kt at the patched native library the app builds and ships (src/desktopMain/native/quickjs-kt,
 * `buildWindowsQuickJs` / `buildMacosQuickJs`) instead of the copy inside its jar, which leaks a JNI local reference
 * set per binding call; see the README there. Uses the library's own loader property, so nothing
 * else about loading changes. Resolution mirrors nuvio_engine.dll's: beside the app runtime first,
 * then the Gradle output for `gradlew run`. A property already set (the test task sets it) wins.
 * Without any candidate the jar's copy loads exactly as before.
 *
 * Must run before the first `QuickJs.create`, which loads the library once per process.
 */
internal object QuickJsNativeLibrary {
    const val LIBRARY_PATH_PROPERTY = "com.dokar.quickjs.library.path"
    val LIBRARY_FILE_NAME: String get() = if (System.getProperty("os.name").contains("mac", ignoreCase = true)) "libquickjs.dylib" else "libquickjs.dll"

    @Volatile
    private var selected = false

    @Synchronized
    fun select() {
        if (selected) return
        selected = true
        val configured = System.getProperty(LIBRARY_PATH_PROPERTY)?.takeIf { it.isNotBlank() }
        if (configured != null) {
            Logger.withTag("PluginRuntime").i { "QuickJS library from $configured (preset)" }
            return
        }
        val library = candidates().firstOrNull(File::isFile)
        if (library == null) {
            Logger.withTag("PluginRuntime").w { "Patched $LIBRARY_FILE_NAME not found; using quickjs-kt's bundled copy" }
            return
        }
        System.setProperty(LIBRARY_PATH_PROPERTY, library.absoluteFile.parentFile.absolutePath)
        Logger.withTag("PluginRuntime").i { "QuickJS library: ${library.absolutePath}" }
    }

    private fun candidates(): List<File> {
        val macos = System.getProperty("os.name").contains("mac", ignoreCase = true)
        val platform = if (macos) "macos" else "windows"
        val home = System.getProperty("java.home")?.let(::File)
        val directory = if (macos) home?.parentFile?.parentFile?.parentFile?.resolve("app/native") else home?.parentFile
        val packaged = directory?.resolve(LIBRARY_FILE_NAME)

        if (!com.nuvio.app.core.build.DesktopDevRun.allowsLocalNativeBuilds) return listOfNotNull(packaged)
        return listOfNotNull(
            packaged,
            File("composeApp/build/native/$platform/$LIBRARY_FILE_NAME"),
            File("build/native/$platform/$LIBRARY_FILE_NAME"),
        )
    }
}
