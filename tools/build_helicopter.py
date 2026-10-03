#!/usr/bin/env python3
"""Intro helicopter in Blender, exported to glTF (ADR-0049).

The low-poly kazuma the helicopter flew as since M24b read as a flat silhouette in the
M24g shots: a dozen faces, the rotor as one line, skids as sticks, no doors, no tail
rotor. No better free model with the rotor as a separate part was found on poly.pizza,
so the helicopter is built here.

A light helicopter with an enclosed rotor, lofted through cross-sections: a rounded
glazed nose, a cabin, a taper into the tail boom, a fin with a stabiliser, an engine
cowling with exhaust and intake, skids on cross tubes with steps, a sliding door — the
cabin light and seats in the opening. The main and tail rotors are separate nodes
`MainRotor` and `TailRotor`, origin on the axis; the game spins them. Since M24k
(ADR-0052, decision 6) the door is also its own node `Door`, closed: the game rolls it
back along the rails. In the cabin is the pilot's seat, its place is the empty
`PilotSeat`: the game seats the pilot. The points for lights, searchlight and winch are
empties: the game puts its own things there rather than guessing from the bounds.

Metres, nose toward +X, the side near the camera is Blender −Y (Godot +Z after export),
origin under the main rotor axis at the level of the skid bottoms, middle in depth.

    python tools/build_helicopter.py
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
    from mathutils import Matrix, Vector
except ImportError:
    bpy = None

ROOT = TOOLS.parent
TARGET = ROOT / "assets" / "models" / "aircraft" / "helicopter.glb"

# Materials: linear RGB colour, metallic, roughness. The game repaints the fuselage and
# glass with its own (`Helicopter`); the rest goes as is.
MATERIALS = {
    "Hull": ((0.1, 0.12, 0.16), 0.5, 0.35),
    "Stripe": ((0.55, 0.05, 0.04), 0.3, 0.4),
    "Glass": ((0.02, 0.03, 0.04), 0.1, 0.05),
    "Cabin": ((0.35, 0.25, 0.15), 0.0, 0.8),
    "Seat": ((0.05, 0.05, 0.055), 0.0, 0.6),
    "Rotor": ((0.04, 0.04, 0.045), 0.4, 0.5),
    "Skid": ((0.3, 0.31, 0.33), 0.7, 0.3),
    "Metal": ((0.18, 0.18, 0.2), 0.7, 0.35),
    "Exhaust": ((0.05, 0.045, 0.04), 0.6, 0.6),
}

# Fuselage cross-sections: x, half-width, half-height, height of the middle above the
# skid bottoms, m. From nose to tail: nose, cabin, taper, boom.
SECTIONS = [
    (2.95, 0.06, 0.06, 1.1),
    (2.8, 0.42, 0.42, 1.14),
    (2.5, 0.7, 0.66, 1.26),
    (2.05, 0.84, 0.8, 1.36),
    (1.2, 0.9, 0.86, 1.4),
    (0.0, 0.9, 0.84, 1.42),
    (-1.1, 0.8, 0.74, 1.48),
    (-1.8, 0.5, 0.48, 1.6),
    (-2.35, 0.24, 0.26, 1.74),
    (-4.9, 0.14, 0.15, 1.86),
    (-5.6, 0.08, 0.1, 1.9),
]
RING = 20
# Glazing: the nose and the cabin top ahead of this x, side windows — between these x
# and above this height.
WINDSCREEN_X = 1.55
SIDE_WINDOWS = (0.25, 1.55, 1.42)
# Sliding door opening on the near side: x from and to, height from and to.
DOOR = (-1.05, 0.2, 0.72, 1.98)
# Main rotor: axis height, radius, blade width and thickness, blade count.
ROTOR_HEIGHT = 3.02
ROTOR_RADIUS = 4.4
BLADE = (0.3, 0.045)
BLADES = 4
# Tail rotor: axis, radius, blade count.
TAIL_ROTOR = (-5.42, -0.2, 2.02)
TAIL_RADIUS = 0.72
TAIL_BLADES = 2
# Pilot seat: x, y, cushion height above the skid bottoms. The right seat is toward the
# near side: the pilot is visible through the side window.
PILOT_SEAT = (1.05, -0.32, 0.98)


class Part:
    """Mesh from bmesh pieces with a material on each face."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.mesh = bmesh.new()
        self.materials: list[str] = []

    def slot(self, material: str) -> int:
        if material not in self.materials:
            self.materials.append(material)
        return self.materials.index(material)

    def paint(self, faces, material: str) -> None:
        index = self.slot(material)
        for face in faces:
            face.material_index = index

    def box(self, size, centre, material: str, rotation: Matrix | None = None):
        made = bmesh.ops.create_cube(self.mesh, size=1.0)
        verts = made["verts"]
        bmesh.ops.scale(self.mesh, vec=size, verts=verts)
        if rotation is not None:
            bmesh.ops.rotate(self.mesh, cent=(0.0, 0.0, 0.0), matrix=rotation, verts=verts)
        bmesh.ops.translate(self.mesh, vec=centre, verts=verts)
        self.paint({face for vert in verts for face in vert.link_faces}, material)
        return verts

    def tube(self, start: Vector, end: Vector, radius: float, material: str, segments: int = 8):
        axis = end - start
        made = bmesh.ops.create_cone(
            self.mesh, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=axis.length
        )
        verts = made["verts"]
        turn = Vector((0.0, 0.0, 1.0)).rotation_difference(axis.normalized()).to_matrix()
        bmesh.ops.rotate(self.mesh, cent=(0.0, 0.0, 0.0), matrix=turn, verts=verts)
        bmesh.ops.translate(self.mesh, vec=(start + end) * 0.5, verts=verts)
        self.paint({face for vert in verts for face in vert.link_faces}, material)
        return verts

    def publish(self, origin=(0.0, 0.0, 0.0), smooth: bool = False):
        origin = Vector(origin)
        bmesh.ops.translate(self.mesh, vec=-origin, verts=self.mesh.verts[:])
        mesh = bpy.data.meshes.new(self.name)
        self.mesh.to_mesh(mesh)
        self.mesh.free()
        for name in self.materials:
            mesh.materials.append(_material(name))
        for polygon in mesh.polygons:
            polygon.use_smooth = smooth
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = origin
        bpy.context.scene.collection.objects.link(obj)
        return obj


