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
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Сколько кадров ждать конца вступления: спуск по тросу занимает меньше секунды.
const LANDING_FRAMES: int = 180

## Сколько кадров дать дверям, чтобы кто-нибудь успел выйти.
const CROWD_FRAMES: int = 240

## Насколько далеко от своей двери агент ещё считается «только что вышедшим», м.
##
## Ровно на коврике его не застать: выход из проёма кончается в шаге от двери,
## и агент оказывается в метре с лишним. Проверка на точное совпадение держалась
## на случайности и развалилась, как только мелкая сетка M18 сдвинула двери.
const JUST_LEFT: float = 2.0

## Сколько кадров держать «вверх» у одинокой двери: хватает и на створку, и на
## то, чтобы Otto успел зайти, если дверь его берёт.
const KNOCK_FRAMES: int = 30


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


## Одинокая дверь на твёрдом полу: здание для неё поднимать незачем.
func _bare_door() -> Door:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)

	var door := DOOR_SCENE.instantiate() as Door
	add_child_autofree(door)
	return door


## Ставит Otto на коврик двери.
func _guest_at(door: Door) -> Otto:
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = WorldSpace.to_scene(door.mat_position())
	return otto


## Зашёл ли Otto за дверь. Снаружи это видно по вводу: спрятанный дверью, он
## ввода не слышит вовсе, и зажатое «вверх» до него не доходит.
func _is_indoors(otto: Otto) -> bool:
	return is_zero_approx(otto.vertical_intent())


## Otto не заходит в дверь, которая открывается под агента.
##
## Пустить его туда значило бы запереть навсегда: створку за вышедшим агентом
## закрывает уровень, а отсидка гостя идёт только при открытой двери — за
## закрытой она не кончается никогда.
func test_a_door_opening_for_an_agent_does_not_take_otto_in() -> void:
	var door := _bare_door()
	var otto := _guest_at(door)
	assert_true(door.summon_agent(), "свободная дверь открывается под агента")

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_false(_is_indoors(otto), "дверь занята агентом и Otto внутрь не пустила")


## А свободная пускает: иначе прошлая проверка прошла бы и на двери, которая
## не пускает никого и никогда.
func test_a_free_door_still_takes_otto_in() -> void:
	var door := _bare_door()
	var otto := _guest_at(door)

	Input.action_press(&"move_up")
	await wait_physics_frames(KNOCK_FRAMES)
	Input.action_release(&"move_up")
	assert_true(_is_indoors(otto), "в свободную дверь Otto заходит как прежде")


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
			var door := level.door_of(agent)
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
				agent.get_collision_layer_value(Enemy.ENEMY_LAYER),
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
				agent.get_collision_layer_value(Enemy.ENEMY_LAYER),
				"вышедший агент — обычный противник, и его берёт пуля"
			)
	assert_gt(seen, 0, "ни один агент так и не вышел из проёма")


func test_the_door_shuts_behind_the_agent_that_left_it() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)
	var closed_behind := 0
	var just_left := 0
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			var door := level.door_of(agent)
			var at := WorldSpace.to_plane(agent.global_position)
			if door == null or absf(door.mat_position().x - at.x) > JUST_LEFT:
				continue
			just_left += 1
			# Агент ещё у своей двери, но проём уже освободил: створка обязана
			# идти обратно, а не стоять нараспашку (ADR-0020, решение 4).
			if door.openness() < 1.0:
				closed_behind += 1
	# «Ноль» бывает и оттого, что дверь не закрылась, и оттого, что за окном
	# наблюдения никто не вышел, — а это разные поломки.
	assert_gt(just_left, 0, "ни один агент не отходил от своей двери")
	assert_gt(
		closed_behind, 0, "ни одна дверь за вышедшим не закрывалась (отошедших %d)" % just_left
	)


## Дверь закрывается и за агентом, которого сняли сразу, как он вышел.
##
## Проём свободен одинаково — ушёл агент своим ходом или его убили, — и створка
## обязана вернуться в обоих случаях (ADR-0020, решение 4). Закрыть её некому,
## кроме уровня, а тот перебирает посты: пост, оставшийся без живого агента,
## обязан отпускать дверь, иначе она стоит открытой навсегда и, что хуже,
## навсегда занятой — [method Door.summon_agent] больше её не откроет.
func test_a_door_shuts_even_when_its_agent_is_killed_on_the_spot() -> void:
	var level := _build(3)
	await _wait_for_the_landing(level)

	var emptied: Door = null
	for _frame: int in CROWD_FRAMES:
		await wait_physics_frames(1)
		if emptied != null:
			if emptied.openness() <= 0.0:
				pass_test("створка вернулась и за убитым")
				return
			continue
		for agent in _live_agents(level):
			if agent.is_emerging():
				continue
			emptied = level.door_of(agent)
			agent.kill()
			break

	assert_not_null(emptied, "из дверей никто не вышел — убивать было некого")
	fail_test("дверь так и осталась открытой за убитым агентом")


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


## Открытая створка не выходит за свой проём.
##
## Шаг места 1.8 м, створка 1.2: на соседнее место остаётся 0.6. Съезжая вбок
## на свою ширину, как было до M18c, она налезала бы на соседнюю дверь или
## шахту — поэтому поворачивается на петле внутрь комнаты (ADR-0026, решение 3).
func test_an_open_leaf_stays_inside_its_doorway() -> void:
	var door := _bare_door()
	assert_true(door.summon_agent(), "дверь открывается")
	var frames := 0
	while door.openness() < 1.0 and frames < 240:
		await wait_physics_frames(1)
		frames += 1
	assert_almost_eq(door.openness(), 1.0, 0.001, "дверь открылась до конца")

	var leaf := door.get_node("Leaf") as MeshInstance3D
	var bounds := leaf.global_transform * leaf.get_aabb()
	var half := Door.LEAF_SIZE.x * 0.5
	var centre := door.global_position.x
	assert_gte(bounds.position.x, centre - half - 0.05, "створка не вышла за проём слева")
	assert_lte(bounds.end.x, centre + half + 0.05, "и справа")
	assert_lt(bounds.position.z, WorldSpace.BACK_WALL_Z, "она ушла в комнату, за стену")
