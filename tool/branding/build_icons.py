#!/usr/bin/env python3
"""Generate Android launcher icon resources from the checked-in mark masters.

Why
---
Android reads launcher icons from `android/app/src/main/res/`, not from
`assets/`. Those PNGs must be re-derived at several densities whenever the
mark or its size changes, and `flutter create` throws them away. This script
is the single reproducible source for those resources:

    assets/branding/vanne_mark.png        full-colour mark, transparent bg
    assets/branding/vanne_monochrome.png  single-colour mask, transparent bg

Both masters are cropped to their non-transparent bounding box. They were
extracted from the approved artwork (`vanne_icon.png`); this script never
redraws the mark, it only scales and composites it.

Outputs
-------
* `drawable-<density>/ic_launcher_foreground.png` — adaptive foreground,
  `MARK_DP` of the `CANVAS_DP` adaptive canvas.
* `drawable-<density>/ic_launcher_monochrome.png` — themed-icon mask, same
  size and position (the launcher supplies its own tint and background).
* `mipmap-<density>/ic_launcher.png` — legacy icon (pre-API 26 only; this
  app's minSdk is 29). Deliberately no `mipmap-night-*` variant: the `night`
  qualifier outranks `anydpi`, so a night legacy bitmap would shadow the
  adaptive icon XML and the launcher would render the bitmap instead.

The day/night background colours are the launcher background and the launch
window colour: pure white in light mode, pure black in dark mode. Keeping
them identical is what makes the Android 12+ splash (launcher icon over
`windowSplashScreenBackground`) seamless.

Usage
-----
    python3 tool/branding/build_icons.py          # write resources
    python3 tool/branding/build_icons.py --check  # exit 1 if they differ

Stdlib only: no Pillow or other third-party package is required.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "assets" / "branding"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Adaptive icons expose a 108 dp canvas; launchers may mask its outer thirds.
CANVAS_DP = 108
# Mark size inside that canvas. 48 dp is Android's stated minimum mark size;
# its bounding-box half-diagonal is 33.9 dp, inside the 72 dp visible circle
# (36 dp radius) and only just outside the 66 dp safe circle — the artwork's
# rounded corners are transparent there, so nothing visible is clipped. Was
# 52 dp, whose bounding corners reached 36.8 dp, past the visible circle. The
# themed (monochrome) icon uses the same size.
MARK_DP = 48
# Legacy bitmaps are a 48 dp tile with the same mark/canvas ratio.
LEGACY_DP = 48

LIGHT_BG = (255, 255, 255, 255)

DENSITIES = (
    ("mdpi", 1.0),
    ("hdpi", 1.5),
    ("xhdpi", 2.0),
    ("xxhdpi", 3.0),
    ("xxxhdpi", 4.0),
)


# --------------------------------------------------------------------------
# Minimal RGBA PNG codec (8-bit, non-interlaced)
# --------------------------------------------------------------------------


def read_png(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")
    pos = 8
    idat = bytearray()
    width = height = bit_depth = colour_type = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos : pos + 4])[0]
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, colour_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", chunk
            )
            if interlace:
                raise ValueError(f"{path}: interlaced PNGs are not supported")
            if bit_depth != 8 or colour_type not in (2, 6):
                raise ValueError(f"{path}: expected 8-bit RGB/RGBA")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break

    channels = 4 if colour_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(bytes(idat))
    out = bytearray(height * stride)
    previous = bytearray(stride)
    src = 0
    for y in range(height):
        filter_type = raw[src]
        src += 1
        line = bytearray(raw[src : src + stride])
        src += stride
        if filter_type == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif filter_type == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 0xFF
        elif filter_type == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 0xFF
        elif filter_type == 4:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                up = previous[x]
                up_left = previous[x - channels] if x >= channels else 0
                estimate = left + up - up_left
                dl, du, dul = abs(estimate - left), abs(estimate - up), abs(
                    estimate - up_left
                )
                if dl <= du and dl <= dul:
                    predictor = left
                elif du <= dul:
                    predictor = up
                else:
                    predictor = up_left
                line[x] = (line[x] + predictor) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"{path}: unsupported PNG filter {filter_type}")
        out[y * stride : (y + 1) * stride] = line
        previous = line

    if channels == 3:  # normalise to RGBA, opaque
        rgba = bytearray(width * height * 4)
        for i in range(width * height):
            rgba[i * 4 : i * 4 + 3] = out[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
        return width, height, bytes(rgba)
    return width, height, bytes(out)


def _chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return (
        struct.pack(">I", len(payload))
        + body
        + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    )


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none — icons compress well either way
        raw += rgba[y * stride : (y + 1) * stride]
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )


# --------------------------------------------------------------------------
# Resampling and compositing
# --------------------------------------------------------------------------


def alpha_bbox(width: int, height: int, rgba: bytes) -> tuple[int, int, int, int]:
    left, top, right, bottom = width, height, -1, -1
    for y in range(height):
        row = y * width * 4
        for x in range(width):
            if rgba[row + x * 4 + 3]:
                if x < left:
                    left = x
                if x > right:
                    right = x
                if y < top:
                    top = y
                if y > bottom:
                    bottom = y
    if right < 0:
        raise ValueError("image is fully transparent")
    return left, top, right, bottom


def crop(width: int, height: int, rgba: bytes) -> tuple[int, int, bytes]:
    left, top, right, bottom = alpha_bbox(width, height, rgba)
    w, h = right - left + 1, bottom - top + 1
    out = bytearray(w * h * 4)
    for y in range(h):
        start = ((y + top) * width + left) * 4
        out[y * w * 4 : (y + 1) * w * 4] = rgba[start : start + w * 4]
    return w, h, bytes(out)


def resize(width: int, height: int, rgba: bytes, new_w: int, new_h: int) -> bytes:
    """Area-average downscale in premultiplied alpha (no dark/white fringes)."""
    if (width, height) == (new_w, new_h):
        return rgba
    if new_w > width or new_h > height:
        raise ValueError("only downscaling is supported by this generator")
    out = bytearray(new_w * new_h * 4)
    x_scale = width / new_w
    y_scale = height / new_h
    for dy in range(new_h):
        y0, y1 = dy * y_scale, (dy + 1) * y_scale
        sy0, sy1 = int(y0), min(int(y1) + (1 if y1 > int(y1) else 0), height)
        for dx in range(new_w):
            x0, x1 = dx * x_scale, (dx + 1) * x_scale
            sx0, sx1 = int(x0), min(int(x1) + (1 if x1 > int(x1) else 0), width)
            acc_r = acc_g = acc_b = acc_a = weight = 0.0
            for sy in range(sy0, sy1):
                wy = min(sy + 1, y1) - max(sy, y0)
                if wy <= 0:
                    continue
                row = sy * width * 4
                for sx in range(sx0, sx1):
                    wx = min(sx + 1, x1) - max(sx, x0)
                    if wx <= 0:
                        continue
                    w = wx * wy
                    i = row + sx * 4
                    a = rgba[i + 3] / 255.0
                    acc_r += rgba[i] * a * w
                    acc_g += rgba[i + 1] * a * w
                    acc_b += rgba[i + 2] * a * w
                    acc_a += a * w
                    weight += w
            o = (dy * new_w + dx) * 4
            if acc_a <= 0.0 or weight <= 0.0:
                continue
            out[o] = min(255, round(acc_r / acc_a))
            out[o + 1] = min(255, round(acc_g / acc_a))
            out[o + 2] = min(255, round(acc_b / acc_a))
            out[o + 3] = min(255, round(255 * acc_a / weight))
    return bytes(out)


def place_centered(
    canvas: int, width: int, height: int, rgba: bytes
) -> bytes:
    out = bytearray(canvas * canvas * 4)
    left = (canvas - width) // 2
    top = (canvas - height) // 2
    for y in range(height):
        start = (y * width) * 4
        dest = ((top + y) * canvas + left) * 4
        out[dest : dest + width * 4] = rgba[start : start + width * 4]
    return bytes(out)


def place_on_background(
    canvas: int,
    width: int,
    height: int,
    rgba: bytes,
    background: tuple[int, int, int, int],
) -> bytes:
    """Composite the mark over an opaque background of the full canvas."""
    out = bytearray(bytes(background) * (canvas * canvas))
    left = (canvas - width) // 2
    top = (canvas - height) // 2
    br, bg, bb, _ = background
    for y in range(height):
        dy = top + y
        if dy < 0 or dy >= canvas:
            continue
        for x in range(width):
            dx = left + x
            if dx < 0 or dx >= canvas:
                continue
            i = ((y * width) + x) * 4
            a = rgba[i + 3] / 255.0
            if a <= 0.0:
                continue
            o = ((dy * canvas) + dx) * 4
            inv = 1.0 - a
            out[o] = min(255, round(rgba[i] * a + br * inv))
            out[o + 1] = min(255, round(rgba[i + 1] * a + bg * inv))
            out[o + 2] = min(255, round(rgba[i + 2] * a + bb * inv))
            out[o + 3] = 255
    return bytes(out)


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------


def scaled(
    master: tuple[int, int, bytes], target_h: int
) -> tuple[int, int, bytes]:
    """Scale a cropped master to `target_h` keeping its aspect ratio."""
    width, height, rgba = master
    target_w = max(1, round(width * target_h / height))
    return target_w, target_h, resize(width, height, rgba, target_w, target_h)


def build() -> dict[Path, bytes]:
    mark = crop(*read_png(BRANDING / "vanne_mark.png"))
    mono = crop(*read_png(BRANDING / "vanne_monochrome.png"))
    expected_ratio = mark[0] / mark[1]
    if abs(mono[0] / mono[1] - expected_ratio) > 0.02:
        raise ValueError("mark and monochrome masters must share a silhouette")

    outputs: dict[Path, bytes] = {}
    for name, density in DENSITIES:
        canvas = round(CANVAS_DP * density)
        w, h, scaled_mark = scaled(mark, round(MARK_DP * density))
        outputs[RES / f"drawable-{name}/ic_launcher_foreground.png"] = encode_png(
            canvas, canvas, place_centered(canvas, w, h, scaled_mark)
        )
        w, h, scaled_mono = scaled(mono, round(MARK_DP * density))
        outputs[RES / f"drawable-{name}/ic_launcher_monochrome.png"] = encode_png(
            canvas, canvas, place_centered(canvas, w, h, scaled_mono)
        )

        legacy = round(LEGACY_DP * density)
        mark_h = round(legacy * MARK_DP / CANVAS_DP)
        w, h, legacy_mark = scaled(mark, mark_h)
        outputs[RES / f"mipmap-{name}/ic_launcher.png"] = encode_png(
            legacy,
            legacy,
            place_on_background(legacy, w, h, legacy_mark, LIGHT_BG),
        )
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify generated resources are up to date instead of writing",
    )
    args = parser.parse_args()

    outputs = build()
    stale = [
        path
        for path, data in outputs.items()
        if not path.exists() or path.read_bytes() != data
    ]

    if args.check:
        if stale:
            for path in stale:
                print(f"stale: {path.relative_to(ROOT)}", file=sys.stderr)
            print(
                "Run: python3 tool/branding/build_icons.py",
                file=sys.stderr,
            )
            return 1
        print(f"ok: {len(outputs)} launcher icon resources are up to date")
        return 0

    for path, data in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(
        f"wrote {len(outputs)} launcher icon resources "
        f"(mark {MARK_DP}dp of {CANVAS_DP}dp canvas, day/night background)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
