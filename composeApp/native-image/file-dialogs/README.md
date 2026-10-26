# file-dialogs

Scope: Windows GraalVM native-image metadata; see the [build overview](../README.md).

`sun.awt.shell.*`, `javax.swing.filechooser.*`, the Windows file dialog peer, the
`sun.awt.windows.awtLocalization` bundle, and the Windows look-and-feel icons
(`com/sun/java/swing/plaf/windows/icons/**` in `java.desktop`: Computer, Directory, File, drives),
which the QA build reported missing on 2026-10-17.

Why: the subtitle "save" dialog and the local library's "add folder" dialog failed natively. Worse,
the failure opened Compose's modal error dialog behind the borderless fullscreen window, so the app
looked frozen while still responding and logging.

This records Windows native-image failures. The macOS JVM app uses native open/save
panels; its file consent and `.app` selection are documented in the
[macOS guide](../../../Docs/macOS.md#permissions). Changing this JSON does not grant
macOS file permissions.
