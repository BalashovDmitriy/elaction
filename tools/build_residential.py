#!/usr/bin/env python3
"""Residential stairwell dressing in Blender, exported to glTF (ADR-0055, decision 6).

A fridge, a stove, a sofa and the rest for an apartment were found in free packs, but
three things of an eighties stairwell were not: a mailbox block, a baby pram and a
cast-iron sectional radiator. The pack's radiator is a white slab without relief, it
read as an empty rectangle in the frame. They are built here:

- `mailboxes` — a brass block of boxes on the wall: three columns, four rows,
  each door with a slot, a number strip and a lock;
- `stroller` — a carrycot pram: body, folding hood, handle, four wheels
  with disc spokes on a frame;
- `radiator` — a cast-iron radiator: a dozen ribbed sections, feet, a valve.

Length along X, depth — Z toward the camera, as in the game; the height and placement
at the wall are set by the catalogue (`PropCatalog`), here only the shape in metres.

The script lives as two halves in one file, like `build_escalator.py`: outside it finds
Blender and runs itself in it, inside it builds the models.

    python tools/build_residential.py
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
    from mathutils import Euler
except ImportError:
    bpy = None

ROOT = TOOLS.parent
TARGET = ROOT / "assets" / "models" / "props"

# Materials: linear RGB colour, metallic, roughness.
MATERIALS = {
    "Brass": ((0.55, 0.38, 0.12), 0.6, 0.38),
    "BrassDark": ((0.22, 0.15, 0.05), 0.5, 0.5),
    "Slot": ((0.02, 0.02, 0.02), 0.0, 0.8),
    "Label": ((0.75, 0.72, 0.62), 0.0, 0.7),
    "Frame": ((0.12, 0.1, 0.08), 0.3, 0.55),
    "Navy": ((0.04, 0.06, 0.14), 0.0, 0.7),
    "Hood": ((0.03, 0.04, 0.1), 0.0, 0.8),
    "Chrome": ((0.6, 0.62, 0.64), 0.7, 0.25),
    "Tyre": ((0.02, 0.02, 0.02), 0.0, 0.7),
    "Iron": ((0.48, 0.46, 0.42), 0.3, 0.6),
    "Valve": ((0.08, 0.08, 0.09), 0.4, 0.5),
}


def _material(name: str) -> "bpy.types.Material":
    color, metallic, roughness = MATERIALS[name]
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return material


# Blender: Z up, Y into depth. In the game Y is up, Z toward the camera.
def _game(x: float, y: float, z: float) -> tuple[float, float, float]:
    return (x, -z, y)


def _size(x: float, y: float, z: float) -> tuple[float, float, float]:
    return (x, z, y)


class Part:
    """A model of boxes and cylinders, each with its own material."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.mesh = bmesh.new()
        self.slots: list[str] = []

    def _paint(self, verts: list, material: str) -> None:
        if material not in self.slots:
            self.slots.append(material)
        slot = self.slots.index(material)
        for face in {f for v in verts for f in v.link_faces}:
            face.material_index = slot

    def box(self, size: tuple[float, float, float], at: tuple[float, float, float], material: str) -> None:
        verts = bmesh.ops.create_cube(self.mesh, size=1.0)["verts"]
        bmesh.ops.scale(self.mesh, vec=_size(*size), verts=verts)
        bmesh.ops.translate(self.mesh, vec=_game(*at), verts=verts)
        self._paint(verts, material)

    def rod(
        self,
        radius: float,
        length: float,
        at: tuple[float, float, float],
        axis: str,
        material: str,
        segments: int = 16,
        tilt: float = 0.0,
    ) -> None:
        """Cylinder along game axis [axis]: X — length, Y — vertical, Z — depth.

        [tilt] — tilt in the frame plane, radians, around the depth.
        """
        verts = bmesh.ops.create_cone(
            self.mesh, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=length
        )["verts"]
        turn = {"X": (0.0, math.pi / 2.0, 0.0), "Y": (0.0, 0.0, 0.0), "Z": (math.pi / 2.0, 0.0, 0.0)}[axis]
        bmesh.ops.rotate(self.mesh, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Euler(turn).to_matrix())
        if tilt != 0.0:
            # Game depth is Blender's Y axis.
            bmesh.ops.rotate(self.mesh, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Euler((0.0, tilt, 0.0)).to_matrix())
        bmesh.ops.translate(self.mesh, vec=_game(*at), verts=verts)
        self._paint(verts, material)

    def export(self) -> None:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        data = bpy.data.meshes.new(self.name)
        self.mesh.to_mesh(data)
        self.mesh.free()
        for name in self.slots:
            data.materials.append(_material(name))
        obj = bpy.data.objects.new(self.name, data)
        bpy.context.scene.collection.objects.link(obj)
        path = TARGET / f"{self.name}.glb"
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", export_yup=True)
        print(f"wrote {path}")


