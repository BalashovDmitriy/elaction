extends GutTest

## The basement is locked until all documents are collected (M24b): the shaft to the basement
## does not go there, the opening above it is closed by a hatch, the last document opens both.
##
## The cab rule is checked without a scene — on [ElevatorMotion]; the hatches — on the
## layout of many seeds: the building is generated, and a hole into the basement on one seed
## out of forty is a hole. The physics assembly is on a small building: Otto stands on the
## hatch and falls through only when the basement is open.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0
const STEP: float = 0.1

## How many layout seeds to check.
const SEEDS: int = 40
const SETTLE_FRAMES: int = 5
## How many physics steps to give Otto to fall and stand up: a fall by one floor is under
## a second, the rest is margin.
const FALL_FRAMES: int = 90
## How many physics steps to wait for the corpse to settle and sleep.
const SLEEP_FRAMES: int = 600


func before_each() -> void:
	GameState.instance().start_game()


func after_each() -> void:
	GameState.instance().start_game()


func _shaft(start_floor: int = 0) -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.speed = 100.0
	motion.floor_pause = 1.0
	motion.settle_distance = 12.0
	motion.setup(PackedFloat32Array([TOP, MIDDLE, BOTTOM]), start_floor)
	return motion


func _run(motion: ElevatorMotion, seconds: float, command: float, occupied: bool) -> float:
	for _frame: int in int(roundf(seconds / STEP)):
		motion.update(STEP, command, occupied)
	return motion.position


func test_a_locked_car_does_not_take_its_rider_to_the_bottom() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.DOWN, true), MIDDLE, 0.01)
	assert_false(motion.can_go(ElevatorMotion.DOWN), "does not go below the locked stop")
	assert_true(motion.can_go(ElevatorMotion.UP))


func test_a_locked_car_does_not_go_to_the_bottom_on_its_own() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	var deepest := TOP
	for _frame: int in 200:
		motion.update(STEP, 0.0, false)
		deepest = maxf(deepest, motion.position)
	assert_almost_eq(deepest, MIDDLE, 0.01, "turns around by itself above the basement")


func test_the_unlocked_car_reaches_the_bottom() -> void:
	var motion := _shaft(0)
	motion.bottom_locked = true
	_run(motion, 10.0, ElevatorMotion.DOWN, true)
	motion.bottom_locked = false
	assert_almost_eq(_run(motion, 10.0, ElevatorMotion.DOWN, true), BOTTOM, 0.01)


## A cab already standing at the bottom when the basement was locked does not go "down" upward.
func test_the_lock_does_not_drag_a_car_already_below() -> void:
	var motion := _shaft(2)
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 1.0, ElevatorMotion.DOWN, true), BOTTOM, 0.01)
	assert_almost_eq(_run(motion, 0.5, ElevatorMotion.UP, true), 150.0, 0.01, "up - allowed")


func test_a_one_floor_shaft_has_nothing_to_lock() -> void:
	var motion := ElevatorMotion.new()
	motion.setup(PackedFloat32Array([TOP]))
	motion.bottom_locked = true
	assert_almost_eq(_run(motion, 1.0, ElevatorMotion.DOWN, true), TOP, 0.01)


## On any seed there is no open shaft opening above the basement: each is closed by a hatch
## exactly its width, in the slab of the floor above the basement.
func test_every_shaft_into_the_basement_is_covered_on_any_seed() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var above := bottom - 1
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		var hatches := BasementLock.hatches(rules, plan)
		var into_basement := 0
		for shaft in plan.shafts:
			if shaft.bottom != bottom:
				continue
			into_basement += 1
			var covered := false
			for rect in hatches:
				covered = (
					covered
					or (
						is_equal_approx(rect.get_center().x, shaft.x)
						and is_equal_approx(rect.size.x, rules.shaft_width)
						and is_equal_approx(rect.position.y, rules.floor_surface(above))
					)
				)
			assert_true(
				covered,
				"seed %d: the shaft at x=%.1f is covered by a hatch" % [building_seed, shaft.x]
			)
		assert_gt(into_basement, 0, "seed %d: a shaft leads to the basement" % building_seed)
		assert_eq(
			hatches.size(), into_basement, "seed %d: as many hatches as shafts" % building_seed
		)


