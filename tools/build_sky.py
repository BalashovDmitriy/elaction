#!/usr/bin/env python3
"""City sky: Poly Haven HDRI panoramas (CC0) by time of day and weather (ADR-0051).

The panoramas were chosen by the user from pictures (2026-10-01). Taken at 1k: the city
in front of them is blurred by depth of field, and 2k would weigh three times more with no
difference in the frame.

The script downloads the panoramas into `assets/sky/` and prints where the sun is on each —
azimuth and elevation of the brightest point: the game rotates the panorama so that its
sun stands where the city sunlight is ([CitySky]).

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
    """Radiance .hdr with RLE lines into a height×width×3 array, linear light."""
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
    """Azimuth and elevation of the brightest point, degrees, and its brightness."""
    height, width, _ = image.shape
    light = image.sum(axis=2)
    # Only the upper half: the bottom of a pure sky is a reflection of the sky.
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
        print(f"{key:14s} {sky:36s} sun: azimuth {azimuth:6.1f}°, elevation {elevation:5.1f}°, "
              f"peak {peak:9.1f}, mean {mean:6.3f}, {path.stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
