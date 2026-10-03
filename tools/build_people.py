#!/usr/bin/env python3
"""Pedestrians at the exit from Quaternius's townspeople packs (ADR-0054, decision 3).

Men — Ultimate Modular Men Pack, women — Ultimate Modular Women Pack
(CC0): one skeleton for all and 24 animations. A pedestrian needs two — walking and
standing — and the rest are removed from the model: this makes it four times lighter.
Output — `assets/models/people/<name>.glb`.

Sources are glTF files of individual pack characters in `.cache/people/` named
`men_casual_2.gltf`, `women_formal.gltf` and so on; they are not in the repository,
like the city pack. Download: https://quaternius.com/packs/ultimatemodularcharacters.html
and https://quaternius.com/packs/ultimatemodularwomen.html — folder
`Individual Characters/glTF`.

    python tools/build_people.py
"""

from __future__ import annotations

import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

try:
    import bpy
except ImportError:
    bpy = None

ROOT = TOOLS.parent
SOURCE = ROOT / ".cache" / "people"
TARGET = ROOT / "assets" / "models" / "people"

# Who walks along the sidewalk: the source name in `.cache/people/`.
PEOPLE = [
    "men_casual_2",
    "men_casual_hoodie",
    "men_suit",
    "men_worker",
    "women_casual",
    "women_formal",
    "women_suit",
    "women_worker",
]

# Which animations remain: walking and standing at the traffic light.
KEEP = {"Walk", "Idle"}

# What is removed from the model: some characters of the pack hold a weapon.
WEAPONS = ("Pistol", "Gun", "Sword", "Knife", "Revolver")


def inside_blender() -> int:
    TARGET.mkdir(parents=True, exist_ok=True)
    for name in PEOPLE:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE / f"{name}.gltf"))
        # The pack's weapons — a pistol and, for some, a sword — are of no use to a pedestrian.
        for obj in list(bpy.context.scene.objects):
            if any(word in obj.name for word in WEAPONS):
                bpy.data.objects.remove(obj, do_unlink=True)
        for action in list(bpy.data.actions):
            if action.name not in KEEP:
                bpy.data.actions.remove(action)
        for obj in bpy.context.scene.objects:
            data = obj.animation_data
            if data is None:
                continue
            for track in list(data.nla_tracks):
                if not any(strip.action and strip.action.name in KEEP for strip in track.strips):
                    data.nla_tracks.remove(track)
        bpy.ops.export_scene.gltf(
            filepath=str(TARGET / f"{name}.glb"),
            export_format="GLB",
            export_animations=True,
            export_animation_mode="ACTIONS",
        )
        print(f"собран {name}")
    return 0


def outside() -> int:
    from blender_bin import require_blender, run_script, use_utf8_output

    use_utf8_output()
    missing = [name for name in PEOPLE if not (SOURCE / f"{name}.gltf").exists()]
    if missing:
        print(f"нет исходников в {SOURCE}: {', '.join(missing)} (см. начало файла)")
        return 1
    blender = require_blender()
    code, output = run_script(blender, Path(__file__), timeout=1800)
    for line in output.splitlines():
        if "собран" in line or "Error" in line or "Traceback" in line or "rror:" in line:
            print(line)
    return code


if __name__ == "__main__":
    raise SystemExit(inside_blender() if bpy is not None else outside())
