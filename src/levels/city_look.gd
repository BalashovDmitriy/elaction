class_name CityLook
extends RefCounted

## Вид города вблизи (M24a, замечание пользователя — «детализацию фона
## поднять»): фасады с поясами и простенками, окна с рамой и жизнью за
## стеклом, вывески с буквами (ADR-0037, решение 4).
##
## Всё шейдерами на тех же мультимешах, что и в M19: узлов и источников
## света не прибавилось, и бюджет кадра город не трогает. Что за каким окном,
## решает хеш окна и дома — город по сиду повторяется до окна.

## Что за стеклом горящего окна: так же и в [code]city_window.gdshaderinc[/code].
enum Inside { PLAIN, BLINDS, CURTAINS, PERSON, TV, FLICKER }

## Стили запечённого фасада — столбцы атласа в порядке `tools/build_city.py`.
enum Style { BRICK, DOUBLE, INSET, GLASS, OFFICE, STONE }

const FACADE_SHADER := preload("res://src/levels/city_facade.gdshader")
const LIT_SHADER := preload("res://src/levels/city_window_lit.gdshader")
const DARK_SHADER := preload("res://src/levels/city_window_dark.gdshader")
const SIGN_SHADER := preload("res://src/levels/city_sign.gdshader")

## Что за стеклом по типу дома ([enum CityPlan.Kind]), веса [enum Inside]: у
## контор жалюзи и лампы дневного света, у жилых — шторы, телевизоры и люди.
const INSIDE_WEIGHTS: Array[Array] = [
	[0.3, 0.4, 0.0, 0.1, 0.0, 0.2],
	[0.2, 0.1, 0.35, 0.15, 0.2, 0.0],
	[0.55, 0.25, 0.0, 0.1, 0.0, 0.1],
	[0.2, 0.1, 0.35, 0.15, 0.2, 0.0],
]

## Тон фасада по типу дома. Все — ночь: фасад виден дымкой, поясами и окнами,
## а не цветом, но кирпич теплее бетона, а стекло холоднее.
const FACADE_TONES: Array[Color] = [
	Color(0.04, 0.042, 0.052),
	Color(0.05, 0.045, 0.048),
	Color(0.025, 0.04, 0.07),
	Color(0.06, 0.036, 0.03),
]

## Окно по типу дома, м: у контор широкие, у стеклянных башен — почти во весь
## шаг сетки ([constant CityPlan.WINDOW_STEP]), у жилых и кирпичных — узкие
## и высокие.
const WINDOW_SIZES: Array[Vector2] = [
	Vector2(1.7, 1.6), Vector2(1.1, 1.5), Vector2(2.1, 2.3), Vector2(1.0, 1.7)
]

## Зарево улиц на фасадах снизу — тон [constant CityDetails.GLOW_COLOUR].
const STREET_GLOW := Color(1.0, 0.55, 0.25)

const BUILDING_SHADER := preload("res://src/levels/city_building.gdshader")
const ALBEDO_ATLAS := preload("res://assets/textures/city/facade_albedo.png")
const NORMAL_ATLAS := preload("res://assets/textures/city/facade_normal.png")
const ORM_ATLAS := preload("res://assets/textures/city/facade_orm.png")

## Какие стили у какого дома ([enum CityPlan.Kind]): контора — металл и
## камень, жилой — кирпич трёх видов, башня — стекло, кирпичный — кирпич.
const STYLES_OF: Array[Array] = [
	[Style.OFFICE, Style.STONE],
	[Style.BRICK, Style.DOUBLE, Style.INSET],
	[Style.GLASS],
	[Style.BRICK, Style.INSET, Style.DOUBLE],
]

## Тон стен поверх фактуры: красный кирпич, бледный, бурый, закопчённый.
## Стекло окон тоном не красится — его держит маска фасада.
const WALL_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.18, 1.08, 0.98),
	Color(0.72, 0.58, 0.5),
	Color(0.62, 0.62, 0.64),
]

## Тон камня и металла контор: песчаник, серый, тёмный.
const STONE_TINTS: Array[Color] = [
	Color(0.78, 0.74, 0.68),
	Color(0.66, 0.67, 0.69),
	Color(0.52, 0.5, 0.48),
]

## Атлас фасадов: размер, пикселей на метр, ширина плитки и ряды, м
## (`assets/textures/city/facade_layout.json`).
const ATLAS_SIZE := Vector2(1536.0, 448.0)
const ATLAS_DENSITY: float = 64.0
const TILE_WIDTH: float = 4.0
const ROW_TOP: float = 1.0
const ROW_FLOOR: float = 3.0
const ROW_GROUND: float = 3.0


