#!/usr/bin/env python3
"""Escalator parts in Blender, export to glTF (ADR-0043, decision 3).

Every escalator in the building is different: the span between floors has a
different length and steepness, the landings have their own length. So the model
is not a single thing but a set of parts from which `Escalator` assembles a span
in place:

- `Step` — a step: aluminium grooved along the travel, a yellow edge at the rim;
  the top at the origin, along X — tread length, down along Y — height;
- `Balustrade` — a glass balustrade one metre long: stainless plinth,
  glass, a black rubber handrail on a guide; the bottom at the origin;
- `Newel` — the post at the end of the balustrade the handrail turns around;
- `Landing` — the entry landing: a grooved plate and a comb at the edge where the
  steps go under; the top at the origin;
- `Truss` — a truss under the span one metre long: chords, diagonals and stainless
  side cladding — since M24h the span reads as a mass, not a pair of rails
  (ADR-0044, decision 10).

Since M24h the balustrade stands on both sides of the belt, and there is no longer
a low side at the camera: the escalator moved into depth, and the railings must read.

Length along X, corridor depth — Z, as in the game. The game stretches the
one-metre parts along X — their pattern is even along the length, and stretching
does not spoil it.

The script lives as two halves in one file, like `build_actors.py`:
outside it finds Blender and runs itself in it, inside it builds the parts.

    python tools/build_escalator.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

try:
    import bmesh
    import bpy
    from mathutils import Euler, Matrix
except ImportError:
    bpy = None

ROOT = TOOLS.parent
TARGET = ROOT / "assets" / "models" / "escalator" / "escalator.glb"

# Sizes — the same as in `Escalator`: tread, belt depth, balustrade height, landing, m.
STEP_RUN = 0.2
STEP_HEIGHT = 0.45
BELT_DEPTH = 0.72
RAIL_HEIGHT = 0.96
LANDING_RUN = 0.42
LANDING_THICKNESS = 0.12
TRUSS_HEIGHT = 0.62

# Materials: colour in linear RGB, metallic, roughness, transparency. Metal without reflections in
# the scene darkens almost to black: it has nothing to reflect, there are no reflection probes in
# the building. So metallic is moderate — the parts catch the diffuse light of the lamps, and the
# highlight stays.
MATERIALS = {
    "Aluminium": ((0.62, 0.64, 0.67), 0.35, 0.45, 1.0),
    "Stainless": ((0.78, 0.79, 0.8), 0.45, 0.32, 1.0),
    "Glass": ((0.6, 0.78, 0.76), 0.0, 0.05, 0.35),
    "Rubber": ((0.03, 0.03, 0.032), 0.0, 0.55, 1.0),
    "Yellow": ((0.85, 0.62, 0.05), 0.0, 0.5, 1.0),
    "Steel": ((0.12, 0.125, 0.13), 0.4, 0.6, 1.0),
    "Comb": ((0.36, 0.37, 0.38), 0.4, 0.4, 1.0),
}


def _material(name: str) -> "bpy.types.Material":
    color, metallic, roughness, alpha = MATERIALS[name]
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        material.surface_render_method = "BLENDED"
    return material


class Part:
    """One part: a mesh of boxes and cylinders, each with its own material."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.mesh = bmesh.new()
        self.slots: list[str] = []

    def _slot(self, material: str) -> int:
        if material not in self.slots:
            self.slots.append(material)
        return self.slots.index(material)

    def box(self, size: tuple[float, float, float], center: tuple[float, float, float], material: str) -> list:
        made = bmesh.ops.create_cube(self.mesh, size=1.0)
        verts = made["verts"]
        bmesh.ops.scale(self.mesh, vec=size, verts=verts)
        bmesh.ops.translate(self.mesh, vec=center, verts=verts)
        slot = self._slot(material)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot
        return verts

    def rod(
        self, radius: float, length: float, center: tuple[float, float, float], axis: str, material: str
    ) -> None:
        """A cylinder along game axis [axis]: X — length, Y — vertical, Z — depth."""
        made = bmesh.ops.create_cone(
            self.mesh, cap_ends=True, segments=16, radius1=radius, radius2=radius, depth=length
        )
        verts = made["verts"]
        # A Blender cone grows along Blender's Z — that is the game's vertical.
        turn = {"X": (0.0, math.pi / 2.0, 0.0), "Y": (0.0, 0.0, 0.0), "Z": (math.pi / 2.0, 0.0, 0.0)}[axis]
        bmesh.ops.rotate(self.mesh, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Euler(turn).to_matrix())
        bmesh.ops.translate(self.mesh, vec=center, verts=verts)
        slot = self._slot(material)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot

    def publish(self) -> None:
        data = bpy.data.meshes.new(self.name)
        self.mesh.to_mesh(data)
        self.mesh.free()
        for name in self.slots:
            data.materials.append(_material(name))
        obj = bpy.data.objects.new(self.name, data)
        bpy.context.scene.collection.objects.link(obj)


