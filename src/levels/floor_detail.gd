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

## Карниз под потолком: высота и вынос от стены.
const CROWN := Vector2(0.12, 0.1)

const RUNNER_COLOR := Color(0.26, 0.08, 0.09)
const RUNNER_EDGE_COLOR := Color(0.62, 0.5, 0.26)
const SEAM_COLOR := Color(0.09, 0.09, 0.1)
const JOINT_COLOR := Color(0.07, 0.08, 0.09)

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _parts: Dictionary = {}


## Собирает детали всех этажей, кроме гаража.
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	_rules = rules
	_plan = plan
	for index in rules.floors - 1:
		_dress_floor(index)
	_commit("runner", GreyboxLook.surface(RUNNER_COLOR))
	_commit("edge", GreyboxLook.surface(RUNNER_EDGE_COLOR))
	_commit("seam", GreyboxLook.surface(SEAM_COLOR))
	_commit("joint", GreyboxLook.surface(JOINT_COLOR))
	_commit("crown", GreyboxLook.metal(GreyboxLook.TRIM.darkened(0.4)))


func _dress_floor(index: int) -> void:
	var surface := _rules.floor_surface(index)
	var bounds := _rules.floor_span(index)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	for span in BuildingPlan.spans_between(_plan.gaps_on(_rules, index), inner):
		var length := span.y - span.x
		if length <= 0.2:
			continue
		var middle := (span.x + span.y) * 0.5
		var top := surface - RUNNER.y * 0.5
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
	var joint_height := wall_height - JOINT_FROM - CROWN.x
	var wall_z := WorldSpace.BACK_WALL_Z + 0.004
	var joints := int((inner.y - inner.x) / JOINT_STEP)
	for joint in joints:
		var x := inner.x + JOINT_STEP * (float(joint) + 0.5)
		if _near_opening(index, x):
			continue
		_add(
			"joint",
			Vector3(JOINT_WIDTH, joint_height, 0.008),
			Vector3(x, story_top + CROWN.x + joint_height * 0.5, wall_z)
		)
	_add(
		"crown",
		Vector3(inner.y - inner.x, CROWN.x, CROWN.y),
		Vector3(
			(inner.x + inner.y) * 0.5,
			story_top + CROWN.x * 0.5,
			WorldSpace.BACK_WALL_Z + CROWN.y * 0.5
		)
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
	if index == _rules.floors - 1 and absf(_plan.exit_x - x) < BuildingShell.EXIT_WIDTH:
		return true
	return false


## Запоминает коробку: [param at] — x и y в плоскости правил, z сцены.
func _add(kind: String, size: Vector3, at: Vector3) -> void:
	if not _parts.has(kind):
		_parts[kind] = [] as Array[Transform3D]
	var place := WorldSpace.to_scene(Vector2(at.x, at.y))
	place.z = at.z
	(_parts[kind] as Array[Transform3D]).append(Transform3D(Basis.from_scale(size), place))


func _commit(kind: String, material: StandardMaterial3D) -> void:
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
	add_child(node)
