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
