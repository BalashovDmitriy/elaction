extends GutTest

## Building surroundings (ADR-0029): weather and city by seed, dressing does not hurt
## readability, roof slopes are a silhouette, not a floor.
##
## Dressing and city layout — without a scene, on any seed. The scene is assembled
## once: the decor has no bodies and adds no light sources.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5]


func after_all() -> void:
	GameState.instance().reset()


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


## Weather repeats by seed, and over thirty buildings all three come up.
func test_weather_follows_the_seed_and_varies() -> void:
	var seen: Dictionary = {}
	for building_seed: int in range(1, 31):
		var kind := Weather.of_seed(building_seed)
		assert_eq(
			Weather.of_seed(building_seed), kind, "seed %d: weather did not repeat" % building_seed
		)
		seen[kind] = true
	assert_eq(seen.size(), Weather.Kind.size(), "not every weather came up over thirty buildings")


## The city repeats by seed and differs between seeds.
func test_the_city_follows_the_seed() -> void:
	var first := CityPlan.generate(1, 0.0, 40.0)
	var again := CityPlan.generate(1, 0.0, 40.0)
	var other := CityPlan.generate(2, 0.0, 40.0)
	assert_eq(_fingerprint(first), _fingerprint(again), "same seed - same city")
	assert_ne(_fingerprint(first), _fingerprint(other), "different seed - different city")


## Each row covers the full width of the building: otherwise the gap between houses
## shows the void that the city was set up to hide.
func test_every_row_covers_the_building() -> void:
	var width := BuildingRules.new().width
	var blocks := CityPlan.generate(3, 0.0, width)
	for row: int in CityPlan.ROWS.size():
		var from := INF
		var to := -INF
		for block in blocks:
			if block.row != row:
				continue
			from = minf(from, block.x - block.width * 0.5)
			to = maxf(to, block.x + block.width * 0.5)
		assert_lt(from, 0.0, "row %d does not reach the left edge" % row)
		assert_gt(to, width, "row %d does not reach the right edge" % row)


## Dressing does not take the place of a door, lamp, shaft, escalator or exit and
## does not press against a solid wall — on any seed and skill.
func test_props_keep_off_doors_lamps_shafts_and_walls() -> void:
	var total := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var step := rules.slot_x(1) - rules.slot_x(0)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed)
			total += dressing.props.size()
			for prop in dressing.props:
				var where := (
					"skill %d, seed %d, floor %d, x=%.1f"
					% [skill, building_seed, prop.floor_index, prop.x]
				)
				assert_gt(prop.floor_index, BuildingRules.ROOF, where + ": furnishing on the roof")
				assert_true(
					plan.safe_spots(rules, prop.floor_index).has(prop.x),
					where + ": prop on a shaft, escalator or exit"
				)
				for door in plan.doors:
					if door.floor_index == prop.floor_index:
						assert_gte(absf(door.x - prop.x), step * 0.5, where + ": at a door")
				for lamp in plan.lamps:
					if lamp.floor_index == prop.floor_index:
						assert_gte(absf(lamp.x - prop.x), step * 0.5, where + ": under a lamp")
				# safe_spots does not reserve the escalator's lower landing: people stand on it.
				for escalator in plan.escalators:
					if escalator.floor_index + 1 == prop.floor_index:
						var landing := escalator.x + escalator.towards * rules.escalator_run
						assert_gte(
							absf(landing - prop.x), step * 0.5, where + ": on an escalator landing"
						)
				for wall in plan.walls:
					if wall.floor_index == prop.floor_index:
						assert_gte(
							absf(wall.x - prop.x),
							step * 0.5 + rules.inner_wall_width * 0.5,
							where + ": pressed against a wall"
						)
	assert_gt(total, 0, "no props at all - nothing to check")


