class_name CityLook
extends RefCounted

## The city look up close (M24a, user's remark — "raise the background
## detail"): the pack's baked facades (ADR-0051, decision 10), lit glass with a frame
## and life behind it, signs with letters (ADR-0037, decision 4).
##
## All by shaders on multimeshes: no nodes or light sources were added, and the city
## does not touch the frame budget. Which facade windows are lit is decided by the
## building shader from the house seed ([method building_custom]) — the city repeats by
## seed down to the window.

## What is behind the glass of a lit window: the same in [code]city_window.gdshaderinc[/code].
enum Inside { PLAIN, BLINDS, CURTAINS, PERSON, TV, FLICKER }

## Baked facade styles — atlas columns in the order of `tools/build_city.py`.
enum Style { BRICK, DOUBLE, INSET, GLASS, OFFICE, STONE }

const LIT_SHADER := preload("res://src/levels/city_window_lit.gdshader")
const SIGN_SHADER := preload("res://src/levels/city_sign.gdshader")

## Window by house type, m: offices have wide ones, glass towers — almost the whole
## grid pitch ([constant CityPlan.WINDOW_STEP]), residential and brick ones — narrow
## and tall.
const WINDOW_SIZES: Array[Vector2] = [
	Vector2(1.7, 1.6), Vector2(1.1, 1.5), Vector2(2.1, 2.3), Vector2(1.0, 1.7)
]

const BUILDING_SHADER := preload("res://src/levels/city_building.gdshader")
const ALBEDO_ATLAS := preload("res://assets/textures/city/facade_albedo.png")
const NORMAL_ATLAS := preload("res://assets/textures/city/facade_normal.png")
const ORM_ATLAS := preload("res://assets/textures/city/facade_orm.png")

## Which styles which house has ([enum CityPlan.Kind]): office — metal and
## stone, residential — three kinds of brick, tower — glass, brick — brick.
const STYLES_OF: Array[Array] = [
	[Style.OFFICE, Style.STONE],
	[Style.BRICK, Style.DOUBLE, Style.INSET],
	[Style.GLASS],
	[Style.BRICK, Style.INSET, Style.DOUBLE],
]

## Wall tone over the texture: red brick, pale, brown, sooty.
## Window glass is not tinted — the facade mask holds it.
const WALL_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.18, 1.08, 0.98),
	Color(0.72, 0.58, 0.5),
	Color(0.62, 0.62, 0.64),
]

## Tone of office stone and metal: sandstone, grey, dark.
const STONE_TINTS: Array[Color] = [
	Color(0.78, 0.74, 0.68),
	Color(0.66, 0.67, 0.69),
	Color(0.52, 0.5, 0.48),
]

## Facade atlas: size, pixels per metre, tile width, margin at the sides of a style
## column and rows, m
## (`assets/textures/city/facade_layout.json`).
const ATLAS_SIZE := Vector2(1920.0, 448.0)
const ATLAS_DENSITY: float = 64.0
const TILE_WIDTH: float = 4.0
const GUTTER: float = 0.5
const ROW_TOP: float = 1.0
const ROW_FLOOR: float = 3.0
const ROW_GROUND: float = 3.0


## House material: the pack's baked facade on a box (ADR-0051, decision 10).
static func building() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = BUILDING_SHADER
	look.set_shader_parameter("albedo_atlas", ALBEDO_ATLAS)
	look.set_shader_parameter("normal_atlas", NORMAL_ATLAS)
	look.set_shader_parameter("orm_atlas", ORM_ATLAS)
	look.set_shader_parameter("styles", float(Style.size()))
	look.set_shader_parameter("tile_width", TILE_WIDTH)
	look.set_shader_parameter("gutter", GUTTER)
	look.set_shader_parameter("top_height", ROW_TOP)
	look.set_shader_parameter("floor_height", ROW_FLOOR)
	look.set_shader_parameter("ground_height", ROW_GROUND)
	look.set_shader_parameter("density", ATLAS_DENSITY)
	look.set_shader_parameter("atlas_size", ATLAS_SIZE)
	look.set_shader_parameter("flash_colour", CityBackdrop.FLASH_GLASS)
	return look


## House facade style and its seed for the shader: in [code]INSTANCE_CUSTOM[/code].
static func building_custom(block: CityPlan.Block) -> Color:
	var styles: Array = STYLES_OF[block.kind]
	var style: int = styles[absi(hash([block.x, "style"])) % styles.size()]
	return Color(float(style), _unit(hash([block.x, "house"])), 0.0, 0.0)


## House wall tone: glass and metal have their own, almost white.
static func wall_tint(block: CityPlan.Block) -> Color:
	if block.kind == CityPlan.Kind.GLASS:
		return Color(0.95, 0.97, 1.0)
	if block.kind == CityPlan.Kind.OFFICE:
		# The pack's light stone burned out to white under full sun: it is darker.
		return STONE_TINTS[absi(hash([block.x, "tint"])) % STONE_TINTS.size()]
	return WALL_TINTS[absi(hash([block.x, "tint"])) % WALL_TINTS.size()]


## Lit window material: past the haze.
static func windows() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = LIT_SHADER
	look.set_shader_parameter("flash_colour", CityBackdrop.FLASH_GLASS)
	return look


## Neon sign material.
static func signs() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = SIGN_SHADER
	return look


## Sign draw for the shader.
static func sign_custom(block: CityPlan.Block) -> Color:
	return Color(_unit(hash([block.x, "sign"])), 0.0, 0.0, 0.0)


static func _unit(value: int) -> float:
	return float(absi(value) % 10007) / 10007.0
