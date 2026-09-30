class_name VisibleFloors
extends RefCounted

## Какие этажи попадают в кадр.
##
## В здании 30 этажей и по источнику света на каждом, а в кадр влезает два
## с половиной. Гореть должны только видимые — ADR-0010, пункт 8.
##
## Считается по номерам этажей, а не по прямоугольнику камеры: высота этажа
## известна, номер — это деление. Поэтому проверяется без сцены и без кадра,
## тем же приёмом, что [OttoStateMachine] и [ElevatorMotion].

## Сколько этажей зажигается сверх видимых, с каждой стороны.
##
## Без запаса источник включался бы ровно на кромке кадра, и въезжающий снизу
## этаж был бы виден тёмным ровно один миг — это заметно и читается как мигание.
const MARGIN: int = 1
## Насколько за край кадра по X свет ещё нужен, м: дальность заливки лампы.
const BAND_REACH: float = Lamp.FILL_RANGE
## Насколько за край кадра лампе ещё нужна тень, м: конус бьёт вниз, и его
## пятно на полу — пара метров; тень лампы из-за края в кадр почти не ложится,
## а стоит каждая как отрисовка сцены заново.
const SHADOW_REACH: float = 2.5
## Шаг, по которому округляются края полосы, м.
const BAND_STEP: float = 1.8


## Первый и последний этаж, которым положено гореть, включительно.
##
## [param view] — видимый кусок мира, его отдаёт [method Otto.camera_view].
static func around(rules: BuildingRules, view: Rect2) -> Vector2i:
	var first := rules.floor_index_near(view.position.y) - MARGIN
	var last := rules.floor_index_near(view.end.y) + MARGIN
	# Снизу полоса упирается в крышу, а не в нулевой этаж: крыша — такой же
	# уровень со своим светом, просто лежит выше здания (ADR-0014, пункт 1).
	return Vector2i(maxi(first, BuildingRules.ROOF), mini(last, rules.floors - 1))


## Этажи, которые видны в кадре хотя бы краем, — без запаса. Им свет с тенью;
## запасным из [method around] — только конус до своего пола (ADR-0042,
## решение 2).
static func seen(rules: BuildingRules, view: Rect2) -> Vector2i:
	return Vector2i(
		maxi(_story_of(rules, view.position.y), BuildingRules.ROOF),
		mini(_story_of(rules, view.end.y), rules.floors - 1)
	)


## Этаж, в высоту которого попадает [param y]: от пола этажа выше до своего пола.
static func _story_of(rules: BuildingRules, y: float) -> int:
	var raw := ceilf((y - rules.sky_height) / rules.floor_height) - 1.0
	return clampi(int(raw), BuildingRules.ROOF, rules.floors - 1)


## Попадает ли этаж в кадр. Тот же счёт, что у [method around], только ответ
## про один этаж: уровню удобнее спрашивать так, когда он обходит все подряд.
static func covers(span: Vector2i, index: int) -> bool:
	return index >= span.x and index <= span.y


## Полоса кадра по X, в которой свету есть смысл гореть: кадр [param view] и
## по [constant BAND_REACH] с боков — дальше лампа до кадра не достаёт.
##
## С M24h (ADR-0044, решение 11): замер по этажам показал, что внизу здания
## кадр вдвое дороже — стилобат в полтора кадра шириной, и лампы этажа за
## краем кадра горели и клали тени: 24 источника с тенью против 8 наверху.
## Края полосы — по шагу [constant BAND_STEP]: кадр сдвинулся на сантиметр —
## пересчитывать свет всего здания незачем.
static func band(view: Rect2, reach: float = BAND_REACH) -> Vector2:
	return Vector2(
		floorf((view.position.x - reach) / BAND_STEP) * BAND_STEP,
		ceilf((view.end.x + reach) / BAND_STEP) * BAND_STEP
	)


## Стоит ли точка [param x] в полосе [param strip] ([method band]).
static func in_band(strip: Vector2, x: float) -> bool:
	return x >= strip.x and x <= strip.y
