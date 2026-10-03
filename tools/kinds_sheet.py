#!/usr/bin/env python3
"""Three building kinds side by side in one shot (ADR-0056): a tower floor and a podium
floor of each kind at the same time of day and weather, which shows whether the kinds
are set apart.

Shoots `tools/m24j_shot.tscn --only=floor --kind=N --floor=F` for every kind and
floor and stitches the rows: hotel, office, residential building.

    python tools/kinds_sheet.py M24n            # night, clear
    python tools/kinds_sheet.py M24n --time=1   # day
    python tools/kinds_sheet.py M24o --floors=27,24,18,16   # halls of special floors

Writes `screens/<milestone>/kinds_t<time>_w<weather>.jpg`; with custom floors,
`kinds_t<time>_w<weather>_f<floors>.jpg`.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

FLOORS = (2, 24)
KINDS = ("отель", "офис", "жилой дом")


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Три типа здания рядом.")
    parser.add_argument("milestone")
    parser.add_argument("--time", type=int, default=3)
    parser.add_argument("--weather", type=int, default=0)
    parser.add_argument("--floors", default=",".join(str(f) for f in FLOORS),
                        help="этажи через запятую, по номеру сверху")
    args = parser.parse_args()
    floors = tuple(int(f) for f in args.floors.split(","))
    godot = require_godot()
    tile = (960, 540)
    sheet = Image.new("RGB", (tile[0] * len(floors), tile[1] * len(KINDS)))
    for row, _name in enumerate(KINDS):
        for column, floor in enumerate(floors):
            # A separate folder per time and weather: the shot is named after them, and in a shared
            # folder "the last by name" would be a shot from the previous run (3night after 1day).
            folder = f"{args.milestone}/kinds/t{args.time}_w{args.weather}/k{row}_f{floor}"
            code, output = run(godot, [
                "res://tools/m24j_shot.tscn", "--", "--only=floor", f"--kind={row}",
                f"--floor={floor}", f"--time={args.time}", f"--weather={args.weather}",
                f"--folder={folder}",
            ], timeout=240)
            shots = sorted((PROJECT_ROOT / "screens" / folder).glob("*_floor.png"))
            if code != 0 or not shots:
                print(output[-1500:])
                return 1
            frame = Image.open(shots[-1]).convert("RGB").resize(tile)
            sheet.paste(frame, (column * tile[0], row * tile[1]))
    suffix = "" if floors == FLOORS else "_f" + "-".join(str(f) for f in floors)
    target = PROJECT_ROOT / "screens" / args.milestone / f"kinds_t{args.time}_w{args.weather}{suffix}.jpg"
    sheet.save(target, quality=88)
    print(f"  {target.relative_to(PROJECT_ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
