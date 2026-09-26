#!/usr/bin/env python3
"""Сборка актёров из паков Quaternius: Otto, агент и машины, экспорт в glTF.

С M21 (ADR-0032) фигура не строится из коробок, а берётся из Ultimate Modular
Men Pack (CC0) — персонаж Business Man, исходник в `assets/source/quaternius/`.
Скрипт приводит его к игре:

- рост — ровно `Proportions.BODY`, вместе с ключами позиций в клипах;
- материалы — палитра актёра: у Otto кремовый костюм, у агента тёмно-синий;
- агенту — федора и тёмные очки на кости головы (ADR-0032, решения 2 и 4);
- обоим — пистолет на кисти правой руки: в паке его нет (решение 5);
- из 24 клипов остаются четыре, с короткими именами (решение 1);
- машины Cars Pack — капотом в +X, длиной `Proportions.CAR_LENGTH` (решение 7).

Скрипт живёт двумя половинами в одном файле:

- **снаружи** (обычный python из `.venv`) он ищет Blender и запускает в нём
  сам себя;
- **внутри** Blender (там есть `bpy`) он собирает модели и пишет `.glb`.

    python tools/build_actors.py             # всех
    python tools/build_actors.py otto        # только Otto
    python tools/build_actors.py cars        # только машины
    python tools/build_actors.py --list
    python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>
"""

from __future__ import annotations

import argparse
import functools
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
# Внутри Blender папка запускаемого скрипта в sys.path не попадает.
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

# Цвет байтами sRGB.
Rgb = tuple[int, int, int]

# Цвета актёров. Жили в `palette.py` — генераторе палитры 2D-спрайтов (ADR-0019,
# решение 8); с уборкой 2D в M22 от него остались только они, и место им здесь.
OTTO_SUIT: Rgb = (0xE8, 0xE3, 0xD2)
OTTO_SUIT_SHADE: Rgb = (0xB9, 0xB4, 0xA4)
OTTO_HAIR: Rgb = (0x3A, 0x2E, 0x27)
OTTO_SKIN: Rgb = (0xD8, 0xA6, 0x7B)
OTTO_TIE: Rgb = (0x3A, 0x3F, 0x4E)
AGENT_SUIT: Rgb = (0x2F, 0x35, 0x47)
AGENT_SUIT_SHADE: Rgb = (0x23, 0x28, 0x3A)
AGENT_HAT: Rgb = (0x26, 0x2B, 0x3B)
AGENT_SKIN: Rgb = (0xC0, 0x8F, 0x68)

try:
    import bpy
except ImportError:  # снаружи Blender
    bpy = None

PROJECT_ROOT = TOOLS.parent
OUT_DIR = PROJECT_ROOT / "assets/models"
PROPORTIONS = PROJECT_ROOT / "src/systems/proportions.gd"
SOURCE = PROJECT_ROOT / "assets/source/quaternius/business_man.glb"

# Клипы пака, которые идут в игру, и их имена там. Остальные двадцать
# выбрасываются: в файле они весили бы больше самой модели. Те же имена ждёт
# `FigureRig` — разойдясь, риг встанет в позу кодом и скажет об этом ошибкой.
#
# С M24c движение приходит из UAL (`UAL_CLIPS`), а у пака не берётся ни одного
# клипа: словарь оставлен, чтобы клип пака можно было вернуть одной строкой.
CLIPS: dict[str, str] = {}

# Движение с M24c — из Universal Animation Library (Quaternius, CC0), перенесённое
# на скелет пака (ADR-0039, решение 1). В репозитории лежит урезанный исходник:
# скелет и нужные клипы без манекена — полный файл больше предела хука. Урезает
# команда `ual`: python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>
UAL_SOURCE = PROJECT_ROOT / "assets/source/quaternius/ual_clips.glb"
UAL_URL = "https://opengameart.org/content/universal-animation-library"

# Клипы UAL и их имена в игре. Имена ждёт `FigurePoses`.
UAL_CLIPS: dict[str, str] = {
    # Нейтральная стойка, руки вниз: основа поз кодом (`FigurePoses`), сама
    # в кадре не играет. Стойка с пистолетом в обеих руках для этого не годится.
    "Idle_Loop": "stand",
    "Pistol_Idle_Loop": "idle",
    "Walk_Loop": "walk",
    "Pistol_Shoot": "shoot",
    "Death01": "death",
    "Jump_Start": "jump_start",
    # Не «jump_loop»: суффикс `_loop` импорт Godot срезает с имени клипа.
    "Jump_Loop": "jump_air",
    "Jump_Land": "jump_land",
    "Crouch_Idle_Loop": "crouch",
}