def build_mailboxes() -> None:
    """Mailbox block: brass doors in a dark frame, bottom at zero."""
    part = Part("mailboxes")
    columns, rows = 3, 4
    door = (0.2, 0.13)
    gap = 0.018
    width = columns * door[0] + (columns + 1) * gap
    height = rows * door[1] + (rows + 1) * gap
    part.box((width, height, 0.12), (0.0, height * 0.5, -0.06), "Frame")
    for column in range(columns):
        for row in range(rows):
            x = -width * 0.5 + gap + door[0] * 0.5 + column * (door[0] + gap)
            y = gap + door[1] * 0.5 + row * (door[1] + gap)
            part.box((door[0], door[1], 0.012), (x, y, 0.006), "Brass")
            # Letter slot, number strip and lock.
            part.box((door[0] * 0.62, 0.012, 0.006), (x, y + door[1] * 0.25, 0.014), "Slot")
            part.box((door[0] * 0.4, 0.022, 0.004), (x - door[0] * 0.1, y - door[1] * 0.18, 0.014), "Label")
            part.rod(0.012, 0.01, (x + door[0] * 0.33, y - door[1] * 0.18, 0.016), "Z", "BrassDark", 10)
    # A canopy on top and a shelf below: the block reads as an object, not a tile.
    part.box((width + 0.04, 0.03, 0.16), (0.0, height + 0.015, -0.04), "Frame")
    part.box((width + 0.04, 0.025, 0.14), (0.0, -0.0125, -0.05), "Frame")
    part.export()


def build_stroller() -> None:
    """An eighties carrycot pram, wheels at zero, handle to the left."""
    part = Part("stroller")
    wheel = 0.13
    axle = wheel
    # Frame: two longitudinal tubes and struts to the body.
    part.rod(0.012, 0.62, (0.0, axle + 0.06, 0.0), "X", "Chrome", 10)
    for x in (-0.2, 0.2):
        part.rod(0.012, 0.18, (x, axle + 0.14, 0.0), "Y", "Chrome", 10)
    # Wheels on both sides: tyre, disc rim, hub.
    for x in (-0.26, 0.26):
        for z in (-0.2, 0.2):
            part.rod(wheel, 0.035, (x, axle, z), "Z", "Tyre", 24)
            part.rod(wheel * 0.72, 0.04, (x, axle, z), "Z", "Chrome", 24)
            part.rod(0.025, 0.05, (x, axle, z), "Z", "Valve", 10)
        part.rod(0.008, 0.42, (x, axle, 0.0), "Z", "Chrome", 8)
    # Carrycot body: a box with a rounded bottom in two steps.
    body_y = axle + 0.24
    part.box((0.62, 0.22, 0.38), (0.0, body_y + 0.11, 0.0), "Navy")
    part.box((0.54, 0.06, 0.32), (0.0, body_y - 0.02, 0.0), "Navy")
    part.box((0.64, 0.025, 0.4), (0.0, body_y + 0.225, 0.0), "Chrome")
    # Folding hood over the head end: a half-cylinder across the body — the lower half
    # goes into the body, an arc on top, like a stretched canopy.
    part.rod(0.2, 0.39, (0.11, body_y + 0.22, 0.0), "Z", "Hood", 24)
    # Handle: slanted struts and a crossbar.
    for z in (-0.17, 0.17):
        part.rod(0.012, 0.42, (-0.42, body_y + 0.32, z), "Y", "Chrome", 10, tilt=-0.55)
    part.rod(0.018, 0.4, (-0.53, body_y + 0.5, 0.0), "Z", "Tyre", 12)
    part.export()


def build_radiator() -> None:
    """Cast-iron sectional radiator on feet, valve on the right."""
    part = Part("radiator")
    sections = 10
    pitch = 0.07
    height = 0.6
    width = sections * pitch
    for index in range(sections):
        x = -width * 0.5 + pitch * (index + 0.5)
        # Section: two columns and ribs between them.
        for z in (-0.045, 0.045):
            part.box((pitch * 0.62, height - 0.06, 0.05), (x, height * 0.5 + 0.02, z), "Iron")
        part.box((pitch * 0.3, height - 0.12, 0.07), (x, height * 0.5 + 0.02, 0.0), "Iron")
    # Headers at top and bottom.
    for y in (0.07, height - 0.02):
        part.rod(0.03, width, (0.0, y, 0.0), "X", "Iron", 12)
    # Feet and the valve on the supply pipe.
    for x in (-width * 0.4, width * 0.4):
        part.box((0.05, 0.06, 0.12), (x, 0.03, 0.0), "Iron")
    part.rod(0.02, 0.12, (width * 0.5 + 0.06, height - 0.02, 0.0), "X", "Valve", 10)
    part.rod(0.045, 0.025, (width * 0.5 + 0.09, height + 0.04, 0.0), "Y", "Valve", 14)
    part.rod(0.012, 0.05, (width * 0.5 + 0.09, height + 0.015, 0.0), "Y", "Valve", 8)
    part.export()


def inside_blender() -> int:
    TARGET.mkdir(parents=True, exist_ok=True)
    build_mailboxes()
    build_stroller()
    build_radiator()
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
