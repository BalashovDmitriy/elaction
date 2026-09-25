class_name ShaftHums
extends Node3D

## Гул шахт (ADR-0036): у каждой шахты свой источник, и он ходит по ней вровень
## с Otto, в пределах её этажей, — шахта гудит вся, а не одной точкой на
## середине высоты.

## Докуда слышно гул шахты, м, и где он стоит в глубине: за кабиной.
const REACH: float = 9.0
const Z: float = -0.4

var _holders: Array[Node3D] = []
## Полоса высот каждой шахты, м плоскости: верх и низ.
var _spans: Array[Vector2] = []


## Заводит гул шахты [param shaft] от [param top] до [param bottom], м.
func add(shaft: BuildingPlan.ShaftSpot, top: float, bottom: float) -> void:
	var holder := Node3D.new()
	holder.name = "ShaftHum"
	holder.position = WorldSpace.to_scene(Vector2(shaft.x, top))
	holder.position.z = Z
	add_child(holder)
	Sounds.source(holder, Sounds.SHAFT_HUM, REACH, true)
	_holders.append(holder)
	_spans.append(Vector2(minf(top, bottom), maxf(top, bottom)))


## Ставит источники на высоту [param height], м плоскости.
func follow(height: float) -> void:
	for index: int in _holders.size():
		var span := _spans[index]
		var holder := _holders[index]
		var at := WorldSpace.to_plane(holder.position)
		holder.position = WorldSpace.to_scene(Vector2(at.x, clampf(height, span.x, span.y)))
		holder.position.z = Z


## Высота источника шахты номер [param index], м плоскости. Нужна тестам.
func height_of(index: int) -> float:
	return WorldSpace.to_plane(_holders[index].position).y
