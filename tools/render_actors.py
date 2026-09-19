#!/usr/bin/env python3
"""Генератор ассетов актёров: лоу-поли модель в Blender, рендер в спрайты.

ADR-0011, пункт 1: покадровая согласованность — главный риск арт-пайплайна, и
Blender закрывает его насовсем. Кадры не рисуются заново, а снимаются с одной
и той же модели в разных позах, поэтому Otto не «дышит» между кадрами ходьбы.

Скрипт живёт двумя половинами в одном файле:

- **снаружи** (обычный python из `.venv`) он ищет Blender, запускает в нём сам
  себя, а потом собирает из отрендеренного готовые карты;
- **внутри** Blender (там есть `bpy`) он строит модель, расставляет позы и
  рендерит по два кадра на позу: цвет и глубину.

Нормаль не берётся из рендера, а считается из глубины тем же кодом, что и у
окружения (`render_env.normals`): соглашение о каналах в проекте одно.

    python tools/render_actors.py            # всё
    python tools/render_actors.py otto       # только Otto
    python tools/render_actors.py --list
"""

from __future__ import annotations

import argparse
import math
import sys
import tempfile
import warnings
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
OUT_DIR = PROJECT_ROOT / "assets/sprites/actors"

# Кадр актёра. Шире и выше коллизии (12×28 у Otto, 12×26 у агента) нарочно:
# шляпа, причёска и выброшенная в ударе нога живут в кадре, а не в коллизии
# (ADR-0011, пункт 4). Привязка кадра — низ, середина.
#
# Ширина взята по лежащему телу: упавший занимает вдоль пола свой рост, и
# в кадре по ширине коллизии от него оставалась бы четверть.
FRAME = (32, 34)
CAR_FRAME = (56, 26)

# Во сколько раз плотнее рендерить кадр. Кадр задан в единицах мира, и масштаб
# меняет только разрешение: камера остаётся на месте, модель занимает ту же
# площадь, но пикселей на неё приходится больше. Здесь — в отличие от
# окружения — прибавка настоящая: это рендер 3D, а не набор прямоугольников.
#
# У актёров масштаб выше, чем у окружения (4.5 против 3): пиксель ассета — это
# единица мира, и более плотный рендер делает Otto крупнее в самом мире. Игра,
# сыгранная руками, показала, что человечек рядом с дверью слишком мал
# (ADR-0018, решение 5).
SCALE: float = 1.0

# Камера стоит далеко и смотрит вдоль +Y; глубина модели укладывается в эту
# полосу вокруг нуля. Из неё же получается карта высот для нормали.
CAMERA_DISTANCE = 100.0
DEPTH_SPAN = 10.0

# Насколько резко глубина превращается в наклон нормали. Мягче, чем у
# окружения: у фигуры и так крутые склоны, и на 3.0 она выглядела жестяной.
NORMAL_STRENGTH = 1.6


def _poses() -> dict[str, dict]:
    """Позы Otto. Углы — в градусах, положительный угол уводит конечность назад.

    Набор ровно тот, что записан в ADR-0011, пункт 5 с дополнением 12:
    по кадру на состояние машины состояний, ходьба в три кадра, смерть в две
    позы и отдельная поза раздавленного.
    """
    return {
        "idle": {"legs": (0.0, 0.0), "arms": (6.0, -6.0)},
        # Три кадра ходьбы: шаг, проход, шаг с другой ноги.
        "walk_0": {"legs": (26.0, -26.0), "arms": (-20.0, 20.0)},
        "walk_1": {"legs": (4.0, -4.0), "arms": (-4.0, 4.0), "lift": 1.0},
        "walk_2": {"legs": (-26.0, 26.0), "arms": (20.0, -20.0)},
        "crouch": {"crouch": True, "arms": (14.0, -14.0)},
        "jump": {"legs": (20.0, -10.0), "arms": (-42.0, -48.0)},
        # Отдельной позы падения нет нарочно: в воздухе Otto бьёт ногой всегда
        # (ADR-0006, пункт 2), и State.FALL показывается тем же «kick». Своя
        # «fall» лежала бы в репозитории ассетом, которого никто не грузит.
        # Удар ногой: нога уходит вперёд горизонтально, корпус отклоняется назад.
        "kick": {"legs": (-80.0, 18.0), "arms": (26.0, -16.0), "lean": 14.0},
        "shoot": {"legs": (0.0, 0.0), "arms": (6.0, -92.0), "gun": True},
        # Смерть: падение и лежащее тело (ADR-0011, пункт 12).
        "dead_0": {"tilt": 45.0, "legs": (-18.0, 10.0), "arms": (34.0, -36.0)},
        "dead_1": {"tilt": 90.0, "legs": (-10.0, 8.0), "arms": (40.0, -30.0)},
        # Раздавленный кабиной или лампой: та же модель, сплющенная по высоте.
        "crushed": {"squash": 0.3, "legs": (-30.0, 30.0), "arms": (60.0, -60.0)},
        # Агент, залёгший под пулю (ADR-0016, пункт 2). От "dead_1" отличается
        # тем, ради чего и ложится: голова поднята, ствол смотрит вперёд —
        # лежачий агент продолжает стрелять, а труп нет.
        "prone": {
            "tilt": 78.0,
            "legs": (-6.0, 6.0),
            "arms": (10.0, -88.0),
            "gun": True,
            "lift": 1.0,
        },
    }