def _material(name: str):
    color, metallic, roughness = MATERIALS[name]
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return material


def _ring(x: float, half_w: float, half_h: float, centre: float) -> list[Vector]:
    """Superellipse cross-section: nearly straight sides, like a cabin, not a tube."""
    points = []
    for step in range(RING):
        angle = math.tau * step / RING
        c, s = math.cos(angle), math.sin(angle)
        y = half_w * math.copysign(abs(c) ** 0.7, c)
        z = half_h * math.copysign(abs(s) ** 0.8, s)
        points.append(Vector((x, y, centre + z)))
    return points


def build_hull() -> None:
    hull = Part("Hull")
    rings = []
    for section in SECTIONS:
        rings.append([hull.mesh.verts.new(point) for point in _ring(*section)])
    faces = []
    for ahead, behind in zip(rings, rings[1:]):
        for step in range(RING):
            nxt = (step + 1) % RING
            faces.append(hull.mesh.faces.new((ahead[step], ahead[nxt], behind[nxt], behind[step])))
    faces.append(hull.mesh.faces.new(list(reversed(rings[0]))))
    faces.append(hull.mesh.faces.new(rings[-1]))
    bmesh.ops.recalc_face_normals(hull.mesh, faces=faces)
    hull.paint(faces, "Hull")
    hull.mesh.normal_update()
    x0, x1, window_low = SIDE_WINDOWS
    doorway = []
    for face in faces:
        centre = face.calc_center_median()
        _, _, _, mid = min(SECTIONS, key=lambda s: abs(s[0] - centre.x))
        # Windscreen and nose top are glass; side windows of the cabin are glass.
        if centre.x > WINDSCREEN_X and centre.z > mid + 0.12 and face.normal.z > -0.3:
            hull.paint([face], "Glass")
        elif x0 < centre.x < x1 and centre.z > window_low and abs(face.normal.y) > 0.5:
            hull.paint([face], "Glass")
        elif DOOR[0] < centre.x < DOOR[1] and DOOR[2] < centre.z < DOOR[3] and face.normal.y < -0.5:
            # The door opening is cut out: the cabin interior is visible through it.
            doorway.append(face)
        elif 0.98 < centre.z < 1.08 and abs(face.normal.y) > 0.5 and centre.x < DOOR[0] - 0.05:
            hull.paint([face], "Stripe")
    bmesh.ops.delete(hull.mesh, geom=doorway, context="FACES")
    # Cabin interior behind the opening: back wall, floor and ceiling — what is seen
    # through the door.
    door_mid = (DOOR[0] + DOOR[1]) * 0.5
    door_len = DOOR[1] - DOOR[0] + 0.3
    hull.box((door_len, 0.04, DOOR[3] - DOOR[2]), Vector((door_mid, 0.55, (DOOR[2] + DOOR[3]) * 0.5)), "Cabin")
    hull.box((door_len, 1.5, 0.04), Vector((door_mid, 0.0, DOOR[2] + 0.02)), "Seat")
    hull.box((door_len, 1.5, 0.04), Vector((door_mid, 0.0, DOOR[3] - 0.02)), "Cabin")
    # Cabin window frames: posts along the near and far sides and a frame along the
    # bottom of the glazing — without them the windows read as a solid fill.
    for side in (-1.0, 1.0):
        for x in (0.25, 0.95, 1.6):
            hull.box((0.07, 0.05, 0.62), Vector((x, side * 0.86, 1.86)), "Metal")
        hull.box((1.45, 0.05, 0.05), Vector((0.93, side * 0.87, 1.5)), "Metal")
    # Post in the middle of the windscreen.
    hull.box((0.7, 0.05, 0.06), Vector((2.3, 0.0, 1.62)), "Metal", Matrix.Rotation(0.6, 3, "Y"))
    # Engine cowling with intake and exhaust, rotor mast.
    hull.box((2.3, 0.9, 0.34), Vector((-0.35, 0.0, 2.35)), "Hull")
    hull.box((0.9, 0.7, 0.18), Vector((-0.2, 0.0, 2.6)), "Hull")
    for side in (-1.0, 1.0):
        hull.box((0.36, 0.05, 0.16), Vector((0.45, side * 0.46, 2.35)), "Metal")
    hull.tube(Vector((-1.45, -0.2, 2.35)), Vector((-1.95, -0.26, 2.3)), 0.11, "Exhaust")
    hull.tube(Vector((0.0, 0.0, 2.6)), Vector((0.0, 0.0, ROTOR_HEIGHT - 0.05)), 0.09, "Metal")
    # Seats in the door opening and the opening's frame.
    for x in (-0.75, -0.2):
        hull.box((0.45, 0.5, 0.12), Vector((x, -0.25, 0.95)), "Seat")
        hull.box((0.1, 0.5, 0.6), Vector((x - 0.2, -0.25, 1.28)), "Seat")
    for x in DOOR[:2]:
        hull.box((0.05, 0.06, DOOR[3] - DOOR[2]), Vector((x, -0.9, (DOOR[2] + DOOR[3]) * 0.5)), "Metal")
    # Sliding door rails: above and below the opening, back by its length.
    door_len = DOOR[1] - DOOR[0]
    hull.box((door_len * 2.0, 0.04, 0.04), Vector((DOOR[0], -0.95, DOOR[3] + 0.02)), "Metal")
    hull.box((door_len * 2.0, 0.03, 0.03), Vector((DOOR[0], -0.94, DOOR[2] - 0.03)), "Metal")
    # Pilot seat in the cabin: back to the cabin, facing the nose.
    hull.box((0.5, 0.5, 0.12), Vector((PILOT_SEAT[0], PILOT_SEAT[1], PILOT_SEAT[2] - 0.06)), "Seat")
    hull.box((0.12, 0.5, 0.7), Vector((PILOT_SEAT[0] - 0.28, PILOT_SEAT[1], PILOT_SEAT[2] + 0.3)), "Seat")
    # Instrument panel under the windscreen.
    hull.box((0.3, 1.3, 0.3), Vector((2.15, 0.0, 1.3)), "Metal")
    # Fin, stabiliser and tail skid.
    fin = hull.box((0.7, 0.06, 1.0), Vector((-5.35, 0.0, 2.35)), "Hull")
    bmesh.ops.rotate(
        hull.mesh, cent=(-5.35, 0.0, 2.35), matrix=Matrix.Rotation(-0.35, 3, "Y"), verts=fin
    )
    hull.box((0.45, 1.5, 0.05), Vector((-4.3, 0.0, 1.88)), "Hull")
    for side in (-1.0, 1.0):
        hull.box((0.4, 0.05, 0.3), Vector((-4.2, side * 0.75, 1.98)), "Hull")
    hull.tube(Vector((-5.4, 0.0, 1.8)), Vector((-5.25, 0.0, 1.45)), 0.03, "Skid")
    # Searchlight under the nose and antenna under the belly.
    hull.tube(Vector((2.2, -0.2, 0.62)), Vector((2.35, -0.2, 0.5)), 0.11, "Metal")
    hull.tube(Vector((-0.5, 0.0, 0.6)), Vector((-0.5, 0.0, 0.35)), 0.015, "Metal")
    # Winch above the door.
    hull.box((0.18, 0.28, 0.14), Vector((0.0, -0.95, 2.05)), "Metal")
    hull.publish(smooth=True)


