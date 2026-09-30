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
# С M24c движение приходит из UAL (`UAL_LIBRARIES`), а у пака не берётся ни одного
# клипа: словарь оставлен, чтобы клип пака можно было вернуть одной строкой.
CLIPS: dict[str, str] = {}

# Движение с M24c — из Universal Animation Library (Quaternius, CC0), перенесённое
# на скелет пака (ADR-0039, решение 1); с M24d к ней добавлена вторая часть,
# UAL 2, — удары и реакции для сценок добивания (ADR-0040). В репозитории лежат
# урезанные исходники: скелет и нужные клипы без манекена — полные файлы больше
# предела хука. Урезает команда `ual`, библиотеку она узнаёт по скелету:
#     python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>
#     python tools/build_actors.py ual <UAL2_Standard.glb>
#
# Скелет у обеих частей один и тот же, до миллиметра в покое, — разные только
# имена костей: у первой по Rigify, у второй по манекену Unreal. Поэтому кости
# пака сопоставлены именам первой (`UAL_BONES`), а вторая переводит их своей
# таблицей (`names`).
UAL_LIBRARIES: dict[str, dict] = {
    "ual": {
        "source": PROJECT_ROOT / "assets/source/quaternius/ual_clips.glb",
        "url": "https://opengameart.org/content/universal-animation-library",
        # По этой кости `ual` узнаёт библиотеку.
        "marker": "DEF-hips",
        # Клипы и их имена в игре. Имена ждёт `FigurePoses`.
        "clips": {
            # Нейтральная стойка, руки вниз: основа поз кодом (`FigurePoses`),
            # сама в кадре не играет. Стойка с пистолетом для этого не годится.
            "Idle_Loop": "stand",
            "Pistol_Idle_Loop": "idle",
            "Walk_Loop": "walk",
            "Pistol_Shoot": "shoot",
            "Death01": "death",
            "Jump_Start": "jump_start",
            # Не «jump_loop»: суффикс `_loop` импорт Godot срезает с имени.
            "Jump_Loop": "jump_air",
            "Jump_Land": "jump_land",
            "Punch_Jab": "punch_jab",
            "Punch_Cross": "punch_cross",
            "Hit_Head": "hit_head",
            "Hit_Chest": "hit_chest",
        },
        "names": {},
    },
    "ual2": {
        "source": PROJECT_ROOT / "assets/source/quaternius/ual2_clips.glb",
        "url": "https://opengameart.org/content/universal-animation-library-2",
        "marker": "pelvis",
        "clips": {
            "Hit_Knockback": "knockback",
        },
        "names": {},
    },
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

# Имена костей UAL 2 по именам UAL 1.
_UAL2_NAMES: dict[str, str] = {
    "DEF-hips": "pelvis",
    "DEF-spine.001": "spine_01",
    "DEF-spine.002": "spine_02",
    "DEF-spine.003": "spine_03",
    "DEF-neck": "neck_01",
    "DEF-head": "Head",
}
for _side, _low in (("L", "l"), ("R", "r")):
    _UAL2_NAMES |= {
        f"DEF-shoulder.{_side}": f"clavicle_{_low}",
        f"DEF-upper_arm.{_side}": f"upperarm_{_low}",
        f"DEF-forearm.{_side}": f"lowerarm_{_low}",
        f"DEF-hand.{_side}": f"hand_{_low}",
        f"DEF-thigh.{_side}": f"thigh_{_low}",
        f"DEF-shin.{_side}": f"calf_{_low}",
        f"DEF-foot.{_side}": f"foot_{_low}",
    }
    for _finger in ("index", "middle", "ring", "pinky"):
        for _joint in (1, 2, 3):
            _UAL2_NAMES[f"DEF-f_{_finger}.0{_joint}.{_side}"] = f"{_finger}_0{_joint}_{_low}"
    for _joint in (1, 2, 3):
        _UAL2_NAMES[f"DEF-thumb.0{_joint}.{_side}"] = f"thumb_0{_joint}_{_low}"
UAL_LIBRARIES["ual2"]["names"] = _UAL2_NAMES

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


def _strip_ual(full: Path) -> str:
    """Урезает полный файл UAL до исходника своей библиотеки: скелет и её клипы.
    Библиотеку узнаёт по скелету и возвращает её имя.

    Манекен и остальные клипы в игру не идут, а полный файл (6.5–8 МБ) больше
    предела хука на крупные файлы.
    """
    bpy.ops.import_scene.gltf(filepath=str(full))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    kind = next(
        (name for name, library in UAL_LIBRARIES.items() if library["marker"] in rig.data.bones),
        None,
    )
    if kind is None:
        raise RuntimeError("не узнаю библиотеку по скелету: " + full.name)
    wanted = UAL_LIBRARIES[kind]["clips"]
    for obj in list(bpy.context.scene.objects):
        if obj is not rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    data = rig.animation_data
    for track in list(data.nla_tracks):
        data.nla_tracks.remove(track)
    data.action = None
    for action in list(bpy.data.actions):
        if action.name not in wanted:
            bpy.data.actions.remove(action)
    missing = set(wanted) - {action.name for action in bpy.data.actions}
    if missing:
        raise RuntimeError(f"в {kind} нет клипов: " + ", ".join(sorted(missing)))
    _stage_clips(rig)
    _export(UAL_LIBRARIES[kind]["source"])
    return kind


def _import_ual(source: Path):
    """Урезанный исходник UAL в сцену: арматура и клипы по исходным именам."""
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=str(source))
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
    """Переносит клипы обеих частей UAL на скелет пака."""
    for library in UAL_LIBRARIES.values():
        _retarget_library(armature, meshes, library)