# Кость пака — кость UAL. Скелет UAL собран по Rigify, и кость к кости ложится
# на пака; пальцы переносятся тоже, иначе кисть не держит пистолет. У пака
# кончики пальцев (…4) лишние — они идут за своим суставом как есть.
UAL_BONES: dict[str, str] = {
    "Hips": "DEF-hips",
    "Abdomen": "DEF-spine.001",
    "Torso": "DEF-spine.002",
    "Chest": "DEF-spine.003",
    "Neck": "DEF-neck",
    "Head": "DEF-head",
    "UpperLeg.L": "DEF-thigh.L",
    "LowerLeg.L": "DEF-shin.L",
    "Foot.L": "DEF-foot.L",
    "UpperLeg.R": "DEF-thigh.R",
    "LowerLeg.R": "DEF-shin.R",
    "Foot.R": "DEF-foot.R",
}
for _side in ("L", "R"):
    UAL_BONES |= {
        f"Shoulder.{_side}": f"DEF-shoulder.{_side}",
        f"UpperArm.{_side}": f"DEF-upper_arm.{_side}",
        f"LowerArm.{_side}": f"DEF-forearm.{_side}",
        f"Wrist.{_side}": f"DEF-hand.{_side}",
    }
    for _finger in ("Index", "Middle", "Ring", "Pinky"):
        for _joint in (1, 2, 3):
            UAL_BONES[f"{_finger}{_joint}.{_side}"] = f"DEF-f_{_finger.lower()}.0{_joint}.{_side}"
    for _joint in (1, 2, 3):
        UAL_BONES[f"Thumb{_joint}.{_side}"] = f"DEF-thumb.0{_joint}.{_side}"

# Стопы пака прицеплены к корню (скелет под IK): в перенесённом клипе стопа
# встаёт на конец голени — туда, где она была в покое относительно голени.
UAL_ATTACH: dict[str, str] = {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}
# Покачивание таза UAL несёт `Body`: ноги пака висят на нём, а не на `Hips`.
UAL_CARRIER = "Body"

CARS_SOURCE = PROJECT_ROOT / "assets/source/quaternius/cars"

# Машины Cars Pack и материал кузова у каждой: его игра перекрашивает жребием
# (ADR-0032, решение 7). У второй спортивной кузов двухцветный — тёмная
# половина уходит в `PaintShade`. Такси и полиции здесь нет: шпион на
# патрульной машине странен.
CARS: dict[str, dict[str, str]] = {
    "sports_car_2": {"Orange": "Paint", "DarkOrange": "PaintShade"},
    "sports_car_1": {"White": "Paint"},
    "car_1": {"Blue": "Paint"},
    "car_2": {"LightBlue": "Paint"},
    "suv": {"White": "Paint"},
}

# Глубина машины по бамперам вместе с колёсами, м: сколько влезает между задней
# стеной и телом Otto (авторевью M18c и M20). Машины пака в 1.8 м шириной
# сжимаются по глубине отдельно — сбоку этого не видно, а колёса остаются
# круглыми: длина и высота идут одним масштабом.
CAR_DEPTH = 0.74

# Кости пака, к которым крепятся надетые вещи.
HEAD_BONE = "Head"
HAND_BONE = "Wrist.R"


def proportion(name: str) -> float:
    """Число из `Proportions` игры, в метрах.

    Рост актёров задаётся в игре одной таблицей (ADR-0026, решение 8), и модель
    обязана быть ровно того роста, что и коллизия. Своей копии числа здесь нет:
    скрипт читает константы из `proportions.gd` и считает их выражения —
    простую арифметику над ранее объявленными.
    """
    return _proportions()[name]


@functools.cache
def _proportions() -> dict[str, float]:
    """Все числовые константы `proportions.gd`, разобранные один раз.

    Числа от векторов (`DOOR_MAT` от `DOOR.x`) и всё, что не число, —
    строка, массив, выражение со словами GDScript — пропускаются: модели они
    не нужны, а падать на них разбору незачем.
    """
    known: dict[str, float] = {}
    for line in PROPORTIONS.read_text(encoding="utf-8").splitlines():
        if not line.startswith("const ") or ":=" in line:
            continue
        head, _, expression = line[len("const ") :].partition("=")
        key = head.split(":")[0].strip()
        try:
            value = eval(expression, {"__builtins__": {}}, dict(known))
        except Exception:  # noqa: BLE001 — любая не-арифметика GDScript
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            known[key] = float(value)
    return known


