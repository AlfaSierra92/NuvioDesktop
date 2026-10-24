package com.nuvio.app.features.locallibrary

import java.nio.file.Files
import java.nio.file.Path

internal actual fun localLibraryPathsEqual(first: String, second: String): Boolean = first == second ||
    runCatching { Files.isSameFile(Path.of(first), Path.of(second)) }.getOrDefault(false)