def _retarget_library(armature, meshes, library: dict) -> None:
    """Переносит клипы одной библиотеки UAL на скелет пака и запекает их в его
    действия.

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

    rig, clips = _import_ual(library["source"])
    names = library["names"]

    def twin_of(bone_name: str) -> str:
        return names.get(UAL_BONES[bone_name], UAL_BONES[bone_name])

    source = {bone.name: bone for bone in rig.data.bones}
    target = sorted(armature.data.bones, key=_depth)
    hips_rest = source[twin_of("Hips")].head_local
    to_world = rig.matrix_world.to_3x3()
    from_world = armature.matrix_world.to_3x3().inverted()
    height = (armature.matrix_world @ armature.data.bones["Hips"].head_local).z
    scale = height / (rig.matrix_world @ hips_rest).z
    # Поворот из пространства арматуры UAL в пространство арматуры пака.
    across = (from_world @ to_world).to_quaternion().to_matrix()

    def rest(bone) -> Matrix:
        return bone.matrix_local.copy()

    armature.animation_data_create()
    for ual_name, game_name in library["clips"].items():
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
                    twin = rig.pose.bones[twin_of(name)]
                    delta = twin.matrix.to_3x3() @ rest(source[twin.name]).to_3x3().inverted()
                    turn = across @ delta @ across.inverted() @ rest(bone).to_3x3()
                    head = matrix.translation
                    if name in UAL_ATTACH:
                        anchor = armature.data.bones[UAL_ATTACH[name]]
                        head = posed[anchor.name] @ rest(anchor).inverted() @ bone.head_local
                    matrix = Matrix.Translation(head) @ turn.normalized().to_4x4()
                elif name == UAL_CARRIER:
                    moved = from_world @ to_world @ (rig.pose.bones[twin_of("Hips")].head - hips_rest) * scale
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
    # Шляпа — своим мешем `hat` на кости головы, а не в общем теле: на ударе
    # добивания она слетает (ADR-0050), и игра прячет её, не трогая тело.
    hat = _hat(meshes, armature, actor["colours"]["Hair"]) if actor["hat"] else None
    if hat is not None:
        hat.name = "hat"
        hat.data.name = "hat"
        modifier = hat.modifiers.new("Armature", "ARMATURE")
        modifier.object = armature
        hat.parent = armature

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
    body = max(
        (obj for obj in objects if "Wheel" not in obj.name), key=lambda obj: len(obj.data.polygons)
    )
    # Проём и салон считаются в мировых координатах: начало кузова — в нуль.
    for other in bpy.context.scene.objects:
        other.select_set(other is body)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    kind = CABIN_KINDS[CABINS[name]]
    cabin = _cabin_box(body)
    _cut_the_door(body, cabin, kind)
    _furnish_the_cabin(cabin, _roof_over(body, cabin), kind)
    _indicators(body)


# Салон и водительская дверь (ADR-0046, решение 1). Дверь — у борта +Y
# Blender: у стоящей у ворот машины он к камере. Дверь — доля длины машины,
# передний край — у основания лобового стекла; порог — над днищем кузова.
DOOR_SILL_LIFT = 0.1
# Салон по типу машины: у купе дверь длиннее, сиденья низкие ковшом и сзади
# только полка; у седана и универсала — диван, у универсала и внедорожника —
# багажник за ним; внедорожник сидит выше и прямее. Числа: доля длины машины
# под дверь, подъём подушки в долях высоты салона, наклон спинки и руля, рад.
CABINS: dict[str, str] = {
    "sports_car_2": "coupe",
    "sports_car_1": "coupe",
    "car_1": "sedan",
    "car_2": "wagon",
    "suv": "suv",
}
CABIN_KINDS: dict[str, dict] = {
    "coupe": {"door": 0.31, "seat": 0.1, "recline": 0.4, "wheel": 0.62, "rear": False, "cargo": False, "buckets": True},
    "sedan": {"door": 0.27, "seat": 0.2, "recline": 0.24, "wheel": 0.45, "rear": True, "cargo": False, "buckets": False},
    "wagon": {"door": 0.27, "seat": 0.2, "recline": 0.22, "wheel": 0.45, "rear": True, "cargo": True, "buckets": False},
    "suv": {"door": 0.27, "seat": 0.3, "recline": 0.14, "wheel": 0.3, "rear": True, "cargo": True, "buckets": False},
}
# Толщина дверцы с обшивкой и глубина проёма в кузове, м.
DOOR_SKIN = 0.03
JAMB_DEPTH = 0.05
# Салон: обшивка, сиденья, торпедо, потолок, плафон — цвета sRGB.
LINING: Rgb = (132, 100, 76)
SEAT: Rgb = (58, 40, 34)
DASH: Rgb = (30, 30, 34)
HEADLINER: Rgb = (168, 156, 136)
DOME_LAMP: Rgb = (255, 236, 200)
CARPET: Rgb = (44, 40, 38)
GAUGE: Rgb = (200, 230, 255)
INDICATOR: Rgb = (255, 140, 20)


def _cabin_box(body):
    """Салон по стёклам модели: (низ, верх) углов, Blender-координаты.

    По длине — от заднего стекла до лобового, по высоте — от порога до крыши,
    по глубине — внутри бортов.
    """
    from mathutils import Vector

    low = Vector((float("inf"),) * 3)
    high = Vector((float("-inf"),) * 3)
    body_low = float("inf")
    for polygon in body.data.polygons:
        centre = body.matrix_world @ polygon.center
        body_low = min(body_low, centre.z)
        slot = body.material_slots[polygon.material_index] if body.material_slots else None
        if slot is None or slot.material is None or slot.material.name != "Windows":
            continue
        low = Vector(map(min, low, centre))
        high = Vector(map(max, high, centre))
    if low.x == float("inf"):
        raise RuntimeError(body.name + ": нет стёкол — не понять, где салон")
    sill = body_low + DOOR_SILL_LIFT
    return Vector((low.x, -0.27, sill)), Vector((high.x, 0.27, high.z + 0.02))


def _cut_the_door(body, cabin, kind: dict) -> None:
    """Водительская дверь — отдельной деталью `DriverDoor`, проём — в кузове.

    Кузов режется плоскостями по краям двери и порогу; грани борта +Y между
    ними уходят в дверь. Край проёма в кузове вытягивается внутрь — у проёма
    видна толщина, а не бумажный срез. Дверь толщиной [constant DOOR_SKIN],
    изнутри — обшивка `Lining`. Начало двери — на петле у передней стойки: игра
    поворачивает её вокруг вертикали через начало.
    """
    import bmesh
    from mathutils import Vector

    low, high = cabin
    front = high.x - 0.02
    rear = front - proportion("CAR_LENGTH") * kind["door"]
    sill = low.z

    bm = bmesh.new()
    bm.from_mesh(body.data)
    for co, no in (((front, 0, 0), (1, 0, 0)), ((rear, 0, 0), (1, 0, 0)), ((0, 0, sill), (0, 0, 1))):
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no)
    bm.normal_update()
    door_faces = [
        face
        for face in bm.faces
        if rear < face.calc_center_median().x < front
        and face.calc_center_median().z > sill
        and face.calc_center_median().y > 0.05
        and face.normal.y > 0.45
    ]
    if not door_faces:
        raise RuntimeError(body.name + ": у борта нет граней под дверь")
    chosen = set(door_faces)
    rim = [edge for edge in {e for f in door_faces for e in f.edges} if any(f not in chosen for f in edge.link_faces)]

    door_bm = bmesh.new()
    mapped: dict = {}
    for face in door_faces:
        verts = []
        for vert in face.verts:
            if vert not in mapped:
                mapped[vert] = door_bm.verts.new(vert.co)
            verts.append(mapped[vert])
        made = door_bm.faces.new(verts)
        made.material_index = face.material_index
        # Кузов пака гранёный: сглаженная дверь шла бы бликами пятнами.
        made.smooth = False
    lining = len(body.material_slots)
    # Обшивка — копия граней двери, сдвинутая внутрь и развёрнутая лицом в
    # салон; по краю — торец двери той же обшивкой.
    outer = list(door_bm.faces)
    edge_loop = [edge for edge in door_bm.edges if edge.is_boundary]
    copied = bmesh.ops.duplicate(door_bm, geom=outer)
    inner = [elem for elem in copied["geom"] if isinstance(elem, bmesh.types.BMFace)]
    inner_verts = [elem for elem in copied["geom"] if isinstance(elem, bmesh.types.BMVert)]
    bmesh.ops.translate(door_bm, vec=(0.0, -DOOR_SKIN, 0.0), verts=inner_verts)
    bmesh.ops.reverse_faces(door_bm, faces=inner)
    for face in inner:
        face.material_index = lining
    edge_map = copied["edge_map"]
    for edge in edge_loop:
        twin = edge_map.get(edge)
        if twin is None:
            continue
        a, b = edge.verts
        c, d = twin.verts
        if (c.co - a.co).length > (d.co - a.co).length:
            c, d = d, c
        for order in ((a, b, d, c), (c, d, b, a)):
            try:
                side = door_bm.faces.new(order)
            except ValueError:
                continue
            side.material_index = lining
            side.smooth = False
    bmesh.ops.delete(bm, geom=door_faces, context="FACES_ONLY")
    rim = [edge for edge in rim if edge.is_valid]
    extruded = bmesh.ops.extrude_edge_only(bm, edges=rim)
    new_verts = [elem for elem in extruded["geom"] if isinstance(elem, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0.0, -JAMB_DEPTH, 0.0), verts=new_verts)
    jamb = [elem for elem in extruded["geom"] if isinstance(elem, bmesh.types.BMFace)]
    # Грани проёма смотрят кто куда — лицом к камере должна быть каждая: копия
    # с обратной стороной.
    twins = bmesh.ops.duplicate(bm, geom=jamb)["geom"]
    bmesh.ops.reverse_faces(bm, faces=[elem for elem in twins if isinstance(elem, bmesh.types.BMFace)])
    bm.to_mesh(body.data)
    bm.free()

    mesh = bpy.data.meshes.new("DriverDoor")
    door_bm.to_mesh(mesh)
    door_bm.free()
    for slot in body.material_slots:
        mesh.materials.append(slot.material)
    mesh.materials.append(_material("Lining", LINING, 0.7))
    door = bpy.data.objects.new("DriverDoor", mesh)
    bpy.context.scene.collection.objects.link(door)
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    hinge_y = max(vert.co.y for vert in mesh.vertices)
    hinge = Vector((front, hinge_y, (sill + high.z) * 0.5))
    for vert in mesh.vertices:
        vert.co -= hinge
    door.location = hinge


def _roof_over(body, cabin) -> float:
    """Низ крыши над серединой салона, м: самое низкое из попаданий луча вниз
    по длине потолка на полуширине [constant HEADLINER_HALF]. Крыша к верху
    сужается, и потолок по высоте стёкол торчал бы из неё углами."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    low, high = cabin
    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    lowest = high.z
    length = high.x - low.x
    for step in range(9):
        x = low.x + length * (0.27 + 0.5 * step / 8.0)
        for y in (-HEADLINER_HALF, HEADLINER_HALF):
            hit, _normal, _index, _distance = tree.ray_cast(Vector((x, y, high.z + 1.0)), Vector((0, 0, -1)))
            # Луч, прошедший мимо крыши, упрётся в днище: такие не в счёт.
            if hit is not None and hit.z > (low.z + high.z) * 0.5:
                lowest = min(lowest, hit.z)
    return lowest