## Материал домов: запечённый фасад пака на коробке (ADR-0051, решение 10).
static func building() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = BUILDING_SHADER
	look.set_shader_parameter("albedo_atlas", ALBEDO_ATLAS)
	look.set_shader_parameter("normal_atlas", NORMAL_ATLAS)
	look.set_shader_parameter("orm_atlas", ORM_ATLAS)
	look.set_shader_parameter("styles", float(Style.size()))
	look.set_shader_parameter("tile_width", TILE_WIDTH)
	look.set_shader_parameter("top_height", ROW_TOP)
	look.set_shader_parameter("floor_height", ROW_FLOOR)
	look.set_shader_parameter("ground_height", ROW_GROUND)
	look.set_shader_parameter("density", ATLAS_DENSITY)
	look.set_shader_parameter("atlas_size", ATLAS_SIZE)
	look.set_shader_parameter("flash_colour", CityBackdrop.FLASH_GLASS)
	return look


## Стиль фасада дома и его сид для шейдера: в [code]INSTANCE_CUSTOM[/code].
static func building_custom(block: CityPlan.Block) -> Color:
	var styles: Array = STYLES_OF[block.kind]
	var style: int = styles[absi(hash([block.x, "style"])) % styles.size()]
	return Color(float(style), _unit(hash([block.x, "house"])), 0.0, 0.0)


## Тон стен дома: у стекла и металла — свой, почти белый.
static func wall_tint(block: CityPlan.Block) -> Color:
	if block.kind == CityPlan.Kind.GLASS:
		return Color(0.95, 0.97, 1.0)
	if block.kind == CityPlan.Kind.OFFICE:
		# Светлый камень пака под полным солнцем выгорал в белое: он темнее.
		return STONE_TINTS[absi(hash([block.x, "tint"])) % STONE_TINTS.size()]
	return WALL_TINTS[absi(hash([block.x, "tint"])) % WALL_TINTS.size()]


## Материал фасадов: пояса, простенки, карниз, зарево снизу.
static func facade() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = FACADE_SHADER
	look.set_shader_parameter("window_step", CityPlan.WINDOW_STEP)
	var heights := Vector4.ZERO
	for kind: int in WINDOW_SIZES.size():
		heights[kind] = WINDOW_SIZES[kind].y
	look.set_shader_parameter("window_heights", heights)
	look.set_shader_parameter("street_glow", STREET_GLOW)
	return look


## Материал окон: горящих — мимо дымки, погасших — в ней.
static func windows(lit: bool) -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = LIT_SHADER if lit else DARK_SHADER
	look.set_shader_parameter("flash_colour", CityBackdrop.FLASH_GLASS)
	return look


## Материал неоновых вывесок.
static func signs() -> ShaderMaterial:
	var look := ShaderMaterial.new()
	look.shader = SIGN_SHADER
	return look


## Во сколько раз окно дома [param block] больше квада окон
## ([constant CityBackdrop.WINDOW_SIZE]).
static func window_scale(block: CityPlan.Block) -> Vector3:
	var size := WINDOW_SIZES[block.kind]
	return Vector3(size.x / CityBackdrop.WINDOW_SIZE.x, size.y / CityBackdrop.WINDOW_SIZE.y, 1.0)


## Тон фасада дома [param block].
static func facade_tone(block: CityPlan.Block) -> Color:
	return FACADE_TONES[block.kind]


## Тип дома для шейдера фасада: в [code]INSTANCE_CUSTOM.x[/code].
static func facade_custom(block: CityPlan.Block) -> Color:
	return Color(float(block.kind), 0.0, 0.0, 0.0)


## Данные окна для шейдера: жребий, что за стеклом, переплёт, горит ли.
static func window_custom(block: CityPlan.Block, cell: Vector2i, lit: bool) -> Color:
	var roll := _unit(hash([block.x, cell, "window"]))
	var inside := 0
	if lit:
		inside = CityPlan.pick_weighted(
			INSIDE_WEIGHTS[block.kind], _unit(hash([block.x, cell, "inside"]))
		)
	return Color(roll, float(inside), float(block.mullions), 1.0 if lit else 0.0)


## Жребий вывески для шейдера.
static func sign_custom(block: CityPlan.Block) -> Color:
	return Color(_unit(hash([block.x, "sign"])), 0.0, 0.0, 0.0)


static func _unit(value: int) -> float:
	return float(absi(value) % 10007) / 10007.0
