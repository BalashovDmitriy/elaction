extends GutTest

## Time of day (ADR-0051): a draw by seed, night more often than the others, darkness and dark
## floors only at night, thunderstorm — in the evening and at night, sun — only outside.
##
## Rules — without a scene, on any building. The scene — for a lamp falling and for the sun.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const FALL_FRAMES: int = 240
const SKILLS: Array[int] = [0, 3, 7]
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Time repeats by seed, anything can come up, and night is about forty percent.
func test_time_follows_the_seed_and_night_comes_most() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for building_seed: int in range(1, 1001):
		var kind := TimeOfDay.of_seed(building_seed)
		assert_eq(
			TimeOfDay.of_seed(building_seed), kind, "сид %d: время не повторилось" % building_seed
		)
		counts[kind] += 1
	for kind: int in counts.size():
		assert_gt(counts[kind], 120, "время %d почти не выпадает: %s" % [kind, counts])
	assert_between(counts[TimeOfDay.Kind.NIGHT], 340, 460, "ночь не около 40 %%: %s" % [counts])
	for kind: int in [TimeOfDay.Kind.MORNING, TimeOfDay.Kind.DAY, TimeOfDay.Kind.EVENING]:
		assert_lt(counts[kind], counts[TimeOfDay.Kind.NIGHT], "ночь не чаще времени %d" % kind)


## Time is its own draw: with the same weather different times come up, and vice versa.
func test_time_does_not_follow_the_weather() -> void:
	var pairs: Dictionary = {}
	for building_seed: int in range(1, 301):
		pairs[Vector2i(Weather.of_seed(building_seed), TimeOfDay.of_seed(building_seed))] = true
	assert_eq(
		pairs.size(),
		Weather.Kind.size() * TimeOfDay.Kind.size(),
		"на трёхстах зданиях выпало не всякое сочетание времени и погоды"
	)


## Dark floors of the map happen only at night, while in daytime lamps hang on them — at any
## skill, and therefore in any building of a game.
func test_dark_floors_only_at_night() -> void:
	for skill: int in SKILLS:
		for kind: int in TimeOfDay.Kind.size():
			var rules := BuildingRules.new()
			rules.skill = skill
			rules.time_of_day = kind as TimeOfDay.Kind
			var unlit := 0
			for index in rules.floors:
				if rules.is_unlit(index):
					unlit += 1
					assert_eq(rules.lamps_on(index), 0, "тёмный этаж %d с лампами" % index)
				elif index > BuildingRules.ROOF:
					assert_gt(rules.lamps_on(index), 0, "светлый этаж %d без ламп" % index)
			if TimeOfDay.is_night(kind as TimeOfDay.Kind):
				assert_gt(unlit, 0, "навык %d: ночью тёмных этажей нет" % skill)
			else:
				assert_eq(unlit, 0, "навык %d, время %d: тёмный этаж не ночью" % [skill, kind])


## Not at night the building has its own layout: on ROM floors 11–15 lamps hang and take
## slots from doors. Such a building must be the same building — a lamp on every
## floor, all documents reachable — on any seed and skill, not just the night one
## that the map tests check.
func test_a_day_building_lays_out_and_can_be_finished() -> void:
	for skill: int in SKILLS:
		for kind: int in [TimeOfDay.Kind.MORNING, TimeOfDay.Kind.DAY, TimeOfDay.Kind.EVENING]:
			var rules := BuildingRules.new()
			rules.skill = skill
			rules.time_of_day = kind as TimeOfDay.Kind
			for building_seed: int in SEEDS:
				var plan := BuildingPlan.generate(rules, building_seed)
				var where := "навык %d, время %d, сид %d" % [skill, kind, building_seed]
				var lamps: Dictionary = {}
				for lamp in plan.lamps:
					lamps[lamp.floor_index] = true
				for index: int in rules.floors:
					assert_true(lamps.has(index), where + ": этаж %d без лампы" % index)
				assert_eq(
					plan.document_floors().size(),
					BuildingDocuments.count(rules, building_seed),
					where + ": документов"
				)
				assert_true(BuildingRoute.is_winnable(plan, rules), where + ": здание не пройти")