def _actors() -> dict[str, dict]:
    """Кто рендерится и чем отличается.

    Агент отличается не только палитрой, но и головой: шляпа с полями против
    помпадура (ADR-0011, пункт 13). На погашенном этаже цвета почти нет, и
    силуэт — единственное, по чему игрок отличает своего от чужого.
    """
    otto_poses = _poses()
    agent_poses = {
        name: pose
        for name, pose in otto_poses.items()
        # Агент не прыгает и не бьёт ногой — ему этого не умеет EnemyBrain,
        # и кадры на несуществующие состояния были бы мусором. А приседать он
        # с M11 умеет: "crouch" служит ему позой «на колене» (ADR-0016, п. 3).
        if name not in ("jump", "kick")
    }
    # "prone" — только агенту: Otto не ложится, у него для уклонения присед.
    otto_poses.pop("prone", None)
    return {
        "otto": {
            "poses": otto_poses,
            "height": 28.0,
            "head": "pompadour",
            "suit": palette.OTTO_SUIT,
            "suit_shade": palette.OTTO_SUIT_SHADE,
            "skin": palette.OTTO_SKIN,
            "crown": palette.OTTO_HAIR,
            "eyes": palette.OTTO_TIE,
        },
        "agent": {
            "poses": agent_poses,
            "height": 26.0,
            "head": "hat",
            "suit": palette.AGENT_SUIT,
            "suit_shade": palette.AGENT_SUIT_SHADE,
            "skin": palette.AGENT_SKIN,
            "crown": palette.AGENT_HAT,
            "eyes": palette.AGENT_SUIT_SHADE,
        },
    }


# --- Половина, которая работает внутри Blender -------------------------------


