# Testing and diagnostics

[Documentation index](README.md) · [macOS troubleshooting](macOS.md#troubleshooting)

Run commands from the repository root on a prepared host. Use
`--no-configuration-cache` with the current custom Gradle tasks. Native/JNI tests
can require built native libraries; a successful compile does not establish
runtime parity on every OS.

## Targeted desktop tests

Bundle paths, JNI linkage, scrolling, application links and LAN URL policy:

```bash
./gradlew --no-configuration-cache :composeApp:desktopTest \
  --tests '*MacosPlayerJniTest' \
  --tests '*NativeRuntimeLayoutTest' \
  --tests '*MacosNativeScrollTest' \
  --tests '*DesktopOpenUriTest' \
  --tests '*PlaybackSourcePolicyTest' \
  --tests '*PlaybackRedirectResolverTest'
```

Settings backup content, game launch targets and application-bundle resolution:

```bash
./gradlew --no-configuration-cache :composeApp:desktopTest \
  --tests '*DesktopSettingsBackupTest' \
  --tests '*GameLauncherTest' \
  --tests '*GameLaunchTargetTest' \
  --tests '*DesktopExecutablesTest'
```

Native-image metadata tests are `*NativeImageMetadataTest` and
`*NativeImageReflectionCheckTest`. These validate Windows GraalVM metadata;
they are not macOS permission or native-playback tests. For a broader desktop run:

```bash
./gradlew --no-configuration-cache :composeApp:desktopTest
```

Reports are under `composeApp/build/reports/tests/desktopTest/`; machine-readable
results are under `composeApp/build/test-results/desktopTest/`. Record the exact
suite/command and platform rather than treating a targeted pass as a full-suite pass.

## Native macOS feature harness

```bash
sh scripts/test-macos-player-features.sh
```

This generates a synthetic clip with audio and black bars, builds against the real
bridge/libmpv, opens a test window and checks PiP state restoration, seek thumbnails,
audio samples, AutoCrop and Now Playing cleanup. Compiler/player output is kept
under `composeApp/build/native/macos-feature-test`. It needs the same JDK/Xcode/
libmpv toolchain as the native build plus ffmpeg.

## Strict HTTP playback regression

```bash
python3 scripts/test-macos-http-headers.py

# Also exercise the development .app with a temporary file-backed profile
python3 scripts/test-macos-http-headers.py \
  --app "composeApp/build/compose/binaries/main/app/Nuvio HTPC.app"
```

The script compiles the production header-setting helper into a native harness,
creates media with ffmpeg and starts a strict server on `127.0.0.1`. It verifies
that User-Agent/Accept/custom headers keep commas and backslashes, then checks
loading and advancing playback directly and through a redirect. `--app` also runs
the actual packaged player with its default browser User-Agent. Its compile log
and generated media are under `composeApp/build/native/macos-http-test/`.

This catches the malformed-header `400 Bad Request` regression. Loopback playback
does **not** exercise a real LAN consent prompt, a provider's authorization, a
self-signed TLS configuration, a NAS or a receiver. Test those separately.

## Packaged playback, HDR and PiP

Build the intended app first. The smoke script defaults to the release `.app`;
pass `--app` to use a development or installed copy:

```bash
python3 scripts/smoke-macos-player.py /path/to/video.mp4 \
  --app "composeApp/build/compose/binaries/main/app/Nuvio HTPC.app"

python3 scripts/smoke-macos-player.py /path/to/video.mp4 --hdr-cycle
python3 scripts/smoke-macos-player.py /path/to/video.mp4 --pip-cycle
python3 scripts/smoke-macos-player.py 'http://192.168.1.10:8096/video.mp4'
```

Use a clip long enough for the run (at least 40 seconds for the default 30-second
smoke check). `--seconds` changes the duration, with a minimum of 10. HDR input can
be required with `--expect-hdr-source`; it is meaningful alongside `--hdr-cycle`.
The script checks a single player creation, file-loaded/first-frame delivery,
advancing playhead, no backward jumps and no player/JNI errors. HDR and PiP flags
add their own checks. A temporary artifact directory containing `console.log` is
printed, and the test process is closed at the end.

The file-backed data directory is temporary. This does not imply that all external
library session storage or OS privacy state is isolated: see
[authentication boundaries](Configuration.md#authentication-and-coexistence).
Test actual consent from a Finder-launched installed app with the intended signing
identity. Do not grant broad access merely to make a test pass.

## Engine and optional integrations

Engine smoke/metadata/cache tests are described in the [engine guide](../composeApp/src/desktopMain/native/nuvio-engine/README.md).
Live network/seek probes are opt-in and use an explicitly provided infohash;
ordinary unit tests do not prove torrent-swarm throughput. QuickJS JNI stress is
covered by `*QuickJsBindingLocalRefTest` against the patched runtime selected by Gradle.

Physical controllers, receiver passthrough, HDR displays, real DLNA devices, SVP
installation compatibility and Finder permission prompts require their own
manual checks. Keep those results separate from synthetic/null-output playback.

## Reporting a problem

Include app version/commit, OS version, architecture, install/source-build method,
the action and expected/observed behavior, relevant log lines and the scope of
reproduction. For network failures include protocol/host type, port, direct versus
redirected playback and HTTP status, with credentials/tokens removed.

The normal log is `<data-root>/logs/nuvio.log`; macOS diagnostic reports, when
created, are in `~/Library/Logs/DiagnosticReports`. Distinguish a player returning
to browsing from the entire process terminating. Include a timestamp so the report
can be matched to a log. Avoid sharing whole settings backups or token-bearing URLs.
