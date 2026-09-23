class_name FloorSigns
extends Node3D

## Номера этажей: красная табличка с белыми цифрами у правой стены каждого этажа.
##
## В оригинале она висит на каждом этаже, под самым потолком, вплотную к правой
## стене. Это не обстановка, а игровая сводка: сколько ещё спускаться и где
## лежит документ (ADR-0026, решение 9). Поэтому табличка светится сама — тем же
## приёмом, что табло дверей (ADR-0023, решение 6), — и читается на погашенном
## этаже.
##
## Нумерация как в оригинале: верхний этаж — самый большой номер, нижний — первый.
## На крыше таблички нет: там нет ни стены, ни потолка, и в оригинале её там нет.

const FONT := preload("res://assets/fonts/Pixellari.ttf")

## Кегль шрифта: чем он крупнее, тем чётче цифра. Высоту цифры в мире задаёт
## [constant Proportions.FLOOR_DIGIT], а не он.
const FONT_SIZE: int = 64

## Доля кегля, которую занимает у Pixellari цифра по высоте: по ней кегль
## переводится в метры.
const DIGIT_SHARE: float = 0.7

## На сколько табличка стоит перед задней стеной: перед пилястрами, чтобы
## не утонуть в них у края простенка.
const STANDOFF: float = 0.25

var _rules: BuildingRules = null


## Вешает таблички на все этажи здания.
func hang(rules: BuildingRules) -> void:
	_rules = rules
	for index in rules.floors:
		_hang_on(index)


## Номер этажа так, как его видит игрок: верхний — [member BuildingRules.floors],
## нижний — первый.
static func number_of(rules: BuildingRules, index: int) -> int:
	return rules.floors - index


## Где висит середина таблички этажа, в координатах правил.
##
## Не вплотную к потолку, как в оригинале, а ниже на полосу, которую закрывает
## кромка перекрытия. Камера смотрит на [constant SideCamera.TILT_DEGREES]
## сверху, и передний край плиты загораживает у задней стены полосу под
## потолком — на первом кадре вехи табличка уходила под неё наполовину, и от
## цифр оставался низ.
static func centre_on(rules: BuildingRules, index: int) -> Vector2:
	var inner_right := rules.floor_span(index).y - BuildingShell.WALL_WIDTH
	var plate := Proportions.FLOOR_SIGN
	return Vector2(
		inner_right - Proportions.FLOOR_SIGN_GAP - plate.x * 0.5,
		rules.story_top(index) + hidden_band() + Proportions.FLOOR_SIGN_GAP + plate.y * 0.5
	)


## Полоса под потолком, которую кромка перекрытия закрывает от камеры на
## глубине таблички, м.
static func hidden_band() -> float:
	var depth := WorldSpace.CORRIDOR_DEPTH * 0.5 - (WorldSpace.BACK_WALL_Z + STANDOFF)
	return depth * tan(deg_to_rad(SideCamera.TILT_DEGREES))


func _hang_on(index: int) -> void:
	var plate := Proportions.FLOOR_SIGN
	var sign_node := Node3D.new()
	sign_node.name = "Floor%d" % number_of(_rules, index)
	sign_node.position = WorldSpace.to_scene(centre_on(_rules, index))
	sign_node.position.z = WorldSpace.BACK_WALL_Z + STANDOFF
	add_child(sign_node)

	var board := GreyboxLook.box(
		Vector3(plate.x, plate.y, 0.04), GreyboxLook.light(GreyboxLook.SIGN_RED)
	)
	sign_node.add_child(board)

	var label := Label3D.new()
	label.text = str(number_of(_rules, index))
	label.font = FONT
	label.font_size = FONT_SIZE
	label.pixel_size = Proportions.FLOOR_DIGIT / (float(FONT_SIZE) * DIGIT_SHARE)
	label.modulate = Color.WHITE
	label.outline_size = 0
	# Цифра — свет, а не краска: освещение сцены её не трогает, как и табличку.
	label.shaded = false
	label.position.z = 0.03
	sign_node.add_child(label)
