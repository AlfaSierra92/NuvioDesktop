# Documentation

These guides describe this repository's Nuvio HTPC fork. Start with the
[project README](../README.md) for features, platform status and a quick build.

| Guide | Contents |
|---|---|
| [macOS](macOS.md) | Installation, native runtime, permissions, signing and troubleshooting. |
| [Configuration](Configuration.md) | Service settings, file locations, accounts, portable mode, links and custom badges. |
| [Development](Development.md) | Toolchains, build targets, release workflow and versioning. |
| [Testing](Testing.md) | Targeted tests, real playback harnesses, evidence and reporting. |
| [macOS port status](Windows-remnants-macOS-audit.md) | Current implementation status and remaining validation work; supersedes the original audit findings. |
| [Changelog](../CHANGELOG.md) | Unreleased changes followed by historical releases. |
| [Contributing](../CONTRIBUTING.md) | Scope, verification and pull-request guidance. |
| [Windows native-image metadata](../composeApp/native-image/README.md) | GraalVM build inputs and topic-specific explanations. |
| [Nuvio Engine](../composeApp/src/desktopMain/native/nuvio-engine/README.md) | Native engine toolchains, checkout and desktop patches. |
| [QuickJS](../composeApp/src/desktopMain/native/quickjs-kt/README.md) | Patched JNI runtime and platform build locations. |
| [App icon](../scripts/app-icon/README.md) | Source artwork, regeneration and output assets. |

## References and historical material

[Stremio addon documentation](Stremio%20addons%20refer/README.md) is a local reference
copy about Stremio's SDK and protocol. Its deployment services, links and platform
claims describe that upstream material, not Nuvio HTPC's release/build support.
Do not rewrite its protocol examples to use the fork's application URL scheme.

[Design prompts](../design-mockups/prompts.md) describe visual concepts, not a
specification of implemented UI. Native-image topic READMEs retain historical
failure explanations, explicitly scoped to Windows GraalVM.

## Maintaining these guides

Keep commands relative to the repository root unless a different directory is
shown. Link to source files with repository-relative paths; avoid workstation
paths and line numbers that go stale. Mark a feature as verified only with the
platform and type of test performed. A JVM unit test, loopback playback test and
a permission prompt from a Finder-launched app establish different things.
