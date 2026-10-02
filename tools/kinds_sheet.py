#!/usr/bin/env python3
"""Три типа здания рядом одним кадром (ADR-0056): этаж башни и стилобата у
каждого типа в одно время суток и погоду — по нему и видно, разведены ли типы.

Снимает `tools/m24j_shot.tscn --only=floor --kind=N --floor=F` на каждый тип и
этаж и склеивает ряды: отель, офис, жилой дом.

    python tools/kinds_sheet.py M24n            # ночь, ясно
    python tools/kinds_sheet.py M24n --time=1   # день

Пишет `screens/<веха>/kinds_t<время>_w<погода>.jpg`.
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
    args = parser.parse_args()
    godot = require_godot()
    tile = (960, 540)
    sheet = Image.new("RGB", (tile[0] * len(FLOORS), tile[1] * len(KINDS)))
    for row, _name in enumerate(KINDS):
        for column, floor in enumerate(FLOORS):
            # Своя папка на время и погоду: кадр зовётся по ним, и в общей папке
            # «последний по имени» был бы кадром прошлого прогона (3night после 1day).
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
    target = PROJECT_ROOT / "screens" / args.milestone / f"kinds_t{args.time}_w{args.weather}.jpg"
    sheet.save(target, quality=88)
    print(f"  {target.relative_to(PROJECT_ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
