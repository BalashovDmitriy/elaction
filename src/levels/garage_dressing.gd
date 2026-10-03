class_name GarageDressing
extends Node3D

## Паркинг по типу здания (ADR-0058, решения 5 и 6).
##
## Отель — чисто, на колоннах таблички VALET, над проездом у ворот вывеска
## VALET PARKING; офис — на колоннах таблички «Reserved» и шлагбаум на
## площадке за воротами, который поднимается перед машиной Otto; жилой дом —
## граффити у пола дальней стены, мусорный бак и велосипеды на свободных
## местах.
##
## Дальняя стена из кадра видна только у пола — верх закрывает кромка
## перекрытия, — поэтому таблички висят на колоннах передней линии.
##
## Только вид, без тел: машина Otto стоит у ворот и выезжает тем же путём, что
## и раньше. Шлагбаум поднимается вместе с воротами ([method Garage.open_gate]) —
## ход и время выезда не меняются.

## Табличка на колонне: на какой высоте над полом и размер, м — между
## полосами краски и кодом места ([method Garage._build_columns]).
const PLATE_RISE: float = 1.18
const PLATE := Vector2(0.46, 0.2)
const PLATE_BLUE := Color(0.1, 0.22, 0.48)
const PLATE_BURGUNDY := Color(0.36, 0.08, 0.1)
const PAINT_WHITE := Color(0.82, 0.82, 0.78)

## Шлагбаум: стойка, стрела и где он стоит — на площадке за воротами, м.
const POST := Vector3(0.24, 1.0, 0.24)
const ARM_LENGTH: float = 2.6
const ARM := Vector2(0.08, 0.1)
const BARRIER_OFF_GATE: float = 1.1
const STRIPE_RED := Color(0.62, 0.1, 0.08)
const STRIPE_WHITE := Color(0.86, 0.86, 0.82)
const BOOTH := Color(0.55, 0.57, 0.6)

## Граффити жилого дома: сколько меток на дальней стене и их размер, м.
const TAGS: int = 4
const TAG_SIZE := Vector2(1.3, 0.7)
const DUMPSTER := Vector3(1.6, 1.2, 1.0)
const DUMPSTER_GREEN := Color(0.16, 0.3, 0.2)

var _rules: BuildingRules = null
var _surface: float = 0.0
var _far: float = 0.0
## Стрела шлагбаума: её поворачивает [method raise_barrier]; null — шлагбаума нет.
var _arm: Node3D = null


## Одевает паркинг здания по типу из [member BuildingRules.kind].
func build(rules: BuildingRules, plan: BuildingPlan, building_seed: int) -> void:
	name = "Dressing"
	_rules = rules
	_surface = rules.floor_surface(rules.floors - 1)
	_far = Garage.FAR_Z + Garage.FAR_THICKNESS * 0.5
	var bays := Garage.bays(rules, plan)
	var columns := Garage.column_xs(rules, plan)
	match rules.kind:
		BuildingIdentity.Kind.OFFICE:
			_plates(columns, "RESERVED", PLATE_BLUE)
			_barrier()
		BuildingIdentity.Kind.RESIDENTIAL:
			_graffiti(bays, building_seed)
			_clutter(rules, plan, bays, building_seed)
		_:
			_plates(columns, "VALET", PLATE_BURGUNDY)
			_valet_sign()


## Поднимает стрелу шлагбаума за [param duration] с; шлагбаума нет — ничего.
func raise_barrier(duration: float) -> void:
	if _arm == null:
		return
	var tween := create_tween()
	tween.tween_property(_arm, "rotation:x", PI * 0.5, duration)


## Поднята ли стрела: тестам.
func barrier_raised() -> bool:
	return _arm != null and _arm.rotation.x > PI * 0.45


## Есть ли шлагбаум: тестам.
func has_barrier() -> bool:
	return _arm != null


## Таблички на колоннах [param columns]: надпись [param text] на цветном щитке.
func _plates(columns: PackedFloat64Array, text: String, colour: Color) -> void:
	var plate := GreyboxLook.surface(colour)
	var front := Garage.COLUMN_Z + Garage.COLUMN * 0.5
	for x: float in columns:
		var board := GreyboxLook.box(Vector3(PLATE.x, PLATE.y, 0.02), plate)
		board.position = Garage.scene_point(x, _surface - PLATE_RISE, front + 0.02)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(board)
		var word := Garage.label(text, 800, PLATE.y * 0.42, PAINT_WHITE)
		word.position = board.position + Vector3(0.0, 0.0, 0.015)
		add_child(word)