# Blender: Z up, Y into depth. In the game Y is up, Z into depth — the glTF export swaps the axes
# itself (+Y up), so everything here is built in Blender axes: length X, depth −Y (toward the camera
# — the game's +Z), height Z.
def _game(x: float, y: float, z: float) -> tuple[float, float, float]:
    """A point in game axes → in Blender axes."""
    return (x, -z, y)


def _size(x: float, y: float, z: float) -> tuple[float, float, float]:
    return (x, z, y)


def build_step() -> None:
    step = Part("Step")
    # Step body and tread.
    step.box(_size(STEP_RUN, STEP_HEIGHT - 0.02, BELT_DEPTH), _game(0.0, -STEP_HEIGHT * 0.5 - 0.01, 0.0), "Aluminium")
    # Tread grooving along the travel: ridges along X.
    ridges = 14
    for index in range(ridges):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / ridges
        step.box(_size(STEP_RUN - 0.02, 0.02, 0.022), _game(0.0, -0.01, z), "Aluminium")
    # Yellow edge along the tread edge and along the camera-side flank.
    step.box(_size(0.03, 0.022, BELT_DEPTH), _game(STEP_RUN * 0.5 - 0.015, -0.009, 0.0), "Yellow")
    step.box(_size(STEP_RUN, 0.022, 0.04), _game(0.0, -0.009, BELT_DEPTH * 0.5 - 0.02), "Yellow")
    # Grooved riser: vertical ridges.
    for index in range(ridges):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / ridges
        step.box(_size(0.012, STEP_HEIGHT - 0.04, 0.022), _game(-STEP_RUN * 0.5 - 0.004, -STEP_HEIGHT * 0.5, z), "Comb")
    step.publish()


def build_balustrade() -> None:
    rail = Part("Balustrade")
    # Plinth: a stainless skirt by the steps.
    rail.box(_size(1.0, 0.12, 0.1), _game(0.0, 0.06, 0.0), "Stainless")
    # Glass.
    rail.box(_size(1.0, RAIL_HEIGHT - 0.2, 0.02), _game(0.0, 0.12 + (RAIL_HEIGHT - 0.2) * 0.5, 0.0), "Glass")
    # Guide and handrail.
    rail.box(_size(1.0, 0.03, 0.05), _game(0.0, RAIL_HEIGHT - 0.07, 0.0), "Stainless")
    rail.rod(0.05, 1.0, _game(0.0, RAIL_HEIGHT - 0.03, 0.0), "X", "Rubber")
    rail.publish()


