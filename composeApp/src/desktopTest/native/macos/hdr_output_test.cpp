#include "hdr_output.h"
#include <cassert>
#include <cstring>
#include <initializer_list>

int main() {
    for (auto mode : {MacosHdrMode::Auto, MacosHdrMode::Tonemap, MacosHdrMode::Passthrough}) {
        const auto sdr = macosHdrOutput(mode, false, 4.0);
        assert(!sdr.extendedRange);
        assert(std::strcmp(sdr.transfer, "srgb") == 0);
        assert(std::strcmp(sdr.primaries, "bt.709") == 0);
        assert(!macosHdrOutput(mode, true, 1.0).extendedRange);
    }
    const auto initial = macosHdrOutput(MacosHdrMode::Auto, true, 4.0);
    assert(initial.extendedRange);
    assert(std::strcmp(initial.transfer, "pq") == 0);
    assert(std::strcmp(initial.primaries, "bt.2020") == 0);
    for (int i = 0; i < 20; ++i) {
        assert(!macosHdrOutput(MacosHdrMode::Tonemap, true, 4.0).extendedRange);
        assert(macosHdrOutput(MacosHdrMode::Passthrough, true, 4.0).extendedRange);
        const auto restored = macosHdrOutput(MacosHdrMode::Auto, true, 4.0);
        assert(restored.extendedRange == initial.extendedRange);
        assert(std::strcmp(restored.transfer, initial.transfer) == 0);
        assert(std::strcmp(restored.primaries, initial.primaries) == 0);
    }
    assert(!macosHdrOutput(MacosHdrMode::Auto, true, 1.0).extendedRange);
    assert(macosHdrOutput(MacosHdrMode::Auto, true, 2.0).extendedRange);
    // Panel changes must preserve colour encoding and survive repeated HDR/SDR transitions.
    for (int i = 0; i < 20; ++i) {
        for (auto mode : {MacosHdrMode::Auto, MacosHdrMode::Tonemap, MacosHdrMode::Passthrough}) {
            for (bool sourceHdr : {false, true}) {
                for (double headroom : {1.0, 4.0}) {
                    const auto lcd = macosHdrOutput(mode, sourceHdr, headroom, false);
                    const auto oled = macosHdrOutput(mode, sourceHdr, headroom, true);
                    assert(std::strcmp(oled.targetContrast, "inf") == 0);
                    assert(std::strcmp(lcd.targetContrast, lcd.extendedRange ? "auto" : "1000") == 0);
                    assert(lcd.extendedRange == oled.extendedRange);
                    assert(std::strcmp(lcd.primaries, oled.primaries) == 0);
                    assert(std::strcmp(lcd.transfer, oled.transfer) == 0);
                    const auto restored = macosHdrOutput(mode, sourceHdr, headroom, false);
                    assert(std::strcmp(restored.targetContrast, lcd.targetContrast) == 0);
                }
            }
        }
    }

}