def _emission(name: str, color: Rgb):
    """Материал, светящийся ровно своим цветом: рендер отдаёт плоское альбедо."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    shader = tree.nodes.new("ShaderNodeEmission")
    shader.inputs["Color"].default_value = (*palette.to_linear(color), 1.0)
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(shader.outputs["Emission"], out.inputs["Surface"])
    return material


def _depth_material():
    """Материал, светящийся глубиной: ближе к камере — светлее.

    Композитор Blender 5.2 переписан на узлы-группы, и вытаскивать через него
    нормаль оказалось дороже, чем снять глубину вторым проходом обычным
    шейдером. Нормаль всё равно считается нашим кодом.
    """
    material = bpy.data.materials.new("depth")
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    camera = tree.nodes.new("ShaderNodeCameraData")
    ramp = tree.nodes.new("ShaderNodeMapRange")
    ramp.inputs["From Min"].default_value = CAMERA_DISTANCE - DEPTH_SPAN
    ramp.inputs["From Max"].default_value = CAMERA_DISTANCE + DEPTH_SPAN
    ramp.inputs["To Min"].default_value = 1.0
    ramp.inputs["To Max"].default_value = 0.0
    ramp.clamp = True
    tree.links.new(camera.outputs["View Z Depth"], ramp.inputs["Value"])
    shader = tree.nodes.new("ShaderNodeEmission")
    tree.links.new(ramp.outputs["Result"], shader.inputs["Color"])
    out = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(shader.outputs["Emission"], out.inputs["Surface"])
    return material


def _box(name: str, size, pivot, centre, material, parent):
    """Коробка, у которой начало координат — сустав.

    Меш сдвигается относительно начала координат, поэтому поворот объекта —
    это поворот в суставе: нога вращается вокруг бедра, а не вокруг ступни.
    """
    from mathutils import Matrix

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 0.0))
    cube = bpy.context.object
    cube.name = name
    cube.data.transform(Matrix.Translation(centre) @ Matrix.Diagonal((*size, 1.0)))
    cube.location = pivot
    cube.data.materials.append(material)
    cube.parent = parent
    return cube


def _build(actor: dict, pose: dict):
    """Фигура целиком: ноги, корпус, руки, голова и то, что на голове."""
    crouch = bool(pose.get("crouch", False))
    legs = pose.get("legs", (0.0, 0.0))
    arms = pose.get("arms", (0.0, 0.0))

    # Присед — это не поза конечностей, а другие пропорции: коллизия приседа
    # 18 px против 28 стоя, и фигура обязана уложиться ровно в неё.
    hip = 2.0 if crouch else 10.0
    torso_top = 9.0 if crouch else 19.0
    head_side = 9.0
    scale = actor["height"] / 28.0

    root = bpy.data.objects.new("figure", None)
    bpy.context.scene.collection.objects.link(root)

    suit = _emission("suit", actor["suit"])
    suit_shade = _emission("suit_shade", actor["suit_shade"])
    skin = _emission("skin", actor["skin"])
    crown = _emission("crown", actor["crown"])
    eyes = _emission("eyes", actor["eyes"])

    leg_length = hip
    for index, (side, angle) in enumerate(zip((-1.0, 1.0), legs, strict=True)):
        leg = _box(
            "leg_%d" % index,
            (3.0, 3.0, leg_length),
            (side * 2.6, side * -1.0, hip),
            (0.0, 0.0, -leg_length * 0.5),
            suit_shade,
            root,
        )
        leg.rotation_euler = (0.0, math.radians(angle), 0.0)

    torso = _box(
        "torso",
        (9.0, 5.0, torso_top - hip),
        (0.0, 0.0, hip),
        (0.0, 0.0, (torso_top - hip) * 0.5),
        suit,
        root,
    )
    torso.rotation_euler = (0.0, math.radians(pose.get("lean", 0.0)), 0.0)

    arm_length = torso_top - hip - 1.0
    shoulder = torso_top - 1.0
    for index, (side, angle) in enumerate(zip((-1.0, 1.0), arms, strict=True)):
        arm = _box(
            "arm_%d" % index,
            (2.5, 2.5, arm_length),
            (side * 5.0, side * -1.4, shoulder),
            (0.0, 0.0, -arm_length * 0.5),
            suit_shade if side < 0 else suit,
            root,
        )
        arm.rotation_euler = (0.0, math.radians(angle), 0.0)
        if pose.get("gun", False) and side > 0:
            # Пистолет висит на самой руке: рука повернулась — повернулся и он.
            _box("gun", (4.0, 1.5, 1.5), (0.0, 0.0, 0.0), (2.5, 0.0, -arm_length), eyes, arm)

    head_bottom = torso_top
    _box(
        "head",
        (head_side, 8.0, head_side),
        (0.0, 0.0, head_bottom),
        (0.0, 0.0, head_side * 0.5),
        skin,
        root,
    )
    for side in (-1.0, 1.0):
        _box(
            "eye_%d" % int(side),
            (1.0, 1.0, 1.0),
            (side * 2.0, -4.0, head_bottom + head_side * 0.55),
            (0.0, 0.0, 0.0),
            eyes,
            root,
        )

    head_top = head_bottom + head_side
    if actor["head"] == "hat":
        # Шляпа: поля шире головы, тулья над ними. Силуэт агента.
        _box("brim", (13.0, 11.0, 1.0), (0.0, 0.0, head_top - 0.5), (0.0, 0.0, 0.0), crown, root)
        _box("crown", (8.0, 7.0, 4.0), (0.0, 0.0, head_top), (0.0, 0.0, 2.0), crown, root)
    else:
        # Помпадур: кок вперёд и вверх. В оригинале он же попал на логотип.
        _box("hair", (9.0, 7.0, 2.5), (0.0, 0.0, head_top - 1.0), (0.0, 0.0, 1.2), crown, root)
        _box("quiff", (6.0, 5.0, 2.5), (0.0, -1.5, head_top), (0.0, 0.0, 1.8), crown, root)

    # Раздавленный расплющивается по высоте и раздаётся вширь: объём тела
    # никуда не девается, а поза должна читаться силуэтом.
    squash = pose.get("squash", 1.0)
    root.scale = (scale * (1.25 if squash < 1.0 else 1.0), scale, scale * squash)

    tilt = pose.get("tilt", 0.0)
    root.rotation_euler = (0.0, math.radians(tilt), 0.0)
    # Падающая фигура вращается вокруг пяток, поэтому уезжает вбок целиком:
    # без сдвига обратно лежащее тело вышло бы за кадр, а не легло в него.
    # По той же причине она опирается на пол боком, а не пяткой.
    fallen = math.sin(math.radians(tilt))
    lift = pose.get("lift", 0.0) + fallen * 5.0
    root.location = (-actor["height"] * fallen * 0.5, 0.0, lift)
    return root


def _car():
    """Красная машина у выхода: ею оригинал заканчивает здание."""
    root = bpy.data.objects.new("car", None)
    bpy.context.scene.collection.objects.link(root)

    body = _emission("car_body", palette.CAR_BODY)
    glass = _emission("car_glass", palette.GLASS)
    wheel = _emission("car_wheel", palette.SLAB_SHADOW)

    _box("body", (52.0, 12.0, 9.0), (0.0, 0.0, 5.0), (0.0, 0.0, 4.5), body, root)
    _box("cabin", (26.0, 11.0, 7.0), (-2.0, 0.0, 14.0), (0.0, 0.0, 3.5), body, root)
    _box("window", (20.0, 12.0, 4.0), (-2.0, -0.4, 15.5), (0.0, 0.0, 2.0), glass, root)
    for side in (-16.0, 16.0):
        _box("wheel_%d" % int(side), (9.0, 13.0, 9.0), (side, 0.0, 4.5), (0.0, 0.0, 0.0), wheel, root)
    return root


def _scene(frame: tuple[int, int]) -> None:
    """Пустая сцена с ортографической камерой: один пиксель кадра — один юнит."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    width, height = frame
    side = float(max(width, height))

    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = side
    camera = bpy.data.objects.new("camera", camera_data)
    camera.location = (0.0, -CAMERA_DISTANCE, height * 0.5)
    camera.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    scene.collection.objects.link(camera)
    scene.camera = camera

    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    # Плёнка без сглаживания: пиксель-арт, края обязаны быть краями.
    scene.cycles.pixel_filter_type = "BOX"
    scene.cycles.filter_width = 0.01
    scene.render.resolution_x = round(width * SCALE)
    scene.render.resolution_y = round(height * SCALE)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def _render(work: Path, name: str) -> None:
    """Два прохода на позу: цвет и глубина."""
    scene = bpy.context.scene

    # Standard, а не AgX по умолчанию: иначе цвет палитры уехал бы в тон плёнки.
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = str(work / f"{name}.png")
    bpy.ops.render.render(write_still=True)

    depth = _depth_material()
    for obj in scene.objects:
        if obj.type != "MESH":
            continue
        obj.data.materials.clear()
        obj.data.materials.append(depth)

    # Raw: глубина — это число, а не цвет, и кривую к ней применять нельзя.
    scene.view_settings.view_transform = "Raw"
    scene.render.filepath = str(work / f"{name}_depth.png")
    bpy.ops.render.render(write_still=True)


