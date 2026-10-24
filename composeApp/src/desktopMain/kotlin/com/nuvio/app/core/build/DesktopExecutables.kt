package com.nuvio.app.core.build

import java.io.File

/** Finder launches have a minimal PATH, so explicitly include the two Homebrew prefixes. */
internal fun desktopExecutableDirectories(
    osName: String = System.getProperty("os.name").orEmpty(),
    environment: (String) -> String? = System::getenv,
): List<File> = buildList {
    environment("PATH").orEmpty().split(File.pathSeparatorChar).filter(String::isNotBlank).forEach { add(File(it)) }
    if (!osName.startsWith("Windows", ignoreCase = true)) {
        add(File("/opt/homebrew/bin"))
        add(File("/usr/local/bin"))
        add(File("/opt/local/bin"))
        add(File("/usr/bin"))
    }
}.distinct()

internal fun applicationBundleExecutable(bundle: File, names: List<String>): File? =
    if (bundle.isDirectory && bundle.extension.equals("app", ignoreCase = true)) {
        names.asSequence().map { File(bundle, "Contents/MacOS/$it") }.firstOrNull { it.isFile && it.canExecute() }
    } else null
