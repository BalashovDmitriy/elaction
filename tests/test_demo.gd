extends GutTest

## Демо-режим (ADR-0041): точки старта, запуск по бездействию меню, конец любым
## нажатием и нижняя точка с открытым подвалом.

const MAIN_SCENE := preload("res://src/main.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_each() -> void:
	get_tree().paused = false
	GameState.instance().reset()
	Sounds.stop_music()


# --- Правило -------------------------------------------------------------------


func test_the_points_go_round() -> void:
	var point := DemoPlan.Point.ROOF
	var seen: Array[int] = []
	for _round in DemoPlan.Point.size():
		seen.append(point)
		point = DemoPlan.next(point)
	assert_eq(point, DemoPlan.Point.ROOF, "три точки — и снова крыша")
	assert_eq(seen.size(), 3, "каждая по разу")


func test_the_start_floors_follow_the_rom() -> void:
	# ROM стартует с 18-го и 5-го этажей снизу (`$802C`); у нас этажи считаются
	# сверху, и в тридцатиэтажном здании это индексы 12 и 25.
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.ROOF, 30), BuildingRules.ROOF, "верх — крыша")
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.MIDDLE, 30), 12, "середина")
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.BOTTOM, 30), 25, "низ")
	assert_eq(DemoPlan.floor_of(DemoPlan.Point.BOTTOM, 3), 0, "в низком здании — в его пределах")


# --- Главное меню ----------------------------------------------------------------


func test_idle_in_the_main_menu_starts_the_demo() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.5)
	assert_null(main.get("_demo"), "полминуты — ещё меню")
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.6)
	var demo := main.get("_demo") as DemoRun
	assert_not_null(demo, "бездействие — демо")
	assert_false((main.get_node("Menu") as Menu).visible, "меню спряталось")
	assert_not_null(main.get("_level"), "здание собрано")


func test_a_press_resets_the_idle_count() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.9)
	main._input(_key())
	main.call("_count_idle", DemoPlan.IDLE_TIME * 0.5)
	assert_null(main.get("_demo"), "нажатие обнулило отсчёт")


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
	assert_eq(level.process_mode, Node.PROCESS_MODE_DISABLED, "здание замерло сразу")
	await wait_seconds(FadeCurtain.FADE_OUT + 0.2)
	assert_null(main.get("_demo"), "демо кончилось")
	assert_null(main.get("_level"), "здание выброшено")
	var menu := main.get_node("Menu") as Menu
	assert_true(menu.visible, "снова меню")
	assert_eq(menu.current_page(), Menu.Page.MAIN, "главное")


func test_the_demo_writes_no_records() -> void:
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	await wait_physics_frames(2)
	main.call("_start_demo")
	await wait_physics_frames(2)
	GameState.instance().game_over.emit()
	var menu := main.get_node("Menu") as Menu
	assert_ne(menu.current_page(), Menu.Page.GAME_OVER, "конца партии демо не показывает")
	assert_true(main.get("_demo_ending"), "а уходит в меню")


# --- Точки ---------------------------------------------------------------------


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
	var index := DemoPlan.floor_of(DemoPlan.Point.BOTTOM, level.rules.floors)
	var where := level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
	assert_eq(where, index, "Otto на нижнем этаже старта")
	assert_false(level.is_in_the_intro(), "вступление пропущено")
	var pending := 0
	for door: Door in level.doors():
		if door.is_pending() and level.rules.floor_index_near(door.mat_position().y) < index:
			pending += 1
	assert_eq(pending, 0, "документов выше старта не осталось — бот идёт вниз, а не наверх")
	run.stop()
	remove_child(level)


func _key() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	return event
