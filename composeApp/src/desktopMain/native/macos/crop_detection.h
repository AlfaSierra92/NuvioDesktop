#pragma once
#include <algorithm>
#include <cstdint>
struct AutoCropBars {
    double top = 0.0, bottom = 0.0, left = 0.0, right = 0.0;
};

// Finds the black bars baked into one packed frame from screenshot-raw (bytesPerPixel 4 for
// bgr0/rgb0-style formats, 8 for rgba64). Each edge is walked inwards until a row/column has
// more than a couple of bright samples (logos and noise are tolerated). Bars are made symmetric
// (only what both sides agree on is trimmed) and hairlines are dropped. Returns false when the
// frame cannot be judged, e.g. a fade to black.
static bool detectAutoCropBars(const uint8_t *data, int64_t width, int64_t height, int64_t stride,
                               int bytesPerPixel, AutoCropBars &out) {
    constexpr int threshold = 16;  // 0-255; at or below counts as black
    constexpr int samples = 64;    // probes per row/column, across the middle 90% of the other axis
    constexpr int stray = 2;       // bright probes tolerated per row/column
    constexpr double minimumBar = 0.012;
    if (!data || width < 64 || height < 64 || stride < width * bytesPerPixel) return false;

    auto bright = [&](int64_t x, int64_t y) {
        const uint8_t *pixel = data + y * stride + x * bytesPerPixel;
        if (bytesPerPixel == 8) {
            // 16-bit little-endian channels: the high byte is enough at this threshold.
            return pixel[1] > threshold || pixel[3] > threshold || pixel[5] > threshold;
        }
        // Channel order doesn't matter: any of the three colour bytes being bright is picture.
        return pixel[0] > threshold || pixel[1] > threshold || pixel[2] > threshold;
    };
    auto probe = [](int64_t span, int index) {
        return (int64_t)(span * (0.05 + 0.90 * (index + 0.5) / samples));
    };
    auto rowHasPicture = [&](int64_t y) {
        int hits = 0;
        for (int i = 0; i < samples; ++i) {
            if (bright(probe(width, i), y) && ++hits > stray) return true;
        }
        return false;
    };
    auto columnHasPicture = [&](int64_t x, int64_t top, int64_t bottom) {
        int hits = 0;
        const int64_t span = bottom - top;
        for (int i = 0; i < samples; ++i) {
            const int64_t y = top + (int64_t)(span * (i + 0.5) / samples);
            if (bright(x, y) && ++hits > stray) return true;
        }
        return false;
    };

    int64_t top = 0;
    while (top < height && !rowHasPicture(top)) ++top;
    if (top >= height) return false;
    int64_t bottom = height;
    while (bottom > top && !rowHasPicture(bottom - 1)) --bottom;
    int64_t left = 0;
    while (left < width && !columnHasPicture(left, top, bottom)) ++left;
    if (left >= width) return false;
    int64_t right = width;
    while (right > left && !columnHasPicture(right - 1, top, bottom)) --right;

    double vertical = std::min((double)top / height, (double)(height - bottom) / height);
    double horizontal = std::min((double)left / width, (double)(width - right) / width);
    if (vertical < minimumBar) vertical = 0.0;
    if (horizontal < minimumBar) horizontal = 0.0;
    out.top = out.bottom = vertical;
    out.left = out.right = horizontal;
    return true;
}
