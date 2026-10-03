extends GutTest

## Demo mode (ADR-0041): start points, launch on menu inactivity, end on any press and the bottom
## point with the basement open.

const MAIN_SCENE := preload("res://src/main.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_each() -> void:
	get_tree().paused = false
	GameState.instance().reset()
	Sounds.stop_music()


# --- Rule ----------------------------------------------------------------------


func test_the_points_go_round() -> void:
	var point := DemoPlan.Point.ROOF
	var seen: Array[int] = []
	for _round: int in DemoPlan.Point.size():
		seen.append(point)
		point = DemoPlan.next(point)
	assert_eq(point, DemoPlan.Point.ROOF, "three points — and the roof again")
	assert_eq(seen.size(), 3, "each once")


func test_the_start_floors_follow_the_rom() -> void:
	# The ROM starts from the 18th and 5th floors from the bottom (`$802C`); our floors are counted
	# from the top, and in a thirty-floor building these are indices 12 and 25.
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.ROOF, 30), BuildingRules.ROOF, "top — the roof")
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.MIDDLE, 30), 12, "middle")
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.BOTTOM, 30), 25, "bottom")
	assert_eq(
		DemoPlan.floor_of(DemoPlan.Point.BOTTOM, 3), 0, "in a low building — within its bounds"
	)


# --- Main menu -----------------------------------------------------------------


func test_idle_in_the_main_menu_starts_the_demo() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.5)
	assert_null(main.get("_demo"), "half a minute — still the menu")
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.6)
	var demo := main.get("_demo") as DemoRun
	assert_not_null(demo, "idleness — the demo")
	assert_false((main.get_node("Menu") as Menu).visible, "the menu hid")
	assert_not_null(main.get("_level"), "the building is assembled")


func test_a_press_resets_the_idle_count() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.9)
	main._input(_key())
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.5)
	assert_null(main.get("_demo"), "a keypress reset the countdown")


func test_any_press_ends_the_demo_back_to_the_menu() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_start_demo")
	await wait_physics_frames(4)
	var level := main.get("_level") as GreyboxLevel
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	main._input(pad)
	assert_eq(level.process_mode, Node.PROCESS_MODE_DISABLED, "the building froze at once")
	await wait_seconds(FadeCurtain.FADE_OUT + 0.2)
	assert_null(main.get("_demo"), "the demo ended")
	assert_null(main.get("_level"), "the building is thrown away")
	var menu := main.get_node("Menu") as Menu
	assert_true(menu.visible, "the menu again")
	assert_eq(menu.current_page(), Menu.Page.MAIN, "main")


func test_the_demo_writes_no_records() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_start_demo")
	await wait_physics_frames(2)
	GameState.instance().game_over.emit()
	var menu := main.get_node("Menu") as Menu
	assert_ne(menu.current_page(), Menu.Page.GAME_OVER, "the demo does not show the end of a game")
	assert_true(main.get("_demo_ending"), "and goes to the menu")


func test_a_screenshot_does_not_end_the_demo() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_start_demo")
	await wait_physics_frames(2)
	var shot := InputEventKey.new()
	shot.physical_keycode = KEY_F12
	shot.pressed = true
	assert_true(shot.is_action(&"screenshot"), "F12 is a shot")
	main._input(shot)
	assert_false(main.get("_demo_ending"), "the shot is taken, the demo goes on")
	main.call("_end_demo")


## The building leaves before the pause lifts: whatever was paused inside it — a takedown
## scene halfway — must not hear the unpause and slow the world down over the menu
## (ADR-0060).
func test_leaving_a_paused_building_does_not_wake_it() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_start_demo")
	await wait_physics_frames(2)
	var level := main.get("_level") as GreyboxLevel
	var probe := _unpause_probe()
	level.add_child(probe)
	main.call("_pause")
	main.call("_open_menu")
	assert_false(get_tree().paused, "the pause is lifted")
	assert_eq(int(probe.get("unpaused")), 0, "the old building did not hear the unpause")
	probe.free()


## Closing the window keeps the settings: the volume set in the menu is not lost
## (ADR-0060).
func test_closing_the_window_saves_the_settings() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var settings := main.get("_settings") as GameSettings
	var path := "user://test_close_settings.cfg"
	settings.file_path = path
	settings.music = 0.25
	main.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	assert_almost_eq(GameSettings.load_from(path).music, 0.25, 0.001, "the volume is on disk")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A node that counts the unpauses it hears.
func _unpause_probe() -> Node:
	var script := GDScript.new()
	script.source_code = (
		"\n"
		. join(
			[
				"extends Node",
				"var unpaused: int = 0",
				"func _notification(what: int) -> void:",
				"\tif what == NOTIFICATION_UNPAUSED:",
				"\t\tunpaused += 1",
			]
		)
	)
	script.reload()
	var probe := Node.new()
	probe.set_script(script)
	probe.process_mode = Node.PROCESS_MODE_PAUSABLE
	return probe


# --- Points --------------------------------------------------------------------