def build_door() -> None:
    """Sliding door, closed: a panel with a window and a handle. Origin — middle of the
    opening on the near side; the game rolls it back along the rails."""
    door = Part("Door")
    door_len = DOOR[1] - DOOR[0]
    middle = Vector(((DOOR[0] + DOOR[1]) * 0.5, -0.95, (DOOR[2] + DOOR[3]) * 0.5))
    door.box((door_len + 0.06, 0.05, DOOR[3] - DOOR[2] + 0.04), middle, "Hull")
    door.box((door_len * 0.6, 0.02, 0.36), middle + Vector((0.0, -0.03, 0.35)), "Glass")
    door.box((0.14, 0.04, 0.04), middle + Vector((door_len * 0.35, -0.04, -0.05)), "Metal")
    door.publish(origin=middle)


def build_skids() -> None:
    skids = Part("Skids")
    for side in (-1.0, 1.0):
        y = side * 0.95
        skids.tube(Vector((-1.7, y, 0.06)), Vector((1.7, y, 0.06)), 0.055, "Skid")
        skids.tube(Vector((1.7, y, 0.06)), Vector((2.05, y, 0.24)), 0.055, "Skid")
        for x in (1.05, -0.95):
            skids.tube(Vector((x, y, 0.06)), Vector((x + 0.05, side * 0.55, 0.62)), 0.045, "Skid")
        # Step on the front strut.
        skids.box((0.4, 0.14, 0.03), Vector((1.1, side * 0.82, 0.32)), "Metal")
    for x in (1.05, -0.95):
        skids.tube(Vector((x + 0.05, -0.55, 0.62)), Vector((x + 0.05, 0.55, 0.62)), 0.04, "Skid")
    skids.publish()


