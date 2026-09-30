class_name FloorDetail
extends Node3D

## Мелкие детали этажей: ковровая дорожка вдоль коридора, швы плитки, стыки
## стеновых панелей и карниз под потолком (ADR-0031, решение 3).
##
## Потолок не детализируется: камера смотрит сверху (ADR-0023, решение 1), и
## его нижней стороны не видно. Детали — там, где их видно: пол и задняя стена.
## Всё мультимешами по одному на материал: деталей тысячи, а узлов — единицы.
## Без тел. Этаж выхода — гараж, у него своя разметка ([BuildingProps]).

## Дорожка: ширина поперёк коридора, толщина, где её середина по глубине.
const RUNNER := Vector2(1.0, 0.012)
const RUNNER_Z: float = -0.15
## Кайма дорожки — светлая полоса по краям.
const RUNNER_EDGE: float = 0.05

## Швы плитки: шаг вдоль коридора и толщина.
const SEAM_STEP: float = 0.9
const SEAM: float = 0.012

## Стыки панелей задней стены: шаг, ширина и докуда от пола (над плинтусом).
const JOINT_STEP: float = 0.9
const JOINT_WIDTH: float = 0.02
const JOINT_FROM: float = BuildingRibs.SKIRTING_HEIGHT + BuildingRibs.RAIL_HEIGHT

const RUNNER_COLOR := Color(0.26, 0.08, 0.09)
const RUNNER_EDGE_COLOR := Color(0.62, 0.5, 0.26)
const SEAM_COLOR := Color(0.09, 0.09, 0.1)
const JOINT_COLOR := Color(0.07, 0.08, 0.09)

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _parts: Dictionary = {}
## Вид по типу здания (ADR-0048): дорожка у отеля, плитка у офиса, карниз.
var _style := BuildingStyle.new()


## Собирает детали всех этажей, кроме гаража. [param style] — вид по типу
## здания; без него — отель, как до M24i.
func build(rules: BuildingRules, plan: BuildingPlan, style: BuildingStyle = null) -> void:
	_rules = rules
	_plan = plan
	if style != null:
		_style = style
	for index in rules.floors - 1:
		_dress_floor(index)
	# Дорожка — в тон кладки раунда: ещё одна метка, какой идёт раунд (ADR-0031).
	_commit(
		"runner", GreyboxLook.surface(RUNNER_COLOR.lerp(rules.palette.masonry.darkened(0.55), 0.6))
	)
	_commit("edge", GreyboxLook.surface(RUNNER_EDGE_COLOR))
	_commit("carpet", GreyboxLook.surface(_style.tile_color))
	_commit("tile_seam", GreyboxLook.surface(_style.tile_color.darkened(0.35)))
	_commit("seam", GreyboxLook.surface(SEAM_COLOR))
	_commit("joint", GreyboxLook.surface(JOINT_COLOR))
	_commit("crown", GreyboxLook.metal(_style.crown_color), true)


