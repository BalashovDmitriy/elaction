extends GutTest

## Темнота по правилам ADR-0023: решает тень Otto, слепой агент патрулирует,
## за дверью Otto невидим. Со сценой: здание настоящее по правилам, агент
## ставится руками — в кадре должен быть ровно один, и известно где.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Сколько кадров даётся агенту на выстрел. Замах 0.35 с, пауза 1.1 с — двух
## секунд игрового времени хватает и на выстрел, и на то, чтобы убедиться, что
## его нет.
const WATCH_FRAMES: int = 120

## Сколько кадров ждать падения лампы.
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


## Этаж дуэли: широкий, в полный размах здания — на нём три лампы и места на
## любую дальность, — и не нижний, где стоит выход.
##
## Не жёстко третий снизу, а первый широкий снизу, где нашлась пара мест
## ([method _pair_on]): раскладка меняется от вехи к вехе, и на M18c стена
## легла на тот самый этаж так, что пары на нём не осталось. Тест молча брал
## тогда одно место дважды и проверял не то.
##
## Выбирается один раз на здание и запоминается: пара ищется по висящим лампам,
## и после сбитой лампы поиск вернул бы уже другой этаж.
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


## Лампа этажа, ближайшая к точке.
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


## Стоит ли точка почти посередине между двумя лампами — там, где зона
## не определена однозначно.
func _on_a_border(level: GreyboxLevel, floor_index: int, x: float) -> bool:
	var gaps: Array[float] = []
	for child in level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == floor_index:
			gaps.append(absf(WorldSpace.to_plane(lamp.global_position).x - x))
	gaps.sort()
	return gaps.size() > 1 and gaps[1] - gaps[0] < 0.1


## Гасит зону лампы и ждёт, пока она долетит.
func _put_out(lamp: Lamp) -> void:
	lamp.shoot_down()
	var left := FALL_FRAMES
	while is_instance_valid(lamp) and left > 0:
		left -= 1
		await wait_physics_frames(1)
	await wait_physics_frames(2)


## Ставит Otto на этаж в точку x.
func _place_otto(level: GreyboxLevel, x: float) -> void:
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(x, level.rules.floor_surface(_floor(level)))
	)
	level.otto.velocity = Vector3.ZERO


## Агент на месте, смотрящий в сторону Otto. Стоит: у него нет хода, чтобы
## дуэль зависела только от того, видит ли он.
func _agent_at(level: GreyboxLevel, x: float, towards: float, walks: bool = false) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(level.rules)
	if not walks:
		agent.walk_speed = 0.0
	level.add_child(agent)
	if not walks:
		# Стоящий агент бродит на месте и поворачивается куда придётся, а
		# стреляет по ROM, только глядя на Otto. Тревога снимает это условие:
		# проверка здесь о том, видит ли он Otto, а не куда он смотрит.
		agent.alert_for(1.0e6)
	agent.global_position = WorldSpace.to_scene(
		Vector2(x, level.rules.floor_surface(_floor(level)))
	)
	agent.setup(level.otto, towards)
	return agent


## Сколько вражеских пуль появилось за время наблюдения.
func _shots_within(level: GreyboxLevel, frames: int) -> int:
	var seen: Dictionary = {}
	for _frame in frames:
		await wait_physics_frames(1)
		for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
			var bullet := node as Bullet
			if bullet != null and bullet.collision_mask == Bullet.FROM_ENEMY:
				seen[bullet.get_instance_id()] = true
	return seen.size()


## Место под лампой и ещё одно на дальности выстрела, но дальше дальности в темноте.
## Пара мест этажа: первое гасят, второе остаётся светлым.
##
## Места берутся **из разных зон** и на дальности выстрела друг от друга. Из
## одной зоны их брать нельзя: погашенная накрывает оба, и «из тени по
## освещённому» проверяло бы не то. Раньше первое место просто ставилось под
## лампу, а второе — в двух-пяти метрах от него; на мелкой сетке M18 оба стали
## попадать в одну зону, и проверка разваливалась. Теперь пара ищется поперёк
## границы зон: у самой границы соседние зоны сходятся вплотную, и дальность
## выстрела туда укладывается.
func _spot_pair(level: GreyboxLevel) -> Vector2:
	return _pair_on(level, _floor(level))


