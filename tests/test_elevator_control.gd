extends GutTest

## Every cab of the building obeys the player.
##
## Feedback after playing: "on some elevators the controls did not work — the cab
## did not obey commands and stood still, and once you stepped off, it drove away". So the
## check is not about one cab from a scene but about all that the generator builds:
## not all of them had the bug.
##
## Heights are compared in the rules plane, where down is growing Y: this is how the cab
## computed in 2D, and this way the assertions below stayed untouched in the move.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many frames the building gets to settle into place.
const SETTLE_FRAMES: int = 4

## How many frames to hold a command. The cab goes 1.8 m/s, a floor is 3.6 m:
## in half a second it must move noticeably.
const DRIVE_FRAMES: int = 30

## How far the cab must move for it to count as "obeys", m.
const MOVED: float = 0.2

## Coordinate match tolerance, m: for floating-point arithmetic, and only for it.
const TOLERANCE: float = 0.01


func before_all() -> void:
	Engine.time_scale = 1.0


func after_all() -> void:
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Cabs with their own drive — one per shaft, in shaft order.
##
## Decks of two-floor pairs ([method ElevatorCar.is_deck]) are not included: they have
## no drive of their own, they hold on to the leading one, and putting them on stops by hand
## is pointless. Since M18b there are one or two more of them in the tree than shafts, and
## the count by order fell apart without this filter (ADR-0025, decision 1).
func _cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck():
			found.append(car)
	return found


