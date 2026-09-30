#!/usr/bin/env python3
"""Детали эскалатора в Blender, экспорт в glTF (ADR-0043, решение 3).

Эскалатор в здании каждый раз свой: пролёт между этажами разной длины и
крутизны, площадки своей длины. Поэтому модель — не цельная вещь, а набор
деталей, из которых `Escalator` собирает пролёт по месту:

- `Step` — ступень: алюминиевая с рифлением по ходу, жёлтая кромка у края;
  верх в начале координат, по X — длина проступи, по Y вниз — высота;
- `Balustrade` — стеклянная балюстрада метр длиной: нержавеющий цоколь,
  стекло, чёрный резиновый поручень на направляющей; низ в начале координат;
- `Newel` — тумба на конце балюстрады, вокруг которой разворачивается поручень;
- `Landing` — входная площадка: рифлёная плита и гребёнка у края, где уходят
  ступени; верх в начале координат;
- `Truss` — ферма под пролётом метр длиной: пояса, раскосы и нержавеющая
  обшивка по бокам — с M24h пролёт читается массой, а не парой реек
  (ADR-0044, решение 10).

С M24h балюстрада стоит с обеих сторон полотна, а низкого борта у камеры
больше нет: эскалатор ушёл в глубину, и перила должны читаться.

Длина вдоль X, глубина коридора — Z, как в игре. Детали в метр длиной игра
растягивает по X — рисунок у них вдоль длины ровный, и растяжка его не портит.

Скрипт живёт двумя половинами в одном файле, как `build_actors.py`:
снаружи он ищет Blender и запускает в нём сам себя, внутри собирает детали.

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

# Размеры — те же, что у `Escalator`: проступь, глубина полотна, высота
# балюстрады, площадка, м.
STEP_RUN = 0.2
STEP_HEIGHT = 0.45
BELT_DEPTH = 0.72
RAIL_HEIGHT = 0.96
LANDING_RUN = 0.42
LANDING_THICKNESS = 0.12
TRUSS_HEIGHT = 0.62

# Материалы: цвет линейный RGB, металличность, шероховатость, прозрачность.
# Металл без отражений в сцене темнеет почти до чёрного: отражать ему нечего,
# зондов отражений в здании нет. Поэтому металличность умеренная — детали ловят
# рассеянный свет ламп, а блик остаётся.
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
    """Одна деталь: сетка из коробок и цилиндров, у каждого свой материал."""

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
        """Цилиндр вдоль оси игры [axis]: X — длина, Y — вертикаль, Z — глубина."""
        made = bmesh.ops.create_cone(
            self.mesh, cap_ends=True, segments=16, radius1=radius, radius2=radius, depth=length
        )
        verts = made["verts"]
        # Конус Blender растёт вдоль Z Blender — это вертикаль игры.
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


# Blender: Z вверх, Y вглубь. В игре Y вверх, Z вглубь — экспорт glTF сам
# меняет оси (+Y вверх), поэтому здесь всё строится в осях Blender: длина X,
# глубина −Y (к камере — +Z игры), высота Z.
def _game(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Точка в осях игры → в осях Blender."""
    return (x, -z, y)


def _size(x: float, y: float, z: float) -> tuple[float, float, float]:
    return (x, z, y)


def build_step() -> None:
    step = Part("Step")
    # Тело ступени и проступь.
    step.box(_size(STEP_RUN, STEP_HEIGHT - 0.02, BELT_DEPTH), _game(0.0, -STEP_HEIGHT * 0.5 - 0.01, 0.0), "Aluminium")
    # Рифление проступи по ходу: гребни вдоль X.
    ridges = 14
    for index in range(ridges):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / ridges
        step.box(_size(STEP_RUN - 0.02, 0.02, 0.022), _game(0.0, -0.01, z), "Aluminium")
    # Жёлтая кромка по краю проступи и по боку со стороны камеры.
    step.box(_size(0.03, 0.022, BELT_DEPTH), _game(STEP_RUN * 0.5 - 0.015, -0.009, 0.0), "Yellow")
    step.box(_size(STEP_RUN, 0.022, 0.04), _game(0.0, -0.009, BELT_DEPTH * 0.5 - 0.02), "Yellow")
    # Рифлёный подступенок: вертикальные гребни.
    for index in range(ridges):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / ridges
        step.box(_size(0.012, STEP_HEIGHT - 0.04, 0.022), _game(-STEP_RUN * 0.5 - 0.004, -STEP_HEIGHT * 0.5, z), "Comb")
    step.publish()


