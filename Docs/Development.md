# Development and releases

[Documentation index](README.md) · [Contributing](../CONTRIBUTING.md)

## Repository and toolchain

Clone this fork, rather than the original repository, to build these changes:

```bash
git clone https://github.com/AlfaSierra92/NuvioDesktop.git
cd NuvioDesktop
```

Use the checked-in Gradle wrapper and a JDK 21 matching the host architecture.
The application uses Kotlin/Compose Multiplatform and a desktop JVM target.
Windows GraalVM native-image is a separate toolchain and uses GraalVM for JDK 25.
Do not confuse that native executable with the native libraries inside the macOS JVM app.

`local.properties` is optional. See [service configuration](Configuration.md#service-configuration)
for backend/integration inputs; building without those settings does not configure
an account service. Do not commit local configuration or test credentials.

Custom native and packaging tasks are not all configuration-cache compatible.
Use `--no-configuration-cache` for the commands below.

## JVM development and packaging

macOS requires the native dependencies described in the [macOS build guide](macOS.md#build).
On a prepared host:

```bash
./gradlew --no-configuration-cache :composeApp:run
./gradlew --no-configuration-cache :composeApp:createDistributable
./gradlew --no-configuration-cache :composeApp:packageReleaseDistributionForCurrentOS
```

PowerShell equivalents use the Windows wrapper:

```powershell
.\gradlew.bat --no-configuration-cache :composeApp:run
.\gradlew.bat --no-configuration-cache :composeApp:createDistributable
.\gradlew.bat --no-configuration-cache :composeApp:packageReleaseMsi
```

| Host | Package target | Notes |
|---|---|---|
| macOS | `:composeApp:packageReleaseDmg` | Host-architecture JVM bundle; final signature verified after staging. |
| Windows | `:composeApp:packageReleaseMsi` | JVM/MSI path; native runtime inputs must be available. |
| Linux | `:composeApp:packageReleaseDeb` | Configured target; full player/feature parity is not established here. |

Targets are host-specific, not a cross-compilation promise. Outputs live under
`composeApp/build/compose/binaries`, with `main` for development and `main-release`
for release. Do not keep permanent portable data in those disposable output trees.

## Native runtime inputs

- Player: macOS Objective-C++/libmpv and Windows C++ bridge sources are under
  [`desktopMain/native`](../composeApp/src/desktopMain/native/). Runtime discovery
  and staging are defined in [`composeApp/build.gradle.kts`](../composeApp/build.gradle.kts).
- QuickJS: the [patched vendored JNI runtime](../composeApp/src/desktopMain/native/quickjs-kt/README.md)
  is built for each supported host; changing its version also requires matching the Maven library.
- Nuvio Engine: follow the [engine instructions](../composeApp/src/desktopMain/native/nuvio-engine/README.md)
  for the separate checkout, desktop patches, CMake and OS-specific toolchains.
- SVP on macOS: use an external compatible VapourSynth/SVP installation. It is not
  installed automatically or included in the bundle. Runtime overrides are
  `nuvio.svp.pluginDir`/`NUVIO_SVP_PLUGIN_DIR` and `nuvio.svp.script`.

On Windows the engine/QuickJS tasks use their documented MSYS2/native toolchains;
packaging can require inputs that a development run only warns about. On macOS an
unavailable engine runtime falls back to TorrServer; existing generated engine
outputs may remain when a checkout is absent.

## Windows GraalVM native image

This path requires Windows, GraalVM for JDK 25 and MSVC/Windows SDK tools, plus the
native player/engine dependencies. Supply `-Pnuvio.graalvm.home=...` or
`GRAALVM_HOME` as needed. See [native-image metadata](../composeApp/native-image/README.md).

```powershell
.\gradlew.bat --no-configuration-cache :composeApp:createNativeDistributable
.\gradlew.bat --no-configuration-cache :composeApp:nativeSmoke
.\gradlew.bat --no-configuration-cache :composeApp:packageNativeReleaseZip
```

The app is laid out in `composeApp/build/native-image/Nuvio`; the release ZIP is
`composeApp/build/native-image/release/Nuvio.zip`. `packageNativeReleaseZip` runs
the smoke gate unless explicitly overridden for local work, and refuses QA images.
A QA build uses `-Pnuvio.native.qa=true`; do not publish it as a normal release.
The interactive `nativeImageTrace` task updates tracing-agent metadata on Windows.

## Versioning and releases

The current desktop version/build code are in
[`DesktopVersion.properties`](../composeApp/Configuration/DesktopVersion.properties).
Read them with:

```bash
./scripts/set-version.sh --show
```

For an intended version change, preview it first, replacing the example values:

```bash
./scripts/set-version.sh --desktop 1.16.1 --desktop-code 28 --dry-run
```

Remove `--dry-run` only when that release/version change is intended. The helper's
mobile/base flags refer to a separate upstream iOS configuration that is absent
from this desktop checkout; use desktop flags here. An Unreleased changelog entry
does not itself change the application version.

The current [`release-macos.yml`](../.github/workflows/release-macos.yml) targets ARM64
on `macos-15`, sets up JDK 21, installs native dependencies, clones/builds Nuvio
Engine, packages a DMG and emits a SHA-256 file. A manual run uploads artifacts;
a matching `v*` tag also runs the GitHub Release publishing step. The workflow
currently blanks signing/notary settings; configuring local signing does not make
that workflow notarize its artifacts. The engine guide documents the pinned,
patched desktop checkout; the workflow's shallow engine clone is a distinct source
selection and should not be described as that pinned checkout automatically.

Release preparation should include the relevant [tests](Testing.md), a review of
package architecture/signature and a changelog entry describing actual behavior.
Documentation updates alone do not require repackaging or a version bump.
