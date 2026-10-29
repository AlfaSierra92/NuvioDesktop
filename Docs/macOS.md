# macOS guide

[Documentation index](README.md) · [Configuration](Configuration.md) · [Testing](Testing.md)

## Support and installation

Nuvio HTPC uses a JVM app bundle with a native Objective-C++/libmpv player. Apple
Silicon builds and playback have been exercised. Intel follows the architecture
of the build JDK and remains unverified; the build does not produce universal apps.

Download this fork's package when available, quit running copies, open the DMG and
copy **Nuvio HTPC.app** to Applications. Installing a package from the original
Nuvio repository does not install this fork's changes.

The bundled player and relocated libraries do not require Homebrew on the user's
machine. Optional integrations can still require external software: SVP needs its
own compatible installation, and casting paths that invoke ffmpeg/ffprobe need
those executables to be discoverable.

## Build

Use a native JDK 21, Xcode Command Line Tools, Python 3 and Homebrew:

```bash
# Install Command Line Tools if they are absent
xcode-select --install
brew install mpv pkg-config
export JAVA_HOME=$(/usr/libexec/java_home -v 21)

./gradlew --no-configuration-cache :composeApp:run
./gradlew --no-configuration-cache :composeApp:createDistributable
./gradlew --no-configuration-cache :composeApp:createReleaseDistributable
./gradlew --no-configuration-cache :composeApp:packageReleaseDmg
```

| Target | Output |
|---|---|
| `createDistributable` | `composeApp/build/compose/binaries/main/app/Nuvio HTPC.app` |
| `createReleaseDistributable` | `composeApp/build/compose/binaries/main-release/app/Nuvio HTPC.app` |
| `packageReleaseDmg` | `composeApp/build/compose/binaries/main-release/dmg/` |

Run commands from the repository root. The custom Gradle tasks are not all
configuration-cache compatible, so these examples disable that cache.

The build compiles the player bridge and patched QuickJS runtime, stages native
libraries and rewrites non-system load paths. An existing MPVKit installation can
be selected with `-Pnuvio.mpvkit.dir=/absolute/path/to/MPVKit`.

### Optional native P2P engine

Install CMake, OpenSSL development files and a C++20 toolchain supporting
`std::jthread`/`std::stop_token`. Follow the [engine guide](../composeApp/src/desktopMain/native/nuvio-engine/README.md)
for its pinned checkout and desktop patches, then build:

```bash
./gradlew --no-configuration-cache :composeApp:buildMacosNuvioEngine \
  -Pnuvio.engine.sourceDir=/absolute/path/to/nuvio-engine
```

When needed, supply a compatible LLVM/libc++ tree with
`-Pnuvio.macos.llvmHome=/absolute/path/to/llvm`. CMake may fetch engine dependencies.
The runtime is staged under `Contents/app/native/engine`, with dependency names
separated from the player's libraries. If no engine runtime is available,
playback falls back to TorrServer. An absent checkout does not remove previously
built engine outputs; account for that when validating a clean fallback build.

## Signing and notarization

These values are read from Gradle properties, environment variables, or
`local.properties`, in that order:

- `NUVIO_MACOS_SIGNING_IDENTITY`
- `NUVIO_MACOS_NOTARY_APPLE_ID`
- `NUVIO_MACOS_NOTARY_TEAM_ID`
- `NUVIO_MACOS_NOTARY_PASSWORD`

Without a configured identity, local builds are ad hoc signed. They are not
Developer ID signed or notarized. The current macOS release workflow explicitly
sets these values to empty, so its artifacts also should not be described as
notarized releases.

After native staging, jar processing and build-info writes, the build signs the
finished bundle and runs a strict recursive verification. Changing bundle contents
afterward invalidates the signature. To inspect a built app:

```bash
codesign --verify --deep --strict "composeApp/build/compose/binaries/main/app/Nuvio HTPC.app"
codesign -dv "composeApp/build/compose/binaries/main/app/Nuvio HTPC.app"
```