def _actors() -> dict[str, dict]:
    """Кто строится и чем отличается.

    Модель у обоих одна, поэтому своего от чужого отличают цвет и голова:
    у агента федора и очки (ADR-0032, решения 2–4). На погашенном этаже цвета
    почти нет, и силуэт со шляпой — то, по чему игрок узнаёт агента.

    Ключи `colours` — материалы пака: `Suit` — брюки, `Suit.001` — пиджак.
    Материалы, которых здесь нет (рубашка, ботинки, глаза), остаются пака.
    """
    return {
        "otto": {
            "colours": {
                "Suit": OTTO_SUIT_SHADE,
                "Suit.001": OTTO_SUIT,
                "Tie": OTTO_TIE,
                "Skin": OTTO_SKIN,
                "Hair": OTTO_HAIR,
            },
            "hat": False,
            "glasses": False,
        },
        "agent": {
            "colours": {
                "Suit": AGENT_SUIT_SHADE,
                "Suit.001": AGENT_SUIT,
                "Tie": AGENT_SUIT_SHADE,
                "Skin": AGENT_SKIN,
                "Hair": AGENT_HAT,
            },
            "hat": True,
            "glasses": True,
        },
    }


# --- Половина, которая работает внутри Blender -------------------------------


def _reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _linear(colour: Rgb) -> tuple[float, float, float, float]:
    """Цвет палитры в материал: байты sRGB, переведённые в линейный цвет.

    Фигура M16 писала байты как есть, и тёмно-синий костюм агента выходил
    бледно-голубым: 0x2F как линейный — это 0.46 на экране. В оригинале агенты
    чёрные, и на сравнении M21 разница била в глаза. Материалы пака заданы
    линейно, и палитра, легшая рядом с ними, обязана быть в том же пространстве.
    """

    def channel(byte: int) -> float:
        value = byte / 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    red, green, blue = colour
    return (channel(red), channel(green), channel(blue), 1.0)


def _material(name: str, colour: Rgb, roughness: float = 0.85):
    material = bpy.data.materials.new(name)
    # В Blender 5 материал узловой с рождения, и флаг только ругается.
    if not material.use_nodes:
        material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _linear(colour)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return material


def _import_pack():
    """Исходник пака в сцену. Возвращает арматуру и её меши.

    Импорт glTF приносит лишнее: пустышки концов костей и икосферу — форму,
    которой импортёр рисует кости. В модель они не идут.
    """
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    meshes = [obj for obj in armature.children if obj.type == "MESH"]
    for obj in list(bpy.context.scene.objects):
        if obj is not armature and obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    return armature, meshes


def _channelbags(action):
    """Кривые клипа. В Blender 5 действия слоёные: слой → полоса → мешок."""
    for layer in action.layers:
        for strip in layer.strips:
            yield from strip.channelbags


def _keep_clips(armature) -> None:
    """Оставляет клипы пака из `CLIPS` и переименовывает их.

    Импортёр раскладывает каждый клип на свою дорожку NLA; экспорт берёт
    действия, поэтому лишние удаляются вместе с дорожками.
    """
    data = armature.animation_data
    for track in list(data.nla_tracks):
        data.nla_tracks.remove(track)
    data.action = None
    for action in list(bpy.data.actions):
        if action.name in CLIPS:
            action.name = CLIPS[action.name]
            action.use_fake_user = True
        else:
            bpy.data.actions.remove(action)
    missing = set(CLIPS.values()) - {action.name for action in bpy.data.actions}
    if missing:
        raise RuntimeError("в паке нет клипов: " + ", ".join(sorted(missing)))


def _stage_clips(armature) -> None:
    """Экспорт в режиме действий берёт те, что можно повесить на арматуру:
    каждый клип по очереди ставится ей дорожкой NLA."""
    data = armature.animation_data
    for action in bpy.data.actions:
        track = data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 0, action)