def _render_inside_blender(work: Path, scale: float, wanted: list[str]) -> None:
    global SCALE
    SCALE = max(scale, 1.0)
    actors = _actors()
    for actor_name in wanted:
        if actor_name == "car":
            _scene(CAR_FRAME)
            _car()
            _render(work, "car_parked")
            continue

        actor = actors[actor_name]
        for pose_name, pose in actor["poses"].items():
            _scene(FRAME)
            _build(actor, pose)
            _render(work, f"{actor_name}_{pose_name}")


# --- Половина, которая работает снаружи --------------------------------------


def _assemble(work: Path, out_dir: Path, name: str) -> list[Path]:
    """Из цвета и глубины — три карты, как у окружения."""
    import numpy as np
    from PIL import Image

    import render_env

    colour = np.array(Image.open(work / f"{name}.png").convert("RGBA"))
    depth = np.array(Image.open(work / f"{name}_depth.png").convert("RGBA"))

    mask = colour[:, :, 3] > 0
    height = depth[:, :, 0].astype(np.float32) / 255.0
    height = _fill_outside(height, mask)

    normal = render_env.normals(height, strength=NORMAL_STRENGTH)
    # За силуэтом нормаль смотрит прямо в камеру: иначе по краю спрайта шёл бы
    # кант от перепада глубины между фигурой и пустотой.
    normal[~mask] = (128, 128, 255)

    material = palette.FABRIC
    specular = np.zeros((*mask.shape, 4), dtype=np.uint8)
    specular[:, :, :3] = round(material.specular * 255.0)
    specular[:, :, 3] = round(material.shininess * 255.0)

    out_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for suffix, data in (
        ("", colour),
        (render_env.NORMAL_SUFFIX, normal),
        (render_env.SPECULAR_SUFFIX, specular),
    ):
        path = out_dir / f"{name}{suffix}.png"
        Image.fromarray(data).save(path, optimize=True)
        written.append(path)
    return written


