#!/usr/bin/env python3
"""Фактуры стен, шахты и крыши (ADR-0033, решения 5, 6 и 8).

Две половины:

- **с ambientCG** (CC0) — дерево, мрамор, штукатурка, пластик, бетон,
  металлические листы, рифлёная сталь, гравий: набор 1K, уменьшенный до
  [SIZE] — на нашем масштабе метр стены это около 80 пикселей экрана;
- **своя** — обои отеля в полоску с мелким узором: у ambientCG обои однотонные,
  а гостиничный коридор узнают по рисунку. Рисуется кодом, как звук.

Цвет кладётся в оттенках серого там, где тон даёт палитра раунда
(`BuildingPalette`): фактура несёт рисунок, раунд — цвет.

    python tools/build_textures.py           # скачать и собрать всё
    python tools/build_textures.py --local   # только своё, без сети

Пишет в `assets/textures/<имя>/`: `albedo.png`, `normal.png`, `roughness.png`.
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

# Имя в игре → набор ambientCG и красить ли его серым под тон раунда.
AMBIENT: dict[str, tuple[str, bool]] = {
    "hotel_wainscot": ("Wood051", False),
    "hotel_pilaster": ("Marble012", True),
    "office_wall": ("PaintedPlaster017", True),
    "office_wainscot": ("Plastic010", True),
    "office_pilaster": ("Concrete034", True),
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
        # Серый с поднятой серединой: тон раунда умножается на светлое, иначе
        # тёмная фактура съела бы цвет.
        albedo = ImageOps.autocontrast(ImageOps.grayscale(albedo), cutoff=1)
        albedo = albedo.point(lambda v: int(190 + v * 0.22)).convert("RGB")
    normal = _pick(archive, "_NormalGL.jpg").convert("RGB")
    rough = _pick(archive, "_Roughness.jpg").convert("L")
    _save(OUT / name, albedo, normal, rough)
    print(f"  {name}: {asset}")


def _wallpaper() -> None:
    """Обои отеля: широкая полоса, узкая полоса, между ними ромбики.

    Рисунок — в светлом сером: цвет даёт палитра раунда. Рельеф — слабое
    тиснение по тому же рисунку, чтобы свет лампы скользил по обоям.
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
                value = 0.55  # широкая полоса
            elif band * 0.55 < u < band * 0.62:
                value = 0.9  # узкая
            else:
                # Ромбик в межполосье через каждые полполосы по высоте.
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
    """Карта нормалей (OpenGL, Y вверх) по карте высот разностями соседей."""
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
    arguments = parser.parse_args()
    _wallpaper()
    if not arguments.local:
        for name, (asset, grey) in AMBIENT.items():
            _ambient(name, asset, grey)
    print(f"Фактуры в {OUT.relative_to(PROJECT_ROOT).as_posix()}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
