extends GutTest

## Smoke test of building assembly.
##
## Between "the layout says: shaft at 12–17" and "the cab actually stands there" lies level code
## that nothing checked. Here the building is assembled for real, with physics, and compared against
## its own layout.
##
## The building is small: the generator is the same, and the run is shorter.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3]

## How many frames to give the building to settle before the checks.
const SETTLE_FRAMES: int = 10

## How many light sources may be kept lit at once.
##
## The number is artistic, not technical: the measurement (ADR-0010, item 1) showed that the
## hardware can take four times more, but a dozen pools of light in the frame is already a mess.
## Checked on a full-height building: that is where the selection is needed.
const LIGHT_BUDGET: int = 12

## How many frames to wait for a lamp to fall. The limit is there on purpose: otherwise waiting for
## a state that never comes would drag on until the end of the run.
const FALL_FRAMES: int = 240


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 8
	rules.documents_cap = 2
	return rules


func _build(building_seed: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = _rules()
	level.building_seed = building_seed
	add_child_autofree(level)
	return level


## Removes the building from the tree at once, without waiting for the end of the test.
##
## [method GutTest.add_child_autofree] frees only after the whole test, and seeds are iterated
## inside one test: without this the buildings stand inside each other in one physics world, with
## their own Ottos and their own agents. GUT will free them anyway.
func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func _count(level: GreyboxLevel, type: Variant) -> int:
	var found := 0
	for child in level.get_children():
		if is_instance_of(child, type):
			found += 1
	return found


func test_every_seed_assembles_and_holds_otto() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await _wait_for_the_landing(level)
		assert_true(
			level.otto.is_grounded(),
			"seed %d: Otto is not on the floor — fell through the geometry" % building_seed
		)
		assert_false(level.otto.is_dead(), "seed %d: Otto died at the start" % building_seed)
		_drop(level)


func test_scene_matches_the_plan() -> void:
	var rules := _rules()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		assert_eq(
			_count(level, ElevatorCar),
			plan.shafts.size(),
			"seed %d: the cars do not match the shafts in number" % building_seed
		)
		assert_eq(_count(level, Door), plan.doors.size(), "seed %d: doors" % building_seed)
		assert_eq(_count(level, Escalator), plan.escalators.size(), "seed %d" % building_seed)
		_drop(level)


## How many sources are lit right now — across the whole level tree, not only among direct children:
## a lamp's light hangs as a child of the lamp itself, and a count over the level's children would
## not see it at all — the check would pass even if not a single lamp in the building went out.
func _lit(level: GreyboxLevel) -> int:
	var count := 0
	for node: Node in level.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		# The camera light shines only on the figure layer: it gives no pool on the floor (ADR-0042,
		# decision 7).
		if light == null or light.light_cull_mask == FigureRig.RENDER_LAYER:
			continue
		# The intro helicopter's light turns off and on by itself — with the door and the departure
		# (ADR-0052): it has nothing to do with the floor lamps.
		if _in_helicopter(light, level):
			continue
		if light.is_visible_in_tree():
			count += 1
	return count


func _in_helicopter(node: Node, level: GreyboxLevel) -> bool:
	var up := node.get_parent()
	while up != null and up != level:
		if up is Helicopter:
			return true
		up = up.get_parent()
	return false


## Full-height building: default rules, thirty floors.
func _tall(building_seed: int) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## The nearest lamp below Otto.
##
## Precisely the nearest, not just any: the floor underfoot is always in the frame, so the light on
## it is on. A lamp from an arbitrary floor could be outside the selection, where its floor is off
## anyway, — and "fewer sources" would not hold, although there is nothing to turn off.
func _nearest_lamp_below(level: GreyboxLevel) -> Lamp:
	# "Below" — in the rules plane, where down is growing Y.
	var otto_y := WorldSpace.to_plane(level.otto.global_position).y
	var found: Lamp = null
	var found_y := INF
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp == null:
			continue
		var lamp_y := WorldSpace.to_plane(lamp.global_position).y
		if lamp_y <= otto_y:
			continue
		if lamp_y < found_y:
			found = lamp
			found_y = lamp_y
	return found


## There are sixty-odd sources in the building, and only a handful should be lit.
func test_a_tall_building_lights_only_what_is_in_frame() -> void:
	for building_seed: int in SEEDS:
		var level := _tall(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var burning := _lit(level)
		assert_gt(burning, 0, "seed %d: no light came on at all" % building_seed)
		assert_lte(
			burning,
			LIGHT_BUDGET,
			"seed %d: %d sources burn with a budget of %d" % [building_seed, burning, LIGHT_BUDGET]
		)
		_drop(level)


## The same path as in the game: a bullet shoots down a lamp, the lamp lands — the floor goes dark.
## What is checked is not a flag but a dead source: a flag without light means nothing.
func test_a_fallen_lamp_puts_its_floor_out() -> void:
	var level := _tall(1)
	# The intro moves the camera in and changes which floors are in the frame, and with them the lit
	# lamps (ADR-0052): the test is about the lamp, so the intro is skipped.
	level.skip_the_intro()
	await wait_physics_frames(SETTLE_FRAMES)

	var lamp := _nearest_lamp_below(level)
	assert_not_null(lamp, "the building must have a lamp below Otto")
	if lamp == null:
		return

	var index := lamp.floor_index
	var lamp_x := WorldSpace.to_plane(lamp.global_position).x
	assert_false(level.is_dark_at(index, lamp_x), "before the shot the zone is lit")
	var before := _lit(level)
	var lamps_on_floor := 0
	for spot in level.plan().lamps:
		if spot.floor_index == index:
			lamps_on_floor += 1

	lamp.shoot_down()
	var left := FALL_FRAMES
	while is_instance_valid(lamp) and left > 0:
		left -= 1
		await wait_physics_frames(1)
	assert_false(is_instance_valid(lamp), "the lamp reached the floor")

	await wait_physics_frames(2)
	assert_true(level.is_dark_at(index, lamp_x), "the lamp zone on floor %d went dark" % index)
	# A zone goes dark, not a floor: neighbouring lamps stay lit (ADR-0023, decision 2).
	assert_eq(
		level.is_dark(index),
		lamps_on_floor == 1,
		"the floor is entirely dark only if there was a single lamp"
	)
	# A lamp has two sources — the cone and the fill (ADR-0023, decision 3), and both go with it: "the
	# zone is lit" and "the lamp hangs" are the same thing.
	assert_eq(_lit(level), before - 2, "and both light sources of the lamp stopped burning")
	_drop(level)


func test_otto_starts_on_the_roof() -> void:
	var rules := _rules()
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_eq(
		rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y),
		BuildingRules.ROOF,
		"Otto starts on the roof, not on the top floor"
	)


## Puts Otto on the roof ([method GreyboxLevel.wait_for_the_landing]).
##
## The intro is skipped, as the player skips it with a jump: what is checked here is that the
## building holds Otto, not the helicopter scene, — and it takes over four seconds per seed without
## time speed-up (`test_roof_arrival.gd`).
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	level.skip_the_intro()
	assert_true(await level.wait_for_the_landing(), "Otto stood on the roof")


## A cab as wide as the shaft: it takes its width from the rules, not from the scene.
##
## Up to M18c the width was held by the scene — 1.2 m, — and a 1.8 m shaft would leave 30 cm gaps on
## each side, through which Otto would fall when stepping out of the cab (ADR-0026, decision 3).
## Non-standard rules are used on purpose: with defaults the number from the scene would also match.
func test_every_car_is_as_wide_as_its_shaft() -> void:
	var rules := _rules()
	rules.shaft_width = 1.62
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	await wait_physics_frames(SETTLE_FRAMES)
	var cars := 0
	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		cars += 1
		assert_almost_eq(car.width(), rules.shaft_width, 0.001, "the car is as wide as the shaft")
		var roof := (car.get_node("RoofShape") as CollisionShape3D).shape as BoxShape3D
		assert_almost_eq(roof.size.x, rules.shaft_width, 0.001, "and its roof is the same width")
	assert_gt(cars, 0, "the building has cars")
	_drop(level)