def _fill_outside(height, mask, rounds: int = 4):
    """Заполняет пустоту вокруг фигуры её же глубиной.

    Иначе на границе силуэта перепад высоты идёт от нуля к телу, наклон там
    получается отвесным, и по контуру спрайта светится кант.
    """
    import numpy as np

    filled = np.where(mask, height, np.nan)
    for _round in range(rounds):
        padded = np.pad(filled, 1, mode="edge")
        neighbours = np.stack(
            (
                padded[:-2, 1:-1],
                padded[2:, 1:-1],
                padded[1:-1, :-2],
                padded[1:-1, 2:],
            )
        )
        with warnings.catch_warnings():
            # nanmean честно ругается на срез целиком из NaN, а в первых раундах
            # такие есть: NaN там — ожидаемый ответ, и следующий раунд его
            # заполнит. errstate этого предупреждения не глушит: оно приходит
            # через warnings, а не через флаги плавающей точки.
            warnings.simplefilter("ignore", RuntimeWarning)
            mean = np.nanmean(neighbours, axis=0)
        filled = np.where(np.isnan(filled), mean, filled)
    return np.nan_to_num(filled, nan=0.0).astype(np.float32)


def _names() -> list[str]:
    return [*_actors().keys(), "car"]


def _frame_names(wanted: list[str]) -> list[str]:
    """Какие кадры ждать от Blender. Считается по запросу, а не по содержимому
    папки: с `--keep` в ней лежат кадры прошлых прогонов, и сборка по ним молча
    перезаписывала бы ассеты, которых в этот раз не просили."""
    actors = _actors()
    names: list[str] = []
    for actor_name in wanted:
        if actor_name == "car":
            names.append("car_parked")
            continue
        names.extend(f"{actor_name}_{pose}" for pose in actors[actor_name]["poses"])
    return names


def _shown(path: Path) -> str:
    """Путь для вывода: внутри проекта — относительный, снаружи — как есть.

    `--out` умеет показывать куда угодно, и `relative_to` на такой путь падает:
    нашлось на пробе FullHD, где ассеты рендерились во временную папку.
    """
    try:
        return path.relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def main() -> int:
    parser = argparse.ArgumentParser(description="Рендер актёров через Blender.")
    parser.add_argument("names", nargs="*", help="кого рисовать; по умолчанию всех")
    parser.add_argument("--list", action="store_true", help="перечислить и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать PNG")
    parser.add_argument("--keep", type=Path, default=None, help="куда сложить сырые кадры")
    parser.add_argument(
        "--scale", type=float, default=1.0, help="во сколько раз плотнее рендерить (по умолчанию 1)"
    )
    arguments = parser.parse_args()

    from godot_bin import use_utf8_output

    use_utf8_output()

    if arguments.list:
        for name in _names():
            print(name)
        return 0

    wanted = arguments.names or _names()
    unknown = [name for name in wanted if name not in _names()]
    if unknown:
        print(f"Неизвестные актёры: {', '.join(unknown)}")
        print(f"Известные: {', '.join(_names())}")
        return 2

    import blender_bin

    blender = blender_bin.require_blender()
    with tempfile.TemporaryDirectory(prefix="elaction-actors-") as temporary:
        work = arguments.keep or Path(temporary)
        work.mkdir(parents=True, exist_ok=True)
        code, output = blender_bin.run_script(
            blender,
            Path(__file__),
            ["--inside", str(work), str(arguments.scale), *wanted],
            timeout=900,
        )
        if code != 0:
            print(output)
            print(f"Blender вернул {code}")
            return code

        for name in _frame_names(wanted):
            for path in _assemble(work, arguments.out, name):
                print(_shown(path))
    return 0


if __name__ == "__main__":
    if bpy is not None:
        arguments = sys.argv[sys.argv.index("--") + 1 :]
        _render_inside_blender(Path(arguments[1]), float(arguments[2]), arguments[3:])
    else:
        raise SystemExit(main())
