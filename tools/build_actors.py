#!/usr/bin/env python3
"""Конструктор актёров: фигура из коробок на скелете, экспорт в glTF.

Наследник `render_actors.py`. Тот строил ту же фигуру в Blender и снимал с неё
спрайты; с M16 (ADR-0022) Blender отдаёт не кадры, а модель: арматуру с костями
бёдер, корпуса, головы, рук и ног и коробки, привязанные весами по одной кости.
Двигает кости уже игра — `FigureRig` по таблице `FigurePoses`, — поэтому
клипов анимации в файле нет.

Скрипт живёт двумя половинами в одном файле:

- **снаружи** (обычный python из `.venv`) он ищет Blender и запускает в нём
  сам себя;
- **внутри** Blender (там есть `bpy`) он строит фигуры и пишет `.glb`.

    python tools/build_actors.py             # всех
    python tools/build_actors.py otto        # только Otto
    python tools/build_actors.py --list
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
# Внутри Blender папка запускаемого скрипта в sys.path не попадает.
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import palette
from palette import Rgb

try:
    import bpy
except ImportError:  # снаружи Blender
    bpy = None

PROJECT_ROOT = TOOLS.parent
OUT_DIR = PROJECT_ROOT / "assets/models"

# Фигура описана в долях роста: 28 долей на Otto, как было у спрайтов
# (ADR-0011, пункт 8). Доля переводится в метры ростом актёра, поэтому
# пропорции чиби общие, а рост — у каждого свой и равен его коллизии.
UNITS: float = 28.0

# Имена костей. Те же ищет FigureRig в Godot: разойдясь, риг молча останется
# стоять столбом — проверяется тестом со сценой.
HIPS = "hips"
TORSO = "torso"
HEAD = "head"
ARM_L = "arm_l"
ARM_R = "arm_r"
LEG_L = "leg_l"
LEG_R = "leg_r"


def _actors() -> dict[str, dict]:
    """Кто строится и чем отличается.

    Агент отличается не только палитрой, но и головой: шляпа с полями против
    помпадура (ADR-0011, пункт 13). На погашенном этаже цвета почти нет, и
    силуэт — единственное, по чему игрок отличает своего от чужого.
    """
    return {
        "otto": {
            "height": 1.26,
            "head": "pompadour",
            "suit": palette.OTTO_SUIT,
            "suit_shade": palette.OTTO_SUIT_SHADE,
            "skin": palette.OTTO_SKIN,
            "crown": palette.OTTO_HAIR,
            "eyes": palette.OTTO_TIE,
        },
        "agent": {
            "height": 1.17,
            "head": "hat",
            "suit": palette.AGENT_SUIT,
            "suit_shade": palette.AGENT_SUIT_SHADE,
            "skin": palette.AGENT_SKIN,
            "crown": palette.AGENT_HAT,
            "eyes": palette.AGENT_SUIT_SHADE,
        },
    }


# --- Половина, которая работает внутри Blender -------------------------------


def _reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _material(name: str, colour: Rgb):
    """Матовый материал ровно своего цвета: шершавость подберёт M17."""
    material = bpy.data.materials.new(name)
    # В Blender 5 материал узловой с рождения, и флаг только ругается.
    if not material.use_nodes:
        material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    red, green, blue = colour
    bsdf.inputs["Base Color"].default_value = (red / 255.0, green / 255.0, blue / 255.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    bsdf.inputs["Metallic"].default_value = 0.0
    return material


def _box(name: str, size, centre, material, bone: str | None = None):
    """Коробка с уже выпеченным положением: объект стоит в начале координат,
    а вершины — где надо. Так слияние в один меш ничего не сдвигает.

    [param bone] — кость, к которой коробка привязана целиком.
    """
    import bmesh

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=centre, verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if bone is not None:
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    return obj


def _armature(name: str, bones: list[tuple[str, tuple, tuple, str | None]]):
    """Арматура из списка (имя, голова, хвост, родитель). Ось кости — от головы
    к хвосту; конечности смотрят вниз, и тогда их локальная X — это бок фигуры:
    поворот вокруг неё качает ногу вперёд-назад, ровно как нужно ходьбе."""
    data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone_name, head, tail, parent in bones:
        bone = data.edit_bones.new(bone_name)
        bone.head = head
        bone.tail = tail
        bone.roll = 0.0
        if parent is not None:
            bone.parent = data.edit_bones[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def _join(parts: list, name: str):
    """Сливает коробки в один меш: группы вершин и материалы переживают слияние."""
    for obj in bpy.context.scene.objects:
        obj.select_set(False)
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    body.data.name = name
    return body


def _figure(actor: dict) -> None:
    """Фигура целиком на скелете. Стоит в начале координат ногами, смотрит в -Y:
    после экспорта с Y вверх это +Z сцены Godot, то есть в камеру."""
    unit = actor["height"] / UNITS
    hip = 10.0 * unit
    torso_top = 19.0 * unit
    head_side = 9.0 * unit
    head_top = torso_top + head_side

    suit = _material("suit", actor["suit"])
    suit_shade = _material("suit_shade", actor["suit_shade"])
    skin = _material("skin", actor["skin"])
    crown = _material("crown", actor["crown"])
    eyes = _material("eyes", actor["eyes"])

    shoulder = torso_top - 1.0 * unit
    arm_length = torso_top - hip - 1.0 * unit
    parts = []

    for bone, side in ((LEG_L, -1.0), (LEG_R, 1.0)):
        parts.append(
            _box(
                bone,
                (3.0 * unit, 3.0 * unit, hip),
                (side * 2.6 * unit, side * -1.0 * unit, hip * 0.5),
                suit_shade,
                bone,
            )
        )

    parts.append(
        _box(
            TORSO,
            (9.0 * unit, 5.0 * unit, torso_top - hip),
            (0.0, 0.0, (hip + torso_top) * 0.5),
            suit,
            TORSO,
        )
    )

    for bone, side in ((ARM_L, -1.0), (ARM_R, 1.0)):
        parts.append(
            _box(
                bone,
                (2.5 * unit, 2.5 * unit, arm_length),
                (side * 5.0 * unit, side * -1.4 * unit, shoulder - arm_length * 0.5),
                suit_shade if side < 0 else suit,
                bone,
            )
        )
    # Пистолет висит в правой руке и смотрит вперёд: рука повернулась —
    # повернулся и он. Всегда при себе: агент, как и Otto, вооружён.
    parts.append(
        _box(
            "gun",
            (1.5 * unit, 4.0 * unit, 1.5 * unit),
            (5.0 * unit, -1.4 * unit - 2.5 * unit, shoulder - arm_length),
            eyes,
            ARM_R,
        )
    )

    parts.append(
        _box(
            HEAD,
            (head_side, 8.0 * unit, head_side),
            (0.0, 0.0, torso_top + head_side * 0.5),
            skin,
            HEAD,
        )
    )
    for side in (-1.0, 1.0):
        parts.append(
            _box(
                "eye_%d" % int(side),
                (1.0 * unit, 1.0 * unit, 1.0 * unit),
                (side * 2.0 * unit, -4.0 * unit, torso_top + head_side * 0.55),
                eyes,
                HEAD,
            )
        )

    if actor["head"] == "hat":
        # Шляпа: поля шире головы, тулья над ними. Силуэт агента.
        parts.append(
            _box(
                "brim",
                (13.0 * unit, 11.0 * unit, 1.0 * unit),
                (0.0, 0.0, head_top - 0.5 * unit),
                crown,
                HEAD,
            )
        )
        parts.append(
            _box(
                "crown",
                (8.0 * unit, 7.0 * unit, 4.0 * unit),
                (0.0, 0.0, head_top + 2.0 * unit),
                crown,
                HEAD,
            )
        )
    else:
        # Помпадур: кок вперёд и вверх. В оригинале он же попал на логотип.
        parts.append(
            _box(
                "hair",
                (9.0 * unit, 7.0 * unit, 2.5 * unit),
                (0.0, 0.0, head_top + 0.2 * unit),
                crown,
                HEAD,
            )
        )
        parts.append(
            _box(
                "quiff",
                (6.0 * unit, 5.0 * unit, 2.5 * unit),
                (0.0, -1.5 * unit, head_top + 1.8 * unit),
                crown,
                HEAD,
            )
        )

    rig = _armature(
        "rig",
        [
            (HIPS, (0.0, 0.0, hip), (0.0, 0.0, hip + 1.5 * unit), None),
            (TORSO, (0.0, 0.0, hip), (0.0, 0.0, torso_top), HIPS),
            (HEAD, (0.0, 0.0, torso_top), (0.0, 0.0, head_top), TORSO),
            (ARM_L, (-5.0 * unit, 1.4 * unit, shoulder), (-5.0 * unit, 1.4 * unit, shoulder - arm_length), TORSO),
            (ARM_R, (5.0 * unit, -1.4 * unit, shoulder), (5.0 * unit, -1.4 * unit, shoulder - arm_length), TORSO),
            (LEG_L, (-2.6 * unit, 1.0 * unit, hip), (-2.6 * unit, 1.0 * unit, 0.0), HIPS),
            (LEG_R, (2.6 * unit, -1.0 * unit, hip), (2.6 * unit, -1.0 * unit, 0.0), HIPS),
        ],
    )

    body = _join(parts, "body")
    modifier = body.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    body.parent = rig


def _car() -> None:
    """Красная машина у выхода: ею оригинал заканчивает здание. Без скелета —
    у неё одна поза. Длина — GreyboxLevel.CAR_LENGTH, 2.4 м; по ней уровень ставит
    машину в зазор от проёма. Высота выходит 0.95 м, ширина 0.6 — они ничьи."""
    unit = 2.4 / 52.0
    body = _material("car_body", palette.CAR_BODY)
    glass = _material("car_glass", palette.GLASS)
    wheel = _material("car_wheel", palette.SLAB_SHADOW)

    parts = [
        _box("body", (52.0 * unit, 12.0 * unit, 9.0 * unit), (0.0, 0.0, 9.0 * unit), body),
        _box("cabin", (26.0 * unit, 11.0 * unit, 7.0 * unit), (-2.0 * unit, 0.0, 17.0 * unit), body),
        _box("window", (20.0 * unit, 12.0 * unit, 4.0 * unit), (-2.0 * unit, -0.4 * unit, 17.5 * unit), glass),
    ]
    for side in (-16.0, 16.0):
        parts.append(
            _box(
                "wheel_%d" % int(side),
                (9.0 * unit, 13.0 * unit, 9.0 * unit),
                (side * unit, 0.0, 4.5 * unit),
                wheel,
            )
        )
    _join(parts, "car")


def _export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_animations=False,
        export_skins=True,
    )


def _build_inside_blender(out_dir: Path, wanted: list[str]) -> None:
    actors = _actors()
    for name in wanted:
        _reset_scene()
        if name == "car":
            _car()
        else:
            _figure(actors[name])
        _export(out_dir / f"{name}.glb")
        print(f"  {name}.glb")


# --- Половина, которая работает снаружи --------------------------------------


def _names() -> list[str]:
    return [*_actors().keys(), "car"]


def _parser() -> argparse.ArgumentParser:
    """Один разбор на обе половины: снаружи — вся командная строка, внутри
    Blender — то, что осталось после `--`."""
    parser = argparse.ArgumentParser(description="Сборка моделей актёров через Blender.")
    parser.add_argument("names", nargs="*", help="кого собирать; по умолчанию всех")
    parser.add_argument("--list", action="store_true", help="перечислить и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать .glb")
    return parser


def main() -> int:
    arguments = _parser().parse_args()

    from blender_bin import require_blender, run_script
    from godot_bin import use_utf8_output

    use_utf8_output()
    if arguments.list:
        for name in _names():
            print(name)
        return 0

    wanted = arguments.names or _names()
    unknown = [name for name in wanted if name not in _names()]
    if unknown:
        print("Не знаю таких актёров: " + ", ".join(unknown))
        return 2

    blender = require_blender()
    out_dir = arguments.out.resolve()
    code, output = run_script(blender, Path(__file__), ["--out", str(out_dir), *wanted])
    # Blender болтлив: печатаем только имена собранных моделей и ошибки.
    for line in output.splitlines():
        if line.strip().endswith(".glb") or "Error" in line or "Traceback" in line or "rror:" in line:
            print(line)
    if code != 0:
        print(f"Blender завершился с кодом {code}")
        return 1
    # Папка вне проекта (`--out` в temp) печатается как есть: relative_to на ней падает.
    shown = (
        out_dir.relative_to(PROJECT_ROOT).as_posix()
        if out_dir.is_relative_to(PROJECT_ROOT)
        else str(out_dir)
    )
    print(f"Модели в {shown}/")
    return 0


def _main_inside_blender() -> None:
    # Blender разбирает командную строку до `--` сам; скрипту достаётся остаток.
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    arguments = _parser().parse_args(argv)
    _build_inside_blender(arguments.out, arguments.names or _names())


if __name__ == "__main__":
    if bpy is not None:
        _main_inside_blender()
    else:
        raise SystemExit(main())
