#!/usr/bin/env python3
"""A milestone frame next to the original's frame: one height, arcade on the left, us on the right.

This way discrepancies are seen by eye, not in a table: on M18c the comparison immediately showed
what was in no measurement — a sparse floor, missing floor
numbers, a roof that does not read as the top of a building.

The original's frames are native MAME snapshots, 256×224. They are downloaded on demand
into `screens/_original/` and do not go into the repository: they are shots of someone else's
game, like the whole `screens/` folder. The building field is taken from the original's frame —
without the HUD above and the brick strip below, 176 px — because that is what our camera shows.

Run:
    python tools/compare_original.py M18C                 # last frame of the milestone
    python tools/compare_original.py M18C --shot stopped  # frame by step label
    python tools/compare_original.py M18C --original elevator

Writes `screens/<milestone>/compare_original.jpg`.
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from pathlib import Path

from PIL import Image

from godot_bin import PROJECT_ROOT, use_utf8_output

SCREENS = PROJECT_ROOT / "screens"
ORIGINALS = SCREENS / "_original"

# MAME snapshots: floors 30–27 with the roof and floors 19–16 with escalators.
SOURCES = {
    "elevatorb": "https://adb.arcadeitalia.net/media/mame.current/ingames/elevatorb.png",
    "elevator": "https://adb.arcadeitalia.net/media/mame.current/ingames/elevator.png",
}

# The building field in the original's frame: below the HUD and above the brick strip.
FIELD = (0, 16, 256, 192)
HEIGHT = 1080
GAP = 20


def original(name: str) -> Path:
    """Path to the original's frame, downloaded on first access."""
    ORIGINALS.mkdir(parents=True, exist_ok=True)
    path = ORIGINALS / f"{name}.png"
    if not path.exists():
        request = urllib.request.Request(SOURCES[name], headers={"User-Agent": "elaction"})
        with urllib.request.urlopen(request, timeout=30) as response:
            path.write_bytes(response.read())
    return path


def our_shot(milestone: str, label: str | None) -> Path:
    """The last frame of the milestone, and with a label — the last frame of that step.

    "Last" — by write time, not by name: the time in a frame name has
    one-second precision, and steps shot in the same second would be sorted by
    label alphabetically. A name taken in the same second is continued by Screenshotter
    with a `-N` suffix, and the label is searched with it too.
    """
    folder = SCREENS / milestone
    shots = [p for p in folder.glob("*.jpg") if not p.name.startswith("compare")]
    if label:
        pattern = re.compile(rf"_{re.escape(label)}(-\d+)?$")
        shots = [p for p in shots if pattern.search(p.stem)]
    shots.sort(key=lambda p: p.stat().st_mtime)
    if not shots:
        raise SystemExit(f"No shots in {folder}{f' for step {label}' if label else ''}: run capture.py first")
    return shots[-1]


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="A milestone shot next to the original.")
    parser.add_argument("milestone", help="milestone, as in capture.py, e.g. M18C")
    parser.add_argument("--shot", help="scenario step label, e.g. stopped")
    parser.add_argument("--original", choices=sorted(SOURCES), default="elevatorb")
    args = parser.parse_args()

    arcade = Image.open(original(args.original)).convert("RGB").crop(FIELD)
    arcade = arcade.resize((round(arcade.width * HEIGHT / arcade.height), HEIGHT), Image.NEAREST)
    ours = Image.open(our_shot(args.milestone, args.shot)).convert("RGB")
    ours = ours.resize((round(ours.width * HEIGHT / ours.height), HEIGHT), Image.LANCZOS)

    sheet = Image.new("RGB", (arcade.width + GAP + ours.width, HEIGHT))
    sheet.paste(arcade, (0, 0))
    sheet.paste(ours, (arcade.width + GAP, 0))
    out = SCREENS / args.milestone / "compare_original.jpg"
    sheet.save(out, quality=90)
    print(out.relative_to(PROJECT_ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