## The pipe is visible: it hangs below the band covered by the slab edge, and does not
## pass through a shaft, an escalator belt or a floor sign. Pipes in plain sight are
## only in a residential building (ADR-0056, decision 5): so that is where we check them.
func test_pipes_show_below_the_slab_edge_and_skip_what_they_would_cover() -> void:
	var laid := 0
	var front := BuildingProps.pipe_z() + BuildingProps.PIPE_THICKNESS * 0.5
	var home := BuildingIdentity.new()
	home.kind = BuildingIdentity.Kind.RESIDENTIAL
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, home)
			for index: int in dressing.pipes:
				var where := "skill %d, seed %d, floor %d" % [skill, building_seed, index]
				assert_gte(
					BuildingProps.pipe_top(rules, index),
					rules.story_top(index) + FloorSigns.hidden_band(front),
					where + ": pipe past the slab edge"
				)
				var covered := _pipe_blockers(rules, plan, index)
				for span: Vector2 in BuildingProps.pipe_spans(rules, plan, index):
					laid += 1
					for blocker: Vector2 in covered:
						assert_true(
							span.y <= blocker.x + 0.001 or span.x >= blocker.y - 0.001,
							where + ": pipe through %s" % blocker
						)
	assert_gt(laid, 0, "no pipes at all - nothing to check")


## Sign neon, shaft indicator digits and the call button light do not carry the colours
## of the game's indicator lights: door indicator, document door and exit (ADR-0023,
## decision 6).
func test_neon_signs_do_not_wear_the_colours_of_game_signs() -> void:
	var reserved: Array[Color] = [
		GreyboxLook.SIGN_WARM, GreyboxLook.SIGN_RED, GreyboxLook.SIGN_GREEN
	]
	var glowing: Array[Color] = [
		VerticalSign.NEON_HOTEL,
		VerticalSign.NEON_OFFICE,
		VerticalSign.NEON_RESIDENTIAL,
		BuildingShafts.CALL_LIT,
	]
	glowing.append_array(BuildingShafts.KIND_DIGITS)
	for neon: Color in glowing:
		for sign_colour: Color in reserved:
			var gap := Vector3(
				neon.r - sign_colour.r, neon.g - sign_colour.g, neon.b - sign_colour.b
			)
			assert_gt(gap.length(), 0.3, "sign %s looks like the light %s" % [neon, sign_colour])


