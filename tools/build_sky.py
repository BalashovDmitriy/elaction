#!/usr/bin/env python3
"""Небо города: HDRI-панорамы Poly Haven (CC0) по времени суток и погоде (ADR-0051).

Панорамы выбраны пользователем по картинкам (2026-10-01). Берутся в 1k: город
за ними размыт глубиной резкости, и 2k весило бы втрое больше без разницы в кадре.

Скрипт качает панорамы в `assets/sky/` и печатает, где на каждой солнце —
азимут и высоту самой яркой точки: игра поворачивает панораму так, чтобы её
солнце стояло там же, где свет солнца города ([CitySky]).

    python tools/build_sky.py
"""

from __future__ import annotations

import math
import sys
import urllib.request
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "assets" / "sky"
CACHE = ROOT / ".cache" / "sky"

SKIES = {
    "morning_clear": "syferfontein_0d_clear_puresky",
    "day_clear": "qwantani_mid_morning_puresky",
    "evening_clear": "belfast_sunset_puresky",
    "night_clear": "qwantani_moonrise_puresky",
    "fog": "kloofendal_28d_misty_puresky",
    "rain": "mud_road_puresky",
    "dusk_overcast": "kloppenheim_01_puresky",
}

URL = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/{id}_1k.hdr"


def read_hdr(path: Path) -> np.ndarray:
    """Radiance .hdr с RLE-строками в массив высота×ширина×3, линейный свет."""
    data = path.read_bytes()
    header_end = data.index(b"\n\n") + 2
    line_end = data.index(b"\n", header_end)
    size = data[header_end:line_end].decode().split()
    height, width = int(size[1]), int(size[3])
    at = line_end + 1
    image = np.zeros((height, width, 4), dtype=np.uint8)
    for row in range(height):
        at += 4
        for channel in range(4):
            column = 0
            while column < width:
                count = data[at]
                at += 1
                if count > 128:
                    count -= 128
                    image[row, column:column + count, channel] = data[at]
                    at += 1
                else:
                    image[row, column:column + count, channel] = np.frombuffer(
                        data, dtype=np.uint8, count=count, offset=at
                    )
                    at += count
                column += count
    exponent = image[..., 3].astype(np.int32)
    scale = np.where(exponent > 0, np.ldexp(1.0, exponent - 136), 0.0)
    return image[..., :3].astype(np.float64) * scale[..., None]


def sun_of(image: np.ndarray) -> tuple[float, float, float]:
    """Азимут и высота самой яркой точки, градусы, и её яркость."""
    height, width, _ = image.shape
    light = image.sum(axis=2)
    # Только верхняя половина: низ pure sky — отражение неба.
    light[height // 2:, :] = 0.0
    row, column = np.unravel_index(np.argmax(light), light.shape)
    azimuth = (column + 0.5) / width * 360.0
    elevation = 90.0 - (row + 0.5) / height * 180.0
    return azimuth, elevation, float(light[row, column])


def main() -> int:
    TARGET.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    for key, sky in SKIES.items():
        path = TARGET / f"{key}.hdr"
        if not path.exists():
            request = urllib.request.Request(URL.format(id=sky), headers={"User-Agent": "elaction"})
            path.write_bytes(urllib.request.urlopen(request, timeout=120).read())
        image = read_hdr(path)
        azimuth, elevation, peak = sun_of(image)
        mean = float(image.mean())
        print(f"{key:14s} {sky:36s} солнце: азимут {azimuth:6.1f}°, высота {elevation:5.1f}°, "
              f"пик {peak:9.1f}, средняя {mean:6.3f}, {path.stat().st_size // 1024} КБ")
    return 0


if __name__ == "__main__":
    sys.exit(main())