A valid ad hoc signature verifies bundle integrity; it does not establish Developer
ID identity or notarization. Apple recommends an Apple-issued identity for reliable
local-network permission tracking across builds; see [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
For a local build blocked by macOS, review its entry in System Settings > Privacy
& Security. Rebuild a modified bundle through Gradle instead of distributing an
app whose signature no longer verifies.

## Permissions

macOS makes the access decision when the relevant action occurs. Declaring a
purpose string does not grant access, and the app does not preapprove consent.

| Feature | Access and behavior |
|---|---|
| LAN streams, NAS servers, local addons and DLNA discovery/control | `NSLocalNetworkUsageDescription`; allow Local Network when macOS asks. |
| Desktop, Documents and Downloads | Purpose strings describe selected media, catalog and backup operations. |
| Network and removable volumes | Purpose strings cover selected media, games and backup files. |
| Open/save operations | Native macOS panels cover media/game folders, game applications, external players, settings backups/imports, catalog import/export and subtitle saves. |
| Optional idle shutdown | `NSAppleEventsUsageDescription` and the Automation entitlement; the shutdown event is sent only when the enabled countdown expires. Failure leaves the app open and offers guidance for denied Automation access. |

The file-dialog helper switches between file/folder modes, allows `.app` bundle
selection, and restores AWT dialog flags afterward, including cancellation.
Camera, microphone and screen capture APIs are not used by media decoding,
thumbnail generation or audio-based subtitle synchronization. Controller input
uses GameController rather than a new raw-Bluetooth implementation. No additional
camera/microphone/screen-capture purpose strings were added for these features.

If access was denied, review **System Settings > Privacy & Security > Local Network**,
**Files & Folders**, or **Automation**, as appropriate. Entries depend on which
operations have been attempted and the macOS version. Access to a selected file
may be inferred by the native panel without a separate folder-wide prompt.
See Apple's [file-access documentation](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdownloadsfolderusagedescription).

Test consent behavior by launching the installed `.app` from Finder. A process
launched from Terminal/Gradle can have different network/privacy attribution;
a successful loopback test does not prove that Finder will display a LAN prompt.

## Coexistence and data

| Item | Fork value |
|---|---|
| Finder/Dock name | `Nuvio HTPC` |
| Bundle identifier | `com.nuvio.htpc.desktop` |
| Registered application scheme | `nuviohtpc://` |
| Installed file-backed data | `~/Library/Application Support/NuvioHTPC` |
| Portable data | `Nuvio HTPC.portable/data` beside the app |
| Log | `<data-root>/logs/nuvio.log` |

On macOS/Linux, a legacy Nuvio directory is imported only if it contains a
fork-specific store. The fork uses separate temporary player resources and no
longer deletes the original app's temporary TorrServer binaries. It registers its
own URL scheme rather than claiming `nuvio://`.

These changes separate the bundle and file stores, but **do not guarantee separate
Supabase login sessions**. See [authentication boundaries](Configuration.md#authentication-and-coexistence)
before testing login/sign-out with both apps installed.

## Troubleshooting

### Stream information and platform-specific controls

During playback, click **Info** to toggle mpv's live stream diagnostics (codec,
resolution, frame rate, audio and cache/network details). In a narrow window it
can move into **More**. The same toggle is available as **MPV diagnostics** in the
right-click menu and through the configurable diagnostics keyboard shortcut.

The SVP control appears only when a compatible installation is available on
macOS. NVIDIA RTX Video, Direct3D renderer selection and Windows HDR interface
correction are Windows-only controls.

### A LAN URL fails to play

Check `<data-root>/logs/nuvio.log` around the selected source. Distinguish a server
response from a connection failure or a process crash:

- `HTTP error 400 Bad Request` means an HTTP response was received. The macOS bridge
  previously split headers on commas, including the comma in the default browser
  User-Agent. It now passes a native list to libmpv, preserving commas and literal
  backslashes in both playback and probe connections.
- Connection refusal, timeout or routing errors can involve the endpoint, port,
  network, firewall or Local Network consent. Check the exact address and macOS
  permission state before attributing them to the same header bug.
- `loading failed` followed by returning to browsing is a playback failure; it does
  not itself show that the process crashed. For process termination, include the
  matching macOS diagnostic report if one exists.

The HTTP fix was reproduced against a strict test server, with direct and
redirected media and advancing playback in the packaged app. A specific provider,
NAS, authentication setup or DLNA device still needs its own end-to-end validation.

### Folder, application or backup selection fails

Use the latest package and choose the resource again in its native panel. Review
Files & Folders for denied access. External players should be selected as `.app`
bundles or valid executables, not as Windows `.exe` files. The app resolves supported
bundles to their executable where needed. Include the operation and error text in
a report; do not solve a file-selection issue by assuming all privacy access is needed.

### Login or sync fails

Match `SUPABASE_URL`/`SUPABASE_ANON_KEY` to the intended backend and rebuild if build-time
configuration changed. An account on the original service is not automatically an
account on a self-hosted backend. Inspect the backend URL/error in the log after
redacting tokens. File-backed profiles and backend sessions have different storage
boundaries; see [Configuration](Configuration.md).

### Player or native runtime fails to load

Rebuild with dependencies matching the JDK architecture. Verify the bundle signature
and that `Contents/app/native` exists. Keep SVP libraries separate from the bundled
player runtime. See [Testing](Testing.md) for native/JNI and playback checks and
[port status](Windows-remnants-macOS-audit.md) for hardware validation limits.