## Roof slopes are inside its walls, do not go onto the machine room and are below it.
func test_roof_steps_frame_the_machine_room() -> void:
	var rules := _rules(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var shaft := plan.roof_shaft()
		var bounds := rules.floor_span(BuildingRules.ROOF)
		var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
		var surface := rules.floor_surface(BuildingRules.ROOF)
		var steps := BuildingRoof.steps(rules, plan)
		assert_gt(steps.size(), 0, "seed %d: no ramps" % building_seed)
		for rect in steps:
			assert_gte(
				rect.position.x, bounds.x, "seed %d: ramp past the left wall" % building_seed
			)
			assert_lte(
				rect.end.x, bounds.y + 0.001, "seed %d: ramp past the right wall" % building_seed
			)
			assert_true(
				(
					rect.end.x <= shaft.x - half_room + 0.001
					or rect.position.x >= shaft.x + half_room - 0.001
				),
				"seed %d: ramp runs onto the machine room" % building_seed
			)
			assert_almost_eq(
				rect.end.y,
				surface,
				0.001,
				"seed %d: ramp does not stand on the deck" % building_seed
			)
			assert_lte(
				rect.size.y,
				BuildingShafts.MACHINE_ROOM_SIZE.y,
				"seed %d: ramp above the machine room" % building_seed
			)


## The decor has no bodies, and there are two sources in the surroundings — a lamp above the roof
## and the glow of the neon sign on the corner (ADR-0033, decision 2): city windows, indicators,
## sign letters and the antenna light glow by emission and do not touch the frame's lamp budget. The
## city's sun or moon (ADR-0051) is in the city's own world, behind a [SubViewport], and does not
## count either.
func test_scenery_adds_no_bodies_and_no_lights() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var scenery := level.get_node_or_null("Scenery")
	assert_not_null(scenery, "no surroundings")
	if scenery == null:
		remove_child(level)
		return
	var bodies := scenery.find_children("*", "CollisionObject3D", true, false)
	assert_eq(bodies.size(), 0, "the decor has bodies")
	var lights: Array[Node] = []
	for light in scenery.find_children("*", "Light3D", true, false):
		if light.get_viewport() == level.get_viewport():
			lights.append(light)
	assert_eq(lights.size(), 2, "the surroundings do not have two light sources")
	assert_not_null(scenery.get_node_or_null("City"), "no city")
	remove_child(level)


## What a pipe on a floor must go around, as "left edge, right edge" pairs.
## Computed anew rather than taken from [BuildingProps]: otherwise the test would check
## the pipe breaks by the same breaks.
func _pipe_blockers(rules: BuildingRules, plan: BuildingPlan, index: int) -> Array[Vector2]:
	var blockers: Array[Vector2] = []
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= index and index <= shaft.bottom:
			blockers.append(Vector2(shaft.x - half, shaft.x + half))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == index:
			blockers.append(escalator.gap(rules))
	var plate := FloorSigns.centre_on(rules, index).x
	var plate_half := Proportions.FLOOR_SIGN.x * 0.5
	blockers.append(Vector2(plate - plate_half, plate + plate_half))
	return blockers


func _fingerprint(blocks: Array[CityPlan.Block]) -> String:
	var parts := PackedStringArray()
	for block in blocks:
		parts.append(
			"%d:%.2f:%.2f:%d:%d" % [block.row, block.x, block.height, block.crown, block.kind]
		)
	return "|".join(parts)


## The car at the exit stands so that along its whole length it touches neither a shaft portal
## (the user's remark on the M20 garage shot), nor the inner wall, nor the run of an
## escalator descending into the garage, and stands within the building walls (M20 code review).
##
## Since M24b the exit is the car itself at the gate (ADR-0038, decision 3): Otto's spot at the
## driver's door falls on it, not next to it.
func test_the_car_parks_clear_of_shafts_and_the_exit() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var bottom := rules.floors - 1
		var bounds := rules.floor_span(bottom)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var x := ExitCar.spot(plan.exit_x, rules, plan)
			var car := Vector2(x - ExitCar.LENGTH * 0.5, x + ExitCar.LENGTH * 0.5)
			var label := "skill %d, seed %d" % [skill, building_seed]
			assert_between(plan.exit_x, car.x, car.y, "%s: exit is not at the car" % label)
			assert_between(
				x,
				bounds.x + BuildingShell.WALL_WIDTH + ExitCar.LENGTH * 0.5,
				bounds.y - BuildingShell.WALL_WIDTH - ExitCar.LENGTH * 0.5,
				"%s: car in the outer wall" % label
			)
			for shaft in plan.shafts:
				if shaft.top > bottom or shaft.bottom < bottom:
					continue
				var shaft_half := rules.shaft_width * 0.5
				var column := Vector2(shaft.x - shaft_half, shaft.x + shaft_half)
				_assert_apart(car, column, "%s: car in front of a shaft x=%.1f" % [label, shaft.x])
			for wall in plan.walls:
				if wall.floor_index == bottom:
					_assert_apart(
						car, wall.band(rules), "%s: car in a wall x=%.1f" % [label, wall.x]
					)
			for escalator in plan.escalators:
				if escalator.floor_index != bottom - 1:
					continue
				var landing := escalator.x + escalator.towards * rules.escalator_run
				var gap := escalator.gap(rules)
				var run := Vector2(minf(gap.x, landing), maxf(gap.y, landing))
				_assert_apart(car, run, "%s: car on an escalator x=%.1f" % [label, escalator.x])


## Segments [param a] and [param b] do not overlap (touching is allowed).
func _assert_apart(a: Vector2, b: Vector2, message: String) -> void:
	assert_true(a.y <= b.x + 0.001 or a.x >= b.y - 0.001, message)


## The cab walls stand on its floor and reach the roof. The floor is at the cab's zero, the slab
## under it: walls measured from the slab top hung 18 cm above the floor
## (M20 code review).
func test_the_cabin_walls_stand_on_its_floor() -> void:
	var scene := load("res://src/systems/elevators/elevator_car.tscn") as PackedScene
	var car := scene.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.fit_to_story(Proportions.CLEARANCE, Proportions.SHAFT)
	var half_slab := ElevatorCar.SLAB_THICKNESS * 0.5
	var floor_top := (car.get_node("FloorVisual") as Node3D).position.y + half_slab
	var roof_bottom := (car.get_node("RoofVisual") as Node3D).position.y - half_slab
	var lowest := INF
	var highest := -INF
	for part: Node in car._detail._body.get_children():
		var mesh := part as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
		highest = maxf(highest, box.end.y)
	assert_almost_eq(lowest, floor_top, 0.01, "cab walls hang above its floor")
	assert_almost_eq(highest, roof_bottom, 0.01, "cab walls do not reach the roof")
	remove_child(car)


## The quality level reaches the building already standing, not from the next one
## (ADR-0030, decision 5): reflections, contact shadows and the building's air fog.
func test_quality_reaches_the_building_already_standing() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var air := (level.get_node("Scenery/Air") as WorldEnvironment).environment
	Graphics.broadcast(Graphics.Quality.LOW)
	var low: Array[bool] = [air.ssr_enabled, air.ssao_enabled, air.volumetric_fog_enabled]
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_eq(low, [false, false, false] as Array[bool], "low quality did not reach the air")
	assert_true(air.ssr_enabled, "high quality did not bring back reflections")
	remove_child(level)


## The exit floor is a garage: it has no doors on any seed and skill, as in
## the original's basement (ADR-0031, decision 4).
func test_the_exit_floor_is_a_garage_without_doors() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		assert_eq(rules.doors_on(rules.floors - 1), 0, "skill %d: garage with doors" % skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for door in plan.doors:
				assert_ne(
					door.floor_index,
					rules.floors - 1,
					"skill %d, seed %d: door in the garage" % [skill, building_seed]
				)


## Roof equipment stands inside its walls and behind Otto: its front no closer than
## the machine room. On seed 2 the 2.7 m deep roof exit stood across the
## play plane (M21b code review).
func test_roof_kit_stays_on_the_roof() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 2
	add_child_autofree(level)
	var kit := level.get_node_or_null("Scenery/RoofKit")
	assert_not_null(kit, "no roof equipment")
	if kit == null:
		return
	var bounds := level.rules.floor_span(BuildingRules.ROOF)
	var parts := kit.find_children("*", "VisualInstance3D", true, false)
	assert_gt(parts.size(), 10, "almost nothing stands on the roof")
	for part: Node in parts:
		var x := (part as Node3D).global_position.x
		assert_between(
			x, bounds.x - 0.1, bounds.y + 0.1, "roof part past its walls: %s" % part.name
		)
	var models := 0
	for child in kit.get_children():
		var model := child as Node3D
		if model == null or PropCatalog.entry(String(model.name)) == null:
			continue
		models += 1
		var front := model.position.z + PropCatalog.bounds_of(model).end.z
		assert_lte(front, RoofKit.FRONT_Z + 0.001, "%s sticks out into the play plane" % model.name)
	assert_gt(models, 3, "almost no models on the roof")
	remove_child(level)


## The counterweight moves opposite the cab: cab at the bottom — it at the top.
func test_the_counterweight_goes_against_the_car() -> void:
	var detail: CarDetail = autofree(CarDetail.new())
	add_child(detail)
	detail.build(1.8, 3.0)
	detail.hang_cables(0.0, 20.0, 23.0)
	detail.follow(0.0, 5.0)
	var weight := detail._weight.global_position.y
	detail.follow(20.0, 5.0)
	assert_gt(weight, detail._weight.global_position.y, "cab went up - counterweight went down")
	# The counterweight does not go above the shaft top: for a shaft to the roof the top is in the
	# machine room, not above the ceiling of the top stop (M20 code review).
	detail.set_top(21.0)
	detail.follow(0.0, 5.0)
	var weight_top := detail._weight.global_position.y + CarDetail.WEIGHT.y * 0.5
	assert_lte(weight_top, 21.0 + 0.001, "counterweight above the top of the shaft")
	remove_child(detail)


## Blood switched off in settings does not splash at all.
func test_blood_respects_the_setting() -> void:
	var host: Node3D = autofree(Node3D.new())
	add_child(host)
	Blood.enabled = false
	Blood.spray(host, Vector3.ZERO, 1.0)
	assert_eq(host.get_child_count(), 0, "disabled blood splattered")
	Blood.enabled = true
	Blood.spray(host, Vector3.ZERO, 1.0)
	assert_eq(host.get_child_count(), 1, "enabled blood did not splatter")
	remove_child(host)


## A shot lamp throws sparks at the point of impact, and they stay there while
## the lamp falls (ADR-0031, decision 3a).
func test_a_shot_lamp_throws_sparks() -> void:
	var host: Node3D = autofree(Node3D.new())
	add_child(host)
	var lamp := (load("res://src/systems/lighting/lamp.tscn") as PackedScene).instantiate() as Lamp
	host.add_child(lamp)
	lamp.shoot_down()
	var sparks := host.find_children("*", "Sparks", false, false)
	assert_eq(sparks.size(), 1, "no sparks or more than one burst")
	remove_child(host)
