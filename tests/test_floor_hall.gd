extends GutTest

## Особые этажи (ADR-0057, решения 2–4): роль этажа — по устройству ROM, на
## особом этаже вместо задней стены зал. Роли проверяются без сцены на любой
## высоте здания, зал — в собранном здании каждого типа: без тел и теней, не
## стоит перед дверями, свет гасится вместе с этажом.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5
const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func after_each() -> void:
	GameState.instance().start_game()
	HallLook.forget()


## Залы — ровно на этажах ROM 1–7 и 11–15, в остальных — коридор.
func test_halls_stand_on_the_rom_bands() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(1, Arcade.FLOORS + 1):
			var hall := FloorRole.is_hall(FloorRole.of_rom(kind, rom))
			var banded := rom <= 7 or (rom >= 11 and rom <= 15)
			assert_eq(hall, banded, "тип %d, этаж ROM %d" % [kind, rom])


## Нижняя полоса — общественные залы, тёмная — технические.
func test_dark_band_is_technical_and_lower_band_public() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(11, 16):
			var role := FloorRole.of_rom(kind, rom)
			assert_true(
				FloorRole.is_technical(role) or role == FloorRole.Role.LAUNDRY,
				"тип %d, ROM %d: %s" % [kind, rom, FloorRole.name_of(role)]
			)
		for rom: int in range(3, 8):
			assert_false(FloorRole.is_technical(FloorRole.of_rom(kind, rom)), "ROM %d" % rom)


## Каждый этаж полосы свой: соседние залы не повторяются (решение 2), лобби
## на 1–2 — одно и то же помещение в два этажа, и паркинг занимает первый.
func test_neighbour_halls_differ() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for rom: int in range(2, 15):
			if rom == 7 or rom == 10:
				continue
			var role := FloorRole.of_rom(kind, rom)
			var above := FloorRole.of_rom(kind, rom + 1)
			if FloorRole.is_hall(role) and FloorRole.is_hall(above):
				assert_ne(role, above, "тип %d, ROM %d и %d" % [kind, rom, rom + 1])


## Типы разведены: у каждой пары типов залы на одних этажах различаются хотя
## бы на половине полосы.
func test_kinds_get_their_own_halls() -> void:
	for first: int in KINDS.size():
		for second: int in range(first + 1, KINDS.size()):
			var same := 0
			var total := 0
			for rom: int in range(3, 16):
				var role := FloorRole.of_rom(KINDS[first], rom)
				if not FloorRole.is_hall(role):
					continue
				total += 1
				if role == FloorRole.of_rom(KINDS[second], rom):
					same += 1
			assert_lt(same * 2, total, "типы %d и %d" % [first, second])


## Крыша и паркинг — не залы на любой высоте здания; у здания любой высоты
## залы есть и все роли — из таблицы.
func test_roof_and_garage_are_never_halls() -> void:
	for floors: int in [6, 8, 12, 20, 30]:
		var rules := BuildingRules.new()
		rules.floors = floors
		for kind: BuildingIdentity.Kind in KINDS:
			rules.kind = kind
			assert_false(FloorRole.hall_at(rules, BuildingRules.ROOF), "крыша, %d этажей" % floors)
			assert_false(FloorRole.hall_at(rules, floors - 1), "паркинг, %d этажей" % floors)
			var halls := 0
			for index: int in floors - 1:
				halls += 1 if FloorRole.hall_at(rules, index) else 0
			assert_gt(halls, 0, "тип %d, %d этажей: есть особые" % [kind, floors])


## Чем отделён зал: технические — сеткой, серверная и переговорные — стеклом,
## общественные офиса — стеклом, остальные — колоннами.
func test_screen_follows_the_role() -> void:
	var office := BuildingIdentity.Kind.OFFICE
	var hotel := BuildingIdentity.Kind.HOTEL
	assert_eq(FloorRole.screen_of(FloorRole.Role.BOILER, hotel), FloorRole.Screen.MESH)
	assert_eq(FloorRole.screen_of(FloorRole.Role.SERVER, office), FloorRole.Screen.GLASS)
	assert_eq(FloorRole.screen_of(FloorRole.Role.LOBBY, office), FloorRole.Screen.GLASS)
	assert_eq(FloorRole.screen_of(FloorRole.Role.LOBBY, hotel), FloorRole.Screen.COLUMNS)