def build_main_rotor() -> None:
    rotor = Part("MainRotor")
    hub = Vector((0.0, 0.0, ROTOR_HEIGHT))
    rotor.tube(hub - Vector((0.0, 0.0, 0.07)), hub + Vector((0.0, 0.0, 0.07)), 0.2, "Metal", 12)
    rotor.tube(hub + Vector((0.0, 0.0, 0.07)), hub + Vector((0.0, 0.0, 0.2)), 0.08, "Metal", 10)
    width, thickness = BLADE
    for blade in range(BLADES):
        angle = math.tau * blade / BLADES
        turn = Matrix.Rotation(angle, 3, "Z")
        middle = hub + turn @ Vector((ROTOR_RADIUS * 0.5 + 0.12, 0.0, 0.02))
        # Blade with a slight pitch angle — catches the light with a face.
        pitch = Matrix.Rotation(0.08, 3, "X")
        rotor.box((ROTOR_RADIUS - 0.25, width, thickness), middle, "Rotor", turn @ pitch)
    rotor.publish(origin=hub)


def build_tail_rotor() -> None:
    rotor = Part("TailRotor")
    hub = Vector(TAIL_ROTOR)
    rotor.tube(hub + Vector((0.0, 0.1, 0.0)), hub - Vector((0.0, 0.1, 0.0)), 0.08, "Metal", 10)
    for blade in range(TAIL_BLADES):
        angle = math.tau * blade / TAIL_BLADES
        turn = Matrix.Rotation(angle, 3, "Y")
        middle = hub + turn @ Vector((TAIL_RADIUS * 0.5, -0.05, 0.0))
        rotor.box((TAIL_RADIUS, 0.03, 0.14), middle, "Rotor", turn)
    rotor.publish(origin=hub)


def mark(name: str, at: Vector) -> None:
    anchor = bpy.data.objects.new(name, None)
    anchor.location = at
    bpy.context.scene.collection.objects.link(anchor)


def inside_blender() -> int:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_hull()
    build_door()
    build_skids()
    build_main_rotor()
    build_tail_rotor()
    # Lights: green on the starboard side (toward the camera), red beacon top and
    # bottom, white strobe on the fin; searchlight, cabin light and winch hook.
    mark("NavGreen", Vector((1.3, -0.92, 1.05)))
    mark("BeaconTop", Vector((-1.0, 0.0, 2.72)))
    mark("BeaconBelly", Vector((0.3, 0.0, 0.52)))
    mark("Strobe", Vector((-5.62, 0.0, 2.75)))
    mark("Searchlight", Vector((2.37, -0.2, 0.47)))
    mark("CabinLight", Vector((-0.4, -0.55, 1.5)))
    mark("Winch", Vector((0.0, -1.02, 2.0)))
    mark("PilotSeat", Vector(PILOT_SEAT))
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(TARGET), export_format="GLB", export_yup=True)
    print(f"wrote {TARGET}")
    return 0


def outside() -> int:
    from blender_bin import require_blender, run_script, use_utf8_output

    use_utf8_output()
    blender = require_blender()
    code, output = run_script(blender, Path(__file__))
    for line in output.splitlines():
        if "wrote" in line or "Error" in line or "Traceback" in line or "rror:" in line:
            print(line)
    return code


if __name__ == "__main__":
    raise SystemExit(inside_blender() if bpy is not None else outside())