def _strip_ual(full: Path) -> None:
    """Урезает полный файл UAL до `UAL_SOURCE`: скелет и клипы `UAL_CLIPS`.

    Манекен и остальные клипы в игру не идут, а полный файл (6.5 МБ) больше
    предела хука на крупные файлы.
    """
    bpy.ops.import_scene.gltf(filepath=str(full))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    for obj in list(bpy.context.scene.objects):
        if obj is not rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    data = rig.animation_data
    for track in list(data.nla_tracks):
        data.nla_tracks.remove(track)
    data.action = None
    for action in list(bpy.data.actions):
        if action.name not in UAL_CLIPS:
            bpy.data.actions.remove(action)
    missing = set(UAL_CLIPS) - {action.name for action in bpy.data.actions}
    if missing:
        raise RuntimeError("в UAL нет клипов: " + ", ".join(sorted(missing)))
    _stage_clips(rig)
    _export(UAL_SOURCE)


def _import_ual():
    """Урезанный исходник UAL в сцену: арматура и клипы по исходным именам."""
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(UAL_SOURCE))
    rig = next(
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE" and obj.name != "CharacterArmature"
    )
    for obj in list(bpy.context.scene.objects):
        if obj.parent is rig and obj.type != "ARMATURE":
            bpy.data.objects.remove(obj, do_unlink=True)
    data = rig.animation_data
    for track in list(data.nla_tracks):
        data.nla_tracks.remove(track)
    clips = {action.name: action for action in bpy.data.actions if action not in before}
    return rig, clips


def _depth(bone) -> int:
    """Глубина кости для порядка переноса: родитель раньше ребёнка, а стопа —
    после голени, на которую её ставит `UAL_ATTACH`."""
    if bone.name in UAL_ATTACH:
        return 1 + _depth(bone.id_data.bones[UAL_ATTACH[bone.name]])
    return 0 if bone.parent is None else 1 + _depth(bone.parent)


def _lowest(meshes) -> float:
    """Низшая точка мешей в мире на текущем кадре, м."""
    import numpy

    depsgraph = bpy.context.evaluated_depsgraph_get()
    low = float("inf")
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        points = numpy.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get("co", points)
        world = numpy.asarray(evaluated.matrix_world)
        heights = points.reshape(-1, 3) @ world[2, :3] + world[2, 3]
        low = min(low, float(heights.min()))
        evaluated.to_mesh_clear()
    return low


