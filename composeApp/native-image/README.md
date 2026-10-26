# Windows native-image build inputs

This directory configures the **Windows GraalVM native executable**. It is not the
macOS JVM app's permission, signing or native-library configuration. See
[Development](../../Docs/Development.md#windows-graalvm-native-image),
[Testing](../../Docs/Testing.md) and the [macOS guide](../../Docs/macOS.md).
The older spike plans referenced by previous versions of this README are not part
of this checkout; the current build contract is in
[`composeApp/build.gradle.kts`](../build.gradle.kts).

## Inputs and generated metadata

| Path | Purpose |
|---|---|
| `agent/` | Tracing-agent output in the legacy multi-file format. Re-trace when needed rather than hand-editing recorded results. |
| `<topic>/reachability-metadata.json` | Hand-maintained registrations with a topic README explaining the failure they address. |
| `nuvio-launcher.manifest` | Windows PerMonitorV2 DPI manifest embedded with the native build tools. |
| `composeApp/build/native-image/generated/` | Generated metadata, outside this source directory. |

`generateNativeMetadata` runs before `nativeCompile`. It gathers serializer types
from app jars and the literal JNI lookups in the Windows player and engine bridge.
Unresolvable C++ lookups fail generation; prefer literal class/member names the
scanner can understand. `NativeImageReflectionCheckTest` checks reflective app
lookups against the registered/generated entries and documented exceptions.

## Build and validation

The build requires Windows, GraalVM for JDK 25, MSVC/Windows SDK and the native
runtime dependencies described in the development guide. It starts from the JVM
app image, compiles it, then lays out the executable and required resources:

```powershell
.\gradlew.bat --no-configuration-cache :composeApp:createNativeDistributable
.\gradlew.bat --no-configuration-cache :composeApp:nativeSmoke
.\gradlew.bat --no-configuration-cache :composeApp:packageNativeReleaseZip
```

The app output is `composeApp/build/native-image/Nuvio`; the release ZIP is under
`composeApp/build/native-image/release`. The interactive `nativeImageTrace` task
uses the tracing agent. `-Pnuvio.trace.freshProfile=true` selects fresh file-backed
trace data; it is not a general promise of authentication isolation. QA builds
use `-Pnuvio.native.qa=true` and are refused by normal release packaging.

## Topics

- [AWT/JNI](awt-jni/README.md), [fonts](fonts/README.md), [Swing](swing/README.md)
- [File dialogs](file-dialogs/README.md), [clipboard](clipboard/README.md)
- [Native bridges](native-bridges/README.md), [QuickJS](quickjs/README.md)
- [ONNX Runtime](onnxruntime/README.md), [Skiko](skiko/README.md)
- [Management](management/README.md), [resources](resources/README.md)

The topic notes preserve historical failure evidence. Type/resource counts are
not fixed contracts: inspect the JSON and generated output rather than copying
numbers from an old trace. Retain an entry until a fresh trace/QA run demonstrates
it is unnecessary; do not remove platform metadata because a macOS JVM test passes.

Save metadata without a BOM. Windows PowerShell 5.1's UTF-8 output can introduce
one and break parsing; `NativeImageMetadataTest` checks these files. Keep changes
attributable to a concrete reflection/JNI/resource requirement and update the
corresponding rationale when it changes.
