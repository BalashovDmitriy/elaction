extends GutTest

## Здание снаружи по типу (ADR-0058): корона за плоскостью игры, торцы и уступ
## снаружи стен, паркинг и вход с улицы, машина жребием по типу. Всё — вид без
## тел и без своих источников света; проверяется на здании каждого типа.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5
const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func after_each() -> void:
	GameState.instance().start_game()


## Модели с нулевым весом типа не выпадают, запрещённые краски — тоже; у жилого
## дома краска выцвела. Первое здание — красная спортивная у любого типа.
func test_cars_follow_the_kind_weights() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var weights: Array = CarModel.MODEL_WEIGHTS[kind]
		var seen := {}
		for draw: int in 400:
			var choice := CarModel.draw(rng, kind, [0])
			assert_gt(
				weights[choice.model], 0, "тип %d: модель %d не из типа" % [kind, choice.model]
			)
			assert_ne(choice.paint, 0, "тип %d: красная запрещена" % kind)
			assert_eq(choice.fade, CarModel.FADE[kind])
			seen[choice.model] = true
		assert_gt(seen.size(), 1, "тип %d: моделей больше одной" % kind)
		var first := CarModel.choose(1, 99, kind)
		assert_eq(first.model, 0, "первое здание — спортивная")
		assert_eq(first.paint, 0, "первое здание — красная")


## У каждого типа своя корона: стоит за плоскостью игры дальше размаха винта,
## без тел; торцы и уступ — снаружи стен башни и над уступом; новых источников
## света нет — у окружения их по-прежнему два.
func test_crown_and_flanks_of_every_kind() -> void:
	var tops := {}
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		var crown := level.find_children("Crown", "BuildingCrown", true, false)
		assert_eq(crown.size(), 1, "тип %d: корона есть" % kind)
		if crown.is_empty():
			continue
		var built := crown[0] as BuildingCrown
		assert_gt(built.top(), 4.0, "тип %d: корона высокая" % kind)
		tops[kind] = built.top()
		for node: Node in built.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			var box := mesh.global_transform * mesh.mesh.get_aabb()
			assert_lt(box.end.z, BuildingCrown.FRONT_Z + 0.2, "тип %d: корона за плоскостью" % kind)
		assert_eq(built.find_children("*", "PhysicsBody3D", true, false).size(), 0, "без тел")
		assert_eq(built.find_children("*", "Light3D", true, false).size(), 0, "без света")

		var flanks := level.find_children("Flanks", "BuildingFlanks", true, false)
		assert_eq(flanks.size(), 1, "тип %d: торцы есть" % kind)
		if flanks.is_empty():
			continue
		var sides := flanks[0] as BuildingFlanks
		assert_eq(sides.find_children("*", "Light3D", true, false).size(), 0, "без света")
		var places := sides.placements()
		assert_gt(places.size(), 20, "тип %d: торцы и уступ не пусты" % kind)
		var tower := rules.floor_span(BuildingRules.ROOF)
		var ledge := rules.floor_surface(rules.wide_from - 1)
		for place: Transform3D in places:
			var at := WorldSpace.to_plane(place.origin)
			assert_true(
				at.x <= tower.x + 0.05 or at.x >= tower.y - 0.05,
				"тип %d: деталь в %.2f — внутри башни" % [kind, at.x]
			)
			assert_lt(at.y, ledge + 0.1, "тип %d: деталь ниже уступа" % kind)
	assert_eq(tops.size(), KINDS.size())


## Паркинг: у офиса шлагбаум, и он поднимается вместе с воротами; у других
## шлагбаума нет. Вход с улицы: парковщик только у отеля.
func test_garage_and_street_front_by_kind() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var garage := level.garage()
		assert_not_null(garage.dressing, "тип %d: отделка паркинга" % kind)
		var office := kind == BuildingIdentity.Kind.OFFICE
		assert_eq(garage.dressing.has_barrier(), office, "тип %d: шлагбаум" % kind)
		if office:
			assert_false(garage.dressing.barrier_raised(), "стрела опущена")
			garage.open_gate(0.05)
			await wait_seconds(0.2)
			assert_true(garage.dressing.barrier_raised(), "стрела поднялась с воротами")
		var front := garage.gate.ramp().front
		assert_not_null(front, "тип %d: вход с улицы" % kind)
		var hotel := kind == BuildingIdentity.Kind.HOTEL
		assert_eq(front.valet != null, hotel, "тип %d: парковщик только у отеля" % kind)
		assert_eq(front.find_children("*", "PhysicsBody3D", true, false).size(), 0, "без тел")


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.rules.documents_cap = 0
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level