def _retarget_ual(armature, meshes) -> None:
    """Переносит клипы UAL на скелет пака и запекает их в его действия.

    Обе фигуры стоят в покое в T-позе лицом в −Y мира, поэтому поворот кости в
    клипе — её поворот в мире, отсчитанный от покоя, — годится для парной кости
    пака как есть: R = R_ual · R_ual_покой⁻¹ · R_пака_покой. Считать приходится
    в мире, а не в пространстве арматуры: импортёр glTF поворачивает арматуру
    пака на 90° вокруг X кватернионом, а у UAL поворота нет.
    Место кости задаёт её родитель по цепочке, как в покое; исключения — стопы
    (`UAL_ATTACH`), которые пак держит на корне, и таз, чей ход несёт
    `UAL_CARRIER` в долях роста.

    Пак в этот момент ещё в своих единицах (масштаб 100 на объекте), поэтому
    ход таза из мира UAL переводится в арматуру пака с поправкой на высоту таза;
    `_scale_to` дальше домножит ключи позиций, как у клипов пака.

    Каждый кадр ставится на пол низшей вершиной меша: ноги пака длиннее, чем у
    UAL, и с перенесёнными углами подошва в шаге уходила в пол на 6 см. Ход
    корня — сдвиг всего скелета, стопы пака висят на нём же. Заземлённый клип
    игра не заземляет, и ей не приходится перебирать вершины на ходу.
    """
    from mathutils import Matrix, Vector

    rig, clips = _import_ual()
    source = {bone.name: bone for bone in rig.data.bones}
    target = sorted(armature.data.bones, key=_depth)
    hips_rest = source[UAL_BONES["Hips"]].head_local
    to_world = rig.matrix_world.to_3x3()
    from_world = armature.matrix_world.to_3x3().inverted()
    height = (armature.matrix_world @ armature.data.bones["Hips"].head_local).z
    scale = height / (rig.matrix_world @ hips_rest).z
    # Поворот из пространства арматуры UAL в пространство арматуры пака.
    across = (from_world @ to_world).to_quaternion().to_matrix()

    def rest(bone) -> Matrix:
        return bone.matrix_local.copy()

    armature.animation_data_create()
    for ual_name, game_name in UAL_CLIPS.items():
        clip = clips[ual_name]
        rig.animation_data.action = clip
        first, last = (int(round(frame)) for frame in clip.frame_range)
        action = bpy.data.actions.new(game_name)
        action.use_fake_user = True
        armature.animation_data.action = action
        for frame in range(first, last + 1):
            bpy.context.scene.frame_set(frame)
            posed: dict[str, Matrix] = {}
            for bone in target:
                name = bone.name
                parent = bone.parent
                parent_pose = posed[parent.name] if parent else Matrix.Identity(4)
                parent_rest = rest(parent) if parent else Matrix.Identity(4)
                # Как в покое за своим родителем — основа для любой кости.
                matrix = parent_pose @ parent_rest.inverted() @ rest(bone)
                if name in UAL_BONES:
                    twin = rig.pose.bones[UAL_BONES[name]]
                    delta = twin.matrix.to_3x3() @ rest(source[twin.name]).to_3x3().inverted()
                    turn = across @ delta @ across.inverted() @ rest(bone).to_3x3()
                    head = matrix.translation
                    if name in UAL_ATTACH:
                        anchor = armature.data.bones[UAL_ATTACH[name]]
                        head = posed[anchor.name] @ rest(anchor).inverted() @ bone.head_local
                    matrix = Matrix.Translation(head) @ turn.normalized().to_4x4()
                elif name == UAL_CARRIER:
                    moved = from_world @ to_world @ (rig.pose.bones[UAL_BONES["Hips"]].head - hips_rest) * scale
                    matrix = Matrix.Translation(bone.head_local + moved) @ rest(bone).to_3x3().to_4x4()
                posed[name] = matrix
                pose_bone = armature.pose.bones[name]
                own = parent_rest.inverted() @ rest(bone)
                pose_bone.matrix_basis = own.inverted() @ parent_pose.inverted() @ matrix
                pose_bone.rotation_mode = "QUATERNION"
                pose_bone.keyframe_insert("location", frame=frame - first)
                pose_bone.keyframe_insert("rotation_quaternion", frame=frame - first)
            bpy.context.view_layer.update()
            root = target[0]
            lifted = Matrix.Translation(from_world @ Vector((0.0, 0.0, -_lowest(meshes)))) @ posed[root.name]
            pose_root = armature.pose.bones[root.name]
            pose_root.matrix_basis = rest(root).inverted() @ lifted
            pose_root.keyframe_insert("location", frame=frame - first)
        armature.animation_data.action = None
    for obj in list(bpy.context.scene.objects):
        if obj is rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in clips.values():
        bpy.data.actions.remove(action)


def _height(meshes) -> tuple[float, float]:
    """Низ и верх фигуры в первом кадре стойки, м — по вершинам в мире.

    Мерка — не покой, а стойка: игра стоит в ней, и именно её рост обязан
    совпасть с коллизией. Клип стойки чуть сгибает колени, и по T-позе фигура
    выходила на 3 см ниже коллизии.
    """
    armature = meshes[0].parent
    data = armature.animation_data
    # Дорожки NLA всех клипов смешались бы со стойкой: на замер они глушатся.
    data.use_nla = False
    data.action = bpy.data.actions["idle"]
    bpy.context.scene.frame_set(0)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    low, high = float("inf"), float("-inf")
    for obj in meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            z = (evaluated.matrix_world @ vertex.co).z
            low, high = min(low, z), max(high, z)
        evaluated.to_mesh_clear()
    data.action = None
    data.use_nla = True
    return low, high


def _scale_to(armature, meshes, height: float) -> None:
    """Приводит рост к игре и запекает масштаб.

    Пак держит скелет в сотых долях с масштабом 100 на объекте арматуры.
    Масштаб объекта запекается в кости и вершины, но не в клипы: ключи
    позиций костей лежат в единицах скелета, и их приходится домножить на
    тот же множитель, иначе Hips в ходьбе качается на сотые доли сантиметра.
    """
    low, high = _height(meshes)
    factor = height / (high - low)
    object_scale = armature.scale.x * factor
    armature.scale = (object_scale,) * 3

    for obj in bpy.context.scene.objects:
        obj.select_set(obj is armature or obj in meshes)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    for action in bpy.data.actions:
        for bag in _channelbags(action):
            for curve in bag.fcurves:
                if curve.data_path.endswith(".location"):
                    for key in curve.keyframe_points:
                        key.co.y *= object_scale
                        key.handle_left.y *= object_scale
                        key.handle_right.y *= object_scale