HEADLINER_HALF = 0.13


def _furnish_the_cabin(cabin, roof: float, kind: dict) -> None:
    """Салон одним мешем `CarInterior` по типу машины [param kind]: пол с
    ковриком, обшивка дальнего борта с подлокотником, потолок, передние
    сиденья (у купе — ковшом, с боковой поддержкой), тоннель с рычагом, задний
    диван или полка, багажник, торпедо со щитком приборов, руль и плафон.

    Место плафона — пустышка `DomeLight`: игра ставит туда источник.
    """
    import math

    import bmesh
    from mathutils import Vector

    low, high = cabin
    length = high.x - low.x
    height = roof - low.z
    front_door = high.x - 0.02
    door = proportion("CAR_LENGTH") * kind["door"]
    driver_x = front_door - door * 0.6
    seat_z = low.z + height * kind["seat"] + 0.05
    belt = low.z + (high.z - low.z) * 0.5
    lean = kind["recline"]
    back_h = max(min(height * 0.5, roof - seat_z - 0.08), 0.18)

    materials = [
        _material("Lining", LINING, 0.7),
        _material("Seat", SEAT, 0.55),
        _material("Dash", DASH, 0.5),
        _material("Headliner", HEADLINER, 0.95),
        _material("DomeLamp", DOME_LAMP, 0.3),
        _material("Carpet", CARPET, 1.0),
        _material("Gauge", GAUGE, 0.2),
    ]
    bm = bmesh.new()

    def part(material: int, build) -> None:
        before = len(bm.faces)
        build()
        bm.faces.ensure_lookup_table()
        for index in range(before, len(bm.faces)):
            bm.faces[index].material_index = material

    def seat(x: float, side: float, width: float) -> None:
        """Подушка, спинка с наклоном назад и подголовник; ковш — с валиками."""
        part(1, lambda: _box_into(bm, (0.34, width, 0.08), (x, side, seat_z)))
        back_x = x - 0.17 - math.sin(lean) * back_h * 0.5
        back_z = seat_z + math.cos(lean) * back_h * 0.5
        part(1, lambda: _box_into(bm, (0.07, width, back_h), (back_x, side, back_z), (-lean, 3, "Y")))
        top_x = x - 0.17 - math.sin(lean) * back_h
        top_z = seat_z + math.cos(lean) * back_h
        if top_z + 0.06 < roof - 0.03:
            part(1, lambda: _box_into(bm, (0.06, width * 0.6, 0.07), (top_x - 0.01, side, top_z + 0.03), (-lean, 3, "Y")))
        if not kind["buckets"]:
            return
        for edge in (-1.0, 1.0):
            bolster = side + edge * (width * 0.5 - 0.015)
            part(1, lambda b=bolster: _box_into(bm, (0.3, 0.03, 0.12), (x, b, seat_z + 0.03)))
            part(
                1,
                lambda b=bolster: _box_into(
                    bm, (0.09, 0.03, back_h * 0.8), (back_x + 0.01, b, back_z - back_h * 0.05), (-lean, 3, "Y")
                ),
            )

    # Пол с ковриком и обшивка дальнего борта до линии окон с подлокотником.
    part(0, lambda: _box_into(bm, (length, 0.54, 0.02), (low.x + length * 0.5, 0.0, low.z)))
    part(5, lambda: _box_into(bm, (length * 0.8, 0.5, 0.012), (low.x + length * 0.55, 0.0, low.z + 0.016)))
    part(0, lambda: _box_into(bm, (length, 0.02, belt - low.z), (low.x + length * 0.5, -0.26, (low.z + belt) * 0.5)))
    part(0, lambda: _box_into(bm, (door * 0.6, 0.04, 0.03), (driver_x, -0.24, seat_z + 0.1)))
    # Потолок под крышей, середина салона. Уже салона: крыша к верху сужается,
    # и потолок во всю ширину торчал бы углами из неё.
    part(3, lambda: _box_into(bm, (length * 0.5, HEADLINER_HALF * 2.0, 0.02), (low.x + length * 0.52, 0.0, roof - 0.03)))
    # Передние сиденья и тоннель между ними с рычагом.
    for side in (0.13, -0.13):
        seat(driver_x, side, 0.2)
    part(2, lambda: _box_into(bm, (door * 0.8, 0.06, seat_z - low.z + 0.02), (driver_x + 0.12, 0.0, (low.z + seat_z) * 0.5 + 0.01)))
    part(2, lambda: _box_into(bm, (0.02, 0.02, 0.1), (driver_x + 0.22, 0.0, seat_z + 0.05), (-0.3, 3, "Y")))
    rear_x = driver_x - 0.62
    if kind["rear"] and rear_x - 0.2 > low.x:
        # Задний диван во всю ширину.
        part(1, lambda: _box_into(bm, (0.34, 0.5, 0.09), (rear_x, 0.0, seat_z)))
        part(1, lambda: _box_into(bm, (0.07, 0.5, back_h * 0.9), (rear_x - 0.2, 0.0, seat_z + back_h * 0.45), (-0.2, 3, "Y")))
        if kind["cargo"] and rear_x - 0.3 > low.x:
            # Багажник за диваном: пол ковром и шторка.
            cargo = rear_x - 0.26 - low.x
            part(5, lambda: _box_into(bm, (cargo, 0.5, 0.02), (low.x + cargo * 0.5, 0.0, seat_z - 0.02)))
            part(2, lambda: _box_into(bm, (cargo, 0.48, 0.012), (low.x + cargo * 0.5, 0.0, seat_z + back_h * 0.8)))
    else:
        # У купе сзади — полка за спинками.
        shelf = max(driver_x - 0.3 - low.x, 0.1)
        part(2, lambda: _box_into(bm, (shelf, 0.5, 0.02), (low.x + shelf * 0.5 + 0.05, 0.0, belt)))
    # Торпедо у лобового стекла, щиток приборов с двумя циферблатами и руль.
    dash_x = high.x - 0.12
    part(2, lambda: _box_into(bm, (0.22, 0.52, 0.12), (dash_x, 0.0, belt - 0.02)))
    part(2, lambda: _box_into(bm, (0.08, 0.2, 0.05), (dash_x - 0.08, 0.13, belt + 0.06)))
    for offset in (-0.04, 0.04):
        part(6, lambda o=offset: _box_into(bm, (0.005, 0.06, 0.04), (dash_x - 0.121, 0.13 + o, belt + 0.035)))
    wheel_at = Vector((dash_x - 0.16, 0.13, belt + 0.02))
    part(2, lambda: _torus_into(bm, wheel_at, 0.1, 0.012, -kind["wheel"]))
    part(2, lambda: _box_into(bm, (0.14, 0.02, 0.02), (dash_x - 0.09, 0.13, belt), (kind["wheel"], 3, "Y")))
    # Плафон под крышей над передними сиденьями.
    dome = Vector((driver_x + 0.12, 0.0, roof - 0.045))
    part(4, lambda: _box_into(bm, (0.1, 0.06, 0.012), tuple(dome)))

    mesh = bpy.data.meshes.new("CarInterior")
    bm.to_mesh(mesh)
    bm.free()
    for material in materials:
        mesh.materials.append(material)
    interior = bpy.data.objects.new("CarInterior", mesh)
    bpy.context.scene.collection.objects.link(interior)
    anchor = bpy.data.objects.new("DomeLight", None)
    anchor.location = dome - Vector((0.0, 0.0, 0.03))
    bpy.context.scene.collection.objects.link(anchor)