def build_newel() -> None:
    newel = Part("Newel")
    # The handrail turns around the newel: a drum across the balustrade.
    newel.rod(0.16, 0.1, _game(0.0, RAIL_HEIGHT - 0.16, 0.0), "Z", "Stainless")
    newel.rod(0.19, 0.08, _game(0.0, RAIL_HEIGHT - 0.16, 0.0), "Z", "Rubber")
    newel.box(_size(0.3, RAIL_HEIGHT - 0.3, 0.1), _game(0.0, (RAIL_HEIGHT - 0.3) * 0.5, 0.0), "Stainless")
    newel.publish()


def build_landing() -> None:
    landing = Part("Landing")
    landing.box(_size(LANDING_RUN, LANDING_THICKNESS, BELT_DEPTH), _game(0.0, -LANDING_THICKNESS * 0.5, 0.0), "Stainless")
    # Plate grooving: a diagonal diamond grid — transverse ridges in two rows.
    for index in range(8):
        x = -LANDING_RUN * 0.5 + LANDING_RUN * (index + 0.5) / 8
        landing.box(_size(0.012, 0.008, BELT_DEPTH - 0.06), _game(x, 0.002, 0.0), "Comb")
    # Comb at the edge where the steps go under: teeth along the travel.
    landing.box(_size(0.05, 0.012, BELT_DEPTH), _game(LANDING_RUN * 0.5 - 0.025, 0.004, 0.0), "Yellow")
    for index in range(20):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / 20
        landing.box(_size(0.05, 0.01, 0.014), _game(LANDING_RUN * 0.5 + 0.02, 0.0, z), "Comb")
    landing.publish()


def build_truss() -> None:
    truss = Part("Truss")
    bar = 0.04
    for z in (-BELT_DEPTH * 0.45, BELT_DEPTH * 0.45):
        # Chords.
        truss.box(_size(1.0, bar, bar), _game(0.0, -bar * 0.5, z), "Steel")
        truss.box(_size(1.0, bar, bar), _game(0.0, -TRUSS_HEIGHT + bar * 0.5, z), "Steel")
        # Diagonals: four per metre, herringbone.
        for index in range(4):
            x = -0.5 + 0.25 * (index + 0.5)
            lean = 1.0 if index % 2 == 0 else -1.0
            length = math.hypot(0.25, TRUSS_HEIGHT)
            angle = math.atan2(TRUSS_HEIGHT, 0.25) * lean
            verts = truss.box(_size(length, bar * 0.8, bar * 0.8), (0.0, 0.0, 0.0), "Steel")
            # Tilt in the "length — vertical" plane: around Blender's Y.
            bmesh.ops.rotate(truss.mesh, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(-angle, 3, "Y"))
            bmesh.ops.translate(truss.mesh, vec=_game(x, -TRUSS_HEIGHT * 0.5, z), verts=verts)
    # Bottom cladding: it is visible from the floor under the escalator.
    truss.box(_size(1.0, 0.02, BELT_DEPTH), _game(0.0, -TRUSS_HEIGHT - 0.01, 0.0), "Stainless")
    # Side cladding with a moulding stripe: from the camera side the span is a stainless box, as on
    # a real escalator.
    for side in (-1.0, 1.0):
        z = side * (BELT_DEPTH * 0.5 + 0.012)
        truss.box(_size(1.0, TRUSS_HEIGHT, 0.02), _game(0.0, -TRUSS_HEIGHT * 0.5, z), "Stainless")
        truss.box(_size(1.0, 0.05, 0.03), _game(0.0, -TRUSS_HEIGHT * 0.45, z), "Steel")
    truss.publish()


def inside_blender() -> int:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_step()
    build_balustrade()
    build_newel()
    build_landing()
    build_truss()
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(TARGET), export_format="GLB", export_yup=True)
    print(f"wrote {TARGET}")
    return 0


def outside() -> int:
    from blender_bin import require_blender, run_script, use_utf8_output

    use_utf8_output()
    blender = require_blender()
    code, output = run_script(blender, Path(__file__))
    print(output[-2000:])
    return code


if __name__ == "__main__":
    raise SystemExit(inside_blender() if bpy is not None else outside())