def build_balustrade() -> None:
    rail = Part("Balustrade")
    # Цоколь: нержавеющая юбка у ступеней.
    rail.box(_size(1.0, 0.12, 0.1), _game(0.0, 0.06, 0.0), "Stainless")
    # Стекло.
    rail.box(_size(1.0, RAIL_HEIGHT - 0.2, 0.02), _game(0.0, 0.12 + (RAIL_HEIGHT - 0.2) * 0.5, 0.0), "Glass")
    # Направляющая и поручень.
    rail.box(_size(1.0, 0.03, 0.05), _game(0.0, RAIL_HEIGHT - 0.07, 0.0), "Stainless")
    rail.rod(0.05, 1.0, _game(0.0, RAIL_HEIGHT - 0.03, 0.0), "X", "Rubber")
    rail.publish()


def build_newel() -> None:
    newel = Part("Newel")
    # Поручень разворачивается вокруг тумбы: барабан поперёк балюстрады.
    newel.rod(0.16, 0.1, _game(0.0, RAIL_HEIGHT - 0.16, 0.0), "Z", "Stainless")
    newel.rod(0.19, 0.08, _game(0.0, RAIL_HEIGHT - 0.16, 0.0), "Z", "Rubber")
    newel.box(_size(0.3, RAIL_HEIGHT - 0.3, 0.1), _game(0.0, (RAIL_HEIGHT - 0.3) * 0.5, 0.0), "Stainless")
    newel.publish()


def build_landing() -> None:
    landing = Part("Landing")
    landing.box(_size(LANDING_RUN, LANDING_THICKNESS, BELT_DEPTH), _game(0.0, -LANDING_THICKNESS * 0.5, 0.0), "Stainless")
    # Рифление плиты: косая сетка ромбами — поперечные гребни в два ряда.
    for index in range(8):
        x = -LANDING_RUN * 0.5 + LANDING_RUN * (index + 0.5) / 8
        landing.box(_size(0.012, 0.008, BELT_DEPTH - 0.06), _game(x, 0.002, 0.0), "Comb")
    # Гребёнка у края, где уходят ступени: зубья по ходу.
    landing.box(_size(0.05, 0.012, BELT_DEPTH), _game(LANDING_RUN * 0.5 - 0.025, 0.004, 0.0), "Yellow")
    for index in range(20):
        z = -BELT_DEPTH * 0.5 + BELT_DEPTH * (index + 0.5) / 20
        landing.box(_size(0.05, 0.01, 0.014), _game(LANDING_RUN * 0.5 + 0.02, 0.0, z), "Comb")
    landing.publish()


def build_truss() -> None:
    truss = Part("Truss")
    bar = 0.04
    for z in (-BELT_DEPTH * 0.45, BELT_DEPTH * 0.45):
        # Пояса.
        truss.box(_size(1.0, bar, bar), _game(0.0, -bar * 0.5, z), "Steel")
        truss.box(_size(1.0, bar, bar), _game(0.0, -TRUSS_HEIGHT + bar * 0.5, z), "Steel")
        # Раскосы: четыре на метр, ёлочкой.
        for index in range(4):
            x = -0.5 + 0.25 * (index + 0.5)
            lean = 1.0 if index % 2 == 0 else -1.0
            length = math.hypot(0.25, TRUSS_HEIGHT)
            angle = math.atan2(TRUSS_HEIGHT, 0.25) * lean
            verts = truss.box(_size(length, bar * 0.8, bar * 0.8), (0.0, 0.0, 0.0), "Steel")
            # Наклон в плоскости «длина — вертикаль»: вокруг Y Blender.
            bmesh.ops.rotate(truss.mesh, verts=verts, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(-angle, 3, "Y"))
            bmesh.ops.translate(truss.mesh, vec=_game(x, -TRUSS_HEIGHT * 0.5, z), verts=verts)
    # Обшивка снизу: её видно с этажа под эскалатором.
    truss.box(_size(1.0, 0.02, BELT_DEPTH), _game(0.0, -TRUSS_HEIGHT - 0.01, 0.0), "Stainless")
    # Обшивка по бокам с полосой-молдингом: со стороны камеры пролёт —
    # нержавеющий короб, как у настоящего эскалатора.
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
    print(f"записан {TARGET}")
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
