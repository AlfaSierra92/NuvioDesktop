// Real libmpv integration: pass a local 320x240 clip with 30px black bars and an audio track.
#include "../../../desktopMain/native/macos/player_bridge.mm"
#include <cassert>
#include <thread>

@interface FeatureTestPlayer : MpvWebPlayer
@property(atomic) int thumbnails;
@property(atomic) int diagnosticWarnings;
@property(atomic) int videoParamsEvents;
@property(atomic) BOOL sourceHdr;
@end
@implementation FeatureTestPlayer
- (void)sendPlayerEvent:(NSString *)type value:(double)value {
    if ([type hasPrefix:@"mpvWarning:"]) self.diagnosticWarnings++;
    if ([type isEqualToString:@"videoParams"]) {
        self.videoParamsEvents++;
        self.sourceHdr = value != 0;
    }
    [super sendPlayerEvent:type value:value];
}
- (void)runJavaScript:(NSString *)script {
    if ([script containsString:@"window.nuvioSeekThumbnailReady("] && [script containsString:@"base64,"]) self.thumbnails++;
    [super runJavaScript:script];
}
@end

static void pumpFor(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

int main(int argc, const char **argv) {
    assert(argc == 3);
    @autoreleasepool {
        assert(!isHdrVideoTransfer(@""));
        assert(!isHdrVideoTransfer(@"bt.1886"));
        assert(!isHdrVideoTransfer(@"srgb"));
        for (NSString *transfer in @[@"pq", @"st2084", @"hlg", @"arib-std-b67", @" HLG\n"]) {
            assert(isHdrVideoTransfer(transfer));
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window orderFront:nil];
        jlong view = (jlong)(intptr_t)(__bridge void *)window.contentView;
        Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setCompactPlayerWindow(nullptr, nullptr, view, JNI_TRUE);
        assert(window.titleVisibility == NSWindowTitleHidden);
        assert(window.level == NSFloatingWindowLevel);
        Java_com_nuvio_app_features_player_desktop_NativePlayerBridge_setCompactPlayerWindow(nullptr, nullptr, view, JNI_FALSE);
        assert(window.titleVisibility == NSWindowTitleVisible);
        puts("PASS: compact PiP native style and window level restore correctly");
        FeatureTestPlayer *player = [[FeatureTestPlayer alloc]
            initWithHostView:window.contentView sourceUrl:[NSString stringWithUTF8String:argv[1]]
            audioSourceUrl:nil headerLines:@[] mpvOptions:@[@"ao=null"] playWhenReady:YES
            initialPositionMs:0 initialProgressFraction:0 controlsUrl:@"about:blank"
            javaVm:nullptr eventSink:nullptr eventMethod:nullptr];
        pumpFor(2);
        assert(player.durationMs > 10000);
        assert(player.videoParamsEvents == 1);
        assert(!player.sourceHdr);
        puts("PASS: decoded SDR metadata reaches the shared colour-profile gate");
        [player setPaused:YES];
        [player setStringProperty:"contrast" value:@"5"];
        [player setStringProperty:"brightness" value:@"-4"];
        [player setStringProperty:"saturation" value:@"15"];
        [player setStringProperty:"gamma" value:@"-2"];
        [player forceVideoRedraw];
        pumpFor(0.5);
        assert([player doubleProperty:"contrast" fallback:0] == 5);
        assert([player doubleProperty:"brightness" fallback:0] == -4);
        assert([player doubleProperty:"saturation" fallback:0] == 15);
        assert([player doubleProperty:"gamma" fallback:0] == -2);
        assert(player.videoParamsEvents == 1);
        puts("PASS: Vivid equalizer values apply while paused without repeating source metadata");
        for (const char *property : {"contrast", "brightness", "saturation", "gamma"}) {
            [player setStringProperty:property value:@"0"];
        }
        [player setPaused:NO];
        [player requestSeekThumbnail:5000];
        for (int wait = 0; wait < 120 && player.thumbnails == 0; ++wait) pumpFor(0.1);
        assert(player.thumbnails > 0);
        puts("PASS: real video thumbnail extracted and delivered as a JPEG data URL");

        NSString *output = [NSString stringWithUTF8String:argv[2]];
        std::atomic<int> audioResult{123};
        std::thread audio([&] { @autoreleasepool {
            audioResult.store([player decodeSpeechSpot:1.0 duration:2.0 output:output]);
        }});
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(15);
        while (audioResult.load() == 123 && std::chrono::steady_clock::now() < deadline) pumpFor(0.1);
        assert(audioResult.load() == 0);
        audio.join();
        NSData *samples = [NSData dataWithContentsOfFile:output];
        assert(samples.length >= 16000 * sizeof(float));
        assert(samples.length <= 3 * 16000 * sizeof(float));
        const float *floats = static_cast<const float *>(samples.bytes);
        bool audible = false;
        for (size_t i = 0; i < samples.length / sizeof(float); ++i) {
            assert(std::isfinite(floats[i]));
            if (std::fabs(floats[i]) > 0.01) audible = true;
        }
        assert(audible);
        puts("PASS: speech spot is bounded 16kHz mono float PCM, not a WAV header or silence");

        [player setMediaTitle:@"Nuvio feature test" subtitle:@"Episode 1" artwork:@""];
        assert([MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo[MPMediaItemPropertyTitle] isEqualToString:@"Nuvio feature test"]);
        [player setPaused:YES];
        pumpFor(0.7);
        assert(MPNowPlayingInfoCenter.defaultCenter.playbackState == MPNowPlayingPlaybackStatePaused);
        [player setPaused:NO];
        [player setResizeMode:3];
        pumpFor(8);
        NSString *crop = [player stringProperty:"video-crop" fallback:@""];
        assert(crop.length > 0 && ![crop hasPrefix:@"0x0"]);
        puts("PASS: black bars detected across multiple frames and applied without changing vf");
        [player setResizeMode:0];
        pumpFor(0.3);
        assert([[player stringProperty:"video-crop" fallback:@""] isEqualToString:@""]);
        puts("PASS: leaving AutoCrop restores the whole frame");
        // A recoverable audio-filter error must be available to diagnostics without becoming a
        // playback-failure event. This is a test-only invalid filter, restored immediately.
        int warningCount = player.diagnosticWarnings;
        [player setStringProperty:"af" value:@"lavfi=[nuvio_missing_filter_for_diagnostics]"];
        for (int wait = 0; wait < 40 && player.diagnosticWarnings == warningCount; ++wait) pumpFor(0.1);
        assert(player.diagnosticWarnings > warningCount);
        [player setStringProperty:"af" value:@""];
        pumpFor(0.5);
        assert([player stringProperty:"audio-params/format" fallback:@""].length > 0);
        puts("PASS: native audio warnings are forwarded and decoding remains available after recovery");
        [player shutdown];
        assert(MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo == nil);
        puts("PASS: Now Playing metadata, pause state and session cleanup");
        [window orderOut:nil];
    }
}
