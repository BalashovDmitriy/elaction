#!/usr/bin/env python3
"""Textures for walls, shaft and roof (ADR-0033, decisions 5, 6 and 8).

Two halves:

- **from ambientCG** (CC0): wood, marble, plaster, plastic, concrete,
  metal sheets, checker-plate steel, gravel: a 1K set scaled down to
  [SIZE]; at our scale a meter of wall is about 80 screen pixels;
- **our own**: striped hotel wallpaper with a small pattern: ambientCG wallpapers are
  plain, and a hotel corridor is recognized by its pattern. Drawn in code, like sound.

Color is stored in shades of gray where the tone comes from the round palette
(`BuildingPalette`): the texture carries the pattern, the round carries the color.

    python tools/build_textures.py           # download and build everything
    python tools/build_textures.py --local   # only our own, no network
    python tools/build_textures.py --only residential_wall  # a single texture

Writes to `assets/textures/<name>/`: `albedo.png`, `normal.png`, `roughness.png`.
"""

from __future__ import annotations

import argparse
import io
import math
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image, ImageFilter, ImageOps

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT = PROJECT_ROOT / "assets/textures"
SIZE = 512

# Name in the game → ambientCG set, and whether to make it gray for the round tone.
AMBIENT: dict[str, tuple[str, bool]] = {
    "hotel_wainscot": ("Wood051", False),
    "hotel_pilaster": ("Marble012", True),
    "office_wall": ("PaintedPlaster017", True),
    "office_wainscot": ("Plastic010", True),
    "office_pilaster": ("Concrete034", True),
    # Residential building (ADR-0055, decision 4): peeling paint on top, painted
    # glazed brick at the bottom, painted brick on the piers.
    "residential_wall": ("PaintedPlaster015", True),
    "residential_wainscot": ("PaintedBricks003", True),
    "residential_pilaster": ("PaintedBricks001", True),
    "shaft_plates": ("MetalPlates006", False),
    "shaft_concrete": ("Concrete046", True),
    "tread_plate": ("DiamondPlate008A", False),
    "roof_gravel": ("Gravel043", False),
}


def _fetch(asset: str) -> zipfile.ZipFile:
    url = f"https://ambientcg.com/get?file={asset}_1K-JPG.zip"
    request = urllib.request.Request(url, headers={"User-Agent": "elaction-build-textures"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return zipfile.ZipFile(io.BytesIO(response.read()))


def _pick(archive: zipfile.ZipFile, suffix: str) -> Image.Image:
    name = next(item for item in archive.namelist() if item.endswith(suffix))
    return Image.open(io.BytesIO(archive.read(name)))


def _save(folder: Path, albedo: Image.Image, normal: Image.Image, rough: Image.Image) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    albedo.resize((SIZE, SIZE), Image.LANCZOS).save(folder / "albedo.png", optimize=True)
    normal.resize((SIZE, SIZE), Image.LANCZOS).save(folder / "normal.png", optimize=True)
    rough.resize((SIZE, SIZE), Image.LANCZOS).save(folder / "roughness.png", optimize=True)


def _ambient(name: str, asset: str, grey: bool) -> None:
    archive = _fetch(asset)
    albedo = _pick(archive, "_Color.jpg").convert("RGB")
    if grey:
        # Gray with a raised middle: the round tone is multiplied by something light, otherwise
        # a dark texture would eat the color.
        albedo = ImageOps.autocontrast(ImageOps.grayscale(albedo), cutoff=1)
        albedo = albedo.point(lambda v: int(190 + v * 0.22)).convert("RGB")
    normal = _pick(archive, "_NormalGL.jpg").convert("RGB")
    rough = _pick(archive, "_Roughness.jpg").convert("L")
    _save(OUT / name, albedo, normal, rough)
    print(f"  {name}: {asset}")


def _wallpaper() -> None:
    """Hotel wallpaper: a wide stripe, a narrow stripe, little diamonds between them.

    The pattern is in light gray: the color comes from the round palette. The relief is a
    faint embossing of the same pattern, so that lamp light glides over the wallpaper.
    """
    size = SIZE
    height = Image.new("L", (size, size), 0)
    pixels = height.load()
    band = size // 4
    for y in range(size):
        for x in range(size):
            u = x % band
            value = 0.0
            if u < band * 0.45:
                value = 0.55  # wide stripe
            elif band * 0.55 < u < band * 0.62:
                value = 0.9  # narrow
            else:
                # A diamond between the stripes every half stripe in height.
                cx = band * 0.785
                cy = (y // (band // 2)) * (band // 2) + band // 4
                if abs(u - cx) / (band * 0.12) + abs(y - cy) / (band * 0.16) < 1.0:
                    value = 0.75
            pixels[x, y] = int(value * 255)
    height = height.filter(ImageFilter.GaussianBlur(1.2))
    albedo = height.point(lambda v: int(170 + v * 0.25)).convert("RGB")
    normal = _normal_from(height, strength=1.6)
    rough = Image.new("L", (size, size), 200)
    _save(OUT / "hotel_wall", albedo, normal, rough)
    print("  hotel_wall: своя, полоса с ромбиком")


def _normal_from(height: Image.Image, strength: float) -> Image.Image:
    """Normal map (OpenGL, Y up) from a height map by neighbor differences."""
    size = height.size[0]
    src = height.load()
    out = Image.new("RGB", (size, size))
    dst = out.load()
    for y in range(size):
        for x in range(size):
            dx = (src[(x + 1) % size, y] - src[(x - 1) % size, y]) / 255.0 * strength
            dy = (src[x, (y + 1) % size] - src[x, (y - 1) % size]) / 255.0 * strength
            nx, ny, nz = -dx, dy, 1.0
            length = math.sqrt(nx * nx + ny * ny + nz * nz)
            dst[x, y] = tuple(int((c / length * 0.5 + 0.5) * 255) for c in (nx, ny, nz))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Фактуры стен, шахты и крыши.")
    parser.add_argument("--local", action="store_true", help="только свои, без сети")
    parser.add_argument("--only", nargs="*", default=[], help="только эти фактуры ambientCG")
    arguments = parser.parse_args()
    if not arguments.only:
        _wallpaper()
    if not arguments.local:
        for name, (asset, grey) in AMBIENT.items():
            if not arguments.only or name in arguments.only:
                _ambient(name, asset, grey)
    print(f"Фактуры в {OUT.relative_to(PROJECT_ROOT).as_posix()}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
