# Configuration and data

[Documentation index](README.md) · [macOS guide](macOS.md)

## Service configuration

`local.properties` in the repository root is optional for compilation and ignored
by Git. A build without backend settings can start, but email/password login and
account sync require the matching backend configuration:

```properties
SUPABASE_URL=https://your-backend.example
SUPABASE_ANON_KEY=your-backend-public-key
```

These values identify the backend, not the user's login credentials. Rebuild after
changing build-time configuration. Other integrations have their own build-time
or user-entered settings; the generated configuration inputs are defined in
[`GenerateRuntimeConfigsTask`](../composeApp/build.gradle.kts). For example,
`TRAKT_CLIENT_ID` and `PREMIUMIZE_CLIENT_ID` are build-time integration inputs.
Do not commit private configuration, account tokens or credentials.

## Data locations and accounts

| OS | Installed file-backed data root |
|---|---|
| macOS | `~/Library/Application Support/NuvioHTPC` |
| Windows | `%LOCALAPPDATA%\NuvioHTPC` (home-directory fallback if that variable is absent) |
| Linux | `$XDG_CONFIG_HOME/nuviohtpc`, or `~/.config/nuviohtpc` |

The root is implemented by [`DesktopInstallPaths.kt`](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopInstallPaths.kt).
Logs are in `<data-root>/logs/nuvio.log`. Custom badges use `<data-root>/Badges`.
Account stores live under `accounts/<slot>/`; stores representing the machine or
shared features remain in the root. Machine stores include local library, games,
downloads, lights, screensaver, external players and P2P settings. The authoritative
list is [`MACHINE_STORE_NAMES`](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopAccountSlots.kt).

Signing out normally preserves the account's file-backed settings. Sign Out and
Erase removes that account's local settings as implemented by the account-slot
flow. Switching account slots, importing settings and changing portable mode can
restart the packaged app so in-memory stores use the selected location.

On macOS/Linux, legacy `Nuvio`/`nuvio` data is considered for migration only if a
fork-specific store identifies an earlier HTPC install. On Windows, the existing
migration still considers the old roaming/local Nuvio directories. Do not describe
this as an identical migration policy on every OS. Existing HTPC data is not
reimported on each launch. See [`DesktopStorage.kt`](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/storage/DesktopStorage.kt).

For file-store tests, `-Dnuvio.desktop.dataDir=/absolute/test/directory` overrides
the root. This override is not a complete authentication or operating-system
privacy sandbox.

## Authentication and coexistence

The macOS bundle ID, file-backed root and temporary player directories are
separate from the original app. The desktop Supabase client, however, still uses
its **default session manager** for ordinary launches; its session state is backed
by Java preferences outside `DesktopStorage.rootDir`. A different bundle name or
a temporary data directory does not guarantee isolated login sessions from other
builds using the same session store.

`SupabaseProvider.memoryOnlySession` is enabled by the explicit native self-test
mode, not by every ordinary launch or every arbitrary data-root override. Use a
separate OS test account when checking authentication isolation. Do not claim that
installing this fork fully isolates sessions or that a file backup necessarily
captures every session maintained by an external library.

The implementation is in [`SupabaseProvider.kt`](../composeApp/src/commonMain/kotlin/com/nuvio/app/core/network/SupabaseProvider.kt)
and [`NativeImageSupport.kt`](../composeApp/src/desktopMain/kotlin/com/nuvio/app/core/build/NativeImageSupport.kt).

## Portable mode and backups

Enable portable mode in Settings > Account from a writable installed location.
On macOS, data is outside the signed bundle, in `Nuvio HTPC.portable/data` beside
`Nuvio HTPC.app`. Move both items together. Disabling portable mode copies data
back to Application Support and retains the former portable data as `data.old`.
On Windows, the portable marker/data folder is beside the executable.

Do not use a disposable Gradle output directory as a permanent portable install:
build/package tasks can replace that directory. Keep portable data with the app
when moving it, rather than editing the signed bundle.

Settings backups can include or omit credentials. Import is validated before the
restart that applies it; use the app's import/export flow. On macOS these operations
use native open/save panels. Review what a backup includes before sharing it.

## Application links

The fork registers `nuviohtpc://` on macOS and Windows. Examples:

```text
nuviohtpc://meta?type=series&id=tt0944947
nuviohtpc://downloads
nuviohtpc://party/K7Q4MX
```

Generated metadata/download links and custom-server party invites use this scheme.
The shared parser retains compatibility with legacy `nuvio://` strings, but the
fork's OS registration and desktop URI dispatch target `nuviohtpc://`; parser
compatibility does not claim the original app's scheme. Standard party share links
can still use `https://nuvio.tv/party/CODE`.

## Custom hero discovery and badges

Create `<data-root>/Badges`, not the original app's `Nuvio/Badges` directory.
Examples for ordinary installs:

```text
macOS:   ~/Library/Application Support/NuvioHTPC/Badges
Windows: %LOCALAPPDATA%\NuvioHTPC\Badges
Linux:   ~/.config/nuviohtpc/Badges  (unless XDG_CONFIG_HOME is set)
```

Place `hero_discovery.json` in that folder:

```json
{
  "version": 1,
  "mergeWithDefaults": true,
  "studios": { "Janus Films": "Janus Films", "Toho": "Toho" },
  "directors": { "Akira Kurosawa": "A. Kurosawa", "Kelly Reichardt": "Kelly Reichardt" }
}
```

`mergeWithDefaults: true` adds to the bundled rules; `false` replaces the bundled
studio/director lists. Keys match metadata names; values are display labels.
Restart after changing configuration or artwork.

Custom badge images go directly in the same `Badges` folder. Supported formats are
`.png`, `.jpg`, `.jpeg` and `.webp`. Matching ignores case, spaces and punctuation;
`Metacritic.png`, `Must See.webp` and `must-see.jpg` can match their respective labels.
A custom image wins over a matching bundled image.

Useful labels include Best Picture, Best Picture Nominee, Golden Globe, Emmy
Winner, Palme dOr, Golden Lion, Golden Bear, Peoples Choice, Metacritic, Must See,
Cult Classic, Trending, Short Film, Mini Series, Binge Ready, True Story, New
Release, Director and Studio. Director names such as `David Fincher.png` or
`Christopher Nolan.webp` can also be used.
