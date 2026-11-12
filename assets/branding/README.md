# Vanne branding assets

## Source of truth

`vanne_icon.png` — the original supplied artwork (1254×1254, opaque, gradient
mark on a black field). **Never edited by scripts**; it is the reference for
colour, background and proportions.

## Where Android actually reads the launcher icon from

Flutter's `assets/` folder is *not* the launcher icon. Android consumes the
generated resources below (`android/app/src/main/res/`):

| Layer | Resource | Used by |
| --- | --- | --- |
| Adaptive background | `values/colors.xml` → `@color/ic_launcher_background` (`#FF000000`) | `mipmap-anydpi-v26/ic_launcher.xml`, `mipmap-anydpi-v33/ic_launcher.xml` |
| Adaptive foreground | `drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png` | same two adaptive XMLs |
| Themed icon (Android 13+) | `drawable-*/ic_launcher_monochrome.png` | `mipmap-anydpi-v33/ic_launcher.xml` `<monochrome>` |
| Legacy bitmap (pre-API 26) | `mipmap-*/ic_launcher.png` (48–192 px) | any device below 26; harmless on 29+ |

`mipmap-anydpi-v26` deliberately has **no** `<monochrome>` so pre-33 parsers
never see an element they do not understand; the v33 copy adds it.

## Proportions

The mark occupies **52 dp of the 108 dp adaptive canvas** (~48 %), centred on
its non-transparent bounding box, so the icon keeps generous padding inside
every launcher mask. Legacy bitmaps use the same 52/108 ratio.

## Monochrome (themed) design

The themed layer is derived **directly from the user's approved reference**
artwork (`monochrome_vanne_icon_ref.png`, kept outside the repo), not from
re-invented geometry:

* the reference's two teal panels are segmented by hue/value (the preview
tile's navy background and the grey corner star are dropped), so the visible
silhouette, corner radii, relative panel sizes and the bold negative-space
seam are exactly the approved design;
* the extracted glyph is emitted as a **single transparent-background mask**
with one fill — the OS tints it, and the seam shows the launcher surface;
* mark size **52 dp** on the 108 dp canvas, centred on its own bounding box
(measured 51.5 × 52.0 dp, margins ≈ 28 dp, seam ≈ 3 dp, corner alpha 0).

Regenerating the monochrome layer means re-running that segmentation on the
reference; do not substitute hand-drawn shapes.

## Regenerating

Layers were generated from `vanne_icon.png` with a small stdlib-only Python
pipeline (PNG decode → alpha extraction / geometric masks → resample per
density). If the artwork or the proportions change, regenerate the PNGs above
in place — do not hand-edit the drawables, and keep the 52 dp mark size.
