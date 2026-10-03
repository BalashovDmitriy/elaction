extends GutTest

## Building intro: the helicopter brings Otto to the roof (ADR-0038, decision 1).
##
## The building is generated, and each has its own landing spot, so the essentials are
## checked on several seeds: the helicopter exists while the intro runs, Otto lands
## exactly on the landing spot and obeys, the helicopter flies away and removes itself.
## Skipping, a repositioned Otto and returning after death — on one building each.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 4, 5]

## How many frames a building gets to settle into place.
const SETTLE_FRAMES: int = 4

## How many frames to wait for the helicopter to leave the frame and remove itself: the
## departure takes about three seconds, at four times time scale — fifty frames.
const GONE_FRAMES: int = 240

## How precisely Otto stands on his spot, m: a centimetre.
const TOLERANCE: float = 0.01


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func after_each() -> void:
	for action: StringName in [&"jump", &"shoot", &"move_right"]:
		Input.action_release(action)


func _build(
	building_seed: int,
	full: bool = false,
	kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> GreyboxLevel:
	GameState.instance().start_game()
	# Each kind has its own crown above the roof (ADR-0058, decision 2): the building
	# of the needed kind is the first such in the game on this seed.
	if kind != BuildingIdentity.Kind.HOTEL:
		GameState.instance().building = BuildingIdentity.first_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	level.full_intro = full
	add_child_autofree(level)
	return level


## Seeds of the hotel [param hotel] and seeds [param others] of the office and the
## residential building: "seed — kind" pairs for tests where the crown matters.
func _seeds_and_kinds(hotel: Array[int], others: Array[int]) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	for seed_value: int in hotel:
		runs.append(Vector2i(seed_value, BuildingIdentity.Kind.HOTEL))
	for kind: BuildingIdentity.Kind in [
		BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
	]:
		for seed_value: int in others:
			runs.append(Vector2i(seed_value, kind))
	return runs


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func _landing(level: GreyboxLevel) -> Vector2:
	var roof := BuildingRules.ROOF
	return Vector2(level.plan().safe_x(level.rules, roof), level.rules.floor_surface(roof))


func _otto_at(level: GreyboxLevel) -> Vector2:
	return WorldSpace.to_plane(level.otto.global_position)


## Helicopters in the level — by node, not by the level's reference: the "left" check
## must also see one the level has already forgotten.
func _helicopters(level: GreyboxLevel) -> int:
	return level.find_children("*", "Helicopter", true, false).size()


func _wait_until_gone(level: GreyboxLevel) -> bool:
	for _frame: int in GONE_FRAMES:
		if _helicopters(level) == 0:
			return true
		await wait_physics_frames(1)
	return _helicopters(level) == 0


## Bounds of the helicopter's look in the rules plane: all its meshes together.
func _extent(helicopter: Helicopter) -> Rect2:
	var box := AABB()
	var first := true
	for node: Node in helicopter.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var part := mesh.global_transform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var top := WorldSpace.height_to_plane(box.end.y)
	return Rect2(box.position.x, top, box.size.x, box.size.y)


## On any building the helicopter brings Otto exactly to the landing spot, hands over
## control and flies away.
func test_the_helicopter_lands_otto_on_the_roof() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		var landing := _landing(level)
		assert_not_null(level.helicopter(), "сид %d: вертолёт прилетел" % building_seed)
		assert_true(
			level.is_in_the_intro(), "сид %d: здание начинается вступлением" % building_seed
		)
		assert_lt(_otto_at(level).y, landing.y, "сид %d: Otto над крышей" % building_seed)

		assert_true(await level.wait_for_the_landing(), "сид %d: Otto встал" % building_seed)
		var at := _otto_at(level)
		assert_almost_eq(at.x, landing.x, TOLERANCE, "сид %d: на месте приземления" % building_seed)
		assert_almost_eq(at.y, landing.y, TOLERANCE, "сид %d: на настиле крыши" % building_seed)
		assert_false(level.is_in_the_intro(), "сид %d: вступление кончилось" % building_seed)
		assert_true(level.otto.visible, "сид %d: Otto виден" % building_seed)

		assert_true(await _wait_until_gone(level), "сид %d: вертолёт улетел" % building_seed)
		assert_null(level.helicopter(), "сид %d: и уровень его забыл" % building_seed)
		_drop(level)


## Control handed over means Otto moved. Checked by movement, not by state: before M12
## "arrived" did not mean "released".
func test_otto_obeys_after_the_landing() -> void:
	var level := _build(1)
	await level.wait_for_the_landing()
	var before := _otto_at(level).x
	Input.action_press(&"move_right")
	await wait_physics_frames(6)
	Input.action_release(&"move_right")
	assert_gt(_otto_at(level).x, before, "Otto слушается игрока")
	_drop(level)


## The rope reaches the roof, and the helicopter with its rotor and the roof fit in the
## frame together — for a building of any kind, with any crown (ADR-0058, decision 2).
func test_the_rope_reaches_the_deck_and_the_frame_holds_both() -> void:
	for run: Vector2i in _seeds_and_kinds([1, 2, 3], [1, 2]):
		var building_seed := run.x
		var level := _build(building_seed, false, run.y as BuildingIdentity.Kind)
		var landing := _landing(level)
		var checked := false
		for _frame: int in GreyboxLevel.LANDING_PATIENCE:
			await wait_physics_frames(1)
			var helicopter := level.helicopter()
			if helicopter == null or not helicopter.rope_is_down():
				continue
			var hook := WorldSpace.to_plane(helicopter.hook())
			assert_almost_eq(hook.x, landing.x, 0.05, "сид %d: трос над местом" % building_seed)
			assert_almost_eq(
				hook.y + helicopter.rope_length(),
				landing.y,
				0.15,
				"сид %d: трос достаёт до крыши" % building_seed
			)
			var view := level.otto.camera_view()
			var extent := _extent(helicopter)
			assert_gt(extent.position.y, view.position.y, "сид %d: винт в кадре" % building_seed)
			assert_lt(landing.y, view.end.y, "сид %d: крыша в кадре" % building_seed)
			checked = true
			break
		assert_true(checked, "сид %d: трос спустился" % building_seed)
		_drop(level)


## Along the whole path — arrival, hover, departure — the helicopter passes over the roof
## equipment, not through it: neither the fuselage nor the rotor disc touches the bounds
## of any item. Seeds are chosen with a water tower by the landing spot (odd) and with a
## tank. The intro is the full one: only it has an arrival, while the hover and
## departure are the same as in the short one (ADR-0052, decision 6).
func test_the_flight_clears_everything_on_the_roof() -> void:
	for run: Vector2i in _seeds_and_kinds([1, 2, 3, 5, 7], [1, 2]):
		var building_seed := run.x
		var level := _build(building_seed, true, run.y as BuildingIdentity.Kind)
		var deck := WorldSpace.to_scene(_landing(level)).y
		var roof := RoofArrival.roof_obstacles(level, deck, [level.otto] as Array[Node])
		# First — that equipment was found at all: an empty list would always pass.
		var kit := level.find_children("*", "RoofKit", true, false)
		assert_eq(kit.size(), 1, "сид %d: на крыше есть техника" % building_seed)
		var props := 0
		for node: Node in kit[0].find_children("*", "MeshInstance3D", true, false):
			var box := (
				(node as MeshInstance3D).global_transform * (node as MeshInstance3D).mesh.get_aabb()
			)
			if roof.has(box):
				props += 1
		assert_gt(props, 3, "сид %d: техника крыши в списке помех" % building_seed)

		var hits := PackedStringArray()
		var frames := 0
		while level.helicopter() != null and frames < GreyboxLevel.LANDING_PATIENCE + GONE_FRAMES:
			var helicopter := level.helicopter()
			for part: AABB in [helicopter.hull_box(), helicopter.rotor_box()]:
				for obstacle: AABB in roof:
					if part.intersects(obstacle) and hits.size() < 5:
						hits.append(
							(
								"x %.1f, y %.1f над крышей"
								% [part.get_center().x, part.position.y - deck]
							)
						)
			await wait_physics_frames(1)
			frames += 1
		assert_eq(
			hits.size(), 0, "сид %d: вертолёт задел технику: %s" % [building_seed, ", ".join(hits)]
		)
		assert_null(level.helicopter(), "сид %d: вертолёт улетел" % building_seed)
		_drop(level)


## Helicopter sound: the hover loop and the flyby layer play from the arrival; on
## approach the flyby is louder, in the hover — the hover loop; the rope sounds while
## Otto rides it.
func test_the_helicopter_sounds_its_flight() -> void:
	# Only the full intro has an approach: in the short one the helicopter already hovers.
	var level := _build(1, true)
	await wait_physics_frames(SETTLE_FRAMES)
	var voices := _voices(level.helicopter())
	assert_true(voices.has(Sounds.HELICOPTER), "петля висения есть")
	assert_true(voices.has(Sounds.HELICOPTER_PASS), "слой пролёта есть")
	if not voices.has(Sounds.HELICOPTER) or not voices.has(Sounds.HELICOPTER_PASS):
		_drop(level)
		return
	var hover := voices[Sounds.HELICOPTER] as AudioStreamPlayer3D
	var flyby := voices[Sounds.HELICOPTER_PASS] as AudioStreamPlayer3D
	var rope := voices[Sounds.ROPE_SLIDE] as AudioStreamPlayer3D
	assert_true(hover.playing and flyby.playing, "оба слоя звучат с прилёта")
	assert_gt(flyby.volume_db, hover.volume_db, "на подлёте громче пролёт")

	var heard_rope := false
	var waits := 0
	while level.is_in_the_intro() and waits < GreyboxLevel.LANDING_PATIENCE:
		heard_rope = heard_rope or rope.playing
		await wait_physics_frames(1)
		waits += 1
	assert_true(heard_rope, "трос звучал, пока Otto ехал")
	assert_gt(hover.volume_db, flyby.volume_db, "в висении громче петля висения")
	_drop(level)


## Helicopter sounds by name: each source's stream is recognised by its file.
func _voices(helicopter: Helicopter) -> Dictionary:
	var found := {}
	for node: Node in helicopter.find_children("*", "AudioStreamPlayer3D", true, false):
		var player := node as AudioStreamPlayer3D
		for name: String in [Sounds.HELICOPTER, Sounds.HELICOPTER_PASS, Sounds.ROPE_SLIDE]:
			if player.stream == Sounds.stream(name):
				found[name] = player
	return found


## The intro is a scene, not a wait: four to six seconds until control.
func test_the_intro_takes_four_to_six_seconds() -> void:
	var level := _build(1)
	# Steps are counted by the engine, not by waits: one GUT wait can be longer than a
	# step, and counting waits underestimated the time by half.
	var start := Engine.get_physics_frames()
	var waits := 0
	while level.is_in_the_intro() and waits < GreyboxLevel.LANDING_PATIENCE:
		await wait_physics_frames(1)
		waits += 1
	var frames := Engine.get_physics_frames() - start
	var seconds := frames * Engine.time_scale / float(Engine.physics_ticks_per_second)
	assert_between(seconds, 3.8, 6.0, "вступление идёт %.2f с" % seconds)
	_drop(level)


## A jump skips the intro: Otto is on the roof at once, the helicopter leaves.
func test_a_jump_skips_the_intro() -> void:
	var level := _build(2)
	await wait_physics_frames(SETTLE_FRAMES * 3)
	assert_true(level.is_in_the_intro(), "вертолёт ещё летит")
	Input.action_press(&"jump")
	await wait_physics_frames(1)
	Input.action_release(&"jump")
	await wait_physics_frames(2)

	assert_false(level.is_in_the_intro(), "вступление пропущено")
	var landing := _landing(level)
	assert_almost_eq(_otto_at(level).x, landing.x, TOLERANCE, "Otto на месте приземления")
	assert_almost_eq(_otto_at(level).y, landing.y, TOLERANCE, "и на крыше")
	assert_true(level.otto.is_grounded(), "стоит на ногах")
	var helicopter := level.helicopter()
	if helicopter != null:
		assert_true(helicopter.is_leaving(), "вертолёт уходит")
	assert_true(await _wait_until_gone(level), "и улетает совсем")
	_drop(level)


## A shot also skips; a button held down in advance does not: skipping is by press.
func test_a_shot_skips_but_a_held_button_does_not() -> void:
	Input.action_press(&"shoot")
	var level := _build(3)
	await wait_physics_frames(SETTLE_FRAMES * 3)
	assert_true(level.is_in_the_intro(), "зажатый выстрел вступление не съел")
	Input.action_release(&"shoot")
	await wait_physics_frames(1)
	Input.action_press(&"shoot")
	await wait_physics_frames(2)
	Input.action_release(&"shoot")
	assert_false(level.is_in_the_intro(), "новое нажатие пропустило вступление")
	_drop(level)


## The press that skipped the intro ends there: Otto does not shoot or jump from the
## same button. Otherwise skipping by shot would also be a shot into nowhere, and
## skipping by jump — a jump from the landing spot.
func test_the_skipping_press_does_not_reach_otto() -> void:
	for action: StringName in [&"shoot", &"jump"]:
		var level := _build(4)
		await wait_physics_frames(SETTLE_FRAMES * 3)
		assert_true(level.is_in_the_intro(), "%s: вертолёт ещё летит" % action)
		Input.action_press(action)
		await wait_physics_frames(1)
		Input.action_release(action)
		assert_false(level.is_in_the_intro(), "%s: вступление пропущено" % action)
		for _frame: int in 3:
			assert_eq(
				level.find_children("*", "Bullet", true, false).size(),
				0,
				"%s: пропуск не стреляет" % action
			)
			assert_true(level.otto.is_grounded(), "%s: пропуск не прыгает" % action)
			await wait_physics_frames(1)
		# The next press is Otto's: skipping swallows one press, not the button.
		if action == &"shoot":
			Input.action_press(action)
			await wait_physics_frames(1)
			Input.action_release(action)
			assert_eq(
				level.find_children("*", "Bullet", true, false).size(), 1, "второе нажатие стреляет"
			)
		_drop(level)


## A repositioned Otto — by a test or a capture — ends the intro himself and stands
## where placed: that way tools work knowing nothing about the helicopter.
func test_moving_otto_ends_the_intro_where_he_was_put() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var floor_index := 5
	var spot := Vector2(
		level.plan().safe_x(level.rules, floor_index), level.rules.floor_surface(floor_index)
	)
	level.otto.global_position = WorldSpace.to_scene(spot)
	await wait_physics_frames(3)
	assert_false(level.is_in_the_intro(), "вступление кончилось")
	assert_almost_eq(_otto_at(level).x, spot.x, TOLERANCE, "Otto там, куда поставили")
	assert_almost_eq(_otto_at(level).y, spot.y, TOLERANCE, "на своём этаже")
	assert_true(level.otto.visible, "и виден")
	_drop(level)


## After death there is no helicopter: Otto returns to his floor, as before.
func test_coming_back_after_death_has_no_helicopter() -> void:
	var level := _build(1)
	level.skip_the_intro()
	await wait_physics_frames(2)
	assert_true(await _wait_until_gone(level), "вертолёт вступления улетел")

	level.otto.kill()
	var waited := 0
	while level.otto.is_dead() and waited < 120:
		await wait_physics_frames(1)
		waited += 1
	assert_false(level.otto.is_dead(), "Otto вернулся в игру")
	await wait_physics_frames(SETTLE_FRAMES)
	assert_false(level.is_in_the_intro(), "вступление не повторилось")
	assert_eq(_helicopters(level), 0, "вертолёт не прилетел")
	assert_true(level.otto.visible, "Otto виден")
	_drop(level)


## Pause during the intro skips it and does not open the menu: in a scene the "Start"
## button means "enough watching".
func test_pause_in_the_intro_skips_it_instead_of_pausing() -> void:
	var main := preload("res://src/main.tscn").instantiate()
	add_child_autofree(main)
	main._start_game()
	await wait_physics_frames(SETTLE_FRAMES)
	var level := main._level as GreyboxLevel
	assert_true(level.is_in_the_intro(), "игра началась вступлением")

	Input.action_press(&"pause")
	main._process(0.0)
	Input.action_release(&"pause")
	main._process(0.0)
	assert_false(level.is_in_the_intro(), "пауза пропустила вступление")
	assert_false(get_tree().paused, "и не поставила игру на паузу")
	assert_false((main.get_node("Menu") as Menu).visible, "меню паузы не открылось")

	Input.action_press(&"pause")
	main._process(0.0)
	Input.action_release(&"pause")
	main._process(0.0)
	assert_true(get_tree().paused, "после вступления пауза снова пауза")
	main._unpause()
	Sounds.stop_music()


## The blur disc lies in the rotation plane of its rotor (ADR-0049): for the main one —
## flat, for the tail one — upright, across its axis. The plane used to be guessed from
## the bounds, and for the two-blade tail rotor the disc lay flat and tumbled around
## the axis (code review M24i).
func test_each_rotor_blur_lies_in_its_plane_of_spin() -> void:
	var helicopter := Helicopter.new()
	autofree(helicopter)
	# The rotation axis is the one around which [Helicopter] itself spins the rotor.
	for pair: Array in [["MainRotor", Vector3.UP], ["TailRotor", Vector3.BACK]]:
		var rotor := helicopter.find_child(String(pair[0]), true, false) as Node3D
		assert_not_null(rotor, "%s есть в модели" % pair[0])
		if rotor == null:
			continue
		var disc := rotor.get_node_or_null(^"Blur") as MeshInstance3D
		assert_not_null(disc, "%s: диск размытия" % pair[0])
		if disc == null:
			continue
		# The normal of a flat mesh is its +Y: it must point along the rotor axis.
		var normal := disc.transform.basis.y.normalized()
		var axis: Vector3 = pair[1]
		assert_almost_eq(
			absf(normal.dot(axis)), 1.0, 0.001, "%s: диск в плоскости вращения" % pair[0]
		)


## The first building's full intro (ADR-0052, decision 6) — on any building: the steps
## go in order, the door is open while Otto is in the opening, the rope swings after the
## drop, Otto lands exactly on the spot, and the helicopter leaves with the door closed.
func test_the_full_intro_plays_every_step_in_order() -> void:
	for building_seed: int in [1, 3, 5]:
		var level := _build(building_seed, true)
		var arrival := level.arrival()
		assert_true(arrival.is_full(), "сид %d: вступление полное" % building_seed)
		var seen: Array[int] = []
		var swung := false
		var door_shut_in_flight := true
		# With a limit: a stalled intro is a test failure, not an endless run.
		var waits := 0
		while level.is_in_the_intro() and waits < GreyboxLevel.LANDING_PATIENCE:
			waits += 1
			var step := arrival.step()
			if seen.is_empty() or seen[seen.size() - 1] != step:
				seen.append(step)
			var helicopter := level.helicopter()
			if step == RoofArrival.Step.FLY_IN and helicopter.door_share() > 0.0:
				door_shut_in_flight = false
			if step in [RoofArrival.Step.PEEK, RoofArrival.Step.SIT, RoofArrival.Step.GRAB]:
				assert_true(helicopter.door_share() >= 1.0, "сид %d: дверь открыта" % building_seed)
			if step == RoofArrival.Step.DROP and helicopter.rope_length() > 1.0:
				var bottom := helicopter.rope_point(helicopter.rope_length())
				swung = swung or absf(bottom.x - helicopter.hook().x) > 0.02
			await wait_physics_frames(1)
		assert_false(level.is_in_the_intro(), "сид %d: вступление кончилось" % building_seed)
		var order: Array[int] = []
		for step: int in RoofArrival.Step.values():
			if step != RoofArrival.Step.DONE:
				order.append(step)
		assert_eq(seen, order, "сид %d: шаги по порядку" % building_seed)
		assert_true(door_shut_in_flight, "сид %d: подлетает с закрытой дверью" % building_seed)
		assert_true(swung, "сид %d: сброшенный трос качается" % building_seed)
		await level.wait_for_the_landing()
		var landing := _landing(level)
		assert_almost_eq(
			_otto_at(level).x, landing.x, TOLERANCE, "сид %d: на месте" % building_seed
		)
		assert_almost_eq(
			_otto_at(level).y, landing.y, TOLERANCE, "сид %d: на крыше" % building_seed
		)
		var helicopter := level.helicopter()
		var frames := 0
		while (
			helicopter != null
			and not helicopter.position.x > _otto_at(level).x + 2.0
			and frames < GONE_FRAMES
		):
			await wait_physics_frames(1)
			frames += 1
			helicopter = level.helicopter()
		if helicopter != null:
			assert_eq(
				helicopter.door_share(), 0.0, "сид %d: уходит с закрытой дверью" % building_seed
			)
			assert_eq(helicopter.rope_length(), 0.0, "сид %d: и с выбранным тросом" % building_seed)
		_drop(level)


## The full intro is a 10–12 second scene until control (ADR-0052).
func test_the_full_intro_takes_ten_to_twelve_seconds() -> void:
	var level := _build(1, true)
	var start := Engine.get_physics_frames()
	var waits := 0
	while level.is_in_the_intro() and waits < GreyboxLevel.LANDING_PATIENCE:
		await wait_physics_frames(1)
		waits += 1
	var frames := Engine.get_physics_frames() - start
	var seconds := frames * Engine.time_scale / float(Engine.physics_ticks_per_second)
	assert_between(seconds, 9.5, 12.5, "полное вступление идёт %.2f с" % seconds)
	_drop(level)


## Short intro: from the first frame the helicopter hovers with the door open.
func test_the_short_intro_starts_hovering_with_the_door_open() -> void:
	var level := _build(2)
	await wait_physics_frames(2)
	var helicopter := level.helicopter()
	assert_false(level.arrival().is_full(), "вступление короткое")
	assert_true(helicopter.is_hovering(), "вертолёт уже висит")
	assert_true(helicopter.door_share() >= 1.0, "и дверь открыта")
	assert_true(level.otto.visible, "Otto виден в проёме")
	_drop(level)


## The pilot sits behind the glazing: in the cabin, above the floor and below the
## ceiling, near the nose.
func test_the_pilot_sits_in_the_cockpit() -> void:
	var helicopter := Helicopter.new()
	add_child_autofree(helicopter)
	await wait_physics_frames(3)
	var pilot := helicopter.find_child("Pilot", true, false) as FigureRig
	assert_not_null(pilot, "пилот есть")
	if pilot == null:
		return
	pilot.snap()
	var box := pilot.skinned_aabb()
	var at := pilot.global_transform * box
	var hull := helicopter.hull_box()
	assert_gt(at.position.y, hull.position.y, "ступни пилота выше днища")
	assert_lt(at.end.y, hull.end.y, "голова пилота ниже крыши")
	assert_gt(at.get_center().x, helicopter.doorway().x, "пилот впереди двери")