## On any seed no cab goes down to the basement while it is locked: neither by itself
## nor with a passenger. Cabs follow the layout's stops, as the level places them;
## for a double-deck pair the lower deck goes to the basement, one floor below the leading one.
func test_no_car_reaches_the_basement_on_any_seed() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	var ceiling := rules.floor_surface(bottom - 1) + ElevatorMotion.FLOOR_EPSILON
	for building_seed in range(1, SEEDS + 1):
		var plan := BuildingPlan.generate(rules, building_seed)
		for shaft in plan.shafts:
			if shaft.bottom != bottom:
				continue
			var deck := rules.floor_height if shaft.double_deck else 0.0
			var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
			var stops := PackedFloat32Array()
			for index in range(shaft.top, lowest + 1):
				stops.append(rules.floor_surface(index))
			var motion := ElevatorMotion.new()
			# A fast cab and short pauses: over the run it goes around the shaft
			# there and back more than once.
			motion.speed = 40.0
			motion.floor_pause = 0.1
			motion.setup(stops)
			motion.bottom_locked = true
			var deepest := -INF
			for frame: int in 1200:
				var driven := frame >= 600
				motion.update(1.0 / 60.0, ElevatorMotion.DOWN if driven else 0.0, driven)
				deepest = maxf(deepest, motion.position + deck)
			assert_lte(
				deepest,
				ceiling,
				(
					"seed %d: the car at x=%.1f does not go down to the basement"
					% [building_seed, shaft.x]
				)
			)


func _building(documents: int) -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 4
	rules.documents_cap = documents
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


## Whether the body is asleep for physics — not "moving slowly" but asleep.
func _sleeping(ragdoll: Ragdoll) -> bool:
	for part: PhysicalBone3D in ragdoll.parts.values():
		if not PhysicsServer3D.body_get_state(part.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING):
			return false
	return true


func _lock_of(level: GreyboxLevel) -> BasementLock:
	return level.get_node_or_null("BasementLock") as BasementLock


## The building's cabs that go down to the basement.
func _basement_cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	var basement := level.rules.floor_surface(level.rules.floors - 1)
	for child in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck() and is_equal_approx(car.bottom_reach(), basement):
			found.append(car)
	return found


func test_the_building_without_documents_leaves_the_basement_open() -> void:
	var level := await _building(0)
	var lock := _lock_of(level)
	assert_not_null(lock)
	assert_false(lock.is_locked(), "nothing to lock")
	for car in _basement_cars(level):
		assert_false(car.is_bottom_locked())


## Otto on the hatch above the basement stands rather than falls; the last document opens
## the hatch and cabs — and the same Otto falls into the basement alive: a one-floor fall.
func test_the_hatch_holds_until_the_last_document() -> void:
	var level := await _building(1)
	var lock := _lock_of(level)
	assert_true(lock.is_locked(), "document not collected - the basement is locked")
	var cars := _basement_cars(level)
	assert_gt(cars.size(), 0, "a car leads to the basement")
	for car in cars:
		assert_true(car.is_bottom_locked(), "the car does not go to the basement")

	var rules := level.rules
	var above := rules.floors - 2
	var hatch := BasementLock.hatches(rules, level.plan())[0]
	var feet := Vector2(hatch.get_center().x, rules.floor_surface(above))
	level.otto.global_position = WorldSpace.to_scene(feet - Vector2(0.0, 0.3))
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	var at := WorldSpace.to_plane(level.otto.global_position)
	assert_true(level.otto.is_grounded(), "stands on the leaves")
	assert_eq(rules.floor_index_near(at.y), above, "above the basement, not in it")

	# A jump in place: lands on the same leaves.
	Input.action_press(&"jump")
	await get_tree().physics_frame
	Input.action_release(&"jump")
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	at = WorldSpace.to_plane(level.otto.global_position)
	assert_true(level.otto.is_grounded(), "after the jump - on the leaves again")
	assert_eq(rules.floor_index_near(at.y), above, "the jump does not let him into the basement")

	assert_gt(lock.closed_hatches(), 0)
	GameState.instance().collect_document()
	assert_false(lock.is_locked(), "the last document opened the basement")
	assert_eq(lock.closed_hatches(), 0, "the leaves no longer hold")
	for car in cars:
		assert_false(car.is_bottom_locked(), "the car goes to the basement again")
	for _frame: int in FALL_FRAMES:
		await get_tree().physics_frame
	at = WorldSpace.to_plane(level.otto.global_position)
	assert_eq(rules.floor_index_near(at.y), rules.floors - 1, "fell into the basement")
	assert_false(level.otto.is_dead(), "a one-floor fall does not kill")
	assert_eq(
		lock.find_children("Hatch", "", false, false).size(),
		0,
		"the leaves parted and were removed"
	)


