extends GutTest

## Вступление здания: вертолёт привозит Otto на крышу (ADR-0038, решение 1).
##
## Здание генерируется, и место приземления у каждого своё, поэтому главное
## проверяется на нескольких сидах: вертолёт есть, пока идёт вступление, Otto
## встаёт ровно на место приземления и слушается, вертолёт улетает и убирается.
## Пропуск, переставленный Otto и возвращение после гибели — по одному зданию.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 4, 5]

## Сколько кадров даётся зданию, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Сколько кадров ждать, пока вертолёт уйдёт из кадра и уберёт себя: уход идёт
## около трёх секунд, под ускорением времени вчетверо — полсотни кадров.
const GONE_FRAMES: int = 240

## Насколько Otto стоит на своём месте, м: сантиметр.
const TOLERANCE: float = 0.01


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func after_each() -> void:
	for action: StringName in [&"jump", &"shoot", &"move_right"]:
		Input.action_release(action)


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


func _landing(level: GreyboxLevel) -> Vector2:
	var roof := BuildingRules.ROOF
	return Vector2(level.plan().safe_x(level.rules, roof), level.rules.floor_surface(roof))


func _otto_at(level: GreyboxLevel) -> Vector2:
	return WorldSpace.to_plane(level.otto.global_position)


## Вертолёты в уровне — узлом, а не по ссылке уровня: проверка «улетел» должна
## видеть и того, кого уровень уже забыл.
func _helicopters(level: GreyboxLevel) -> int:
	return level.find_children("*", "Helicopter", true, false).size()


func _wait_until_gone(level: GreyboxLevel) -> bool:
	for _frame: int in GONE_FRAMES:
		if _helicopters(level) == 0:
			return true
		await wait_physics_frames(1)
	return _helicopters(level) == 0


## Габарит вида вертолёта в плоскости правил: все его меши вместе.
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


## На любом здании вертолёт привозит Otto ровно на место приземления, отдаёт
## управление и улетает.
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


## Отдали управление — значит Otto пошёл. Проверяется ходом, а не состоянием:
## до M12 «приехал» не означало «отпустили».
func test_otto_obeys_after_the_landing() -> void:
	var level := _build(1)
	await level.wait_for_the_landing()
	var before := _otto_at(level).x
	Input.action_press(&"move_right")
	await wait_physics_frames(6)
	Input.action_release(&"move_right")
	assert_gt(_otto_at(level).x, before, "Otto слушается игрока")
	_drop(level)


## Трос достаёт до крыши, а вертолёт с винтом и крыша влезают в кадр вместе.
func test_the_rope_reaches_the_deck_and_the_frame_holds_both() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
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


## Весь путь — прилёт, висение, уход — вертолёт идёт над техникой крыши, а не
## сквозь неё: ни корпус, ни диск винта не задевают габарита ни одного предмета.
## Сиды выбраны с водонапорной башней у места посадки (нечётные) и с баком.
func test_the_flight_clears_everything_on_the_roof() -> void:
	for building_seed: int in [1, 2, 3, 5, 7]:
		var level := _build(building_seed)
		var deck := WorldSpace.to_scene(_landing(level)).y
		var roof := RoofArrival.roof_obstacles(level, deck, [level.otto] as Array[Node])
		# Сначала — что техника вообще нашлась: пустой список прошёл бы всегда.
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


## Звук вертолёта: петля висения и слой пролёта звучат с прилёта; на подлёте
## громче пролёт, в висении — петля висения; трос звучит, пока Otto едет.
func test_the_helicopter_sounds_its_flight() -> void:
	var level := _build(1)
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
	while level.is_in_the_intro():
		heard_rope = heard_rope or rope.playing
		await wait_physics_frames(1)
	assert_true(heard_rope, "трос звучал, пока Otto ехал")
	assert_gt(hover.volume_db, flyby.volume_db, "в висении громче петля висения")
	_drop(level)


## Звуки вертолёта по именам: поток каждого источника узнаётся по файлу.
func _voices(helicopter: Helicopter) -> Dictionary:
	var found := {}
	for node: Node in helicopter.find_children("*", "AudioStreamPlayer3D", true, false):
		var player := node as AudioStreamPlayer3D
		for name: String in [Sounds.HELICOPTER, Sounds.HELICOPTER_PASS, Sounds.ROPE_SLIDE]:
			if player.stream == Sounds.stream(name):
				found[name] = player
	return found


## Вступление — сценка, а не ожидание: от четырёх до шести секунд до управления.
func test_the_intro_takes_four_to_six_seconds() -> void:
	var level := _build(1)
	# Счёт шагов — по движку, а не по ожиданиям: одно ожидание GUT бывает дольше
	# шага, и счёт ожиданий занижал время вдвое.
	var start := Engine.get_physics_frames()
	var waits := 0
	while level.is_in_the_intro() and waits < GreyboxLevel.LANDING_PATIENCE:
		await wait_physics_frames(1)
		waits += 1
	var frames := Engine.get_physics_frames() - start
	var seconds := frames * Engine.time_scale / float(Engine.physics_ticks_per_second)
	assert_between(seconds, 3.8, 6.0, "вступление идёт %.2f с" % seconds)
	_drop(level)


## Прыжок пропускает вступление: Otto сразу на крыше, вертолёт уходит.
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


## Выстрел — тоже пропуск; а зажатая заранее кнопка — нет: пропуск по нажатию.
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


## Нажатие, пропустившее вступление, на этом и кончается: Otto не стреляет
## и не прыгает от той же кнопки. Иначе пропуск выстрелом — это ещё и выстрел
## в пустоту, а пропуск прыжком — прыжок с места приземления.
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
		# Следующее нажатие — уже Otto: пропуск глушит одно нажатие, а не кнопку.
		if action == &"shoot":
			Input.action_press(action)
			await wait_physics_frames(1)
			Input.action_release(action)
			assert_eq(
				level.find_children("*", "Bullet", true, false).size(), 1, "второе нажатие стреляет"
			)
		_drop(level)


## Переставленный Otto — тестом или съёмкой — кончает вступление сам и стоит,
## где поставили: так инструменты работают, ничего не зная про вертолёт.
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


## После гибели вертолёта нет: Otto возвращается на свой этаж, как было.
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


## Пауза во вступлении его пропускает и меню не открывает: в сценке кнопка
## «Start» значит «хватит смотреть».
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