## Thunderstorm — in the evening and at night, in the morning and daytime rain without lightning.
func test_thunder_only_in_the_evening_and_at_night() -> void:
	assert_false(TimeOfDay.has_thunder(TimeOfDay.Kind.MORNING))
	assert_false(TimeOfDay.has_thunder(TimeOfDay.Kind.DAY))
	assert_true(TimeOfDay.has_thunder(TimeOfDay.Kind.EVENING))
	assert_true(TimeOfDay.has_thunder(TimeOfDay.Kind.NIGHT))


## In daytime a shot-down lamp falls, and the zone stays lit; at night — it goes dark.
func test_a_lamp_puts_out_its_zone_only_at_night() -> void:
	for kind: int in [TimeOfDay.Kind.DAY, TimeOfDay.Kind.NIGHT]:
		var level := _build(kind as TimeOfDay.Kind)
		var lamp := _a_lamp(level)
		assert_not_null(lamp, "на этаже 2 нет лампы")
		if lamp == null:
			level.queue_free()
			return
		var x := WorldSpace.to_plane(lamp.global_position).x
		var index := lamp.floor_index
		lamp.shoot_down()
		var left := FALL_FRAMES
		while is_instance_valid(lamp) and left > 0:
			left -= 1
			await wait_physics_frames(1)
		await wait_physics_frames(2)
		if kind == TimeOfDay.Kind.NIGHT:
			assert_true(level.is_dark_at(index, x), "ночью зона сбитой лампы не погасла")
		else:
			assert_false(level.is_dark_at(index, x), "днём зона сбитой лампы погасла")
		level.queue_free()
		await wait_physics_frames(1)


## There is sun only when it is not night, it shines only on the outside layer, and the roof
## gets into it, but not the corridors.
func test_the_sun_lights_only_the_outdoors() -> void:
	for kind: int in TimeOfDay.Kind.size():
		var level := _build(kind as TimeOfDay.Kind)
		var scenery := level.get_node("Scenery") as BuildingScenery
		var sun := scenery.sun()
		if TimeOfDay.is_night(kind as TimeOfDay.Kind):
			assert_null(sun, "ночью есть солнце")
		else:
			assert_not_null(sun, "время %d без солнца" % kind)
			assert_eq(sun.light_cull_mask, Outdoors.LAYER, "солнце светит не только снаружи")
		var roof := level.get_node("Scenery/Roof")
		var outside := 0
		for node in roof.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).layers & Outdoors.LAYER:
				outside += 1
		assert_gt(outside, 0, "крыша не снаружи")
		var under_roof := WorldSpace.height_to_scene(
			level.rules.floor_surface(BuildingRules.ROOF) + level.rules.slab_height
		)
		for node in level.find_children("*", "GeometryInstance3D", true, false):
			var visual := node as GeometryInstance3D
			if not (visual.layers & Outdoors.LAYER):
				continue
			var box := visual.global_transform * visual.get_aabb()
			assert_true(
				box.position.y >= under_roof - 0.05 or _outdoor_root(visual, level),
				"%s снаружи, хотя стоит под крышей" % visual.get_path()
			)
		level.queue_free()
		await wait_physics_frames(1)


## Any combination of time and weather builds the building without errors.
func test_every_time_and_weather_builds() -> void:
	for kind: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var level := _build(kind as TimeOfDay.Kind, weather)
			var scenery := level.get_node("Scenery") as BuildingScenery
			assert_eq(scenery.weather, weather as Weather.Kind)
			var city := level.get_node("Scenery/City") as CityBackdrop
			var storm := weather == Weather.Kind.RAIN and TimeOfDay.has_thunder(kind)
			assert_eq(city.has_lightning(), storm, "время %d, погода %d: гроза" % [kind, weather])
			level.queue_free()
			await wait_physics_frames(1)


func _build(kind: TimeOfDay.Kind, weather: int = -1) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.rules.time_of_day = kind
	level.rules.forced_weather = weather
	level.building_seed = 1
	level.spawn_agents = false
	add_child(level)
	return level


func _a_lamp(level: GreyboxLevel) -> Lamp:
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == 2:
			return lamp
	return null


## Whether a node is under something entirely outside: helicopter, sign, roof equipment.
func _outdoor_root(node: Node, level: GreyboxLevel) -> bool:
	var up := node.get_parent()
	while up != null and up != level:
		# The street at the exit is outside too: since M24k it has sun (ADR-0052, decision 3).
		if up is Helicopter or up is VerticalSign or up is RoofKit or up is BuildingRoof:
			return true
		if up is ExitStreet:
			return true
		up = up.get_parent()
	return false
