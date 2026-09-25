extends GutTest

## Тесты двери с Otto внутри — узлом, со створкой, вводом и звуком (ADR-0038,
## решение 2).
##
## Правила визита без сцены — в [code]test_door_visit.gd[/code]. Здесь то, чего
## там не проверить: что ввод игрока до двери и правда не доходит ничем, что
## створку видно закрытой, что документ засчитывается на выходе в настоящем
## здании и что агенты этажа ждут у двери не больше одного за раз — на
## нескольких сидах, а не на одном удобном этаже.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Ускорение времени: визит — почти пять секунд, и зданий в тесте несколько.
const TIME_SCALE: float = 4.0

## Сколько кадров ждать, пока Otto зайдёт или выйдет, прежде чем сдаться.
const PATIENCE: int = 240

## Всё, чем игрок мог бы попроситься наружу: раньше срока не выпускает ничто.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_down", &"move_up", &"jump", &"shoot"
]

## Сиды зданий для проверок на уровне.
const SEEDS: Array[int] = [1, 2, 3]

## Насколько далеко от двери ставить агентов, м: дальше отступа места ожидания и
## близко настолько, чтобы дойти, пока Otto внутри.
const AGENT_NEAR: float = 1.9
const AGENT_FAR: float = 4.2


func before_all() -> void:
	Engine.time_scale = TIME_SCALE


func after_all() -> void:
	Engine.time_scale = 1.0
	_release_all()
	GameState.instance().reset()


func after_each() -> void:
	_release_all()


func _release_all() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


## Шаг физики в секундах игры: под ускорением он длиннее.
func _step() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## Ждёт [param seconds] секунд игры шагами физики: под ускорением настенные
## часы не в счёт.
func _wait_game(seconds: float) -> void:
	for _frame: int in int(ceilf(seconds / _step())):
		await get_tree().physics_frame


## Одинокая дверь на твёрдом полу, как в [code]test_agent_doors.gd[/code].
func _bare_door(red: bool) -> Door:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)

	var door := DOOR_SCENE.instantiate() as Door
	door.has_document = red
	add_child_autofree(door)
	return door


func _guest_at(door: Door) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = WorldSpace.to_scene(door.mat_position())
	return otto


## Жмёт «вверх», пока дверь не возьмёт Otto. Возвращает, взяла ли.
func _knock(otto: Otto) -> bool:
	Input.action_press(&"move_up")
	for _frame: int in PATIENCE:
		await get_tree().physics_frame
		if not otto.is_on_foot():
			return true
	return false


## Ждёт, пока Otto спрячется за створкой.
func _wait_hidden(otto: Otto) -> bool:
	for _frame: int in PATIENCE:
		if otto.is_hidden():
			return true
		await get_tree().physics_frame
	return otto.is_hidden()


## Ждёт, пока дверь выпустит спрятанного Otto: он снова на виду.
func _wait_out(otto: Otto) -> void:
	var frames := 0
	while otto.is_hidden() and frames < PATIENCE * 2:
		await get_tree().physics_frame
		frames += 1


func test_the_leaf_shuts_behind_otto_and_opens_to_let_him_out() -> void:
	var door := _bare_door(false)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "дверь взяла Otto")
	assert_false(otto.is_hidden(), "пока створка идёт, он ещё в проёме")
	assert_true(await _wait_hidden(otto), "створка открылась — он внутри")
	# Секунда: створка успела закрыться за ним, а до выхода ещё далеко.
	await _wait_game(1.0)
	assert_true(otto.is_hidden(), "он всё ещё внутри")
	assert_eq(door.openness(), 0.0, "за ним створка закрыта")
	await _wait_out(otto)
	assert_false(otto.is_hidden(), "вышел")
	assert_gt(door.openness(), 0.9, "выходит в открытую створку")
	assert_false(otto.is_on_foot(), "пока она закрывается, он ещё выходит")
	await _wait_game(1.0)
	assert_eq(door.openness(), 0.0, "и за ним она закрывается")
	assert_true(otto.is_on_foot(), "закрылась — управление снова у игрока")


func test_otto_is_out_exactly_after_seventy_ticks_whatever_he_presses() -> void:
	var door := _bare_door(false)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "дверь взяла Otto")
	var frames := 0
	var hid := false
	while frames < PATIENCE * 2:
		# Каждый кадр — другая кнопка, с отпусканием: и зажатая, и свежая.
		_release_all()
		Input.action_press(ACTIONS[frames % ACTIONS.size()])
		await get_tree().physics_frame
		frames += 1
		hid = hid or otto.is_hidden()
		if hid and not otto.is_hidden():
			break
		assert_false(otto.is_on_foot(), "раньше срока не выпускают, кадр %d" % frames)
	_release_all()
	var inside := float(frames) * _step()
	var rom := Arcade.seconds(Arcade.ROOM_TICKS)
	assert_almost_eq(inside, rom, _step() * 2.0, "ровно 70 тиков ROM")


func test_the_document_is_counted_on_the_way_out() -> void:
	var door := _bare_door(true)
	var otto := _guest_at(door)
	watch_signals(door)
	assert_true(await _knock(otto), "дверь взяла Otto")
	assert_true(await _wait_hidden(otto))
	assert_signal_not_emitted(door, "document_taken", "за вход документ не дают")
	assert_true(door.is_pending(), "пока он внутри, дверь ещё красная")
	await _wait_out(otto)
	assert_signal_emit_count(door, "document_taken", 1, "документ — на выходе")
	assert_false(door.is_pending(), "вышел — дверь обычная")


