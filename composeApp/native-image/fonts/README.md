# fonts

Scope: Windows GraalVM native-image metadata; see the [build overview](../README.md).

All of `sun.font.*`, JNI-accessible.

Why: AWT fonts (the Swing tray menu, the subtitle font list) need JNI into `sun.font`, and JDK 25
calls methods the JDK 21 trace never saw (for example `Font2D.charToGlyphRaw`). The build also has
to ship `runtime\lib\fontconfig.bfc` beside the exe; that is a file, not metadata.

A fresh GraalVM 25 trace may cover these registrations; verify before removing them.
