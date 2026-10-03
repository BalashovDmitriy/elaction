extends GutTest

## Tests of agents riding in cabs (ADR-0025, decision 6).
##
## In the original agents ride but do not control the cab: "When Otto is not in
## an elevator, it will move from floor to floor automatically, even when enemy
## spies are in it". Hence the whole design: an agent walks to the cab that already
## stands level with his floor and rides as a passenger. Nobody has a call.
##
## Tests with a scene and physics are the most expensive level of checking
## ([`testing.md`](../docs/testing.md)), so there are exactly two here: one that
## the agent arrives, the other that he does not take control away from Otto.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## How many frames to give the building to assemble.
const SETTLE_FRAMES: int = 10

## Cap on waiting for a ride, physics steps. The cab runs by itself and stands on a floor
## for a second and a half, so the agent may not catch it at once.
const RIDE_FRAMES: int = 1800

## Seed of the agent's decisions: wandering pauses and turns. Any — the ride does not
## depend on them; seeded so the run repeats.
const AGENT_SEED: int = 1


func _build() -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	# Their own doors do not release agents: the frame must have one, placed
	# by the test, not eight that came out on schedule.
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## A longer podium shaft: that is the one ridden.
##
## Not the longest in the building: that one runs from the roof, and at the top the floor is narrow
## — seven slots, including a shaft, a door and a lamp — and the agent has no room there to pass the
## opening.
func _a_shaft_to_ride(level: GreyboxLevel) -> BuildingPlan.ShaftSpot:
	var best: BuildingPlan.ShaftSpot = null
	for shaft in level.plan().shafts:
		if shaft.top <= level.rules.wide_from:
			continue
		if best == null or shaft.height() > best.height():
			best = shaft
	return best


## An agent who lost Otto one floor down comes to him by elevator.
##
## Before M18b he would have stayed on his floor forever: in all of `src/` `ElevatorCar`
## knew only Otto, and the debt dragged on since ADR-0006.
func test_an_agent_rides_down_to_otto() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var shaft := _a_shaft_to_ride(level)
	assert_not_null(shaft, "на сиде 1 есть шахта стилобата, по которой ездят")
	if shaft == null:
		return
	var from_index := shaft.top + 1
	var to_index := shaft.bottom
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(rules, to_index), rules.floor_surface(to_index))
	)

	# The agent comes out when the cab is already standing level with his floor, and right at its
	# opening. Before, he came out at once and caught the cab while wandering the floor: whether he
	# catches it in the second and a half of standing was decided by his pauses and turns — a draw,
	# an unseeded one at that. The M24b layout shifted neighbouring shafts, and the test began
	# passing every other time. What is checked is the ride, not luck in wandering.
	var standing := false
	for _step in RIDE_FRAMES:
		if _car_standing_at(level, shaft.x, from_index):
			standing = true
			break
		await wait_physics_frames(1)
	assert_true(standing, "кабина шахты %.1f встала на этаже %d" % [shaft.x, from_index])

	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(
		Vector2(shaft.x - rules.shaft_width, rules.floor_surface(from_index))
	)
	# Seeded the way the level seeds its own ([method GreyboxLevel._release_agent]):
	# an unseeded generator would give each run its own wandering pauses.
	agent.seed_decisions(AGENT_SEED)
	agent.setup(level.otto, 1.0)

	var lowest := from_index
	for _step in RIDE_FRAMES:
		await wait_physics_frames(1)
		var where := rules.floor_index_near(WorldSpace.to_plane(agent.global_position).y)
		lowest = maxi(lowest, where)
		if where >= to_index:
			break

	# Two floors down is precisely a ride. On foot the agent cannot get down: at the slab
	# edge he turns around, and an escalator starts only on a press,
	# which he does not have (ADR-0005, point 8).
	assert_gte(
		lowest,
		from_index + 2,
		"агент с этажа %d так и не уехал вниз к Otto на %d" % [from_index, to_index]
	)
	assert_false(agent.is_dead(), "ехал, а не падал в шахту")


## An agent in a cab does not control it: it runs on its own schedule, like an empty one.
##
## That is the whole difference between "rides" and "drives". Controlling the cab is Otto's
## privilege, and in the original even one standing on the roof does not have it.
func test_an_agent_aboard_does_not_drive() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var shaft := _a_shaft_to_ride(level)
	assert_not_null(shaft, "на сиде 1 есть шахта стилобата, по которой ездят")
	if shaft == null:
		return
	var index := shaft.top
	# Otto is far away: the agent in the cab must not gain power over it under any
	# circumstances, but the frame must not also turn into a shootout.
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(rules, rules.floors - 1), rules.floor_surface(rules.floors - 1))
	)

	var agent := ENEMY_SCENE.instantiate() as Enemy
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(shaft.x, rules.floor_surface(index)))
	agent.setup(level.otto, 1.0)
	await wait_physics_frames(SETTLE_FRAMES)

	var car := _car_in_column(level, shaft.x)
	assert_not_null(car, "в шахте %.1f стоит кабина" % shaft.x)
	if car == null:
		return
	# An empty cab goes from floor to floor with a pause on each. An agent inside
	# changes nothing in this: it does not stop and does not speed up.
	#
	# It is also checked that the agent really was inside all this time:
	# without this "the cab runs by itself" would also hold for an empty shaft, that is,
	# it would not check exactly what the test was written for.
	var moved := 0
	var aboard := 0
	for _step in 240:
		await wait_physics_frames(1)
		if not car.is_aligned():
			moved += 1
		# A tolerance of the whole shaft width, not half: inside the cab the agent
		# steps from wall to wall, and the measure must tell "rides"
		# from "walked off along the floor", not catch his steps.
		if absf(WorldSpace.to_plane(agent.global_position).x - shaft.x) <= rules.shaft_width:
			aboard += 1
	assert_gt(moved, 0, "кабина с агентом внутри продолжает ходить сама")
	assert_eq(aboard, 240, "агент все эти кадры ехал в кабине, а не ушёл по этажу")


## Whether a cab stands level with floor [param index] in shaft [param x].
func _car_standing_at(level: GreyboxLevel, x: float, index: int) -> bool:
	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null or absf(car.position.x - x) >= 0.1 or not car.is_aligned():
			continue
		if level.rules.floor_index_near(WorldSpace.to_plane(car.global_position).y) == index:
			return true
	return false


func _car_in_column(level: GreyboxLevel, x: float) -> ElevatorCar:
	for child in level.get_children():
		var car := child as ElevatorCar
		if car != null and absf(car.position.x - x) < 0.1:
			return car
	return null