func test_the_corridor_is_muffled_while_otto_is_inside() -> void:
	var director := AudioDirector.instance()
	if director == null:
		pass_test("звука нет — глушить нечего")
		return
	director.reset()
	var door := _bare_door(false)
	var otto := _guest_at(door)
	assert_true(await _knock(otto), "дверь взяла Otto")
	assert_true(await _wait_hidden(otto))
	assert_true(director.world_muffled(), "коридор из-за стены")
	assert_true(director.music_muffled(), "и музыка тоже")
	await _wait_out(otto)
	assert_false(director.world_muffled(), "вышел — коридор слышно")
	assert_false(director.music_muffled(), "и музыку")


func test_a_level_freed_with_otto_inside_brings_the_sound_back() -> void:
	var director := AudioDirector.instance()
	if director == null:
		pass_test("звука нет — глушить нечего")
		return
	director.reset()
	var level := _build(SEEDS[0])
	await level.wait_for_the_landing()
	var door := level.doors()[0]
	level.otto.global_position = WorldSpace.to_scene(door.mat_position())
	await get_tree().physics_frame
	assert_true(await _knock(level.otto), "дверь взяла Otto")
	assert_true(await _wait_hidden(level.otto))
	assert_true(director.world_muffled(), "коридор из-за стены")
	remove_child(level)
	level.free()
	assert_false(director.world_muffled(), "здание ушло — коридор слышно")
	assert_false(director.music_muffled(), "и музыку")


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	if is_instance_valid(level):
		remove_child(level)
		level.free()


## Документ и 500 очков — на выходе, в любом здании из набора.
func test_a_red_door_pays_on_the_way_out_in_any_building() -> void:
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await level.wait_for_the_landing()
		var red: Door = null
		for door in level.doors():
			if door.is_pending():
				red = door
				break
		assert_not_null(red, "в здании нет красной двери, сид %d" % building_seed)
		if red == null:
			_drop(level)
			continue
		var game := GameState.instance()
		level.otto.global_position = WorldSpace.to_scene(red.mat_position())
		await get_tree().physics_frame
		var score := game.score
		assert_true(await _knock(level.otto), "дверь взяла Otto, сид %d" % building_seed)
		assert_true(await _wait_hidden(level.otto))
		assert_eq(game.documents_collected, 0, "за вход не засчитано, сид %d" % building_seed)
		assert_eq(game.score, score, "и очков нет")
		await _wait_out(level.otto)
		_release_all()
		assert_eq(game.documents_collected, 1, "на выходе засчитано, сид %d" % building_seed)
		assert_eq(game.score, score + GameState.DOCUMENT_SCORE, "и 500 очков")
		_drop(level)


## Где на этаже двери поставить агентов, чтобы им было дойти: места, где можно
## стоять, на свободном пути до двери.
func _agent_spots(level: GreyboxLevel, door: Door) -> Array[float]:
	var mat := door.mat_position()
	var floor_index := level.rules.floor_index_near(mat.y)
	var blocks := level.plan().blocks_on(level.rules, floor_index)
	var spots: Array[float] = []
	for x: float in level.plan().safe_spots(level.rules, floor_index):
		var gap := absf(x - mat.x)
		if gap < AGENT_NEAR or gap > AGENT_FAR:
			continue
		var clear := true
		for block: Vector2 in blocks:
			var low := minf(x, mat.x)
			var high := maxf(x, mat.x)
			if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
				clear = false
		if clear:
			spots.append(x)
	return spots


func _spawn_agent(level: GreyboxLevel, x: float, y: float, towards: float, index: int) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(level.rules)
	agent.seed_decisions(1000 + index)
	level.add_child(agent)
	agent.global_position = WorldSpace.to_scene(Vector2(x, y))
	agent.setup(level.otto, towards)
	return agent


## Агенты этажа ждут у двери с Otto не больше одного за раз, дошедший стоит у
## коврика лицом к двери, а вышел Otto — ждать некого.
func test_agents_wait_at_otto_s_door_one_at_most_and_let_go_when_he_is_out() -> void:
	var watched := 0
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await level.wait_for_the_landing()
		var door: Door = null
		var spots: Array[float] = []
		for candidate in level.doors():
			spots = _agent_spots(level, candidate)
			if spots.size() >= 2:
				door = candidate
				break
		if door == null:
			_drop(level)
			continue
		var mat := door.mat_position()
		level.otto.global_position = WorldSpace.to_scene(mat)
		await get_tree().physics_frame
		assert_true(await _knock(level.otto), "дверь взяла Otto, сид %d" % building_seed)
		assert_true(await _wait_hidden(level.otto))
		_release_all()
		var agents: Array[Enemy] = []
		for index: int in spots.size():
			agents.append(_spawn_agent(level, spots[index], mat.y, mat.x - spots[index], index))

		var watcher: Enemy = null
		while level.otto.is_hidden():
			await get_tree().physics_frame
			var waiting := 0
			for agent in agents:
				if not is_nan(agent.watch_at):
					waiting += 1
					watcher = agent
			assert_lte(waiting, 1, "у двери не больше одного, сид %d" % building_seed)
		if watcher != null:
			watched += 1
			var x := WorldSpace.to_plane(watcher.global_position).x
			var off := absf(x - mat.x)
			assert_gt(off, Proportions.DOOR_MAT * 0.5, "не на коврике, сид %d" % building_seed)
			assert_lt(off, Proportions.DOOR.x, "а у самой двери, сид %d" % building_seed)
			assert_eq(watcher.facing(), signf(mat.x - x), "лицом к двери")
		await get_tree().physics_frame
		await get_tree().physics_frame
		for agent in agents:
			assert_true(is_nan(agent.watch_at), "Otto вышел — ждать некого")
		_drop(level)
	assert_gt(watched, 0, "ни в одном здании никто не пошёл к двери — проверять было нечего")
