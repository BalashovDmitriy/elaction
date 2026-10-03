extends GutTest

## Darkness by the ADR-0023 rules: Otto's shadow decides, a blind agent patrols,
## behind a door Otto is invisible. With a scene: the building is real by the rules, the
## agent is placed by hand: there must be exactly one in the frame, and where is known.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## How many frames an agent gets for a shot. Windup 0.35 s, pause 1.1 s: two
## seconds of game time are enough both for a shot and for making sure there is
## none.
const WATCH_FRAMES: int = 120

## How many frames to wait for a lamp to fall.
const FALL_FRAMES: int = 240


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func _build() -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## The duel floor: wide, spanning the full building width (it has three lamps and spots
## for any range), and not the bottom one, where the exit is.
##
## Not strictly the third from the bottom but the first wide one from the bottom where a
## pair of spots was found ([method _pair_on]): the layout changes from milestone to
## milestone, and on M18c a wall fell onto that very floor so that no pair was left on
## it. The test then silently took one spot twice and checked the wrong thing.
##
## It is chosen once per building and remembered: the pair is searched by hanging lamps,
## and after a lamp is knocked down the search would return a different floor.
func _floor(level: GreyboxLevel) -> int:
	if level.has_meta(&"duel_floor"):
		return level.get_meta(&"duel_floor") as int
	var rules := level.rules
	var chosen := rules.floors - 3
	for index in range(rules.floors - 3, rules.wide_from - 1, -1):
		var pair := _pair_on(level, index)
		if pair.x != pair.y:
			chosen = index
			break
	level.set_meta(&"duel_floor", chosen)
	return chosen


## The floor's lamp nearest to the point.
func _lamp_near(level: GreyboxLevel, floor_index: int, x: float) -> Lamp:
	var found: Lamp = null
	var gap := INF
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp == null or lamp.floor_index != floor_index:
			continue
		var distance := absf(WorldSpace.to_plane(lamp.global_position).x - x)
		if distance < gap:
			gap = distance
			found = lamp
	return found


## Whether the point stands almost midway between two lamps, where the zone
## is not unambiguously defined.
func _on_a_border(level: GreyboxLevel, floor_index: int, x: float) -> bool:
	var gaps: Array[float] = []
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == floor_index:
			gaps.append(absf(WorldSpace.to_plane(lamp.global_position).x - x))
	gaps.sort()
	return gaps.size() > 1 and gaps[1] - gaps[0] < 0.1


## Knocks out a lamp's zone and waits for it to finish falling.
func _put_out(lamp: Lamp) -> void:
	lamp.shoot_down()
	var left := FALL_FRAMES
	while is_instance_valid(lamp) and left > 0:
		left -= 1
		await wait_physics_frames(1)
	await wait_physics_frames(2)


## Puts Otto on the floor at point x.
func _place_otto(level: GreyboxLevel, x: float) -> void:
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(x, level.rules.floor_surface(_floor(level)))
	)
	level.otto.velocity = Vector3.ZERO


## An agent in place, facing Otto. He stands still: he has no movement, so that the
## duel depends only on whether he can see.
func _agent_at(level: GreyboxLevel, x: float, towards: float, walks: bool = false) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(level.rules)
	if not walks:
		agent.walk_speed = 0.0
	level.add_child(agent)
	if not walks:
		# A standing agent wanders in place and turns whichever way, and
		# by the ROM he shoots only when facing Otto. An alarm lifts this condition:
		# the check here is about whether he sees Otto, not where he looks.
		agent.alert_for(1.0e6)
	agent.global_position = WorldSpace.to_scene(
		Vector2(x, level.rules.floor_surface(_floor(level)))
	)
	agent.setup(level.otto, towards)
	return agent


## How many enemy bullets appeared during the observation.
func _shots_within(level: GreyboxLevel, frames: int) -> int:
	var seen: Dictionary = {}
	for _frame in frames:
		await wait_physics_frames(1)
		for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
			var bullet := node as Bullet
			if bullet != null and bullet.collision_mask == Bullet.FROM_ENEMY:
				seen[bullet.get_instance_id()] = true
	return seen.size()


## A spot under a lamp and another within shot range, but beyond the range in darkness.
## A pair of floor spots: the first gets knocked out, the second stays lit.
##
## The spots are taken **from different zones** and within shot range of each other.
## They cannot be taken from one zone: the knocked-out one covers both, and "from the
## shadow at the lit one" would check the wrong thing. Previously the first spot was
## simply placed under a lamp and the second two to five meters from it; on the fine
## M18 grid both started falling into one zone, and the check fell apart. Now the pair
## is searched across a zone border: right at the border neighboring zones meet closely,
## and the shot range fits there.
func _spot_pair(level: GreyboxLevel) -> Vector2:
	return _pair_on(level, _floor(level))