def _recolour(meshes, colours: dict[str, Rgb]) -> None:
    """Материалы пака в палитру актёра; шершавость у всех одна, как у M16."""
    seen = set()
    for obj in meshes:
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.name in seen:
                continue
            seen.add(material.name)
            bsdf = material.node_tree.nodes.get("Principled BSDF")
            if bsdf is None:
                continue
            if material.name in colours:
                base = bsdf.inputs["Base Color"]
                # Импорт glTF заводит цвет иных материалов через свой узел, и
                # тогда значение гнезда молчит: связь рвётся, цвет пишется в гнездо.
                for link in list(base.links):
                    material.node_tree.links.remove(link)
                base.default_value = _linear(colours[material.name])
            bsdf.inputs["Roughness"].default_value = 0.85
            bsdf.inputs["Metallic"].default_value = 0.0


def _bone_head(armature, bone: str):
    return armature.matrix_world @ armature.data.bones[bone].head_local


def _head_box(meshes):
    """Габарит головы в покое: вершины материалов лица и волос выше шеи."""
    from mathutils import Vector

    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for obj in meshes:
        if obj.name != "Suit_Head":
            continue
        for vertex in obj.data.vertices:
            world = obj.matrix_world @ vertex.co
            low = Vector(map(min, low, world))
            high = Vector(map(max, high, world))
    return low, high


def _part(name: str, build, material, bone: str):
    """Меш из `build(bm)`, целиком привязанный к кости [param bone]."""
    import bmesh

    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    group = obj.vertex_groups.new(name=bone)
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    return obj


def _box_into(bm, size, centre, rotation=None) -> None:
    import bmesh
    from mathutils import Matrix

    made = bmesh.ops.create_cube(bm, size=1.0)
    verts = made["verts"]
    bmesh.ops.scale(bm, vec=size, verts=verts)
    if rotation is not None:
        bmesh.ops.rotate(bm, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(*rotation), verts=verts)
    bmesh.ops.translate(bm, vec=centre, verts=verts)


def _cylinder_into(bm, radius_x, radius_y, radius_top_scale, height, base, segments=16) -> None:
    """Эллиптический цилиндр от [param base] вверх; верх сужен в [param radius_top_scale]."""
    import bmesh

    made = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=1.0,
        radius2=radius_top_scale,
        depth=height,
    )
    verts = made["verts"]
    bmesh.ops.scale(bm, vec=(radius_x, radius_y, 1.0), verts=verts)
    bmesh.ops.translate(bm, vec=(base[0], base[1], base[2] + height * 0.5), verts=verts)


def _hat(meshes, armature, colour: Rgb):
    """Федора: узкие поля и тулья с заломом сверху (ADR-0032, решение 2).

    Сидит низко, над бровями, и прячет волосы: грани причёски выше полей
    удаляются, иначе они прорастали бы сквозь тулью в любой позе.
    """
    low, high = _head_box(meshes)
    centre_x = (low.x + high.x) * 0.5
    centre_y = (low.y + high.y) * 0.5
    half_x = (high.x - low.x) * 0.5
    half_y = (high.y - low.y) * 0.5
    head_height = high.z - low.z
    brim_z = high.z - head_height * 0.3
    crown_height = head_height * 0.36

    def build(bm) -> None:
        # Поля: плоский эллипс шире головы, чуть длиннее вперёд-назад.
        _cylinder_into(bm, half_x * 2.0, half_y * 1.85, 1.0, head_height * 0.025, (centre_x, centre_y, brim_z))
        # Тулья сужается кверху, а верх её — залом: вторая, узкая и низкая
        # ступень сверху даёт силуэту «гребень», по которому федору и узнают.
        _cylinder_into(bm, half_x * 1.08, half_y * 1.04, 0.8, crown_height * 0.8, (centre_x, centre_y, brim_z))
        _cylinder_into(
            bm, half_x * 0.62, half_y * 0.8, 0.7, crown_height * 0.2, (centre_x, centre_y, brim_z + crown_height * 0.8)
        )

    hat = _part("hat", build, _material("hat", colour, roughness=0.7), HEAD_BONE)
    _trim_hair(meshes, brim_z + head_height * 0.02)
    return hat


