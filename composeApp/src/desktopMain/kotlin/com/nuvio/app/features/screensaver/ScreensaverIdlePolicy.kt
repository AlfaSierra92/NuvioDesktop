package com.nuvio.app.features.screensaver

internal data class ScreensaverIdleDecision(
    val dim: Boolean = false,
    val countdownStartedAtMs: Long? = null,
    val countdownRemainingSeconds: Int? = null,
) {
    val shutdownDue: Boolean get() = countdownRemainingSeconds?.let { it <= 0 } == true
}

/** Pure timer policy: system actions stay outside this function. Times use a monotonic clock. */
internal fun screensaverIdleDecision(
    settings: ScreensaverSettings,
    playerActive: Boolean,
    windowShowing: Boolean,
    foreground: Boolean,
    shutdownAvailable: Boolean,
    idleMs: Long,
    nowMs: Long,
    countdownStartedAtMs: Long?,
): ScreensaverIdleDecision {
    if (!settings.anyActionEnabled || !windowShowing || (playerActive && !settings.activeDuringPlayback)) {
        return ScreensaverIdleDecision()
    }
    val shutdown = shutdownAvailable && foreground && settings.shutdownEnabled &&
        idleMs >= settings.shutdownDelayMinutes(playerActive) * 60_000L
    val start = if (shutdown) countdownStartedAtMs ?: nowMs else null
    return ScreensaverIdleDecision(
        dim = settings.enabled && idleMs >= settings.dimDelayMinutes(playerActive) * 60_000L,
        countdownStartedAtMs = start,
        countdownRemainingSeconds = start?.let {
            SCREENSAVER_SHUTDOWN_COUNTDOWN_SECONDS - ((nowMs - it).coerceAtLeast(0L) / 1_000L).toInt()
        },
    )
}
