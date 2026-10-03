#!/usr/bin/env python3
"""Application icon: `icon.ico` from the same geometry as `icon.svg`.

Windows takes the icon from the `.exe`, and `rcedit` writes it there, and only from
`.ico`; it does not understand SVG. Drawing it separately in an editor would mean a
second copy of the picture that drifts from the first; so it is built in code, like the
other assets (ADR-0011, item 1, and ADR-0013, item 9).

The geometry is a shaft with a cab and three rows of windows, one of them red: the same
as in `icon.svg`, only in pixels and in all the sizes Windows asks for. The result is
committed to the repository; CI does not call the script.

    python tools/render_icon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

from godot_bin import PROJECT_ROOT, use_utf8_output

OUT_FILE = PROJECT_ROOT / "icon.ico"

# Sizes inside the .ico. 256 is for large Explorer tiles, 16 is for the window title.
SIZES: tuple[int, ...] = (16, 24, 32, 48, 64, 128, 256)

# Original canvas: the same 128 units as in the viewBox of the SVG icon.
CANVAS: int = 128

# Draw large and scale down: edges are smooth at all sizes, not ragged at small ones.
SUPERSAMPLE: int = 8

type Rgba = tuple[int, int, int, int]

BACKDROP: Rgba = (0x14, 0x16, 0x1F, 0xFF)
SHAFT: Rgba = (0x0B, 0x0D, 0x14, 0xFF)
CABLE: Rgba = (0x3B, 0x42, 0x57, 0xFF)
CAR: Rgba = (0xF2, 0xC1, 0x4E, 0xFF)
CAR_TOP: Rgba = (0xFF, 0xF0, 0xC2, 0xFF)
WINDOW_DARK: Rgba = (0x3B, 0x42, 0x57, 0xFF)
WINDOW_LIT: Rgba = (0xF2, 0xC1, 0x4E, 0xD9)
WINDOW_RED: Rgba = (0xC0, 0x39, 0x2B, 0xFF)

CORNER_RADIUS: int = 20

# Rectangles on top of the background: (x, y, width, height, color) in canvas units.
PARTS: tuple[tuple[int, int, int, int, Rgba], ...] = (
    (46, 14, 36, 100, SHAFT),  # shaft
    (63, 14, 2, 44, CABLE),  # rope
    (50, 56, 28, 32, CAR),  # cab
    (50, 56, 28, 4, CAR_TOP),  # glint on the cab roof
    (18, 30, 18, 12, WINDOW_LIT),  # windows: lit on the left, not on the right
    (92, 30, 18, 12, WINDOW_DARK),
    (18, 62, 18, 12, WINDOW_DARK),
    (92, 62, 18, 12, WINDOW_LIT),
    (18, 94, 18, 12, WINDOW_RED),  # red door, the game's identifying mark
    (92, 94, 18, 12, WINDOW_DARK),
)


def draw(scale: int) -> Image.Image:
    """Draws the icon on a `CANVAS * scale` canvas."""
    size = CANVAS * scale
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas = ImageDraw.Draw(image)
    canvas.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=CORNER_RADIUS * scale,
        fill=BACKDROP,
    )

    for x, y, width, height, color in PARTS:
        # Semi-transparent windows go on a separate layer: Pillow cannot draw them directly onto
        # the background, since it replaces alpha instead of blending colors.
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rectangle(
            (x * scale, y * scale, (x + width) * scale - 1, (y + height) * scale - 1),
            fill=color,
        )
        image = Image.alpha_composite(image, layer)

    return image


def main() -> int:
    use_utf8_output()
    master = draw(SUPERSAMPLE)
    largest = max(SIZES)
    # Pillow itself spreads the large image over the other sizes, scaling it down with the
    # same LANCZOS; our job is to hand it an image already reduced from the large canvas.
    frame = master.resize((largest, largest), Image.Resampling.LANCZOS)
    frame.save(OUT_FILE, format="ICO", sizes=[(size, size) for size in SIZES])
    print(f"{Path(OUT_FILE).name}: {', '.join(str(size) for size in SIZES)} px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
