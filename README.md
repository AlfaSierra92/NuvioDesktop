<div align="center">
  <img src="composeApp/src/desktopMain/resources/icons/nuvio-app-icon.png" alt="Nuvio HTPC" width="96" />
  <h1>Nuvio HTPC</h1>
  <p>A desktop media client for Windows and macOS, for desk and couch.</p>
</div>

Nuvio HTPC is an independent fork of [Nuvio Desktop](https://github.com/NuvioMedia/NuvioDesktop).
It browses metadata, manages libraries and watch progress, and plays media from
user-installed extensions, local folders and user-provided sources. This fork is
not affiliated with the original Nuvio team.

[Documentation](Docs/README.md) · [macOS guide](Docs/macOS.md) ·
[Configuration](Docs/Configuration.md) · [Development](Docs/Development.md) ·
[Testing](Docs/Testing.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

[![Nuvio TV Mode Demo](https://img.youtube.com/vi/txiM8_y2aD8/maxresdefault.jpg)](https://youtu.be/txiM8_y2aD8)

## Installation and platform support

Use this fork's [releases](https://github.com/AlfaSierra92/NuvioDesktop/releases)
and [macOS workflow artifacts](https://github.com/AlfaSierra92/NuvioDesktop/actions/workflows/release-macos.yml)
when available. Packages from the original Nuvio repository are a different app
and do not necessarily contain this fork's fixes.

| Platform | Packaging and status |
|---|---|
| Windows | JVM application/MSI and a separate GraalVM native executable/ZIP build path. Native-image tooling requires Windows. |
| macOS Apple Silicon | JVM `.app` and `.dmg` with the Objective-C++/libmpv player and bundled native libraries. Local and loopback HTTP playback have been exercised. |
| macOS Intel | The build follows the host JDK architecture; Intel has not been verified. Universal binaries are not generated. |
| Linux | Gradle has a DEB target, but this repository does not establish full Linux feature parity. See the separate [Linux fork](https://github.com/iamSlokker/NuvioDesktop-Linux). |

For a macOS DMG, quit older copies, open the image and copy **Nuvio HTPC.app** to
Applications. Homebrew is needed to build the app, not to run its bundled player.
Local builds use ad hoc signing unless a signing identity is configured; Developer
ID signing and notarization are separate steps. See the [macOS guide](Docs/macOS.md).

## Features

### Home theatre and navigation

- Mouse, keyboard and controller navigation, TV Mode and fullscreen browsing.
- Game Mode with a game library and platform-specific executable/application launching.
- IPTV from an Xtream Codes or M3U provider, optional XMLTV guide, favourites,
  programme guide, channel switching and rewind controls. No channels are supplied.
- Smart-light integrations, idle dimming, optional automatic shutdown and display
  keep-awake during playback.
- Casting, including DLNA device playback; device and format compatibility vary.

### Discovery and metadata

- Adaptive heroes, trailers, metadata badges, configurable artwork and custom rows.
- Discovery from watch history, favourites, unfinished titles and custom criteria.
- Optional AI discovery with user-configured services.
- Calendars, random play, anime ID mappings and metadata enrichment.
- TMDB, TVDB, SIMKL, Trakt, MDBList and other integrations where configured.

### Library and downloads

- Local movie/series folders with automatic matching and manual corrections.
- Monitored downloads with schedules, concurrency and bandwidth controls.
- Debrid/cloud library integration, cached-source inspection and season-pack selection.
- Per-account settings plus machine-wide libraries and services; see
  [data locations and account boundaries](Docs/Configuration.md#data-locations-and-accounts).

### Playback

- libmpv player with custom options, buffering presets, source failover and playlists.
- Chapters, intro/outro skipping, dual subtitles, subtitle styling and synchronization.
- Seek thumbnails, AutoCrop, playback speed, volume boost and Picture-in-Picture.
- Direct URLs, local files, external players, watch-progress tracking and next episodes.
- HDR modes, colour profiles and anime shaders. NVIDIA RTX Video and Direct3D are
  Windows integrations. SVP requires a compatible external installation on macOS.
- Stream scoring based on quality, language, codec, cache status and other metadata.

### Customization

Themes, fonts, keyboard shortcuts, UI scale, settings favourites, artwork, badges,
provider preferences and player controls are configurable. Custom hero rules and
badge images are documented in [Configuration](Docs/Configuration.md#custom-hero-discovery-and-badges).
The design draws inspiration from Nuvio TV and Stremio Kai. IPTV builds on Slokker's
GoatTV; the corresponding features were incorporated with permission.

## macOS permissions and coexistence

The fork uses bundle ID `com.nuvio.htpc.desktop`, URL scheme `nuviohtpc://`, and
`~/Library/Application Support/NuvioHTPC` for ordinary file-backed data. Temporary
player resources use HTPC-specific names. It no longer deletes binaries from the
original app's temporary TorrServer directory.

The package declares local-network, protected-folder, network/removable-volume
and Apple Events usage descriptions. Native open/save panels cover folders,
backup/import, catalog import/export, game applications, external players and
subtitle saves. macOS owns the consent decision; previously denied access may
need to be enabled in System Settings. See [permissions](Docs/macOS.md#permissions).

The bundle/data separation does **not** establish complete login-session isolation:
Supabase currently uses its default desktop session manager outside the file-backed
data directory. The [configuration guide](Docs/Configuration.md#authentication-and-coexistence)
explains that remaining boundary.

## Build on macOS

Use a native JDK 21, Xcode Command Line Tools, Homebrew, Python 3, `mpv` and
`pkg-config`. Run from the repository root:

```bash
brew install mpv pkg-config
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
./gradlew --no-configuration-cache :composeApp:run

# Create a development .app or a release DMG
./gradlew --no-configuration-cache :composeApp:createDistributable
./gradlew --no-configuration-cache :composeApp:packageReleaseDmg
```

The development app is written to
`composeApp/build/compose/binaries/main/app/Nuvio HTPC.app`. The release app is in
`composeApp/build/compose/binaries/main-release/app/`; release DMGs are under
`composeApp/build/compose/binaries/main-release/dmg/`.

The [macOS guide](Docs/macOS.md) covers the optional Nuvio Engine, MPVKit, signing,
notarization and troubleshooting. The [development guide](Docs/Development.md)
covers Windows, service configuration, native builds and release workflow details.
`--no-configuration-cache` avoids known incompatibilities in the current custom tasks.

## Verification and troubleshooting

A strict local HTTP regression verifies intact headers and actual playback,
including redirects and an optional run of the packaged app:

```bash
python3 scripts/test-macos-http-headers.py \
  --app "composeApp/build/compose/binaries/main/app/Nuvio HTPC.app"
```

Other targeted tests, the native feature harness, HDR/PiP smoke checks, log locations
and the limits of loopback testing are in [Testing](Docs/Testing.md) and the
[macOS troubleshooting guide](Docs/macOS.md#troubleshooting).

An HTTP `400 Bad Request` is a server response, not proof of a denied network
permission. The macOS bridge now passes headers as a native libmpv list, preserving
commas in browser User-Agents and literal backslashes. This fix was verified with a
strict test server; any particular provider or NAS still needs its own end-to-end test.

## Project layout and versions

- `composeApp/src/commonMain/`: shared UI, features, repositories and protocols.
- `composeApp/src/desktopMain/`: desktop Kotlin, native bridges and resources.
- `composeApp/src/desktopTest/`: desktop tests and native harnesses.
- `composeApp/Configuration/DesktopVersion.properties`: desktop version/build code.
- `composeApp/native-image/`: Windows GraalVM reachability metadata and rationale.
- `scripts/`: build helpers and playback validation.
- `Docs/`: maintained guides, port status and external protocol references.

Read the current version from the version file or run:

```bash
./scripts/set-version.sh --show
```

Do not infer the installed version from an example command or an unreleased entry.
See [versioning](Docs/Development.md#versioning-and-releases) before changing it.

## License and media sources

The repository is distributed under [GPL-3.0](LICENSE), with separate notices for
bundled third-party components. Nuvio HTPC is a client; users provide their own
sources and are responsible for having permission to access the media. It does not
supply a media catalogue of playable content or operate a media hosting service.
Upstream's [legal page](https://nuvioapp.space/legal) describes the original project;
it is not a statement of affiliation with this fork.
