package com.nuvio.engine.internal

import java.io.File

/**
 * Locates and loads the engine DLL/dylib. The packaged runtime is preferred; on macOS its
 * dependencies live in app/native/engine, isolated from the player runtime.
 * An explicit `-Dnuvio.engine.library=<abs path>` / `NUVIO_ENGINE_LIBRARY` wins over both.
 *
 * [isAvailable] is the cheap pre-check the P2P engine uses to decide between this backend and
 * TorrServer without triggering a load; [load] is what [NativeBridge]'s initializer calls.
 */
internal object NuvioEngineLibrary {
    val LIBRARY_FILE_NAME: String get() = if (System.getProperty("os.name").contains("mac", ignoreCase = true)) "libnuvio_engine.dylib" else "nuvio_engine.dll"

    @Volatile
    private var loadedFrom: File? = null

    /** The file that was, or would be, loaded; null when no candidate exists on disk. */
    fun resolve(): File? {
        loadedFrom?.let { return it }
        configuredPath()?.let { return it.takeIf(File::isFile) }
        return candidates().firstOrNull(File::isFile)
    }

    val isAvailable: Boolean
        get() = resolve() != null

    @Synchronized
    fun load() {
        if (loadedFrom != null) return
        val library = resolve()
            ?: throw UnsatisfiedLinkError(
                "$LIBRARY_FILE_NAME was not found in the packaged or development native runtime; " +
                    "build the native engine for this OS or pass -Dnuvio.engine.library=<path>",
            )
        System.load(library.absolutePath)
        loadedFrom = library
    }

    private fun configuredPath(): File? =
        (System.getProperty("nuvio.engine.library")?.takeIf { it.isNotBlank() }
            ?: System.getenv("NUVIO_ENGINE_LIBRARY")?.takeIf { it.isNotBlank() })
            ?.let(::File)

    private fun candidates(): List<File> {
        val macos = System.getProperty("os.name").contains("mac", ignoreCase = true)
        val platform = if (macos) "macos" else "windows"
        val home = System.getProperty("java.home")?.let(::File)
        val directory = if (macos) home?.parentFile?.parentFile?.parentFile?.resolve("app/native/engine") else home?.parentFile
        val packaged = directory?.resolve(LIBRARY_FILE_NAME)

        if (!com.nuvio.app.core.build.DesktopDevRun.allowsLocalNativeBuilds) return listOfNotNull(packaged)
        return listOfNotNull(
            packaged,
            File("composeApp/build/native/macos-engine-runtime/$LIBRARY_FILE_NAME"),
            File("build/native/macos-engine-runtime/$LIBRARY_FILE_NAME"),
            File("composeApp/build/native/$platform/$LIBRARY_FILE_NAME"),
            File("build/native/$platform/$LIBRARY_FILE_NAME"),
        )
    }
}
