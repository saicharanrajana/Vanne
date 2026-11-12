# Vanne branding assets

## Source of truth

`vanne_icon.png` — the original supplied artwork (1254×1254, opaque, gradient
mark on a black field). **Never edited by scripts**; it is the reference for
colour, background and proportions.

The two **mark masters** are checked in so the Android resources can be
rebuilt without re-running the segmentation:

| File | What it is |
| --- | --- |
| `vanne_mark.png` | Full-colour mark, transparent background, cropped to its bounding box (206×208 px) |
| `vanne_monochrome.png` | Single-colour themed-icon silhouette, same size and crop |

They were extracted from the approved artwork (not redrawn). The generator
only scales and composites them.

## Generate the Android resources

```sh
python3 tool/branding/build_icons.py          # rewrite all icon PNGs
python3 tool/branding/build_icons.py --check  # fail if any shipped PNG is stale
```

The script is stdlib-only (no Pillow). It writes:

| Output | Purpose |
| --- | --- |
| `drawable-{mdpi…xxxhdpi}/ic_launcher_foreground.png` | Adaptive foreground: mark at **48 dp** on the 108 dp canvas |
| `drawable-{mdpi…xxxhdpi}/ic_launcher_monochrome.png` | Themed icon mask (Android 13+), same size and position |
| `mipmap-{mdpi…xxxhdpi}/ic_launcher.png` | Legacy icon (pre-API 26; this app's minSdk is 29) on the **white** background |

There is deliberately **no** `mipmap-night-*` legacy variant. The `night`
resource qualifier outranks `anydpi`, so a night bitmap would shadow
`mipmap-anydpi-v26/ic_launcher.xml` and the launcher would render a flat bitmap
instead of the adaptive icon. The adaptive icon background is fixed white in
all modes.

`tool/apply_android_overrides.sh` runs the generator after copying `res/`, so
`flutter create` cannot leave the stock Flutter logo behind.

## Background: white in every theme

The normal adaptive and legacy launcher icon use a fixed pure-white background
(`@color/ic_launcher_background` in `values/colors.xml`). There is deliberately
no night-qualified background resource, so launchers cannot cache a separate
dark-mode icon variant.

The system splash remains theme-aware: `values*/launch_colors.xml` and
`lib/app/launch_background.dart` select pure white in light mode and pure black
in dark mode. API 31+ splash themes use the transparent
`@drawable/ic_launcher_foreground` layer instead of the full adaptive icon.
That separation keeps the splash black in dark mode without putting a white
square behind the mark. The splash and launcher icon no longer share a
background resource by design.

**Themed icons** ignore the normal icon background: the launcher supplies the
tint and wallpaper-derived background. Only the mask's size and shape matter.

## Proportions

The mark occupies **48 dp of the 108 dp adaptive canvas** (~44 %). Its
bounding-box half-diagonal is 33.9 dp, inside the 72 dp visible circle
(36 dp radius); the rounded corners are transparent, so no launcher mask clips
it. 48 dp is Android's stated minimum mark size. Legacy bitmaps use the same
48/108 ratio inside a 48 dp tile.

The 48 dp size is a deliberate ~8 % reduction from the previous 52 dp, whose
bounding corners (36.8 dp) reached past the visible circle.

## Monochrome (themed) design

The themed layer is derived **directly from the approved reference**, not from
re-invented geometry:

* the reference's two gradient panels are segmented by hue/value (the preview
  tile's navy background and grey corner star are dropped), so the visible
  silhouette, corner radii, relative panel sizes and the bold negative-space
  seam match the approved design;
* the glyph is emitted as a **single transparent-background mask** with one
  fill — the OS tints it, and the seam shows the launcher surface;
* same 48 dp mark size and centring as the colour foreground.

To change the mark, replace `vanne_mark.png` / `vanne_monochrome.png` (same
crop and aspect) and re-run the generator. Do not hand-edit drawables.