def _torus_into(bm, centre, radius: float, tube: float, tilt: float, segments: int = 16, sides: int = 6) -> None:
    """Баранка: тор радиуса [param radius] с трубкой [param tube], плоскостью
    вдоль Y и наклоном [param tilt] рад от вертикали к водителю."""
    import math

    from mathutils import Matrix, Vector

    turn = Matrix.Rotation(tilt, 3, "Y")
    rings = []
    for step in range(segments):
        around = math.tau * step / segments
        ring = []
        for side in range(sides):
            across = math.tau * side / sides
            reach = radius + tube * math.cos(across)
            local = Vector((tube * math.sin(across), reach * math.cos(around), reach * math.sin(around)))
            ring.append(bm.verts.new(centre + turn @ local))
        rings.append(ring)
    for step in range(segments):
        ring, following = rings[step], rings[(step + 1) % segments]
        for side in range(sides):
            nxt = (side + 1) % sides
            bm.faces.new((ring[side], following[side], following[nxt], ring[nxt]))


def _indicators(body) -> None:
    """Поворотники по четырём углам кузова, материалы `IndicatorLeft` у борта +Y
    и `IndicatorRight` у борта -Y: капот в +X, и правый борт — -Y. Стекло
    ставится лучом на кузов — у каждой модели свой изгиб угла."""
    import bmesh
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    tree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    heights: dict[str, float] = {}
    for polygon in body.data.polygons:
        slot = body.material_slots[polygon.material_index] if body.material_slots else None
        if slot is not None and slot.material is not None and slot.material.name in ("Headlights", "TailLights"):
            heights.setdefault(slot.material.name, (body.matrix_world @ polygon.center).z)
    half = proportion("CAR_LENGTH") * 0.5
    for name, side in (("IndicatorLeft", 1.0), ("IndicatorRight", -1.0)):
        bm = bmesh.new()
        for end, lights in ((1.0, "Headlights"), (-1.0, "TailLights")):
            z = heights.get(lights, 0.45)
            origin = Vector((end * (half + 0.3), side * 0.5, z))
            aim = Vector((end * (half - 0.14), side * 0.26, z)) - origin
            hit, normal, _index, _distance = tree.ray_cast(origin, aim.normalized())
            if hit is None:
                continue
            _box_into(bm, (0.07, 0.07, 0.035), tuple(hit + normal * 0.012))
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(_material(name, INDICATOR, 0.3))
        lamp = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(lamp)


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
        kind = _strip_ual(Path(wanted[1]))
        print("  " + UAL_LIBRARIES[kind]["source"].name)
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
            urls = ", ".join(library["url"] for library in UAL_LIBRARIES.values())
            print(f"Нужен путь к .glb библиотеки для Godot — архивы на {urls}")
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