func _pair_on(level: GreyboxLevel, index: int) -> Vector2:
	var rules := level.rules
	var spots := level.plan().safe_spots(rules, index)
	var closest := rules.agent_dark_fire_range * 1.5
	# There is no fire range, only the frame (ADR-0027, decision 3a): the pair must
	# fit into it together with Otto standing on one of the spots.
	var furthest := SideCamera.DEFAULT_HALF_HEIGHT * 16.0 / 9.0 * 0.9

	for here: float in spots:
		for there: float in spots:
			var gap := absf(here - there)
			if gap <= closest or gap >= furthest:
				continue
			if _lamp_near(level, index, here) == _lamp_near(level, index, there):
				continue
			# A spot exactly on the zone border is a tie, decided by the last bit of the fraction:
			# the test and the lighting resolved it in different directions. On M18c the border
			# fell exactly onto a grid spot (13.2 between lamps 6.0 and 20.4).
			if _on_a_border(level, index, here) or _on_a_border(level, index, there):
				continue
			# A wall between the spots makes the agent blind, and rightly so
			# (ADR-0024, decision 5). The check here is about darkness, not walls,
			# and the pair must stand on one side of it. Without this the test would fail
			# on the seeds where a wall fell onto the duel floor: "lit Otto
			# gets shot at" would turn into "behind a wall he does not get shot at".
			if level.plan().wall_between(index, here, there):
				continue
			return Vector2(here, there)
	return Vector2(spots[0], spots[0])


## An agent gets a lit Otto from full range: it was so and stays so.
func test_a_lit_otto_is_shot_from_afar() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "the floor has two spots at shot range")
	_place_otto(level, pair.x)
	_agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_gt(await _shots_within(level, WATCH_FRAMES), 0, "a lit Otto gets shot at")
	remove_child(level)


## An agent does not see Otto in the shadow from afar and does not shoot; closer, he sees.
func test_an_otto_in_the_dark_is_seen_only_up_close() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "a pair of duel spots was found")
	_place_otto(level, pair.x)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	assert_true(level.is_dark_at(_floor(level), pair.x), "zone under Otto went dark")

	var agent := _agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_eq(
		await _shots_within(level, WATCH_FRAMES), 0, "Otto in shadow is not visible from this range"
	)

	# Now the agent approaches Otto to a range from which he is visible even in darkness.
	#
	# The agent approaches, not Otto: on the fine M18 grid a step toward the agent took Otto
	# out of the shadow into the agent's lit zone, and what was checked was no longer
	# "in the shadow at close range". And a hit is counted by Otto's death, not by bullets:
	# from a meter the bullet arrives in the same physics step in which it was fired, and
	# the bullet count does not see it.
	agent.queue_free()
	var close := _floor_beside(level, pair.x, level.rules.agent_dark_fire_range * 0.6)
	assert_false(is_nan(close), "there is floor next to Otto for the agent to stand on")
	_agent_at(level, close, signf(pair.x - close))
	var hit := [false]
	level.otto.died.connect(func() -> void: hit[0] = true)
	await wait_physics_frames(WATCH_FRAMES)
	assert_true(level.is_dark_at(_floor(level), pair.x), "Otto still stands in shadow")
	assert_true(hit[0], "point-blank he is seen even in shadow")
	remove_child(level)


## A floor spot at [param reach] from [param x] on the duel floor, in either direction,
## where the agent has something to stand on. NAN if there is none.
func _floor_beside(level: GreyboxLevel, x: float, reach: float) -> float:
	var rules := level.rules
	var index := _floor(level)
	var half := Proportions.BODY_WIDTH * 0.5
	for side: float in [-1.0, 1.0]:
		var at := x + side * reach
		var clear := true
		for block: Vector2 in level.plan().blocks_on(rules, index):
			if at + half > block.x and at - half < block.y:
				clear = false
		if clear and not level.plan().wall_between(index, x, at):
			return at
	return NAN


## The agent's shadow decides nothing: from the shadow a lit Otto is visible.
func test_an_agent_in_the_dark_still_sees_a_lit_otto() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "a pair of duel spots was found")
	_place_otto(level, pair.y)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	# The duel relies on Otto staying under a burning lamp: the zones are narrow, and the
	# second spot could fall into the same knocked-out one, and then the wrong thing would
	# be checked.
	assert_false(level.is_dark_at(_floor(level), pair.y), "Otto stands in a lit zone")
	var agent := _agent_at(level, pair.x, signf(pair.y - pair.x))
	# The shadow is checked before the duel, not after: an agent who hits kills Otto, and
	# Otto, returning per the ROM, takes all living agents off the floor (ADR-0053,
	# decision 2), so by the end of the observation this agent is gone.
	await wait_physics_frames(1)
	assert_true(agent.is_in_the_dark(), "agent stands in shadow")
	var shots := await _shots_within(level, WATCH_FRAMES)
	assert_gt(shots, 0, "and still sees the lit Otto")
	remove_child(level)


## Otto is not behind the door: agents lose him, as in the original (M14 debt).
func test_agents_lose_otto_behind_a_door() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "a pair of duel spots was found")
	_place_otto(level, pair.x)
	level.otto.stay_indoors(true)
	_agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_eq(await _shots_within(level, WATCH_FRAMES), 0, "a hidden target is not shot at")
	level.otto.stay_indoors(false)
	assert_gt(await _shots_within(level, WATCH_FRAMES), 0, "stepped out — a target again")
	remove_child(level)


## A blind agent does not guard the floor edge but walks along it back and forth.
func test_a_blind_agent_patrols_the_floor() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "a pair of duel spots was found")
	_place_otto(level, pair.x)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	# The agent walks away from Otto, to the floor edge.
	var away := signf(pair.y - pair.x)
	var agent := _agent_at(level, pair.y, away, true)
	var turned := false
	for _frame in FALL_FRAMES * 2:
		await wait_physics_frames(1)
		if agent.is_dead():
			break
		if agent.facing() == -away:
			turned = true
			break
	assert_true(turned, "reached the edge and turned around")
	remove_child(level)
