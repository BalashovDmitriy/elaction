#!/usr/bin/env python3
"""Builds the actors from Quaternius packs: Otto, the agent and the cars, exported to glTF.

Since M21 (ADR-0032) the figure is not built from boxes but taken from the Ultimate Modular
Men Pack (CC0) — the Business Man character, source in `assets/source/quaternius/`.
The script adapts it to the game:

- height — exactly `Proportions.BODY`, together with the position keys in the clips;
- materials — the actor's palette: Otto has a cream suit, the agent a dark blue one;
- the agent gets a fedora and dark glasses on the head bone (ADR-0032, decisions 2 and 4);
- both get a pistol on the right hand: the pack has none (decision 5);
- of the 24 clips four remain, with short names (decision 1);
- Cars Pack cars — hood towards +X, length `Proportions.CAR_LENGTH` (decision 7).

The script lives as two halves in one file:

- **outside** (plain python from `.venv`) it finds Blender and launches
  itself in it;
- **inside** Blender (where `bpy` exists) it builds the models and writes `.glb`.

    python tools/build_actors.py             # all
    python tools/build_actors.py otto        # Otto only
    python tools/build_actors.py cars        # cars only
    python tools/build_actors.py --list
    python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>
"""

from __future__ import annotations

import argparse
import functools
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
# Inside Blender the folder of the running script does not get into sys.path.
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

# Colour as sRGB bytes.
Rgb = tuple[int, int, int]

# Actor colours. They lived in `palette.py`, the 2D sprite palette generator (ADR-0019,
# decision 8); after 2D was removed in M22 only they remained of it, and they belong here.
OTTO_SUIT: Rgb = (0xE8, 0xE3, 0xD2)
OTTO_SUIT_SHADE: Rgb = (0xB9, 0xB4, 0xA4)
OTTO_HAIR: Rgb = (0x3A, 0x2E, 0x27)
OTTO_SKIN: Rgb = (0xD8, 0xA6, 0x7B)
OTTO_TIE: Rgb = (0x3A, 0x3F, 0x4E)
AGENT_SUIT: Rgb = (0x2F, 0x35, 0x47)
AGENT_SUIT_SHADE: Rgb = (0x23, 0x28, 0x3A)
AGENT_HAT: Rgb = (0x26, 0x2B, 0x3B)
AGENT_SKIN: Rgb = (0xC0, 0x8F, 0x68)
# Pilot of the intro helicopter (ADR-0052, decision 6): olive flight
# suit, light helmet with a dark visor.
PILOT_SUIT: Rgb = (0x4E, 0x55, 0x3C)
PILOT_SUIT_SHADE: Rgb = (0x3E, 0x44, 0x30)
PILOT_HELMET: Rgb = (0xC9, 0xCB, 0xC4)
PILOT_SKIN: Rgb = (0xC8, 0x98, 0x70)
# Agents by building kind (ADR-0055, decision 7). Office — business charcoal
# suit, burgundy tie, no hat, hair visible. Residential building — street look:
# dark leather jacket over a dark turtleneck, tweed cap, no glasses.
OFFICE_SUIT: Rgb = (0x45, 0x48, 0x50)
OFFICE_SUIT_SHADE: Rgb = (0x33, 0x36, 0x3D)
OFFICE_TIE: Rgb = (0x5E, 0x1C, 0x22)
OFFICE_HAIR: Rgb = (0x2A, 0x22, 0x1C)
STREET_JACKET: Rgb = (0x2E, 0x25, 0x20)
STREET_TROUSERS: Rgb = (0x24, 0x26, 0x2C)
STREET_SWEATER: Rgb = (0x1B, 0x1B, 0x1E)
STREET_CAP: Rgb = (0x4A, 0x40, 0x34)

try:
    import bpy
except ImportError:  # outside Blender
    bpy = None

PROJECT_ROOT = TOOLS.parent
OUT_DIR = PROJECT_ROOT / "assets/models"
PROPORTIONS = PROJECT_ROOT / "src/systems/proportions.gd"
SOURCE = PROJECT_ROOT / "assets/source/quaternius/business_man.glb"

# Pack clips that go into the game, and their names there. The other twenty
# are dropped: in the file they would weigh more than the model itself. `FigureRig`
# expects the same names — if they diverge, the rig falls back to a code pose and
# reports it as an error.
#
# Since M24c motion comes from UAL (`UAL_LIBRARIES`) and no clip is taken from the pack:
# the dictionary is kept so a pack clip can be brought back with one line.
CLIPS: dict[str, str] = {}

