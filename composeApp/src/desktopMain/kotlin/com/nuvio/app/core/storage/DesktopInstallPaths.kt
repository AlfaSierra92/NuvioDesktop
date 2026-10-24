package com.nuvio.app.core.storage

import java.nio.file.Path
import java.util.Locale

/** Only the jpackage layout qualifies; never mistake an arbitrary ancestor for our bundle. */
internal fun macosAppBundle(launcher: Path): Path? {
    val executableDirectory = launcher.parent ?: return null
    val contents = executableDirectory.parent ?: return null
    val bundle = contents.parent ?: return null
    return bundle.takeIf {
        executableDirectory.fileName.toString() == "MacOS" &&
            contents.fileName.toString() == "Contents" &&
            it.fileName.toString().endsWith(".app", ignoreCase = true)
    }
}

internal fun desktopPortableInstallRoot(launcher: Path, osName: String): Path? =
    if (osName.lowercase(Locale.ROOT).contains("mac")) {
        // Keep both the marker and data outside the signed bundle, in a dedicated directory
        // rather than sharing /Applications/data between unrelated installations.
        macosAppBundle(launcher)?.let { bundle ->
            bundle.resolveSibling(bundle.fileName.toString().dropLast(4) + ".portable")
        }
    } else {
        launcher.parent
    }

/** Used by ordinary startup AND both directions of a portable migration. */
internal fun desktopInstalledDataDirectory(
    osName: String,
    userHome: Path,
    environment: (String) -> String? = System::getenv,
): Path = when {
    osName.contains("mac", ignoreCase = true) -> userHome.resolve("Library/Application Support/NuvioHTPC")
    osName.contains("win", ignoreCase = true) ->
        (environment("LOCALAPPDATA")?.takeIf(String::isNotBlank)?.let(Path::of)
            ?: userHome.resolve("AppData/Local")).resolve("NuvioHTPC")
    else -> (environment("XDG_CONFIG_HOME")?.takeIf(String::isNotBlank)?.let(Path::of)
        ?: userHome.resolve(".config")).resolve("nuviohtpc")
}
