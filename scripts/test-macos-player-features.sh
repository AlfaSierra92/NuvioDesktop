#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="$repo_root/composeApp/build/native/macos-feature-test"
mkdir -p "$work"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
java_home=${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=24:duration=30' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=30' \
    -vf 'pad=320:240:0:30:black' -c:v mpeg4 -c:a aac -shortest "$work/feature clip.mp4"
xcrun clang++ -std=c++17 -fobjc-arc -ObjC++ -mmacosx-version-min=11.0 \
    "$repo_root/composeApp/src/desktopTest/native/macos/player_features_test.mm" \
    "-I$java_home/include" "-I$java_home/include/darwin" \
    -framework Cocoa -framework Carbon -framework CoreGraphics -framework IOKit -framework OpenGL \
    -framework QuartzCore -framework WebKit -framework Metal -framework Security \
    -framework GameController -framework MediaPlayer \
    $(pkg-config --cflags --libs mpv) -o "$work/player_features_test"
exec "$work/player_features_test" "$work/feature clip.mp4" "$work/speech.f32"