func _dress_floor(index: int) -> void:
	var surface := _rules.floor_surface(index)
	var bounds := _rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	# Над проёмом эскалатора дорожки и швов нет: они легли бы поперёк дыры в
	# задней полосе коридора (ADR-0044, решение 10).
	var cuts := _plan.gaps_on(_rules, index) + _plan.escalator_holes_on(_rules, index)
	for span in BuildingPlan.spans_between(cuts, inner):
		var length := span.y - span.x
		if length <= 0.2:
			continue
		var middle := (span.x + span.y) * 0.5
		var top := surface - RUNNER.y * 0.5
		if not _style.runner:
			_carpet_tiles(span, surface)
			continue
		_add("runner", Vector3(length, RUNNER.y, RUNNER.x), Vector3(middle, top, RUNNER_Z))
		for side: float in [-1.0, 1.0]:
			var edge_z := RUNNER_Z + side * (RUNNER.x * 0.5 - RUNNER_EDGE * 0.5)
			_add(
				"edge", Vector3(length, RUNNER.y + 0.002, RUNNER_EDGE), Vector3(middle, top, edge_z)
			)
		var seams := int(length / SEAM_STEP)
		for seam in seams:
			var x := span.x + SEAM_STEP * (float(seam) + 0.5)
			_add(
				"seam",
				Vector3(SEAM, 0.004, WorldSpace.CORRIDOR_DEPTH),
				Vector3(x, surface - 0.002, 0.0)
			)
	var story_top := _rules.story_top(index)
	var wall_height := surface - story_top
	var joint_height := wall_height - JOINT_FROM - _style.crown.x
	var wall_z := WorldSpace.BACK_WALL_Z + 0.004
	var joints := int((inner.y - inner.x) / JOINT_STEP)
	for joint in joints:
		var x := inner.x + JOINT_STEP * (float(joint) + 0.5)
		if _near_opening(index, x):
			continue
		_add(
			"joint",
			Vector3(JOINT_WIDTH, joint_height, 0.008),
			Vector3(x, story_top + _style.crown.x + joint_height * 0.5, wall_z)
		)
	var crown := _style.crown
	_add(
		"crown",
		Vector3(inner.y - inner.x, crown.x, crown.y),
		Vector3(
			(inner.x + inner.y) * 0.5,
			story_top + crown.x * 0.5,
			WorldSpace.BACK_WALL_Z + crown.y * 0.5
		)
	)


## Ковровая плитка офиса во весь пол коридора с сеткой швов (ADR-0048).
func _carpet_tiles(span: Vector2, surface: float) -> void:
	var length := span.y - span.x
	var middle := (span.x + span.y) * 0.5
	var depth := WorldSpace.CORRIDOR_DEPTH
	_add("carpet", Vector3(length, RUNNER.y, depth), Vector3(middle, surface - RUNNER.y * 0.5, 0.0))
	var step := _style.tile_step
	for across in int(length / step):
		var x := span.x + step * (float(across) + 1.0)
		_add("tile_seam", Vector3(SEAM, 0.004, depth), Vector3(x, surface - RUNNER.y - 0.001, 0.0))
	for row in int(depth / step):
		var z := -depth * 0.5 + step * (float(row) + 1.0)
		_add(
			"tile_seam",
			Vector3(length, 0.004, SEAM),
			Vector3(middle, surface - RUNNER.y - 0.001, z)
		)


## Стоит ли точка стены в проёме двери или в портале шахты: стыку там не место.
func _near_opening(index: int, x: float) -> bool:
	var half_door := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	for door in _plan.doors:
		if door.floor_index == index and absf(door.x - x) < half_door:
			return true
	var half_shaft := _rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in _plan.shafts:
		if shaft.top <= index and index <= shaft.bottom and absf(shaft.x - x) < half_shaft:
			return true
	return false


## Запоминает коробку: [param at] — x и y в плоскости правил, z сцены.
func _add(kind: String, size: Vector3, at: Vector3) -> void:
	if not _parts.has(kind):
		_parts[kind] = [] as Array[Transform3D]
	var place := WorldSpace.to_scene(Vector2(at.x, at.y))
	place.z = at.z
	(_parts[kind] as Array[Transform3D]).append(Transform3D(Basis.from_scale(size), place))


## Кладёт накопленные коробки [param kind] одним мультимешем. Тень кладёт только
## карниз ([param casts_shadow]): мультимеш — на всё здание, его не отсечь по
## кадру, и тысячи швов и стыков рисовались бы в каждом проходе теней каждой
## лампы, хотя плоской детали отбрасывать нечего.
func _commit(kind: String, material: StandardMaterial3D, casts_shadow: bool = false) -> void:
	if not _parts.has(kind):
		return
	var places: Array[Transform3D] = _parts[kind]
	var box := BoxMesh.new()
	box.material = material
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = box
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = kind.capitalize()
	node.multimesh = many
	if not casts_shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