# Motion since M24c comes from the Universal Animation Library (Quaternius, CC0), retargeted
# to the pack skeleton (ADR-0039, decision 1); in M24d its second part, UAL 2, was added —
# strikes and reactions for the takedown scenes (ADR-0040). The repository holds
# trimmed sources: the skeleton and the needed clips without the mannequin — the full files
# exceed the hook limit. The `ual` command trims them, recognising the library by skeleton:
#     python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>
#     python tools/build_actors.py ual <UAL2_Standard.glb>
#
# Both parts have the same skeleton, identical to the millimetre at rest — only the
# bone names differ: the first uses Rigify names, the second the Unreal mannequin's. So the
# pack bones are mapped to the first part's names (`UAL_BONES`), and the second translates
# them with its own table (`names`).
UAL_LIBRARIES: dict[str, dict] = {
    "ual": {
        "source": PROJECT_ROOT / "assets/source/quaternius/ual_clips.glb",
        "url": "https://opengameart.org/content/universal-animation-library",
        # `ual` recognises the library by this bone.
        "marker": "DEF-hips",
        # Clips and their names in the game. `FigurePoses` expects these names.
        "clips": {
            # Neutral stance, arms down: the base for code poses (`FigurePoses`),
            # never played on screen itself. The stance with a pistol does not fit this.
            "Idle_Loop": "stand",
            "Pistol_Idle_Loop": "idle",
            "Walk_Loop": "walk",
            "Pistol_Shoot": "shoot",
            "Death01": "death",
            "Jump_Start": "jump_start",
            # Not "jump_loop": Godot import strips the `_loop` suffix from the name.
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

# Pack bone — UAL bone. The UAL skeleton is built on Rigify and maps bone to bone
# onto the pack; fingers are retargeted too, otherwise the hand does not hold the pistol.
# The pack's fingertips (…4) are extra — they follow their joint as is.
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

# UAL 2 bone names by UAL 1 names.
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

# The pack's feet are attached to the root (the skeleton is rigged for IK): in a
# retargeted clip the foot goes to the end of the shin — where it was at rest relative to it.
UAL_ATTACH: dict[str, str] = {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}
# UAL's pelvis sway is carried by `Body`: the pack's legs hang from it, not from `Hips`.
UAL_CARRIER = "Body"

CARS_SOURCE = PROJECT_ROOT / "assets/source/quaternius/cars"

# Cars Pack cars and the body material of each: the game repaints it by draw
# (ADR-0032, decision 7). The second sports car has a two-tone body — the dark
# half goes to `PaintShade`. No taxi or police car here: a spy in a
# patrol car would be odd.
CARS: dict[str, dict[str, str]] = {
    "sports_car_2": {"Orange": "Paint", "DarkOrange": "PaintShade"},
    "sports_car_1": {"White": "Paint"},
    "car_1": {"Blue": "Paint"},
    "car_2": {"LightBlue": "Paint"},
    "suv": {"White": "Paint"},
}

# Car depth across the bumpers including wheels, m: what fits between the back
# wall and Otto's body (code review M18c and M20). The pack's cars, 1.8 m wide, are
# squeezed in depth separately — this is not visible from the side, and the wheels stay
# round: length and height share one scale.
CAR_DEPTH = 0.74

# Pack bones that worn items attach to.
HEAD_BONE = "Head"
HAND_BONE = "Wrist.R"


def proportion(name: str) -> float:
    """A number from the game's `Proportions`, in metres.

    Actor heights are set in the game by one table (ADR-0026, decision 8), and the model
    must be exactly as tall as the collision. There is no copy of the number here:
    the script reads the constants from `proportions.gd` and evaluates their expressions —
    simple arithmetic over earlier declared ones.
    """
    return _proportions()[name]


@functools.cache
def _proportions() -> dict[str, float]:
    """All numeric constants of `proportions.gd`, parsed once.

    Numbers derived from vectors (`DOOR_MAT` from `DOOR.x`) and everything that is not a
    number — a string, an array, an expression with GDScript words — are skipped: the models
    do not need them, and there is no reason for the parser to fail on them.
    """
    known: dict[str, float] = {}
    for line in PROPORTIONS.read_text(encoding="utf-8").splitlines():
        if not line.startswith("const ") or ":=" in line:
            continue
        head, _, expression = line[len("const ") :].partition("=")
        key = head.split(":")[0].strip()
        try:
            value = eval(expression, {"__builtins__": {}}, dict(known))
        except Exception:  # noqa: BLE001 — any GDScript non-arithmetic
            continue
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            known[key] = float(value)
    return known


def _actors() -> dict[str, dict]:
    """Who is built and how they differ.

    The model is the same for everyone, so friend is told from foe by colour and head:
    the agent has a fedora and glasses (ADR-0032, decisions 2–4). Since M24m there are three
    agents, by building kind (ADR-0055, decision 7): in the hotel — a fedora, in the office —
    no hat and a tie, in the residential building — a leather jacket and a cap. `hat` is
    `True` (fedora), `"cap"` (cap) or `False`. On a dark floor there is almost
    no colour, and the silhouette with a hat is what the player recognises the agent by.

    Keys of `colours` are pack materials: `Suit` — trousers, `Suit.001` — jacket.
    Materials not listed here (shirt, shoes, eyes) stay as in the pack.
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
        "agent_office": {
            "colours": {
                "Suit": OFFICE_SUIT_SHADE,
                "Suit.001": OFFICE_SUIT,
                "Tie": OFFICE_TIE,
                "Skin": AGENT_SKIN,
                "Hair": OFFICE_HAIR,
            },
            "hat": False,
            "glasses": True,
        },
        "agent_residential": {
            "colours": {
                "Suit": STREET_TROUSERS,
                "Suit.001": STREET_JACKET,
                "Tie": STREET_SWEATER,
                "Skin": AGENT_SKIN,
                "Hair": STREET_CAP,
            },
            "hat": "cap",
            "glasses": False,
        },
        # The pilot sits behind the helicopter glazing and nods on departure: no weapon,
        # the head is covered by a helmet with a visor.
        "pilot": {
            "colours": {
                "Suit": PILOT_SUIT_SHADE,
                "Suit.001": PILOT_SUIT,
                "Tie": PILOT_SUIT_SHADE,
                "Skin": PILOT_SKIN,
                "Hair": PILOT_HELMET,
            },
            "hat": False,
            "glasses": False,
            "helmet": True,
            "gun": False,
        },
    }


# --- The half that runs inside Blender ---------------------------------------


def _reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _linear(colour: Rgb) -> tuple[float, float, float, float]:
    """Palette colour into a material: sRGB bytes converted to linear colour.

    The M16 figure wrote the bytes as is, and the agent's dark blue suit came out
    pale blue: 0x2F taken as linear is 0.46 on screen. In the original the agents are
    black, and in the M21 comparison the difference was glaring. The pack materials are
    linear, and a palette placed next to them must be in the same space.
    """

    def channel(byte: int) -> float:
        value = byte / 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    red, green, blue = colour
    return (channel(red), channel(green), channel(blue), 1.0)


def _material(name: str, colour: Rgb, roughness: float = 0.85):
    material = bpy.data.materials.new(name)
    # In Blender 5 a material is node-based from birth, and the flag only complains.
    if not material.use_nodes:
        material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = _linear(colour)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    return material


def _import_pack():
    """Pack source into the scene. Returns the armature and its meshes.

    glTF import brings extras: empties at the bone tips and an icosphere — the shape
    the importer draws bones with. They do not go into the model.
    """
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    meshes = [obj for obj in armature.children if obj.type == "MESH"]
    for obj in list(bpy.context.scene.objects):
        if obj is not armature and obj not in meshes:
            bpy.data.objects.remove(obj, do_unlink=True)
    return armature, meshes


def _channelbags(action):
    """Clip curves. In Blender 5 actions are layered: layer → strip → bag."""
    for layer in action.layers:
        for strip in layer.strips:
            yield from strip.channelbags


def _keep_clips(armature) -> None:
    """Keeps the pack clips from `CLIPS` and renames them.

    The importer puts each clip on its own NLA track; export takes
    actions, so the extra ones are deleted together with their tracks.
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
        raise RuntimeError("no clips in the pack: " + ", ".join(sorted(missing)))


def _stage_clips(armature) -> None:
    """Export in actions mode takes the ones that can be hung on the armature:
    each clip in turn is set on it as an NLA track."""
    data = armature.animation_data
    for action in bpy.data.actions:
        track = data.nla_tracks.new()
        track.name = action.name
        track.strips.new(action.name, 0, action)


def _strip_ual(full: Path) -> str:
    """Trims a full UAL file down to the source of its library: the skeleton and its clips.
    Recognises the library by skeleton and returns its name.

    The mannequin and the other clips do not go into the game, and the full file (6.5–8 MB)
    exceeds the hook limit on large files.
    """
    bpy.ops.import_scene.gltf(filepath=str(full))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    kind = next(
        (name for name, library in UAL_LIBRARIES.items() if library["marker"] in rig.data.bones),
        None,
    )
    if kind is None:
        raise RuntimeError("cannot recognise the library by its skeleton: " + full.name)
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
        raise RuntimeError(f"no clips in {kind}: " + ", ".join(sorted(missing)))
    _stage_clips(rig)
    _export(UAL_LIBRARIES[kind]["source"])
    return kind


def _import_ual(source: Path):
    """Trimmed UAL source into the scene: armature and clips under their original names."""
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
    """Bone depth for the retarget order: parent before child, and the foot
    after the shin that `UAL_ATTACH` puts it on."""
    if bone.name in UAL_ATTACH:
        return 1 + _depth(bone.id_data.bones[UAL_ATTACH[bone.name]])
    return 0 if bone.parent is None else 1 + _depth(bone.parent)


def _lowest(meshes) -> float:
    """Lowest point of the meshes in the world at the current frame, m."""
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
    """Retargets the clips of both UAL parts to the pack skeleton."""
    for library in UAL_LIBRARIES.values():
        _retarget_library(armature, meshes, library)


def _retarget_library(armature, meshes, library: dict) -> None:
    """Retargets the clips of one UAL library to the pack skeleton and bakes them into its
    actions.

    Both figures stand at rest in a T-pose facing world −Y, so a bone's rotation in the
    clip — its world rotation measured from rest — fits the paired pack bone
    as is: R = R_ual · R_ual_rest⁻¹ · R_pack_rest. It has to be computed
    in the world, not in armature space: the glTF importer rotates the pack armature
    by 90° around X with a quaternion, while UAL has no rotation.
    A bone's position is set by its parent along the chain, as at rest; the exceptions are
    the feet (`UAL_ATTACH`), which the pack keeps on the root, and the pelvis, whose motion
    `UAL_CARRIER` carries in fractions of height.

    At this point the pack is still in its own units (scale 100 on the object), so
    the pelvis motion from UAL world is converted to pack armature space corrected for
    pelvis height; `_scale_to` later multiplies the position keys, as for the pack clips.

    Each frame is put on the floor by the mesh's lowest vertex: the pack's legs are longer
    than UAL's, and with retargeted angles the sole sank 6 cm into the floor mid-step. Root
    motion is a shift of the whole skeleton; the pack's feet hang from it too. The game does
    not ground an already grounded clip, and does not have to walk vertices at runtime.
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
    # Rotation from UAL armature space into pack armature space.
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
                # As at rest behind its parent — the base for any bone.
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
    """Bottom and top of the figure in the first frame of the stance, m — by world vertices.

    The measure is not the rest pose but the stance: the game stands in it, and it is its
    height that must match the collision. The stance clip bends the knees slightly, and
    measured by the T-pose the figure came out 3 cm below the collision.
    """
    armature = meshes[0].parent
    data = armature.animation_data
    # NLA tracks of all clips would blend with the stance: they are muted for measuring.
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
    """Brings the height to the game's and bakes the scale.

    The pack keeps the skeleton in hundredths with scale 100 on the armature object.
    The object scale is baked into bones and vertices but not into clips: bone
    position keys are in skeleton units and have to be multiplied by
    the same factor, otherwise Hips sways by hundredths of a centimetre when walking.
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
    """Pack materials into the actor's palette; roughness is the same for all, as in M16."""
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
                # glTF import routes the colour of some materials through its own node, and
                # then the socket value is ignored: the link is cut, the colour goes to the socket.
                for link in list(base.links):
                    material.node_tree.links.remove(link)
                base.default_value = _linear(colours[material.name])
            bsdf.inputs["Roughness"].default_value = 0.85
            bsdf.inputs["Metallic"].default_value = 0.0


def _bone_head(armature, bone: str):
    return armature.matrix_world @ armature.data.bones[bone].head_local


def _head_box(meshes):
    """Head bounds at rest: vertices of the face and hair materials above the neck."""
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
    """Mesh from `build(bm)`, fully bound to bone [param bone]."""
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
    """Elliptic cylinder from [param base] upwards; top narrowed to [param radius_top_scale]."""
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
    """Fedora: narrow brim and a crown with a pinch on top (ADR-0032, decision 2).

    It sits low, above the brows, and hides the hair: hair faces above the brim
    are removed, otherwise they would poke through the crown in any pose.
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
        # Brim: a flat ellipse wider than the head, slightly longer front to back.
        _cylinder_into(bm, half_x * 2.0, half_y * 1.85, 1.0, head_height * 0.025, (centre_x, centre_y, brim_z))
        # The crown narrows upwards, and its top is the pinch: a second, narrow and low
        # step on top gives the silhouette the "ridge" the fedora is recognised by.
        _cylinder_into(bm, half_x * 1.08, half_y * 1.04, 0.8, crown_height * 0.8, (centre_x, centre_y, brim_z))
        _cylinder_into(
            bm, half_x * 0.62, half_y * 0.8, 0.7, crown_height * 0.2, (centre_x, centre_y, brim_z + crown_height * 0.8)
        )

    hat = _part("hat", build, _material("hat", colour, roughness=0.7), HEAD_BONE)
    _trim_hair(meshes, brim_z + head_height * 0.02)
    return hat


def _cap(meshes, colour: Rgb):
    """Tweed cap: a flat crown slightly wider than the head, peak forward.

    It sits lower than the fedora and also hides the hair, and on a takedown strike it
    flies off the same way — the mesh is named `hat`.
    """
    low, high = _head_box(meshes)
    centre_x = (low.x + high.x) * 0.5
    centre_y = (low.y + high.y) * 0.5
    half_x = (high.x - low.x) * 0.5
    half_y = (high.y - low.y) * 0.5
    head_height = high.z - low.z
    band_z = high.z - head_height * 0.24

    def build(bm) -> None:
        # Crown: low, almost flat on top and shifted towards the peak.
        _cylinder_into(bm, half_x * 1.1, half_y * 1.12, 0.92, head_height * 0.2, (centre_x, centre_y - half_y * 0.06, band_z))
        _cylinder_into(
            bm, half_x * 1.0, half_y * 1.1, 0.8, head_height * 0.05, (centre_x, centre_y - half_y * 0.12, band_z + head_height * 0.2)
        )
        # Peak — forward, towards the face (the face is at Blender −Y), slightly down.
        _box_into(bm, (half_x * 1.5, half_y * 0.7, head_height * 0.03), (centre_x, low.y - half_y * 0.2, band_z + head_height * 0.02))

    cap = _part("hat", build, _material("hat", colour, roughness=0.9), HEAD_BONE)
    _trim_hair(meshes, band_z + head_height * 0.02)
    return cap


def _helmet(meshes, colour: Rgb):
    """Flight helmet: a dome over the head down to below the ears and a dark visor in front."""
    low, high = _head_box(meshes)
    centre_x = (low.x + high.x) * 0.5
    centre_y = (low.y + high.y) * 0.5
    half_x = (high.x - low.x) * 0.5
    half_y = (high.y - low.y) * 0.5
    head_height = high.z - low.z
    rim_z = high.z - head_height * 0.62

    def build(bm) -> None:
        # Dome in steps: wider than the head at the bottom, narrowing to the top.
        _cylinder_into(bm, half_x * 1.16, half_y * 1.14, 0.97, head_height * 0.4, (centre_x, centre_y, rim_z))
        _cylinder_into(
            bm, half_x * 1.12, half_y * 1.1, 0.78, head_height * 0.18, (centre_x, centre_y, rim_z + head_height * 0.4)
        )
        _cylinder_into(
            bm, half_x * 0.88, half_y * 0.86, 0.5, head_height * 0.1, (centre_x, centre_y, rim_z + head_height * 0.58)
        )

    helmet = _part("helmet", build, _material("helmet", colour, roughness=0.35), HEAD_BONE)
    _trim_hair(meshes, rim_z)
    return helmet


def _visor(meshes):
    """Dark helmet visor in front of the eyes — wider and taller than the glasses."""
    eye_low, eye_high = _material_box(meshes, "Eye")
    front_y = eye_low.y - 0.018
    centre_z = (eye_low.z + eye_high.z) * 0.5 + 0.012
    span = eye_high.x - eye_low.x

    def build(bm) -> None:
        _box_into(bm, (span * 1.25, 0.012, span * 0.55), (0.0, front_y, centre_z))

    return _part("visor", build, _material("visor", (0x10, 0x14, 0x1C), roughness=0.08), HEAD_BONE)


def _trim_hair(meshes, above_z: float) -> None:
    """Removes hair faces above [param above_z]: the hat covers them."""
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
    """Dark glasses: two lenses and a bridge in front of the eyes (ADR-0032, decision 4)."""
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
    """Bounds of the faces of one material at rest."""
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
        raise RuntimeError("no such material in the model: " + material_name)
    return low, high


def _gun(armature):
    """Pistol in the right hand (ADR-0032, decision 5).

    Placed at rest, in the T-pose: the arm stretched sideways palm down, fingers to −X.
    The pack's "armed" clips turn the hand so that in the shooting pose its −X
    looks along the gaze, and +Y (back of the hand in the T-pose, towards the back) — down.
    So the barrel lies along the fingers, and the grip goes out of the palm towards +Y.
    Checked by frames of `tools/actor_shot.tscn`: a barrel along −Y stood upright in the
    shooting pose.
    """
    wrist = _bone_head(armature, HAND_BONE)
    palm = wrist.x - 0.06  # middle of the palm: the fingers go to −X

    def build(bm) -> None:
        # Slide with barrel along the fingers, above the fist.
        _box_into(bm, (0.19, 0.036, 0.03), (palm - 0.04, wrist.y - 0.035, wrist.z))
        # Grip — in the fist, towards the back of the hand, slightly tilted back.
        _box_into(bm, (0.035, 0.1, 0.028), (palm + 0.01, wrist.y + 0.02, wrist.z), (-0.25, 3, "Z"))

    return _part("gun", build, _material("gun", (0x1A, 0x1C, 0x22), roughness=0.4), HAND_BONE)


def _dress(armature, meshes, actor: dict) -> None:
    """Puts on the items and merges everything into one mesh under the skeleton."""
    parts = [_gun(armature)] if actor.get("gun", True) else []
    if actor["glasses"]:
        parts.append(_glasses(meshes))
    if actor.get("helmet", False):
        parts.append(_helmet(meshes, actor["colours"]["Hair"]))
        parts.append(_visor(meshes))
    # The hat is its own mesh `hat` on the head bone, not part of the body: on a takedown
    # strike it flies off (ADR-0050), and the game hides it without touching the body.
    hat = None
    if actor["hat"] == "cap":
        hat = _cap(meshes, actor["colours"]["Hair"])
    elif actor["hat"]:
        hat = _hat(meshes, armature, actor["colours"]["Hair"])
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
    """A Cars Pack car adapted to the game.

    Hood — towards Blender +X (which is also Godot scene +X after export), length — exactly
    `Proportions.CAR_LENGTH` and height by the same scale, depth —
    [constant CAR_DEPTH]. The headlights tell where the front is: in the pack the cars
    face every which way. The wheels remain separate objects — the game spins them when
    the car drives off. Their origin is not on the axle but at the car's zero, as the pack
    placed them, so `ExitCar` spins each around the middle of its mesh.
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
        raise RuntimeError(name + ": the car has no headlights — cannot tell which end is the front")
    lights /= count
    size = high - low
    centre = (low + high) * 0.5
    # Length — along the larger horizontal axis; the rotation puts the headlights at +X.
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
    # Centre in length and depth — at zero, wheels — on the floor.
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
    # The door opening and the interior are computed in world coordinates: body origin at zero.
    for other in bpy.context.scene.objects:
        other.select_set(other is body)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    kind = CABIN_KINDS[CABINS[name]]
    cabin = _cabin_box(body)
    _cut_the_door(body, cabin, kind)
    _furnish_the_cabin(cabin, _roof_over(body, cabin), kind)
    _indicators(body)


# Interior and the driver's door (ADR-0046, decision 1). The door is on the Blender +Y side:
# for a car standing at the gate it faces the camera. The door is a fraction of the car
# length, its front edge at the base of the windscreen; the sill is above the body floor.
DOOR_SILL_LIFT = 0.1
# Interior by car type: the coupe has a longer door, low bucket seats and only a shelf
# at the back; the sedan and the estate have a bench, the estate and the SUV have a
# boot behind it; the SUV sits higher and more upright. Numbers: fraction of car length
# for the door, cushion rise as a fraction of interior height, seatback and wheel tilt, rad.
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
# Thickness of the door with its lining and depth of the opening in the body, m.
DOOR_SKIN = 0.03
JAMB_DEPTH = 0.05
# Interior: lining, seats, dashboard, ceiling, dome light — sRGB colours.
LINING: Rgb = (132, 100, 76)
SEAT: Rgb = (58, 40, 34)
DASH: Rgb = (30, 30, 34)
HEADLINER: Rgb = (168, 156, 136)
DOME_LAMP: Rgb = (255, 236, 200)
CARPET: Rgb = (44, 40, 38)
GAUGE: Rgb = (200, 230, 255)
INDICATOR: Rgb = (255, 140, 20)


def _cabin_box(body):
    """Interior by the model's windows: (bottom, top) corners, Blender coordinates.

    In length — from the rear window to the windscreen, in height — from the sill to the
    roof, in depth — inside the sides.
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
        raise RuntimeError(body.name + ": no glass — cannot tell where the cabin is")
    sill = body_low + DOOR_SILL_LIFT
    return Vector((low.x, -0.27, sill)), Vector((high.x, 0.27, high.z + 0.02))


def _cut_the_door(body, cabin, kind: dict) -> None:
    """Driver's door — a separate part `DriverDoor`, the opening — in the body.

    The body is cut by planes at the door edges and the sill; +Y side faces between
    them go to the door. The edge of the opening in the body is extruded inwards — the
    opening shows thickness rather than a paper-thin cut. The door is [constant DOOR_SKIN]
    thick, with the `Lining` trim inside. The door origin is at the hinge by the front
    pillar: the game swings it around the vertical through the origin.
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
        raise RuntimeError(body.name + ": the side has no faces for a door")
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
        # The pack body is faceted: a smoothed door would show blotchy highlights.
        made.smooth = False
    lining = len(body.material_slots)
    # Lining — a copy of the door faces, shifted inwards and turned to face the
    # interior; along the edge — the door's end in the same lining.
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
    # The opening faces point every which way — each must face the camera: a copy
    # with the reverse side.
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
    """Bottom of the roof above the middle of the interior, m: the lowest of the downward ray
    hits along the ceiling at half-width [constant HEADLINER_HALF]. The roof narrows towards
    the top, and a ceiling at window height would stick out of it at the corners."""
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
            # A ray that misses the roof hits the floor pan: those do not count.
            if hit is not None and hit.z > (low.z + high.z) * 0.5:
                lowest = min(lowest, hit.z)
    return lowest


HEADLINER_HALF = 0.13


def _furnish_the_cabin(cabin, roof: float, kind: dict) -> None:
    """Interior as one mesh `CarInterior` by car type [param kind]: floor with a
    mat, far-side lining with an armrest, ceiling, front
    seats (buckets with side bolsters in the coupe), tunnel with a lever, rear
    bench or shelf, boot, dashboard with an instrument cluster, steering wheel and dome light.

    The dome light's place is the empty `DomeLight`: the game puts a light source there.
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
        """Cushion, seatback tilted back and a headrest; a bucket has bolsters."""
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

    # Floor with a mat and the far-side lining up to the window line with an armrest.
    part(0, lambda: _box_into(bm, (length, 0.54, 0.02), (low.x + length * 0.5, 0.0, low.z)))
    part(5, lambda: _box_into(bm, (length * 0.8, 0.5, 0.012), (low.x + length * 0.55, 0.0, low.z + 0.016)))
    part(0, lambda: _box_into(bm, (length, 0.02, belt - low.z), (low.x + length * 0.5, -0.26, (low.z + belt) * 0.5)))
    part(0, lambda: _box_into(bm, (door * 0.6, 0.04, 0.03), (driver_x, -0.24, seat_z + 0.1)))
    # Ceiling under the roof, middle of the interior. Narrower than the interior: the roof
    # narrows towards the top, and a full-width ceiling would stick out of it at the corners.
    part(3, lambda: _box_into(bm, (length * 0.5, HEADLINER_HALF * 2.0, 0.02), (low.x + length * 0.52, 0.0, roof - 0.03)))
    # Front seats and the tunnel between them with a lever.
    for side in (0.13, -0.13):
        seat(driver_x, side, 0.2)
    part(2, lambda: _box_into(bm, (door * 0.8, 0.06, seat_z - low.z + 0.02), (driver_x + 0.12, 0.0, (low.z + seat_z) * 0.5 + 0.01)))
    part(2, lambda: _box_into(bm, (0.02, 0.02, 0.1), (driver_x + 0.22, 0.0, seat_z + 0.05), (-0.3, 3, "Y")))
    rear_x = driver_x - 0.62
    if kind["rear"] and rear_x - 0.2 > low.x:
        # Rear bench across the full width.
        part(1, lambda: _box_into(bm, (0.34, 0.5, 0.09), (rear_x, 0.0, seat_z)))
        part(1, lambda: _box_into(bm, (0.07, 0.5, back_h * 0.9), (rear_x - 0.2, 0.0, seat_z + back_h * 0.45), (-0.2, 3, "Y")))
        if kind["cargo"] and rear_x - 0.3 > low.x:
            # Boot behind the bench: carpeted floor and a cover.
            cargo = rear_x - 0.26 - low.x
            part(5, lambda: _box_into(bm, (cargo, 0.5, 0.02), (low.x + cargo * 0.5, 0.0, seat_z - 0.02)))
            part(2, lambda: _box_into(bm, (cargo, 0.48, 0.012), (low.x + cargo * 0.5, 0.0, seat_z + back_h * 0.8)))
    else:
        # The coupe has a shelf behind the seatbacks.
        shelf = max(driver_x - 0.3 - low.x, 0.1)
        part(2, lambda: _box_into(bm, (shelf, 0.5, 0.02), (low.x + shelf * 0.5 + 0.05, 0.0, belt)))
    # Dashboard at the windscreen, instrument cluster with two dials, and steering wheel.
    dash_x = high.x - 0.12
    part(2, lambda: _box_into(bm, (0.22, 0.52, 0.12), (dash_x, 0.0, belt - 0.02)))
    part(2, lambda: _box_into(bm, (0.08, 0.2, 0.05), (dash_x - 0.08, 0.13, belt + 0.06)))
    for offset in (-0.04, 0.04):
        part(6, lambda o=offset: _box_into(bm, (0.005, 0.06, 0.04), (dash_x - 0.121, 0.13 + o, belt + 0.035)))
    wheel_at = Vector((dash_x - 0.16, 0.13, belt + 0.02))
    part(2, lambda: _torus_into(bm, wheel_at, 0.1, 0.012, -kind["wheel"]))
    part(2, lambda: _box_into(bm, (0.14, 0.02, 0.02), (dash_x - 0.09, 0.13, belt), (kind["wheel"], 3, "Y")))
    # Dome light under the roof above the front seats.
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
    """Steering wheel: a torus of radius [param radius] with tube [param tube], in a plane
    along Y and tilted by [param tilt] rad from vertical towards the driver."""
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
    """Turn signals at the four corners of the body, materials `IndicatorLeft` on the +Y side
    and `IndicatorRight` on the -Y side: hood towards +X, so the right side is -Y. The lens
    is placed on the body by a ray — each model has its own corner curve."""
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


# --- The half that runs outside ----------------------------------------------


def _names() -> list[str]:
    return [*_actors().keys(), "cars"]


def _parser() -> argparse.ArgumentParser:
    """One parser for both halves: outside — the whole command line, inside
    Blender — what remains after `--`."""
    parser = argparse.ArgumentParser(description="Build actor models through Blender.")
    parser.add_argument("names", nargs="*", help="whom to build; all by default")
    parser.add_argument("--list", action="store_true", help="list and exit")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="where to write .glb")
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
            print(f"A path to the library .glb for Godot is needed — archives at {urls}")
            return 2
        wanted = ["ual", str(Path(wanted[1]).resolve())]
    unknown = [name for name in wanted if name not in _names() and wanted[0] != "ual"]
    if unknown:
        print("Unknown actors: " + ", ".join(unknown))
        return 2

    blender = require_blender()
    out_dir = arguments.out.resolve()
    code, output = run_script(blender, Path(__file__), ["--out", str(out_dir), *wanted])
    # Blender is chatty: only the names of the built models and errors are printed.
    for line in output.splitlines():
        if line.strip().endswith(".glb") or "Error" in line or "Traceback" in line or "rror:" in line:
            print(line)
    if code != 0:
        print(f"Blender exited with code {code}")
        return 1
    # A folder outside the project (`--out` in temp) is printed as is: relative_to fails on it.
    shown = (
        out_dir.relative_to(PROJECT_ROOT).as_posix()
        if out_dir.is_relative_to(PROJECT_ROOT)
        else str(out_dir)
    )
    print(f"Models in {shown}/")
    return 0


def _main_inside_blender() -> None:
    # Blender parses the command line up to `--` itself; the script gets the rest.
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    arguments = _parser().parse_args(argv)
    _build_inside_blender(arguments.out, arguments.names or _names())


if __name__ == "__main__":
    if bpy is not None:
        _main_inside_blender()
    else:
        raise SystemExit(main())
