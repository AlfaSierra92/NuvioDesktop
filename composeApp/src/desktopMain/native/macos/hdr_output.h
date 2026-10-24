#pragma once

enum class MacosHdrMode { Auto, Tonemap, Passthrough };

struct MacosHdrOutput {
    bool extendedRange;
    const char *primaries;
    const char *transfer;
};

// Rendered pixels and the Core Animation layer must use the same encoding.
// Passthrough cannot turn an SDR source or an SDR display into HDR.
inline MacosHdrOutput macosHdrOutput(MacosHdrMode mode, bool hdrSource, double headroom) {
    const bool hdr = mode != MacosHdrMode::Tonemap && hdrSource && headroom > 1.0;
    return hdr ? MacosHdrOutput{true, "bt.2020", "pq"}
               : MacosHdrOutput{false, "bt.709", "srgb"};
}
