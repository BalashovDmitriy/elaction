class_name Shelter
extends RefCounted

## Тело под осадками (ADR-0054, решение 5): капля и хлопок гаснут о голову,
## плечи, кузов и фюзеляж, а не пролетают сквозь Otto, агента, машину или
## вертолёт. Крыша ловит их картой высот ([RoofCatch]), но карта неподвижна:
## тот, кто ходит и ездит, в ней не числится, — и до M24l дождь шёл сквозь
## людей.
##
## Ловец — коробка столкновений частиц, дочерняя телу: едет с ним. Невидим и
## физики не трогает — только частицы.

## Насколько ловец шире тела: плечи и шляпа выходят за коробку столкновений.
const SPREAD: float = 1.4


## Ловец на теле [param body] размером [param size] с низом на его ступнях.
static func over(body: Node3D, size: Vector3) -> GPUParticlesCollisionBox3D:
	var shield := GPUParticlesCollisionBox3D.new()
	shield.name = "Shelter"
	shield.size = Vector3(size.x * SPREAD, size.y, size.z * SPREAD)
	shield.position = Vector3(0.0, size.y * 0.5, 0.0)
	body.add_child(shield)
	return shield


## Ловец по габариту видимого под [param body] — для машины и вертолёта, у
## которых нет одной коробки тела. Габарит — в осях [param body]; считается
## по цепочке узлов, а не по мировым осям: машину собирают до дерева. То, что
## под узлами [param skip], не в счёт: диск винта и трос дали бы сухую коробку
## во весь винт. Пустые места в [param skip] пропускаются: винта у модели может
## и не быть.
static func over_meshes(body: Node3D, skip: Array[Node] = []) -> GPUParticlesCollisionBox3D:
	var reach := AABB()
	var first := true
	var parts := skip.filter(func(part: Node) -> bool: return part != null)
	# Только геометрия: у источника света габарит — его дальность, и прожектор
	# вертолёта раздувал ловец до шестнадцати метров.
	for node: Node in body.find_children("*", "GeometryInstance3D", true, false):
		var shape := node as GeometryInstance3D
		if shape is GPUParticles3D or shape.get_aabb().size == Vector3.ZERO:
			continue
		if parts.any(func(part: Node) -> bool: return part == shape or part.is_ancestor_of(shape)):
			continue
		var box := relative(body, shape) * shape.get_aabb()
		reach = box if first else reach.merge(box)
		first = false
	var shield := GPUParticlesCollisionBox3D.new()
	shield.name = "Shelter"
	shield.size = reach.size
	shield.position = reach.get_center()
	body.add_child(shield)
	return shield


## Положение [param node] в осях его предка [param body] — по цепочке узлов,
## и до дерева тоже. Им же меряет рост прохожего [Passerby].
static func relative(body: Node3D, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != body:
		var spatial := at as Node3D
		if spatial != null:
			chain = spatial.transform * chain
		at = at.get_parent()
	return chain
