# App icon

The shipped assets are
`composeApp/src/desktopMain/resources/icons/nuvio-app-icon.{ico,png,icns}`.
They adapt the original Nuvio glyph with variant G's night-sky fill and silver
edge so the HTPC build is visually distinguishable from the original.

The historical source was the 1024px iOS master at
`iosApp/iosApp/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png` in upstream's
`Dev` tree. Neither that iOS tree nor a configured `upstream/Dev` Git ref is
required/present in every checkout. Supply the source image explicitly as
`scripts/app-icon/up_ios_1024.png` before regeneration.

From the repository root, with Python 3, Pillow and NumPy installed:

```bash
cp /path/to/app-icon-1024.png scripts/app-icon/up_ios_1024.png
python3 scripts/app-icon/extract.py
python3 scripts/app-icon/export_g.py
```

`extract.py` recovers the alpha into `official_1024_rgba.png`. `export_g.py` uses
`reskin.py`, `reskin2.py` and `border.py` to produce the final assets under
`scripts/app-icon/final/`. Inspect the results at tray, Dock and larger sizes,
then copy the intended outputs:

```bash
cp scripts/app-icon/final/nuvio-app-icon.{ico,png,icns} composeApp/src/desktopMain/resources/icons/
```

The silver band is recomputed per ICO frame so the silhouette remains visible
at small sizes. The 1080px PNG is also used at small tray/window sizes. Earlier
colour variants remain in the generator scripts as design history. Regeneration
changes artwork, not the macOS bundle identifier, URL scheme or privacy settings;
see the [macOS guide](../../Docs/macOS.md).
