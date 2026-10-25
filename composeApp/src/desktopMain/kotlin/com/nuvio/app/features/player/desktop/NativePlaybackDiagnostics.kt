package com.nuvio.app.features.player.desktop

import co.touchlab.kermit.Logger

internal val nativePlaybackLog = Logger.withTag("NativePlayback")

/** Preserve the device/decoder warning without writing authenticated stream URLs to disk. */
internal fun nativePlaybackWarningText(event: String): String? {
    if (!event.startsWith("mpvWarning:")) return null
    return event.removePrefix("mpvWarning:")
        .replace(Regex("(?i)https?://[^\\s<>\"']+"), "<url>")
        .replace(Regex("[\\r\\n]+"), " ")
        .trim()
        .take(2048)
}
