extends GutTest

## Otto at a shaft with a cab heading to his floor never freezes together with it
## (ADR-0037, decision 1).
##
## Feedback after M23: Otto became a passenger as soon as his body entered the opening, though
## the cab was still a couple of metres below the floor. An occupied cab without a command stands,
## and one cannot step out of it off level — both stood forever. Same with
## a cab from above and with a double-deck pair. So the check runs on any building:
## on several seeds, at each shaft, with the cab below and above. One of two
## outcomes is allowed: Otto can walk (he is not in a cab or the cab is level
## with the floor) or he died. He must not freeze in a cab between floors.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3]

## How many frames the building is given to settle into place, and Otto — to stand.
const SETTLE_FRAMES: int = 4

## How far from the floor the cab is when Otto sets off to the shaft, m.
##
## Two distances, alternating from shaft to shaft. Near — Otto approaches when
## the cab has almost arrived: from below he steps onto its floor, from above he hits its underside.
## Far — the cab is still a metre away: from below he hits its roof or falls onto the cab's
## floor, from above — into its underside. It was with the far one that Otto boarded the cab in M23.
const TRIGGERS: Array[float] = [1.3, 0.6]

## How far from the shaft edge Otto stands waiting for the cab, m, edge to body edge.
const WAIT_GAP: float = 0.4

## How many bot steps to wait for the cab to reach the distance: the pause on a floor
## and the run, with margin.
const APPROACH_STEPS: int = 200

## How many steps Otto walks to the shaft before the outcome counts as settled:
## the cab arrives, stands its pause, he enters — a couple of seconds under time_scale 4.
const WALK_STEPS: int = 90

## How many steps in a row a passenger may stand in a cab between floors before
## it counts as freezing. A cab in transit does not stand a single step.
const FROZEN_STEPS: int = 20

## How many steps to wait for the level to return a dead Otto to play.
const RESPAWN_STEPS: int = 120


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Cabs with their own motion — one per shaft, in shaft order.
func _cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck():
			found.append(car)
	return found


## Stops of the leading cab — the same way the level counts them: the upper deck of a pair
## does not go down to the shaft's bottom floor.
func _stops(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot) -> PackedFloat32Array:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var stops := PackedFloat32Array()
	for index: int in range(shaft.top, lowest + 1):
		stops.append(level.rules.floor_surface(index))
	return stops


## Where the cab that will reach Otto's floor first stands, and which floor that is.
##
## From below — the leading one from its bottom stop, to the floor above it. From above — from
## the top, to the floor below; for a pair a deck stands one floor below the leading one, and it
## reaches the floor first — so Otto's floor is one more below. A short run
## has nothing to check: an empty vector.
func _approach(shaft: BuildingPlan.ShaftSpot, from_below: bool) -> Vector2i:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var deck := 1 if shaft.double_deck else 0
	if from_below:
		var start := lowest
		var target := start - 1 - deck
		return Vector2i(start, target) if target >= shaft.top else Vector2i(-99, -99)
	var target := shaft.top + 1 + deck
	return Vector2i(shaft.top, target) if target <= shaft.bottom else Vector2i(-99, -99)


func _plane(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## Places Otto at the shaft on floor [param index], on the side that has floor.
## Returns the side, -1 or +1, or 0 if there is no floor at the shaft on either side.
func _stand_by(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot, index: int) -> float:
	var surface := level.rules.floor_surface(index)
	var aside := level.rules.shaft_width * 0.5 + Proportions.BODY_WIDTH * 0.5 + WAIT_GAP
	for side: float in [-1.0, 1.0]:
		level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x + side * aside, surface))
		level.otto.velocity = Vector3.ZERO
		await wait_physics_frames(SETTLE_FRAMES)
		var at := _plane(level.otto)
		if level.otto.is_grounded() and absf(at.y - surface) < 0.05:
			return side
	return 0.0


