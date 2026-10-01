#!/usr/bin/env python3
"""Фасады города из пака Quaternius Downtown City MegaKit (ADR-0051, решение 10).

Город за зданием — сотни домов в рядах на 90–600 м от камеры, размытых глубиной
резкости, и дома пака целиком (18–45 тыс. треугольников) столько не потянут.
Поэтому фасад запекается: на каждый стиль из модулей пака собираются три ряда —
первый этаж, типовой этаж и карниз, — и снимаются ортокамерой спереди. Игра
кладёт их фактурой на коробку дома ([CityLook]): этажи повторяются, окна — по
сетке ряда, а ночью горит то, что под маской окон.

Проходы — по одной картинке ряда на каждый:
  albedo  — цвет материала без света;
  normal  — нормаль в пространстве фасада (x вправо, y вверх, z к камере);
  orm     — затенение углов (AO), шероховатость, металл;
  mask    — окно: стекло и плоскость комнаты за ним.
Из рядов складывается атлас `assets/textures/city/facade_*.png`: стили
столбцами, ряды — сверху вниз: карниз, этаж, первый этаж.

Исходник — пак Downtown Standard (CC0) в `.cache/downtown/`: его нет в
репозитории, как и исходников звука. Скачать с https://quaternius.itch.io/downtown-city-megakit
(Standard, бесплатно), распаковать так, чтобы были `.cache/downtown/gltf/*.gltf`.

    python tools/build_city.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

try:
    import bmesh
    import bpy
except ImportError:
    bpy = None

ROOT = TOOLS.parent
PACK = ROOT / ".cache" / "downtown" / "gltf"
BAKE = ROOT / ".cache" / "city_bake"
TARGET = ROOT / "assets" / "textures" / "city"

# Пикселей на метр фасада. Ближний ряд города — около 27 пикселей на метр
# экрана в FullHD; вдвое больше — с запасом на 4K и мипмапы.
DENSITY = 64

# Ширина плитки фасада, м: два модуля по 2 м или один на 4 м.
TILE_WIDTH = 4.0

# Ряды плитки сверху вниз: имя и высота, м.
ROWS = [("top", 1.0), ("floor", 3.0), ("ground", 3.0)]

# Стили фасада: модули ряда слева направо. Тон кирпича и камня игра даёт
# множителем — красный, бледный, бурый из одного стиля.
STYLES = {
    "brick": {
        "top": ["Cornice_Brick_Center", "Cornice_Brick_Center"],
        "floor": ["Brick_Window_Trim", "Brick_Window_Trim"],
        "ground": ["Trim_FirstFloor_Window_001", "Trim_FirstFloor_Window_001"],
    },
    "double": {
        "top": ["Cornice_Trim_Center", "Cornice_Trim_Center"],
        "floor": ["Brick_RedWhite_DoubleWindow"],
        "ground": ["Trim_FirstFloor_Window_001", "Trim_FirstFloor_Window_001"],
    },
    "inset": {
        "top": ["Cornice_Trim_Center", "Cornice_Trim_Center"],
        "floor": ["Brick_Inset_Window"],
        "ground": ["Trim_FirstFloor_Window_001", "Trim_FirstFloor_Window_001"],
    },
    "glass": {
        "top": ["Cornice_Metal_Center", "Cornice_Metal_Center"],
        "floor": ["Metal_FullWindow", "Metal_FullWindow"],
        "ground": ["Metal_FirstFloor_Window", "Metal_FirstFloor_Window"],
    },
    "office": {
        "top": ["Cornice_Metal_Center", "Cornice_Metal_Center"],
        "floor": ["Metal_Window", "Metal_Window"],
        "ground": ["Metal_FirstFloor_Window", "Metal_FirstFloor_Window"],
    },
    "stone": {
        "top": ["Cornice_Trim_Center", "Cornice_Trim_Center"],
        "floor": ["Trim_Window", "Trim_Window"],
        "ground": ["Trim_FirstFloor_Window_001", "Trim_FirstFloor_Window_001"],
    },
}

PASSES = ["albedo", "normal", "orm", "mask"]

# Окно за стеклом: в цвете — тёмное стекло, в маске — единица. Само стекло
# пака полупрозрачное и снимается: за ним видна бы была серая плоскость комнаты.
WINDOW_MATERIALS = ("MI_FakeInterior",)
GLASS = "MI_Glass"
WINDOW_ALBEDO = (0.02, 0.022, 0.026)
WINDOW_ROUGHNESS = 0.06


def _module_width(obj) -> float:
    xs = [(obj.matrix_world @ v.co).x for v in obj.data.vertices]
    return max(xs) - min(xs)


def _import(name: str):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(PACK / f"{name}.gltf"))
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    return meshes[0]


def _drop_glass(obj) -> None:
    mesh = obj.data
    glass = {i for i, m in enumerate(mesh.materials) if m is not None and m.name.startswith(GLASS)}
    if not glass:
        return
    work = bmesh.new()
    work.from_mesh(mesh)
    bmesh.ops.delete(work, geom=[f for f in work.faces if f.material_index in glass], context="FACES")
    work.to_mesh(mesh)
    work.free()


def _source(node_tree, principled, name: str):
    socket = principled.inputs[name]
    return socket.links[0].from_socket if socket.is_linked else None


def _texture(socket):
    """Фактура, из которой идёт цвет: импортёр glTF умножает её на вершинный
    цвет, а у пака в нём маска износа — красный канал красил металл в красное."""
    queue = [socket.links[0].from_node] if socket.is_linked else []
    seen = set()
    while queue:
        node = queue.pop(0)
        if node in seen:
            continue
        seen.add(node)
        if node.type == "TEX_IMAGE":
            return node.outputs["Color"]
        for entry in node.inputs:
            queue.extend(link.from_node for link in entry.links)
    return None


def _rig_material(material) -> None:
    """Готовит у материала по эмиссии на каждый проход: выход переключается."""
    if material.get("passes_ready"):
        return
    tree = material.node_tree
    nodes, links = tree.nodes, tree.links
    principled = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    output = next(n for n in nodes if n.type == "OUTPUT_MATERIAL")
    window = material.name.startswith(WINDOW_MATERIALS)

    def emission(name: str):
        node = nodes.new("ShaderNodeEmission")
        node.name = "pass_" + name
        node.inputs["Strength"].default_value = 1.0
        return node

    albedo = emission("albedo")
    if window or principled is None:
        albedo.inputs["Color"].default_value = (*WINDOW_ALBEDO, 1.0)
    else:
        colour = _texture(principled.inputs["Base Color"])
        if colour is not None:
            links.new(colour, albedo.inputs["Color"])
        else:
            albedo.inputs["Color"].default_value = principled.inputs["Base Color"].default_value

    # Нормаль: мировая из карты нормалей, переведённая в плоскость фасада.
    normal = emission("normal")
    geometry = nodes.new("ShaderNodeNewGeometry")
    world = geometry.outputs["Normal"]
    if principled is not None:
        mapped = _source(tree, principled, "Normal")
        if mapped is not None:
            world = mapped
    split = nodes.new("ShaderNodeSeparateXYZ")
    links.new(world, split.inputs[0])
    flip = nodes.new("ShaderNodeMath")
    flip.operation = "MULTIPLY"
    flip.inputs[1].default_value = -1.0
    links.new(split.outputs["Y"], flip.inputs[0])
    facade = nodes.new("ShaderNodeCombineXYZ")
    links.new(split.outputs["X"], facade.inputs["X"])
    links.new(split.outputs["Z"], facade.inputs["Y"])
    links.new(flip.outputs[0], facade.inputs["Z"])
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "MULTIPLY_ADD"
    scale.inputs[1].default_value = (0.5, 0.5, 0.5)
    scale.inputs[2].default_value = (0.5, 0.5, 0.5)
    links.new(facade.outputs[0], scale.inputs[0])
    links.new(scale.outputs[0], normal.inputs["Color"])

    orm = emission("orm")
    occlusion = nodes.new("ShaderNodeAmbientOcclusion")
    occlusion.samples = 32
    occlusion.inputs["Distance"].default_value = 0.35
    combine = nodes.new("ShaderNodeCombineColor")
    links.new(occlusion.outputs["AO"], combine.inputs[0])
    for index, name in ((1, "Roughness"), (2, "Metallic")):
        source = None if principled is None or window else _source(tree, principled, name)
        if source is not None:
            links.new(source, combine.inputs[index])
        elif window:
            combine.inputs[index].default_value = WINDOW_ROUGHNESS if index == 1 else 0.0
        elif principled is not None:
            combine.inputs[index].default_value = principled.inputs[name].default_value
    links.new(combine.outputs[0], orm.inputs["Color"])

    mask = emission("mask")
    mask.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0) if window else (0.0, 0.0, 0.0, 1.0)
    material["output_name"] = output.name
    material["passes_ready"] = True


def _show(material, name: str) -> None:
    tree = material.node_tree
    output = tree.nodes[material["output_name"]]
    for link in list(output.inputs["Surface"].links):
        tree.links.remove(link)
    tree.links.new(tree.nodes["pass_" + name].outputs[0], output.inputs["Surface"])


def _scene(width: float, height: float) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.cycles.filter_width = 0.8
    scene.render.resolution_x = round(width * DENSITY)
    scene.render.resolution_y = round(height * DENSITY)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    world = bpy.data.worlds.new("Black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    scene.world = world
    camera = bpy.data.cameras.new("Front")
    camera.type = "ORTHO"
    camera.ortho_scale = max(width, height)
    camera.clip_start = 0.01
    camera.clip_end = 20.0
    holder = bpy.data.objects.new("Front", camera)
    holder.location = (0.0, -5.0, height * 0.5)
    holder.rotation_euler = (1.5707963, 0.0, 0.0)
    scene.collection.objects.link(holder)
    scene.camera = holder


def _colour_space(raw: bool) -> None:
    settings = bpy.context.scene.view_settings
    settings.view_transform = "Raw" if raw else "Standard"
    settings.look = "None"
    settings.exposure = 0.0
    settings.gamma = 1.0


def _bake_row(style: str, row: str, height: float, modules: list[str]) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    placed = []
    x = -TILE_WIDTH * 0.5
    for name in modules:
        obj = _import(name)
        _drop_glass(obj)
        width = _module_width(obj)
        obj.location.x += x + width * 0.5
        x += width
        placed.append(obj)
    _scene(TILE_WIDTH, height)
    materials = {slot.material for obj in placed for slot in obj.material_slots if slot.material}
    for material in materials:
        _rig_material(material)
    for name in PASSES:
        for material in materials:
            _show(material, name)
        _colour_space(raw=name != "albedo")
        path = BAKE / f"{style}_{row}_{name}.png"
        bpy.context.scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        print(f"снят {path.name}")


def inside_blender() -> int:
    BAKE.mkdir(parents=True, exist_ok=True)
    for style, rows in STYLES.items():
        for row, height in ROWS:
            _bake_row(style, row, height, rows[row])
    return 0


def _compose() -> None:
    from PIL import Image

    TARGET.mkdir(parents=True, exist_ok=True)
    width = round(TILE_WIDTH * DENSITY)
    height = sum(round(h * DENSITY) for _, h in ROWS)
    names = list(STYLES)
    sheets = {name: Image.new("RGB", (width * len(names), height)) for name in PASSES}
    for column, style in enumerate(names):
        top = 0
        for row, row_height in ROWS:
            for name in PASSES:
                piece = Image.open(BAKE / f"{style}_{row}_{name}.png").convert("RGB")
                sheets[name].paste(piece, (column * width, top))
            top += round(row_height * DENSITY)
    albedo = sheets["albedo"].convert("RGBA")
    albedo.putalpha(sheets["mask"].convert("L"))
    albedo.save(TARGET / "facade_albedo.png")
    sheets["normal"].save(TARGET / "facade_normal.png")
    sheets["orm"].save(TARGET / "facade_orm.png")
    layout = {
        "styles": names,
        "tile_width": TILE_WIDTH,
        "density": DENSITY,
        "rows": [{"name": name, "height": h} for name, h in ROWS],
    }
    (TARGET / "facade_layout.json").write_text(json.dumps(layout, indent=2) + chr(10), encoding="utf-8")
    print(f"записан атлас {width * len(names)}×{height} в {TARGET}")


def outside() -> int:
    from blender_bin import require_blender, run_script, use_utf8_output

    use_utf8_output()
    if not PACK.exists():
        print(f"нет пака {PACK}: скачайте Downtown Standard (см. начало файла)")
        return 1
    blender = require_blender()
    code, output = run_script(blender, Path(__file__), timeout=1800)
    for line in output.splitlines():
        if "снят" in line or "Error" in line or "Traceback" in line or "rror:" in line:
            print(line)
    if code != 0:
        return code
    _compose()
    return 0


if __name__ == "__main__":
    raise SystemExit(inside_blender() if bpy is not None else outside())
