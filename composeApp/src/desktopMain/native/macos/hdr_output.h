#pragma once

enum class MacosHdrMode { Auto, Tonemap, Passthrough };

struct MacosHdrOutput {
    bool extendedRange;
    const char *primaries;
    const char *transfer;
    const char *targetContrast;
};

// Rendered pixels and the Core Animation layer must use the same encoding.
// Passthrough cannot turn an SDR source or an SDR display into HDR.
inline MacosHdrOutput macosHdrOutput(MacosHdrMode mode, bool hdrSource, double headroom, bool oled = false) {
    const bool hdr = mode != MacosHdrMode::Tonemap && hdrSource && headroom > 1.0;
    // Match the shared display-panel setting while keeping LCD defaults output-dependent.
    const char *contrast = oled ? "inf" : (hdr ? "auto" : "1000");
    return hdr ? MacosHdrOutput{true, "bt.2020", "pq", contrast}
               : MacosHdrOutput{false, "bt.709", "srgb", contrast};
}