## Pair decks: one per two-floor shaft.
func _decks(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and car.is_deck():
			found.append(car)
	return found


## Cab height in the rules plane.
func _height(car: ElevatorCar) -> float:
	return WorldSpace.to_plane(car.global_position).y


## How visible the indicator is: the box is dimmed by transparency.
func _alpha(arrow: MeshInstance3D) -> float:
	return 1.0 - arrow.transparency


## Puts Otto inside the cab and waits until it notices him.
func _get_in(level: GreyboxLevel, car: ElevatorCar) -> void:
	level.otto.global_position = car.global_position
	level.otto.velocity = Vector3.ZERO
	await wait_physics_frames(SETTLE_FRAMES)


## Puts the cab on the needed floor of its band.
##
## Via [method ElevatorCar.setup], not via the coordinate: the cab drive has its own
## state, and moved by hand it returns to where it thinks it is.
func _park(
	level: GreyboxLevel, car: ElevatorCar, shaft: BuildingPlan.ShaftSpot, index: int
) -> void:
	var stops := PackedFloat32Array()
	for floor_index: int in range(shaft.top, shaft.bottom + 1):
		stops.append(level.rules.floor_surface(floor_index))
	car.setup(stops, index - shaft.top)
	# The cab moves itself to the coordinate on its own frame: until it has passed, it
	# stands where it stood, and someone entering it would end up at the old place.
	await wait_physics_frames(1)


func _drive(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(DRIVE_FRAMES)
	Input.action_release(action)
	await wait_physics_frames(1)


func test_every_car_obeys_the_player() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var shafts := level.plan().shafts
		var cars := _cars(level)
		# Cabs stand in the tree in shaft order — the level places them that way. The order
		# is promised nowhere, but the test relies on it: a mixed-up pair would silently
		# put a cab on someone else's stops, and the check would turn green
		# without checking anything.
		assert_eq(
			cars.size(), shafts.size(), "сид %d: кабин не столько, сколько шахт" % building_seed
		)
		var pairs := 0
		for shaft in shafts:
			if shaft.double_deck:
				pairs += 1
		assert_eq(
			_decks(level).size(),
			pairs,
			"сид %d: ярусов не столько, сколько двухэтажных шахт" % building_seed
		)
		for index: int in cars.size():
			var shaft: BuildingPlan.ShaftSpot = shafts[index]
			var number := index + 1
			assert_almost_eq(
				WorldSpace.to_plane(cars[index].global_position).x,
				shaft.x,
				TOLERANCE,
				"сид %d, кабина %d: встала не в своей шахте" % [building_seed, number]
			)
			# The cab is put at the top of its band rather than taken where the run
			# found it. An empty cab rides on its own, and it can be found
			# at the bottom stop — then "did not go down on command" would mean
			# "there was nowhere to go", i.e. the test would fail now and then on different
			# seeds without any breakage.
			var car: ElevatorCar = cars[index]
			await _park(level, car, shaft, shaft.top)
			await _get_in(level, car)
			assert_true(
				level.otto.is_riding(),
				(
					"сид %d, кабина %d: Otto внутри, а кабина этого не заметила"
					% [building_seed, number]
				)
			)

			var before := _height(car)
			await _drive(&"move_down")
			var moved := _height(car) - before
			assert_gt(
				moved,
				MOVED,
				(
					"сид %d, кабина %d на %.2f: не поехала вниз по команде (сдвинулась на %.2f м)"
					% [building_seed, number, before, moved]
				)
			)
		_drop(level)


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## A cab at the edge of its band goes no further — and this is not a breakage but how
## the shafts work: they do not go through (ADR-0008). But it must go up.
##
## The feedback after playing looked exactly like this: "does not obey and stands, stepped
## off — it drove away". A cab standing at its limit behaves exactly so, and the test keeps
## this behaviour described, so that next time it is not fixed as a bug.
func test_car_at_the_end_of_its_band_still_goes_the_other_way() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	# We put the cab on the bottom floor of its band and Otto into it.
	await _park(level, car, shaft, shaft.bottom)
	await _get_in(level, car)

	var before := _height(car)
	await _drive(&"move_down")
	assert_almost_eq(_height(car), before, MOVED, "ниже своей полосы кабина не идёт")

	await _drive(&"move_up")
	assert_lt(_height(car), before - MOVED, "а вверх — идёт")
	_drop(level)


## Otto enters the cab by a step, like a player, rather than appearing in it.
##
## Entering by a step is the only way it happens in the game, and it is on it that the cab
## once stopped obeying: it considered itself occupied but received no commands.
func test_car_obeys_after_otto_walks_in() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	# The cab stands on the top floor of the band, Otto next to the opening on the same floor.
	var index := maxi(shaft.top, 0)
	var surface := rules.floor_surface(index)
	await _park(level, car, shaft, index)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x - rules.shaft_width, surface))
	await wait_physics_frames(SETTLE_FRAMES)

	# We walk right until we end up in the cab.
	Input.action_press(&"move_right")
	var left := 120
	while not level.otto.is_riding() and left > 0:
		await wait_physics_frames(1)
		left -= 1
	Input.action_release(&"move_right")
	await wait_physics_frames(1)
	assert_true(level.otto.is_riding(), "Otto вошёл в кабину шагом")

	var before := _height(car)
	await _drive(&"move_down")
	assert_gt(_height(car) - before, MOVED, "вошедшего шагом кабина слушается так же")
	_drop(level)


## The indicator in the cab goes dark where the band ends.
##
## This is the second half of the answer to "the elevator does not obey": a stop in the
## shaft shows the limit from outside, the arrow — from inside the cab, where the stop is
## not visible.
func test_car_arrow_goes_dark_at_the_end_of_the_band() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	var down := car.get_node("DownArrow") as MeshInstance3D
	var up := car.get_node("UpArrow") as MeshInstance3D

	await _park(level, car, shaft, shaft.bottom)
	await wait_physics_frames(1)
	assert_lt(_alpha(down), 0.5, "внизу полосы стрелка вниз погасла")
	assert_almost_eq(_alpha(up), 1.0, 0.01, "а вверх — горит")

	await _park(level, car, shaft, shaft.top)
	await wait_physics_frames(1)
	assert_lt(_alpha(up), 0.5, "наверху полосы гаснет стрелка вверх")
	assert_almost_eq(_alpha(down), 1.0, 0.01, "а вниз — горит")
	_drop(level)