## Returns a dead Otto to play by the level's hands and waits until it has done so.
func _wait_for_respawn(level: GreyboxLevel) -> void:
	var left := RESPAWN_STEPS
	while level.otto.is_dead() and left > 0:
		await wait_physics_frames(1)
		left -= 1


func test_otto_never_freezes_with_an_arriving_car() -> void:
	var checked := 0
	var boarded := 0
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)
		var shafts := level.plan().shafts
		var cars := _cars(level)
		assert_eq(
			cars.size(), shafts.size(), "сид %d: кабин не столько, сколько шахт" % building_seed
		)
		for index: int in cars.size():
			for from_below: bool in [true, false]:
				var shaft: BuildingPlan.ShaftSpot = shafts[index]
				var plan := _approach(shaft, from_below)
				if plan.y == -99:
					continue
				var where := (
					"сид %d, шахта %d, кабина %s, этаж %d"
					% [building_seed, index + 1, "снизу" if from_below else "сверху", plan.y]
				)
				var outcome := await _meet(
					level, cars[index], shaft, plan, TRIGGERS[(index + int(from_below)) % 2], where
				)
				if outcome < 0:
					continue
				checked += 1
				boarded += outcome
		remove_child(level)
	# A check that never fired checks nothing.
	assert_gt(checked, 10, "встреч с кабиной проверено слишком мало: %d" % checked)
	assert_gt(boarded, 5, "Otto сел в подошедшую кабину слишком редко: %d" % boarded)


## One encounter: the cab heads to Otto's floor, he sets off to the shaft at the distance.
##
## Returns 1 if Otto boarded the cab level with the floor, 0 — if the outcome
## was different but allowed, and -1 if the encounter could not be set up.
func _meet(
	level: GreyboxLevel,
	car: ElevatorCar,
	shaft: BuildingPlan.ShaftSpot,
	plan: Vector2i,
	trigger: float,
	where: String
) -> int:
	GameState.instance().lives = GameState.STARTING_LIVES
	await _wait_for_respawn(level)
	var otto := level.otto
	# First Otto stands, then the cab is placed: while he looks for the floor, an empty
	# cab would manage to leave.
	var side := await _stand_by(level, shaft, plan.y)
	if side == 0.0:
		return -1
	var stops := _stops(level, shaft)
	car.setup(stops, plan.x - shaft.top)
	await wait_physics_frames(1)

	var surface := level.rules.floor_surface(plan.y)
	var left := APPROACH_STEPS
	while absf(_plane(car).y - surface) > trigger + _deck_drop(level, shaft, plan) and left > 0:
		await wait_physics_frames(1)
		left -= 1
	if left == 0:
		fail_test("%s: кабина не подошла к этажу" % where)
		return -1

	var toward := &"move_left" if side > 0.0 else &"move_right"
	Input.action_press(toward)
	var stuck := 0
	var boarded := false
	for _step: int in WALK_STEPS:
		await wait_physics_frames(1)
		if otto.is_dead():
			break
		if otto.is_riding() and car.is_aligned():
			boarded = true
			break
		if otto.is_riding() and car.speed_now() == 0.0:
			stuck += 1
		else:
			stuck = 0
		if stuck >= FROZEN_STEPS:
			break
	Input.action_release(toward)
	await wait_physics_frames(1)

	var frozen := otto.is_riding() and not car.is_aligned()
	assert_false(
		frozen,
		(
			"%s: Otto застыл в кабине между этажами (кабина в %.2f м от этажа)"
			% [where, _plane(car).y - surface]
		)
	)
	return 1 if boarded else 0


## How much lower than the leading one stands the cab that will reach Otto's floor: for a pair
## from above the deck arrives first, and the distance to the floor must be counted by it.
func _deck_drop(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot, plan: Vector2i) -> float:
	if not shaft.double_deck or plan.y < plan.x:
		return 0.0
	# The leading one comes from above, the deck is one floor below it: it is one floor further
	# from Otto's floor than the deck.
	return level.rules.floor_height