## В собранном здании любого типа: залы есть на каждом особом этаже, без тел и
## теней; свет — только на светлых этажах и гаснет вне кадра; ни одна мелкая
## деталь не стоит перед дверью на глубину её комнаты.
func test_halls_in_a_built_building_of_every_kind() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		assert_eq(rules.kind, kind, "уровень ставит тип в правила")
		var halls := level.find_children("FloorHall", "FloorHall", true, false)
		assert_eq(halls.size(), 1, "тип %d: залы собраны" % kind)
		if halls.is_empty():
			continue
		var hall := halls[0] as FloorHall
		assert_gt(hall.parts(), 0, "детали остались в мультимешах")
		assert_eq(hall.find_children("*", "PhysicsBody3D", true, false).size(), 0, "без тел")
		for many: Node in hall.find_children("*", "MultiMeshInstance3D", true, false):
			assert_eq(
				(many as MultiMeshInstance3D).cast_shadow,
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"без теней"
			)
		for light: OmniLight3D in hall.lights():
			assert_false(light.shadow_enabled, "свет зала без теней")
			var index := _story_of(rules, WorldSpace.to_plane(light.position).y)
			assert_true(FloorRole.hall_at(rules, index), "свет — на особом этаже %d" % index)
			assert_false(rules.is_unlit(index), "на тёмном этаже свет зала погашен")
		hall.light_span(Vector2i(-10, -5))
		for light: OmniLight3D in hall.lights():
			assert_false(light.visible, "вне кадра свет зала гаснет")
		_assert_clear_of_doors(level, hall, kind)


## Обстановка коридора и вещи на стене не ставятся на особом этаже: стены нет.
func test_no_corridor_dressing_on_hall_floors() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var level := await _level(kind)
		var rules := level.rules
		var scenery := level.get_node("Scenery") as BuildingScenery
		for prop: BuildingDressing.PropSpot in scenery.dressing.props:
			assert_false(
				FloorRole.hall_at(rules, prop.floor_index),
				"мебель коридора на этаже %d" % prop.floor_index
			)
		for decor: BuildingDressing.PropSpot in scenery.dressing.decor:
			assert_false(
				FloorRole.hall_at(rules, decor.floor_index),
				"вещь на стене этажа %d" % decor.floor_index
			)


func _assert_clear_of_doors(
	level: GreyboxLevel, hall: FloorHall, kind: BuildingIdentity.Kind
) -> void:
	var rules := level.rules
	var office := kind == BuildingIdentity.Kind.OFFICE
	var reach := FloorHall.LEAF_CLEAR if office else DoorRoom.DEPTH
	var clear := Door.LEAF_SIZE.x * 0.5 if office else DoorRoom.WIDTH * 0.5 + DoorRoom.SHIFT
	for many: Node in hall.find_children("*", "MultiMeshInstance3D", true, false):
		var multimesh := (many as MultiMeshInstance3D).multimesh
		for item: int in multimesh.instance_count:
			var place := multimesh.get_instance_transform(item)
			# Пол, стены и ленты окон — во весь пролёт, их середина где угодно.
			if place.basis.get_scale().x > 2.5:
				continue
			var depth := WorldSpace.BACK_WALL_Z - place.origin.z
			if depth > reach - 0.2 or depth < 0.0:
				continue
			var index := _story_of(rules, -place.origin.y)
			for spot: BuildingPlan.DoorSpot in level.plan().doors:
				if spot.floor_index != index:
					continue
				assert_true(
					absf(place.origin.x - spot.x) >= clear - 0.05,
					(
						"тип %d, этаж %d: деталь в %.2f перед дверью в %.2f"
						% [kind, index, place.origin.x, spot.x]
					)
				)


## Этаж, в высоту которого попадает [param y]: от пола этажа выше до своего пола.
func _story_of(rules: BuildingRules, y: float) -> int:
	return int(ceilf((y - rules.sky_height) / rules.floor_height)) - 1


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	var rules := BuildingRules.new()
	rules.floors = 30
	rules.documents_cap = 0
	level.rules = rules
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level