def _trim_hair(meshes, above_z: float) -> None:
    """Удаляет грани причёски выше [param above_z]: их закрывает шляпа."""
    import bmesh

    for obj in meshes:
        if obj.name != "Suit_Head":
            continue
        hair = [index for index, slot in enumerate(obj.material_slots) if slot.material and slot.material.name == "Hair"]
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        doomed = [
            face
            for face in bm.faces
            if face.material_index in hair and (obj.matrix_world @ face.calc_center_median()).z > above_z
        ]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(obj.data)
        bm.free()


def _glasses(meshes):
    """Тёмные очки: два стекла и перемычка перед глазами (ADR-0032, решение 4)."""
    eye_low, eye_high = _material_box(meshes, "Eye")
    front_y = eye_low.y - 0.006
    centre_z = (eye_low.z + eye_high.z) * 0.5
    span = eye_high.x - eye_low.x
    lens = (span * 0.5, 0.008, span * 0.28)

    def build(bm) -> None:
        for side in (-1.0, 1.0):
            _box_into(bm, lens, (side * span * 0.3, front_y, centre_z))
        _box_into(bm, (span * 0.14, 0.006, span * 0.06), (0.0, front_y, centre_z + span * 0.06))

    return _part("glasses", build, _material("glasses", (0x0B, 0x0C, 0x10), roughness=0.2), HEAD_BONE)


def _material_box(meshes, material_name: str):
    """Габарит граней одного материала в покое."""
    from mathutils import Vector

    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for obj in meshes:
        slots = [i for i, slot in enumerate(obj.material_slots) if slot.material and slot.material.name == material_name]
        if not slots:
            continue
        for polygon in obj.data.polygons:
            if polygon.material_index not in slots:
                continue
            for index in polygon.vertices:
                world = obj.matrix_world @ obj.data.vertices[index].co
                low = Vector(map(min, low, world))
                high = Vector(map(max, high, world))
    if low.x == float("inf"):
        raise RuntimeError("в модели нет материала " + material_name)
    return low, high


def _gun(armature):
    """Пистолет в правой кисти (ADR-0032, решение 5).

    Ставится в покое, в T-позе: рука вытянута вбок ладонью вниз, пальцы — к −X.
    Клипы пака «с оружием» проворачивают кисть так, что в позе выстрела её −X
    смотрит по взгляду, а +Y (тыл ладони в T-позе, к спине) — вниз. Поэтому
    ствол лежит вдоль пальцев, а рукоять уходит из ладони к +Y. Пробой по кадрам
    `tools/actor_shot.tscn`: ствол по −Y вставал в позе выстрела торчком.
    """
    wrist = _bone_head(armature, HAND_BONE)
    palm = wrist.x - 0.06  # середина ладони: пальцы идут к −X

    def build(bm) -> None:
        # Затвор со стволом вдоль пальцев, над кулаком.
        _box_into(bm, (0.19, 0.036, 0.03), (palm - 0.04, wrist.y - 0.035, wrist.z))
        # Рукоять — в кулаке, к тылу ладони, с лёгким завалом назад.
        _box_into(bm, (0.035, 0.1, 0.028), (palm + 0.01, wrist.y + 0.02, wrist.z), (-0.25, 3, "Z"))

    return _part("gun", build, _material("gun", (0x1A, 0x1C, 0x22), roughness=0.4), HAND_BONE)


def _dress(armature, meshes, actor: dict) -> None:
    """Надевает вещи и сливает всё в один меш под скелетом."""
    parts = [_gun(armature)]
    if actor["glasses"]:
        parts.append(_glasses(meshes))
    if actor["hat"]:
        parts.append(_hat(meshes, armature, actor["colours"]["Hair"]))

    for obj in bpy.context.scene.objects:
        obj.select_set(obj in meshes or obj in parts)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "body"
    body.data.name = "body"
    if not any(modifier.type == "ARMATURE" for modifier in body.modifiers):
        modifier = body.modifiers.new("Armature", "ARMATURE")
        modifier.object = armature
    body.parent = armature


def _figure(actor: dict) -> None:
    armature, meshes = _import_pack()
    _keep_clips(armature)
    _retarget_ual(armature, meshes)
    _stage_clips(armature)
    _scale_to(armature, meshes, proportion("BODY"))
    _recolour(meshes, actor["colours"])
    _dress(armature, meshes, actor)


