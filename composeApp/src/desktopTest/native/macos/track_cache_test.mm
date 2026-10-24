// Integration harness: compile against Homebrew libmpv and the JDK's JNI headers.
// Arguments: local video containing at least two audio tracks, local SRT subtitle.
#include "../../../desktopMain/native/macos/player_bridge.mm"
#include <cassert>

@interface TrackCacheTestPlayer : MpvWebPlayer
@property(atomic) int trackReads;
@end
@implementation TrackCacheTestPlayer
- (NSString *)tracksJsonForType:(NSString *)type {
    self.trackReads++;
    return [super tracksJsonForType:type];
}
@end

static void pump(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (until.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

static NSArray *tracks(NSString *json) {
    return [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]
                                         options:0 error:nil];
}

int main(int argc, const char **argv) {
    assert(argc == 3);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        [window orderFront:nil];
        TrackCacheTestPlayer *player = [[TrackCacheTestPlayer alloc]
            initWithHostView:window.contentView sourceUrl:[NSString stringWithUTF8String:argv[1]]
            audioSourceUrl:nil headerLines:@[] mpvOptions:@[@"ao=null"] playWhenReady:YES
            initialPositionMs:0 initialProgressFraction:0 controlsUrl:@"about:blank"
            javaVm:nullptr eventSink:nullptr eventMethod:nullptr];
        pump(3);
        NSArray *audio = tracks(player.audioTracksJson);
        assert(audio.count == 2);
        int reads = player.trackReads;
        // Hundreds of JNI-style getters and multiple timer ticks must not re-read mpv tracks.
        for (int i = 0; i < 100; i++) {
            assert(tracks(player.audioTracksJson).count == 2);
            (void)player.subtitleTracksJson;
        }
        pump(1.5);
        assert(player.trackReads == reads);
        puts("PASS: stable playback and repeated getters reuse cached track lists");

        NSString *secondId = audio[1][@"id"];
        assert([player selectAudioTrackId:secondId.intValue]);
        pump(1);
        NSArray *selectedAudio = tracks(player.audioTracksJson);
        assert([selectedAudio[1][@"selected"] boolValue]);
        assert(![selectedAudio[0][@"selected"] boolValue]);
        puts("PASS: audio selection invalidates the cached selection");

        [player addSubtitleUrl:[NSString stringWithUTF8String:argv[2]]];
        pump(1);
        assert(tracks(player.subtitleTracksJson).count == 1);
        [player removeExternalSubtitles];
        pump(1);
        assert(tracks(player.subtitleTracksJson).count == 0);
        puts("PASS: adding and removing external subtitles updates cached tracks");

        [player shutdown];
        [window orderOut:nil];
    }
    return 0;
}
