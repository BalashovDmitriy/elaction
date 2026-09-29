class_name CarCut
extends RefCounted

## Срез тела днищем кабины (ADR-0043, решения 7–9).
##
## Кабина, опускаясь, режет фигуру по своим стенкам: всё, что между ними и
## выше днища, пропадает, и срез идёт вниз вместе с кабиной. Режет шейдер
## ([method FigureRig.carve]), а не геометрия: фигура из пака скиннута, и
## резать её меш на ходу — пересчитывать вершины каждый кадр. Срез держит
## самую низкую высоту днища: ушедшая вверх кабина отрезанного не возвращает.
##
## Пока срез проходит по телу, из него брызжет кровь; дойдя до пола, кабина
## оставляет под собой пятно. Физику тела — что от него осталось — решает сам
## [Corpse] по [method remains_of].

## Через сколько метров хода днища по телу брызги повторяются.
const SPRAY_STEP: float = 0.08
## Остаток тела короче этого, м, — уже не тело: пропадает целиком.
const SCRAP: float = 0.08

var left: float = 0.0
var right: float = 0.0
## Высота днища, до которой срез дошёл, м сцены.
var top: float = INF
## Габарит тела в мире на миг первого касания.
var body := AABB()
## Кабина дошла до пола под телом: срез окончен, пятно лежит.
var done: bool = false

var _sprayed_at: float = INF


## Ведёт срез [param figure] кабиной со стенками [param from_x]..[param to_x] и
## днищем на высоте [param bottom]. Первый вызов снимает габарит тела. Брызги и
## пятно кладёт в [param host]. Возвращает true, если срез опустился.
func advance(figure: FigureRig, host: Node, from_x: float, to_x: float, bottom: float) -> bool:
	if top == INF:
		left = from_x
		right = to_x
		body = figure.global_transform * figure.skinned_aabb()
	if bottom >= top:
		return false
	top = bottom
	figure.carve_under(left, right, top)
	var low := maxf(body.position.x, left)
	var high := minf(body.end.x, right)
	if high <= low:
		done = true
		return true
	if top < body.end.y and _sprayed_at - top >= SPRAY_STEP:
		_sprayed_at = top
		_spray(host, low, high)
	if not done and top <= body.position.y + SPRAY_STEP:
		done = true
		Blood.puddle(
			host, Vector3((low + high) * 0.5, body.position.y, body.get_center().z), high - low
		)
	return true


## Что останется от тела на отрезке [param part] по X под кабиной со стенками
## [param from_x]..[param to_x]: больший из кусков по обе стороны от неё, или
## пустой, если остатка нет.
static func remains_of(part: Vector2, from_x: float, to_x: float) -> Vector2:
	var before := Vector2(part.x, minf(part.y, from_x))
	var after := Vector2(maxf(part.x, to_x), part.y)
	var best := before if before.y - before.x >= after.y - after.x else after
	if best.y - best.x < SCRAP:
		return Vector2.ZERO
	return best


## Брызги из среза: у стенки, за которой тело продолжается, — наружу, из-под
## днища — в обе стороны.
func _spray(host: Node, low: float, high: float) -> void:
	var z := body.get_center().z
	var at := clampf(top, body.position.y, body.end.y)
	if body.position.x < left:
		Blood.spray(host, Vector3(left, at, z), -1.0)
	if body.end.x > right:
		Blood.spray(host, Vector3(right, at, z), 1.0)
	if body.position.x >= left and body.end.x <= right:
		var middle := (low + high) * 0.5
		Blood.spray(host, Vector3(middle, at, z), -1.0)
		Blood.spray(host, Vector3(middle, at, z), 1.0)
