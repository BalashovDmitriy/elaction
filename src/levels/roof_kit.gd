class_name RoofKit
extends Node3D

## Техника крыши: бак или водонапорная башня, кондиционеры, тарелка,
## солнечные панели, выход на крышу, лестница и антенна с мигающим огнём
## (ADR-0031, решение 2; с M21b — модели паков, ADR-0033, решение 8).
##
## Всё без тел и без источников света: огонь антенны — эмиссия. Стоит у задней
## стены крыши и за ней, на своих ступенях кровли, и не встаёт перед шахтой:
## над ней машинное отделение, с которого начинается спуск. Неоновая вывеска
## с M21b живёт на углу фасада ([VerticalSign]): на крыше её закрывала техника.

## Техника стоит за задней стеной крыши, на ступенях кровли, м.
const DEPTH_Z: float = WorldSpace.BACK_WALL_Z - 1.8
## Ближе к краю кровли техника не встаёт, и между предметами зазор, м.
const EDGE_GAP: float = 0.3
const GAP: float = 0.35

## Лестница на машинное отделение.
const STEEL := Color(0.3, 0.31, 0.33)
const STEEL_LIGHT := Color(0.52, 0.53, 0.55)

## Огонь на макушке антенны: размер, период и доля, когда горит.
const BEACON: float = 0.16
const BEACON_PERIOD: float = 1.4
const BEACON_ON: float = 0.35
const BEACON_RED := Color(1.0, 0.12, 0.08)

## Что ставится вдоль длинной стороны кровли — по порядку от края, пока
## влезает, — и насколько каждый предмет выдвинут от [constant DEPTH_Z]:
## высокое — дальше, низкое — ближе, иначе башня закрыла бы кондиционеры.
const LONG_SIDE: Array[String] = [
	"water_tower", "satellite_dish", "air_conditioner", "air_conditioner", "solar_panel"
]
const FORWARD := {
	"water_tower": 0.0,
	"water_tank": 0.0,
	"satellite_dish": 0.9,
	"air_conditioner": 1.1,
	"solar_panel": 0.5,
	"roof_exit": 0.8,
	"antenna_small": 0.6,
}

var _beacon: MeshInstance3D = null
var _clock: float = 0.0


## Ставит технику по правилам и плану. [param building_seed] решает, бак или
## водонапорная башня: крыши зданий не повторяют друг друга.
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int = 1) -> void:
	var shaft := plan.roof_shaft()
	if shaft == null:
		return
	var steps := BuildingRoof.steps(rules, plan)
	var surface := rules.floor_surface(BuildingRules.ROOF)
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
	var left := Vector2(bounds.x + BuildingShell.WALL_WIDTH, shaft.x - half_room)
	var right := Vector2(shaft.x + half_room, bounds.y - BuildingShell.WALL_WIDTH)
	var on_the_left := left.y - left.x >= right.y - right.x
	var long := left if on_the_left else right
	var short := right if on_the_left else left

	var line := LONG_SIDE.duplicate()
	if building_seed % 2 == 0:
		line[0] = "water_tank"
	# От парапета внутрь: у края — самое высокое, к отделению — низкое.
	var cursor := long.x + EDGE_GAP if on_the_left else long.y - EDGE_GAP
	var inward := 1.0 if on_the_left else -1.0
	var limit := long.y - GAP if on_the_left else long.x + GAP
	for prop_name: String in line:
		var width := PropCatalog.footprint(prop_name).x
		var far_edge := cursor + inward * width
		if (far_edge - limit) * inward > 0.0:
			break
		_place(prop_name, cursor + inward * width * 0.5, steps, surface)
		cursor = far_edge + inward * GAP

	var room := short.y - short.x - EDGE_GAP * 2.0
	for prop_name: String in ["roof_exit", "antenna_small"]:
		if PropCatalog.footprint(prop_name).x <= room:
			_place(prop_name, (short.x + short.y) * 0.5, steps, surface)
			break
	_ladder(shaft.x - half_room - 0.2, surface)
	_antenna(shaft.x, surface - BuildingShafts.MACHINE_ROOM_SIZE.y)


## Мигает огнём антенны. Картинка, а не правило: по настенным часам.
func _process(delta: float) -> void:
	if _beacon == null:
		return
	_clock = fmod(_clock + delta, BEACON_PERIOD)
	_beacon.visible = _clock < BEACON_PERIOD * BEACON_ON


## Верх кровли в точке [param x]: верх самой высокой ступени над ней или настил.
static func _top_at(steps: Array[Rect2], surface: float, x: float) -> float:
	var top := surface
	for rect in steps:
		if x >= rect.position.x and x <= rect.end.x:
			top = minf(top, rect.position.y)
	return top


## Модель каталога на кровле: низом на ступень под серединой.
func _place(prop_name: String, x: float, steps: Array[Rect2], surface: float) -> void:
	var item := PropCatalog.make(prop_name)
	if item == null:
		return
	item.position = WorldSpace.to_scene(Vector2(x, _top_at(steps, surface, x)))
	item.position.z = DEPTH_Z + float(FORWARD.get(prop_name, 0.5))
	add_child(item)


func _box(size: Vector3, at: Vector2, z: float, material: StandardMaterial3D) -> MeshInstance3D:
	var part := GreyboxLook.box(size, material)
	part.position = WorldSpace.to_scene(at)
	part.position.z = z
	add_child(part)
	return part


## Лестница на машинное отделение: две тетивы и перекладины.
func _ladder(x: float, surface: float) -> void:
	var steel := GreyboxLook.metal(STEEL_LIGHT)
	var height := BuildingShafts.MACHINE_ROOM_SIZE.y + 0.4
	var z := WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH * 0.5
	for dx: float in [-0.18, 0.18]:
		_box(Vector3(0.04, height, 0.04), Vector2(x + dx, surface - height * 0.5), z, steel)
	var rungs := int(height / 0.3)
	for rung in rungs:
		_box(Vector3(0.36, 0.03, 0.03), Vector2(x, surface - 0.25 - float(rung) * 0.3), z, steel)


## Антенна на машинном отделении с мигающим огнём на макушке.
func _antenna(x: float, base: float) -> void:
	var z := WorldSpace.BACK_WALL_Z - 0.2
	var mast := PropCatalog.make("roof_antenna")
	var height := 0.0
	if mast != null:
		mast.position = WorldSpace.to_scene(Vector2(x, base))
		mast.position.z = z - PropCatalog.footprint("roof_antenna").z * 0.5
		add_child(mast)
		height = PropCatalog.footprint("roof_antenna").y
	_beacon = _box(
		Vector3(BEACON, BEACON, BEACON),
		Vector2(x, base - height - BEACON * 0.5),
		z,
		GreyboxLook.light(BEACON_RED)
	)