def _car(name: str) -> None:
    """Машина Cars Pack, приведённая к игре.

    Капот — в +X Blender (он же +X сцены Godot после экспорта), длина — ровно
    `Proportions.CAR_LENGTH` и высота тем же масштабом, глубина —
    [constant CAR_DEPTH]. Где перед, скажут фары: у пака машины смотрят кто
    куда. Колёса остаются своими объектами — игра крутит их, когда машина
    уезжает. Начало у них не на оси, а в нуле машины, как их положил пак,
    поэтому `ExitCar` крутит каждое вокруг середины его меша.
    """
    from mathutils import Matrix, Vector

    bpy.ops.import_scene.gltf(filepath=str(CARS_SOURCE / f"{name}.glb"))
    objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]

    lights = Vector((0.0, 0.0, 0.0))
    count = 0
    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    for obj in objects:
        for polygon in obj.data.polygons:
            material = obj.material_slots[polygon.material_index].material if obj.material_slots else None
            centre = obj.matrix_world @ polygon.center
            if material is not None and material.name == "Headlights":
                lights += centre
                count += 1
        for vertex in obj.data.vertices:
            world = obj.matrix_world @ vertex.co
            low = Vector(map(min, low, world))
            high = Vector(map(max, high, world))
    if count == 0:
        raise RuntimeError(name + ": у машины нет фар — не понять, где перед")
    lights /= count
    size = high - low
    centre = (low + high) * 0.5
    # Длина — по большей горизонтальной оси; поворот кладёт фары в +X.
    along_y = size.y > size.x
    angle = 0.0
    if along_y:
        angle = -1.5707963 if lights.y > centre.y else 1.5707963
    elif lights.x < centre.x:
        angle = 3.1415927
    length = size.y if along_y else size.x
    depth = size.x if along_y else size.y
    factor = proportion("CAR_LENGTH") / length
    squeeze = CAR_DEPTH / depth
    # Центр по длине и глубине — в нуле, колёса — на полу.
    place = (
        Matrix.Diagonal((factor, squeeze, factor, 1.0))
        @ Matrix.Rotation(angle, 4, "Z")
        @ Matrix.Translation((-centre.x, -centre.y, -low.z))
    )
    tops = [obj for obj in objects if obj.parent is None or obj.parent.type != "MESH"]
    for obj in tops:
        obj.matrix_world = place @ obj.matrix_world
    for obj in objects:
        for other in bpy.context.scene.objects:
            other.select_set(other is obj)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        if "Wheel" in obj.name:
            obj.name = "Wheel" + obj.name.split("Wheel", 1)[1].split("_", 1)[0]

    renames = CARS[name]
    for obj in objects:
        for slot in obj.material_slots:
            material = slot.material
            if material is not None and material.name in renames:
                material.name = renames[material.name]
            if material is not None:
                bsdf = material.node_tree.nodes.get("Principled BSDF")
                if bsdf is not None:
                    bsdf.inputs["Metallic"].default_value = 0.0
    for obj in list(bpy.context.scene.objects):
        if obj.type not in ("MESH", "EMPTY"):
            bpy.data.objects.remove(obj, do_unlink=True)


def _export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
    )


def _build_inside_blender(out_dir: Path, wanted: list[str]) -> None:
    actors = _actors()
    if wanted and wanted[0] == "ual":
        _reset_scene()
        _strip_ual(Path(wanted[1]))
        print(f"  {UAL_SOURCE.name}")
        return
    for name in wanted:
        if name == "cars":
            for car in CARS:
                _reset_scene()
                _car(car)
                _export(out_dir / "cars" / f"{car}.glb")
                print(f"  cars/{car}.glb")
            continue
        _reset_scene()
        _figure(actors[name])
        _export(out_dir / f"{name}.glb")
        print(f"  {name}.glb")


# --- Половина, которая работает снаружи --------------------------------------


def _names() -> list[str]:
    return [*_actors().keys(), "cars"]


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
    if wanted[0] == "ual":
        if len(wanted) != 2 or not Path(wanted[1]).is_file():
            print(f"Нужен путь к AnimationLibrary_Godot_Standard.glb — архив на {UAL_URL}")
            return 2
        wanted = ["ual", str(Path(wanted[1]).resolve())]
    unknown = [name for name in wanted if name not in _names() and wanted[0] != "ual"]
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
