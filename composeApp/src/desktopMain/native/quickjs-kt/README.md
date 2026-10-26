# quickjs-kt native library (patched)

The native half of `io.github.dokar3:quickjs-kt` **1.0.15** (tag `v1.0.15`, commit
`a081755bcdb18ee6afa7ffee25b8fa976f06d31f`, QuickJS submodule `04be246`), vendored so the app can
ship its own `libquickjs.dll` instead of the one inside the jar. The shared JNI build sources are here: `quickjs/` (QuickJS, MIT), `common/`, `jni/`, `c-vector/cvector.h` (MIT),
`quickjs.def`. quickjs-kt itself is Apache-2.0 (`LICENSE.txt`).

Built by `:composeApp:buildWindowsQuickJs` with MSYS2 UCRT64 GCC into
`build/native/windows/libquickjs.dll`, staged beside `Nuvio.exe`, and loaded through quickjs-kt's
own `com.dokar.quickjs.library.path` property (`PluginRuntime.kt`). The Kotlin half still comes
from the Maven artifact, so the version here must match `quickjsKt` in `gradle/libs.versions.toml`.

## The one change: `binding_bridge-local-frames.patch`

Every JS -> Kotlin binding call (`jni_invoke_getter/setter/function/async_function`) runs inside
its own `PushLocalFrame`/`PopLocalFrame`. Upstream leaks the argument array, the boxed promise
handles and the host's return value of each call; they live until the outermost Java -> native call
returns, which for a scraper is one whole pending job (a page parsed through the cheerio bindings:
thousands of calls). On GraalVM native image a deleted local slot is not reused until its frame
pops either, so each job grew the thread's JNI handle table without bound. A startup heap dump
(2026-10-19) had 34.6 MB of handle tables holding ~49 MB of Strings. The measurement is historical evidence for the patch; the former spike plan is
not included in this checkout. See the [development guide](../../../../../Docs/Development.md).

To upgrade quickjs-kt: copy the same files from the new tag, re-apply the patch, bump the version
above and in `libs.versions.toml` together.


## macOS build and validation

`:composeApp:buildMacosQuickJs` invokes `scripts/build-macos-quickjs.sh` and writes
`composeApp/build/native/macos/libquickjs.dylib`. The app stages the patched dylib
with its native runtime and points the Kotlin QuickJS loader at that library.
This is separate from the Windows `libquickjs.dll` and its GraalVM metadata.

```bash
./gradlew --no-configuration-cache :composeApp:buildMacosQuickJs
./gradlew --no-configuration-cache :composeApp:desktopTest --tests '*QuickJsBindingLocalRefTest'
```

The regression uses the patched host runtime selected by Gradle. Keep JNI/library
updates synchronized with `quickjsKt` in `gradle/libs.versions.toml`; do not substitute
the dependency jar's unpatched native library as a validation shortcut.
