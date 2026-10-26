# quickjs

Scope: Windows GraalVM native-image metadata; see the [build overview](../README.md).

`java.util.LinkedHashMap`, JNI-accessible with its public (incl. inherited) methods.

Why: plugins run in QuickJS (quickjs-kt, `PluginRuntime`). When a plugin finishes, quickjs-kt's
native code builds the JavaScript result as a `LinkedHashMap` through JNI (`GetMethodID` for `put`,
which is declared on `HashMap`). A historical QA run reported the failure
`NoSuchMethodError: java.util.LinkedHashMap.put`, so every scraper returned 0 streams and nothing
appeared in the stream list. Found by the step-3 QA build on 2026-10-17 (258 failures in one
session). quickjs-kt's own bundled metadata does not cover it.

The `libquickjs.dll` extraction needs the `jni/windows_x64/**` glob in `resources/`.

This metadata and the [patched QuickJS JNI runtime](../../src/desktopMain/native/quickjs-kt/README.md)
address different failure paths. Keep the runtime/library versions matched; a
metadata entry alone is not proof that plugin execution works.