func test_the_bottom_point_opens_the_basement() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	await wait_physics_frames(4)
	var run := DemoRun.start(level, DemoPlan.Point.BOTTOM)
	await wait_physics_frames(2)
	var wanted := DemoPlan.floor_of(DemoPlan.Point.BOTTOM, level.rules.floors)
	var index := level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
	# The start is at a shaft whose cab starts from this floor, near the ROM floor.
	assert_lte(absi(index - wanted), DemoPlan.SHAFT_SEARCH, "Otto is down, near the ROM floor")
	var starts_here := false
	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		starts_here = starts_here or shaft.top == index
	assert_true(starts_here, "the car starts on the start floor")
	assert_false(level.is_in_the_intro(), "the intro is skipped")
	# The view snaps onto Otto rather than travelling to him from the roof through the whole building.
	var feet := WorldSpace.to_plane(level.otto.global_position)
	assert_true(level.otto.camera_view().has_point(feet), "Otto is in frame from the first step")
	var pending := 0
	for door: Door in level.doors():
		if door.is_pending() and level.rules.floor_index_near(door.mat_position().y) < index:
			pending += 1
	assert_eq(pending, 0, "no documents left above the start — the bot goes down, not up")
	run.stop()
	remove_child(level)


## The demo holds the cab at the start for the pair's tier too: the tier has no motion of its own,
## and the leading cab must stand — otherwise the pair leaves on schedule.
func test_holding_a_deck_holds_its_pair() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	level.spawn_agents = false
	add_child_autofree(level)
	await wait_physics_frames(4)
	var deck: ElevatorCar = null
	var leader: ElevatorCar = null
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and car.is_deck():
			deck = car
	if deck == null:
		pending("the building has no two-floor pair")
		remove_child(level)
		return
	# The leading cab is the nearest cab above in the same column: one column can also have two shafts
	# at different heights.
	var closest := INF
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car == null or car.is_deck() or not is_equal_approx(car.position.x, deck.position.x):
			continue
		var above := car.position.y - deck.position.y
		if above > 0.0 and above < closest:
			closest = above
			leader = car
	assert_not_null(leader, "the tier has a leader")
	var before := leader.position.y
	deck.hold(DemoRun.CAR_WAIT)
	# Longer than an ordinary stop at a floor ([member ElevatorCar.floor_pause]).
	await wait_physics_frames(int((leader.floor_pause + 1.0) * Engine.physics_ticks_per_second))
	assert_almost_eq(leader.position.y, before, 0.01, "the pair stands while the tier is held")
	remove_child(level)


func _key() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	return event


## Game over is not in the death frame (ADR-0042, decision 5): first a slow-down and a camera
## push-in, then the page, and that one does not enable its items at once.
func test_game_over_waits_for_the_last_death() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	# The table is full of large scores: a zero one will not get into it and will not touch the
	# player's file.
	var records := Records.new()
	for _row: int in Records.LIMIT:
		records.rows.append({Records.SCORE: 1000000, Records.DATE: "2026-01-01"})
	main.set("_records", records)
	main.call("_start_game")
	await wait_physics_frames(4)
	GameState.instance().game_over.emit()
	await wait_physics_frames(2)
	var menu := main.get_node("Menu") as Menu
	assert_false(menu.visible, "no menu in the death frame")
	assert_false(get_tree().paused, "the world is still going — slowly")
	assert_lt(Engine.time_scale, 1.0, "slowed down")
	# By tree frames: they run during pause too, while a GUT wait under pause stops together with the
	# building. Time is in frame steps without slow-down, as [LastDeath] counts it, not by the clock:
	# under `--fixed-fps` frames run faster than the clock, and within two seconds of clock time the
	# items managed to unlock (run_tests.py).
	var waited := 0.0
	while waited < LastDeath.DURATION + 0.1:
		await get_tree().process_frame
		waited += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
	assert_true(menu.visible, "then — the end of the game")
	assert_eq(menu.current_page(), Menu.Page.GAME_OVER)
	assert_true(get_tree().paused, "the building froze")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "the pace returned")
	assert_true(menu.rows()[0].disabled, "the items cannot be pressed yet")


## Esc during the last death does not continue the game (M24f code review): the closed menu
## remembers the pause page, and after a pause in this game Esc "continued" the game with a dead
## Otto — the game over screen never showed.
func test_escape_during_the_last_death_does_not_resume() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	var records := Records.new()
	for _row: int in Records.LIMIT:
		records.rows.append({Records.SCORE: 1000000, Records.DATE: "2026-01-01"})
	main.set("_records", records)
	main.call("_start_game")
	await wait_physics_frames(4)
	main.call("_pause")
	main.call("_resume")
	await get_tree().process_frame
	GameState.instance().game_over.emit()
	await get_tree().process_frame
	Input.action_press(&"pause")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(&"pause")
	var waited := 0.0
	while waited < LastDeath.DURATION + 0.5:
		await get_tree().process_frame
		waited += get_process_delta_time() / maxf(Engine.time_scale, 0.001)
	var menu := main.get_node("Menu") as Menu
	assert_true(menu.visible, "the end of the game is shown")
	assert_eq(menu.current_page(), Menu.Page.GAME_OVER)
	assert_false(main.get("_playing"), "the game did not continue")
