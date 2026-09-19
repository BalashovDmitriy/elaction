extends GutTest

## Тесты выхода агента из двери.
##
## До M14 уровень ставил агента прямо на коврик закрытой двери, и створка при
## этом не двигалась вовсе. Здесь проверяется обратное: сперва дверь, потом
## агент, и пока он в проёме — его не берут (ADR-0020).
##
## Здание собирается по настоящим правилам, как и в [code]test_building_architecture[/code]:
## уменьшенные здания уже один раз скрыли от нас нерабочий выпуск агентов.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_LAYER: int = 3

## Сколько кадров ждать конца вступления: спуск по тросу занимает меньше секунды.
const LANDING_FRAMES: int = 180

## Сколько кадров дать дверям, чтобы кто-нибудь успел выйти.
const CROWD_FRAMES: int = 240


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = true
	add_child_autofree(level)
	return level


## Ждёт, пока Otto доедет по тросу и встанет на крышу.
func _wait_for_the_landing(level: GreyboxLevel) -> void:
	for _frame: int in LANDING_FRAMES:
		await wait_physics_frames(1)
		if level.otto.is_grounded():
			return


func _live_agents(level: GreyboxLevel) -> Array[Enemy]:
	var live: Array[Enemy] = []
	for agent in level.agents():
		if is_instance_valid(agent) and not agent.is_dead():
			live.append(agent)
	return live


## Дверь, из которой этот агент вышел: ближайшая к нему по горизонтали на его
## этаже. Другого способа связать их снаружи нет — пост живёт внутри уровня.
func _door_behind(level: GreyboxLevel, agent: Enemy) -> Door:
	var nearest: Door = null
	var gap := INF
	for door in level.doors():
		var mat := door.mat_position()
		if absf(mat.y - agent.global_position.y) > 1.0:
			continue
		var distance := absf(mat.x - agent.global_position.x)
		if distance < gap:
			gap = distance
			nearest = door
	return nearest


func test_no_agent_ever_shows_up_in_front_of_a_shut_door() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	# Каждый кадр: если агент виден, дверь за ним обязана быть открытой.
	# Именно это и было сломано — агент возникал на закрытой створке.
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if not agent.is_emerging():
				continue
			var door := _door_behind(level, agent)
			assert_not_null(door, "агент вышел неизвестно откуда")
			if door == null:
				return
			assert_gt(door.openness(), 0.0, "агент в проёме — значит створка не закрыта")


func test_an_agent_in_the_doorway_is_not_a_target() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var seen := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if not agent.is_emerging():
				continue
			seen += 1
			assert_false(
				agent.get_collision_layer_value(ENEMY_LAYER),
				"пока агент в проёме, пуле не во что попадать"
			)
	assert_gt(seen, 0, "ни один агент не выходил — проверять было нечего")


func test_an_agent_out_of_the_doorway_becomes_a_target() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var seen := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			seen += 1
			assert_true(
				agent.get_collision_layer_value(ENEMY_LAYER),
				"вышедший агент — обычный противник, и его берёт пуля"
			)
	assert_gt(seen, 0, "ни один агент так и не вышел из проёма")


func test_the_door_shuts_behind_the_agent_that_left_it() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var closed_behind := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			var door := _door_behind(level, agent)
			if door == null or absf(door.mat_position().x - agent.global_position.x) > 1.0:
				continue
			# Агент ещё стоит на самом коврике, но проём уже освободил: створка
			# обязана идти обратно, а не стоять нараспашку (ADR-0020, решение 4).
			if door.openness() < 1.0:
				closed_behind += 1
	assert_gt(closed_behind, 0, "ни одна дверь за вышедшим не закрывалась")


func test_an_emptied_red_door_starts_letting_agents_out() -> void:
	var level := _build(3)
	var red: Door = null
	for door in level.doors():
		if door.is_pending():
			red = door
			break
	assert_not_null(red, "в здании обязаны быть красные двери")
	if red == null:
		return

	# Документ забирают не входом Otto, а прямо: веха про двери, не про визит.
	assert_false(level.agent_doors().has(red), "красная дверь засад не держит")
	red.has_document = false
	red.document_taken.emit()
	assert_true(
		level.agent_doors().has(red), "опустевшая дверь выглядит обычной и ведёт себя как обычная"
	)