## A corpse asleep on the leaves falls into the basement together with them: a removed support does
## not wake a sleeping body by itself, and it would hang over the opening (ADR-0043, decision 12).
func test_a_corpse_asleep_on_the_hatch_falls_when_it_opens() -> void:
	var level := await _building(1)
	var rules := level.rules
	var above := rules.floors - 2
	var hatch := BasementLock.hatches(rules, level.plan())[0]
	var feet := WorldSpace.to_scene(Vector2(hatch.get_center().x, rules.floor_surface(above)))
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(rules)
	agent.walk_speed = 0.0
	level.add_child(agent)
	agent.global_position = Vector3(feet.x, feet.y + 0.02, WorldSpace.PLAY_Z)
	agent.setup(null, 1.0)
	while agent.is_emerging():
		await get_tree().physics_frame
	agent.kill()
	for _frame: int in SLEEP_FRAMES:
		await get_tree().physics_frame
		if _sleeping(agent.corpse.ragdoll):
			break
	var lying := agent.corpse.ragdoll.bounds().position.y
	assert_true(_sleeping(agent.corpse.ragdoll), "the corpse fell asleep")
	assert_almost_eq(lying, feet.y, 0.15, "lies on the leaves")
	GameState.instance().collect_document()
	for _frame: int in FALL_FRAMES * 2:
		await get_tree().physics_frame
	assert_lt(
		agent.corpse.ragdoll.bounds().position.y,
		lying - rules.floor_height * 0.5,
		"fell into the basement, not hanging over the opening"
	)


## Locked leaves are heavy steel, not floor tiles (M24b shot): hazard stripes along
## the edge and red indicator lights while locked; the last document puts the lights out.
func test_the_locked_hatch_reads_as_a_steel_shutter() -> void:
	var level := await _building(1)
	var lock := _lock_of(level)
	assert_gt(
		lock.find_children("Hazard*", "MeshInstance3D", true, false).size(), 0, "zebra stripes"
	)
	var lamps := lock.find_children("LockLamp*", "MeshInstance3D", true, false)
	assert_gt(lamps.size(), 0, "lock lights")
	for lamp: Node in lamps:
		assert_true((lamp as MeshInstance3D).visible, "lit while locked")
	GameState.instance().collect_document()
	for lamp: Node in lamps:
		if is_instance_valid(lamp):
			assert_false((lamp as MeshInstance3D).visible, "open - went out")


## This building's basement shaft and its cab.
func _basement_shaft(level: GreyboxLevel) -> BuildingPlan.ShaftSpot:
	for shaft in level.plan().shafts:
		if shaft.bottom == level.rules.floors - 1:
			return shaft
	return null


## Puts the cab of shaft [param shaft] at the stop of the floor above the basement.
func _park_above_the_basement(
	level: GreyboxLevel, car: ElevatorCar, shaft: BuildingPlan.ShaftSpot
) -> void:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var stops := PackedFloat32Array()
	for index in range(shaft.top, lowest + 1):
		stops.append(level.rules.floor_surface(index))
	# The locked stop is the last; the cab stops at the one before.
	car.setup(stops, stops.size() - 2)


## A passenger presses "down" in a cab above the basement — the cab stands while the basement
## is locked, and goes to the bottom when it is open.
func test_the_rider_goes_down_only_after_the_last_document() -> void:
	var level := await _building(1)
	var shaft := _basement_shaft(level)
	var car := _basement_cars(level)[0]
	if shaft.double_deck:
		pass_test("pair: the bottom tier sits above the basement, checked by the layout")
		return
	_park_above_the_basement(level, car, shaft)
	var rules := level.rules
	var above := rules.floor_surface(rules.floors - 2)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x, above - 0.05))
	Input.action_press(&"move_down")
	for _frame: int in FALL_FRAMES * 2:
		await get_tree().physics_frame
	assert_true(level.otto.is_riding(), "Otto is in the car")
	assert_almost_eq(WorldSpace.to_plane(car.global_position).y, above, 0.02, "the car stands")

	GameState.instance().collect_document()
	var basement := rules.floor_surface(rules.floors - 1)
	for _frame: int in FALL_FRAMES * 3:
		await get_tree().physics_frame
		if absf(WorldSpace.to_plane(car.global_position).y - basement) < 0.02:
			break
	Input.action_release(&"move_down")
	assert_almost_eq(
		WorldSpace.to_plane(car.global_position).y, basement, 0.02, "the car reached the basement"
	)
	var at := WorldSpace.to_plane(level.otto.global_position)
	assert_eq(rules.floor_index_near(at.y), rules.floors - 1, "and Otto with it")


## One standing on the roof of a cab above the basement does not go down: the cab turns back.
func test_the_car_roof_does_not_carry_otto_into_the_basement() -> void:
	var level := await _building(1)
	var shaft := _basement_shaft(level)
	var car := _basement_cars(level)[0]
	_park_above_the_basement(level, car, shaft)
	var rules := level.rules
	var above := rules.floor_surface(rules.floors - 2)
	var roof := (
		WorldSpace.to_plane(car.global_position).y - (rules.floor_height - rules.slab_height)
	)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x, roof - 0.05))
	var deepest := -INF
	# A pause on the floor and an attempt to go down — the empty cab turns back.
	for _frame: int in FALL_FRAMES * 4:
		await get_tree().physics_frame
		deepest = maxf(deepest, WorldSpace.to_plane(level.otto.global_position).y)
	assert_lte(deepest, above + 0.02, "Otto is not below the floor above the basement")
	assert_lte(WorldSpace.to_plane(car.global_position).y, above + 0.02, "the car too")
