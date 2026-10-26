// Exercise the production header configuration against a strict local HTTP server.
#include "../../../desktopMain/native/macos/player_bridge.mm"
#include <chrono>
#include <cstdio>

int main(int argc, const char **argv) {
    if (argc != 2) return 2;
    @autoreleasepool {
        mpv_handle *player = mpv_create();
        if (!player) return 2;
        for (const auto &option : std::vector<std::pair<const char *, const char *>>{
            {"config", "no"}, {"terminal", "no"}, {"load-scripts", "no"},
            {"ytdl", "no"}, {"vo", "null"}, {"ao", "null"}, {"network-timeout", "5"}}) {
            mpv_set_option_string(player, option.first, option.second);
        }
        setMpvHttpHeaders(player, @[
            @"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            @"Accept: video/*, application/octet-stream",
            @"X-Nuvio-Test: comma,value\\path",
        ]);
        if (mpv_initialize(player) < 0) {
            mpv_terminate_destroy(player);
            return 2;
        }
        const char *load[] = {"loadfile", argv[1], nullptr};
        bool failed = mpv_command(player, load) < 0;
        bool loaded = false;
        bool advanced = false;
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        while (!failed && !advanced && std::chrono::steady_clock::now() < deadline) {
            mpv_event *event = mpv_wait_event(player, 0.1);
            if (event->event_id == MPV_EVENT_FILE_LOADED) loaded = true;
            if (event->event_id == MPV_EVENT_END_FILE) {
                auto *end = static_cast<mpv_event_end_file *>(event->data);
                if (end->reason == MPV_END_FILE_REASON_ERROR) failed = true;
            }
            double position = 0;
            advanced = mpv_get_property(player, "time-pos", MPV_FORMAT_DOUBLE, &position) >= 0 && position >= 0.5;
        }
        mpv_terminate_destroy(player);
        if (failed || !loaded || !advanced) {
            std::fprintf(stderr, "HTTP playback failed: loaded=%d advanced=%d error=%d\n", loaded, advanced, failed);
            return 1;
        }
        std::puts("PASS: native HTTP playback loads and advances with comma/backslash headers");
    }
}
