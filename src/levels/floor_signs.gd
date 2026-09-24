class_name FloorSigns
extends Node3D

## Номера этажей: табло с красными цифрами у правой стены каждого этажа.
##
## В оригинале она висит на каждом этаже, под самым потолком, вплотную к правой
## стене. Это не обстановка, а игровая сводка: сколько ещё спускаться и где
## лежит документ (ADR-0026, решение 9). Поэтому цифры светятся сами — тем же
## приёмом, что табло дверей (ADR-0023, решение 6), — и читаются на погашенном
## этаже.
##
## С M21b светится только цифра, а не вся табличка (замечание пользователя:
## красный светящийся щит «сильно выделяется» среди обоев и мебели). Табло как
## настоящее: стальная рамка, тёмное стекло, красные цифры с ореолом. Красный —
## от таблички оригинала.
##
## Нумерация как в оригинале: верхний этаж — самый большой номер, нижний — первый.
## На крыше таблички нет: там нет ни стены, ни потолка, и в оригинале её там нет.

## Кегль шрифта: чем он крупнее, тем чётче цифра. Высоту цифры в мире задаёт
## [constant Proportions.FLOOR_DIGIT], а не он.
const FONT_SIZE: int = 64

## Доля кегля, которую занимает у Exo 2 цифра по высоте: по ней кегль
## переводится в метры. Замер по глифам: от 0.69 («1», «4», «7») до 0.72
## («0», «3»); у Pixellari, на котором табличка жила до M22b, было 0.69.
const DIGIT_SHARE: float = 0.71

## На сколько табличка стоит перед задней стеной: перед пилястрами, чтобы
## не утонуть в них у края простенка.
const STANDOFF: float = 0.25

## Рамка табло: насколько шире стекла с каждой стороны и её цвет — тёмная сталь.
const BEZEL: float = 0.04
const BEZEL_COLOR := Color(0.34, 0.35, 0.38)
## Стекло: почти чёрное с красным отливом — цифре есть на чём гореть.
const GLASS := Color(0.06, 0.02, 0.02)
## Цифра — красный светодиод с ореолом того же тона.
const DIGIT := Color(1.0, 0.28, 0.2)

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
## глубине [param z] (по умолчанию — таблички), м.
##
## Нужна всему, что висит под потолком у задней стены: трубы обстановки на
## первых кадрах M19 целиком уходили под кромку (авторевью M19).
static func hidden_band(z: float = WorldSpace.BACK_WALL_Z + STANDOFF) -> float:
	var depth := WorldSpace.CORRIDOR_DEPTH * 0.5 - z
	return depth * tan(deg_to_rad(SideCamera.TILT_DEGREES))


func _hang_on(index: int) -> void:
	var plate := Proportions.FLOOR_SIGN
	var sign_node := Node3D.new()
	sign_node.name = "Floor%d" % number_of(_rules, index)
	sign_node.position = WorldSpace.to_scene(centre_on(_rules, index))
	sign_node.position.z = WorldSpace.BACK_WALL_Z + STANDOFF
	add_child(sign_node)

	# Первым — стекло, вторым — цифра: тест ищет её вторым ребёнком.
	var glass := GreyboxLook.box(Vector3(plate.x, plate.y, 0.03), GreyboxLook.polished(GLASS))
	sign_node.add_child(glass)

	var label := Label3D.new()
	label.text = str(number_of(_rules, index))
	label.font = NeonStyle.font(700)
	label.font_size = FONT_SIZE
	label.pixel_size = Proportions.FLOOR_DIGIT / (float(FONT_SIZE) * DIGIT_SHARE)
	label.modulate = DIGIT
	label.outline_modulate = Color(DIGIT, 0.35)
	label.outline_size = 10
	# Цифра — свет, а не краска: освещение сцены её не трогает.
	label.shaded = false
	label.position.z = 0.02
	sign_node.add_child(label)

	var bezel := GreyboxLook.box(
		Vector3(plate.x + BEZEL * 2.0, plate.y + BEZEL * 2.0, 0.02), GreyboxLook.metal(BEZEL_COLOR)
	)
	bezel.position.z = -0.015
	sign_node.add_child(bezel)