## Вывеска отеля над проездом у ворот: щит на подвесах из-под потолка.
func _valet_sign() -> void:
	var x := Garage.inner_span(_rules).x + 2.4
	var z := WorldSpace.BACK_WALL_Z + 0.4
	var rise := _surface - _rules.story_top(_rules.floors - 1) - 0.55
	var board := GreyboxLook.box(Vector3(2.4, 0.42, 0.04), GreyboxLook.surface(PLATE_BURGUNDY))
	board.position = Garage.scene_point(x, _surface - rise, z)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(board)
	var word := Garage.label("VALET PARKING", 800, 0.22, PAINT_WHITE)
	word.position = board.position + Vector3(0.0, 0.0, 0.025)
	add_child(word)


## Шлагбаум офиса на площадке за воротами: стойка с будкой у переднего края
## проезда и полосатая стрела поперёк него. На кадре закрытая стрела уходит в
## глубину и почти не видна, поднятая — встаёт полосатым столбом.
func _barrier() -> void:
	var gate := Garage.gate_x(_rules) - BuildingShell.WALL_WIDTH * 0.5 - BARRIER_OFF_GATE
	var lane_front := Garage.CAR_Z + Garage.CAR_WIDTH * 0.5 + 0.35
	var post := GreyboxLook.box(POST, GreyboxLook.metal(BOOTH))
	post.position = Garage.scene_point(gate, _surface - POST.y * 0.5, lane_front)
	add_child(post)
	var pivot := Node3D.new()
	pivot.name = "Barrier"
	pivot.position = Garage.scene_point(gate, _surface - POST.y + 0.05, lane_front)
	add_child(pivot)
	var stripes := 6
	for stripe: int in stripes:
		var piece := GreyboxLook.box(
			Vector3(ARM.x, ARM.y, ARM_LENGTH / stripes),
			GreyboxLook.surface(STRIPE_RED if stripe % 2 == 0 else STRIPE_WHITE)
		)
		piece.position.z = -ARM_LENGTH / stripes * (stripe + 0.5)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(piece)
	_arm = pivot


## Граффити на дальней стене паркинга жилого дома — метками [WallWear].
func _graffiti(bays: Array[Vector2], building_seed: int) -> void:
	if bays.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, 0x6A2F])
	for index: int in mini(TAGS, bays.size()):
		var bay := bays[rng.randi_range(0, bays.size() - 1)]
		var low := rng.randf_range(0.45, 0.75)
		var quad := QuadMesh.new()
		quad.size = TAG_SIZE
		var look := StandardMaterial3D.new()
		var tag := WallWear.TAGS[index % WallWear.TAGS.size()]
		look.albedo_texture = load("%s/%s.png" % [WallWear.DIR, tag]) as Texture2D
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.roughness = 0.9
		quad.material = look
		var mark := MeshInstance3D.new()
		mark.mesh = quad
		var x := rng.randf_range(
			bay.x + TAG_SIZE.x * 0.5, maxf(bay.y - TAG_SIZE.x * 0.5, bay.x + TAG_SIZE.x * 0.5)
		)
		mark.position = Garage.scene_point(x, _surface - low, _far + 0.008 + index * 0.002)
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)


## Мусорный бак и велосипеды на свободных местах паркинга жилого дома.
func _clutter(
	rules: BuildingRules, plan: BuildingPlan, bays: Array[Vector2], building_seed: int
) -> void:
	var taken: Array[float] = []
	for car: Garage.Parked in Garage.parked(rules, plan, building_seed):
		taken.append(car.x)
	var banned := Garage.keep_out(rules, plan)
	var free: Array[Vector2] = []
	for bay: Vector2 in bays:
		var middle := (bay.x + bay.y) * 0.5
		var busy := false
		for x: float in taken:
			busy = busy or absf(x - middle) < 0.5
		for span: Vector2 in banned:
			busy = busy or (bay.y > span.x and bay.x < span.y)
		if not busy:
			free.append(bay)
	if free.is_empty():
		return
	var bin := free[0]
	var dumpster := GreyboxLook.box(DUMPSTER, GreyboxLook.metal(DUMPSTER_GREEN))
	dumpster.position = Garage.scene_point(
		(bin.x + bin.y) * 0.5, _surface - DUMPSTER.y * 0.5, _far - DUMPSTER.z * 0.5 + 0.1
	)
	add_child(dumpster)
	var lid := GreyboxLook.box(
		Vector3(DUMPSTER.x + 0.06, 0.06, DUMPSTER.z + 0.06),
		GreyboxLook.surface(Color(0.1, 0.1, 0.1))
	)
	lid.position = dumpster.position + Vector3(0.0, DUMPSTER.y * 0.5 + 0.03, 0.0)
	add_child(lid)
	if free.size() < 2:
		return
	var rack := free[1]
	for offset: float in [-0.45, 0.35]:
		var bike := PropCatalog.make("bicycle", true)
		if bike == null:
			continue
		bike.position = Garage.scene_point((rack.x + rack.y) * 0.5 + offset, _surface, _far - 0.9)
		add_child(bike)
