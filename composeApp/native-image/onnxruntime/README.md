# onnxruntime

Scope: Windows GraalVM native-image metadata; see the [build overview](../README.md).

`ai.onnxruntime.*`, JNI-accessible.

Why: the hero backdrop framer runs face detection through ONNX Runtime (`HeroBackdropFramer`,
models in `<install>\resources\`), and its Java API is driven from native code via JNI. The native
library itself comes in through the `ai/onnxruntime/native/win-x64/**` glob in `resources/`.

The macOS JVM package must preserve its own ONNX native libraries during jar
processing; this Windows resource glob is not a cross-platform replacement.