func _pair_on(level: GreyboxLevel, index: int) -> Vector2:
	var rules := level.rules
	var spots := level.plan().safe_spots(rules, index)
	var closest := rules.agent_dark_fire_range * 1.5
	# Дальности огня нет — есть кадр (ADR-0027, решение 3а): пара обязана
	# влезать в него вместе с Otto, стоящим на одном из мест.
	var furthest := SideCamera.DEFAULT_HALF_HEIGHT * 16.0 / 9.0 * 0.9

	for here: float in spots:
		for there: float in spots:
			var gap := absf(here - there)
			if gap <= closest or gap >= furthest:
				continue
			if _lamp_near(level, index, here) == _lamp_near(level, index, there):
				continue
			# Место ровно на границе зон — ничья, и решает её последний бит дроби:
			# тест и освещение разрешали её в разные стороны. На M18c граница
			# легла точно на место сетки (13.2 между лампами 6.0 и 20.4).
			if _on_a_border(level, index, here) or _on_a_border(level, index, there):
				continue
			# Стена между местами делает агента слепым — и правильно делает
			# (ADR-0024, решение 5). Проверка здесь про темноту, а не про стены,
			# и пара обязана стоять по одну её сторону. Без этого тест падал бы
			# на тех сидах, где стена легла на дуэльный этаж: «освещённого Otto
			# обстреливают» превращалось бы в «за стеной не обстреливают».
			if level.plan().wall_between(index, here, there):
				continue
			return Vector2(here, there)
	return Vector2(spots[0], spots[0])


## Освещённого Otto агент берёт с полной дальности — так было и так остаётся.
func test_a_lit_otto_is_shot_from_afar() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "на этаже есть два места на дальности выстрела")
	_place_otto(level, pair.x)
	_agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_gt(await _shots_within(level, WATCH_FRAMES), 0, "освещённого Otto обстреливают")
	remove_child(level)


## Otto в тени агент издалека не видит и не стреляет; подошёл ближе — видит.
func test_an_otto_in_the_dark_is_seen_only_up_close() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "пара мест для дуэли нашлась")
	_place_otto(level, pair.x)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	assert_true(level.is_dark_at(_floor(level), pair.x), "зона под Otto погасла")

	var agent := _agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_eq(await _shots_within(level, WATCH_FRAMES), 0, "Otto в тени с этой дальности не виден")

	# Теперь агент подходит к Otto на дальность, с которой видно и в темноте.
	#
	# Подходит агент, а не Otto: на мелкой сетке M18 шаг к агенту выводил Otto
	# из тени в освещённую зону агента, и проверялось уже не «в тени вплотную».
	# А попадание считается по гибели Otto, а не по пулям: с метра пуля
	# долетает в тот же шаг физики, в котором вылетела, и счёт пуль её не видит.
	agent.queue_free()
	var close := _floor_beside(level, pair.x, level.rules.agent_dark_fire_range * 0.6)
	assert_false(is_nan(close), "рядом с Otto есть пол, куда встать агенту")
	_agent_at(level, close, signf(pair.x - close))
	var hit := [false]
	level.otto.died.connect(func() -> void: hit[0] = true)
	await wait_physics_frames(WATCH_FRAMES)
	assert_true(level.is_dark_at(_floor(level), pair.x), "Otto так и стоит в тени")
	assert_true(hit[0], "вплотную его видно и в тени")
	remove_child(level)


## Место на полу в [param reach] от [param x] по этажу дуэли, в любую сторону,
## где агенту есть на чём стоять. NAN — таких нет.
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


## Тень агента ничего не решает: из тени освещённого Otto видно.
func test_an_agent_in_the_dark_still_sees_a_lit_otto() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "пара мест для дуэли нашлась")
	_place_otto(level, pair.y)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	# Дуэль ставится на том, что Otto остался под горящей лампой: зоны узкие, и
	# второе место могло попасть в ту же погашенную — тогда проверялось бы не то.
	assert_false(level.is_dark_at(_floor(level), pair.y), "Otto стоит в освещённой зоне")
	var agent := _agent_at(level, pair.x, signf(pair.y - pair.x))
	var shots := await _shots_within(level, WATCH_FRAMES)
	assert_true(agent.is_in_the_dark(), "агент стоит в тени")
	assert_gt(shots, 0, "и всё равно видит освещённого Otto")
	remove_child(level)


## За дверью Otto нет: агенты теряют его, как в оригинале (долг M14).
func test_agents_lose_otto_behind_a_door() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "пара мест для дуэли нашлась")
	_place_otto(level, pair.x)
	level.otto.stay_indoors(true)
	_agent_at(level, pair.y, signf(pair.x - pair.y))
	assert_eq(await _shots_within(level, WATCH_FRAMES), 0, "спрятанного не обстреливают")
	level.otto.stay_indoors(false)
	assert_gt(await _shots_within(level, WATCH_FRAMES), 0, "вышел — снова цель")
	remove_child(level)


## Слепой агент не караулит у края этажа, а ходит по нему туда и обратно.
func test_a_blind_agent_patrols_the_floor() -> void:
	var level := _build()
	await wait_physics_frames(4)
	var pair := _spot_pair(level)
	assert_ne(pair.x, pair.y, "пара мест для дуэли нашлась")
	_place_otto(level, pair.x)
	await _put_out(_lamp_near(level, _floor(level), pair.x))
	# Агент идёт прочь от Otto, до края этажа.
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
	assert_true(turned, "дошёл до края и развернулся")
	remove_child(level)
