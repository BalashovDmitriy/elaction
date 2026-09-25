extends GutTest

## Тесты езды агентов в кабинах (ADR-0025, решение 6).
##
## В оригинале агенты ездят, но кабиной не распоряжаются: «When Otto is not in
## an elevator, it will move from floor to floor automatically, even when enemy
## spies are in it». Отсюда всё устройство: агент идёт к той кабине, что уже
## стоит вровень с его этажом, и едет пассажиром. Вызова нет ни у кого.
##
## Тесты со сценой и физикой — самый дорогой уровень проверки
## ([`testing.md`](../docs/testing.md)), поэтому их здесь ровно два: один про то,
## что агент доезжает, другой про то, что он не отбирает у Otto управление.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")

## Сколько кадров дать зданию собраться.
const SETTLE_FRAMES: int = 10

## Потолок ожидания поездки, шагов физики. Кабина ходит сама и стоит на этаже
## полторы секунды, так что застать её агент может не сразу.
const RIDE_FRAMES: int = 1800

## Сид решений агента: паузы и повороты брожения. Любой — поездка от них не
## зависит; сеется, чтобы прогон повторялся.
const AGENT_SEED: int = 1


func _build() -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	# Свои двери агентов не выпускают: в кадре должен быть один, поставленный
	# тестом, а не восемь, вышедших по расписанию.
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Шахта стилобата подлиннее: по ней и ездят.
##
## Не самая длинная в здании: та идёт с крыши, а наверху этаж узкий — семь мест,
## из них шахта, дверь и лампа, — и агенту там негде разойтись с проёмом.
func _a_shaft_to_ride(level: GreyboxLevel) -> BuildingPlan.ShaftSpot:
	var best: BuildingPlan.ShaftSpot = null
	for shaft in level.plan().shafts:
		if shaft.top <= level.rules.wide_from:
			continue
		if best == null or shaft.height() > best.height():
			best = shaft
	return best


## Агент, потерявший Otto этажом ниже, приезжает к нему на лифте.
##
## До M18b он остался бы на своём этаже навсегда: во всём `src/` `ElevatorCar`
## знал только Otto, и долг тянулся с ADR-0006.
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

	# Агент выходит, когда кабина уже стоит вровень с его этажом, и прямо у её
	# проёма. Раньше он выходил сразу и ловил кабину, бродя по этажу: застанет
	# ли он её в полторы секунды стоянки, решали его паузы и повороты — жребий,
	# ещё и несеянный. Раскладка M24b сдвинула соседние шахты, и тест стал
	# проходить через раз. Проверяется поездка, а не удача в брожении.
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
	# Сеется, как сеет своих уровень ([method GreyboxLevel._release_agent]):
	# несеянный генератор давал бы каждому прогону свои паузы брожения.
	agent.seed_decisions(AGENT_SEED)
	agent.setup(level.otto, 1.0)

	var lowest := from_index
	for _step in RIDE_FRAMES:
		await wait_physics_frames(1)
		var where := rules.floor_index_near(WorldSpace.to_plane(agent.global_position).y)
		lowest = maxi(lowest, where)
		if where >= to_index:
			break

	# Два этажа вниз — это именно поездка. Пешком агенту вниз не попасть: у края
	# перекрытия он разворачивается, а эскалатор трогается только с нажатия,
	# которого у него нет (ADR-0005, пункт 8).
	assert_gte(
		lowest,
		from_index + 2,
		"агент с этажа %d так и не уехал вниз к Otto на %d" % [from_index, to_index]
	)
	assert_false(agent.is_dead(), "ехал, а не падал в шахту")


## Агент в кабине ею не управляет: она ходит своим расписанием, как пустая.
##
## Это и есть вся разница между «ездит» и «водит». Управление кабиной — привилегия
## Otto, и в оригинале её нет даже у стоящего на крыше.
func test_an_agent_aboard_does_not_drive() -> void:
	var level := _build()
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var shaft := _a_shaft_to_ride(level)
	assert_not_null(shaft, "на сиде 1 есть шахта стилобата, по которой ездят")
	if shaft == null:
		return
	var index := shaft.top
	# Otto далеко: агент в кабине не должен получить власть над ней ни при каких
	# обстоятельствах, но кадр не должен ещё и превратиться в перестрелку.
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
	# Пустая кабина ходит от этажа к этажу и с паузой на каждом. Агент внутри
	# ничего в этом не меняет: она не встаёт и не разгоняется.
	#
	# Заодно проверяется, что агент всё это время действительно был внутри:
	# без этого «кабина ходит сама» сходилось бы и с пустой шахтой, то есть
	# не проверяло бы ровно того, ради чего тест написан.
	var moved := 0
	var aboard := 0
	for _step in 240:
		await wait_physics_frames(1)
		if not car.is_aligned():
			moved += 1
		# Допуск в целую ширину шахты, а не в половину: внутри кабины агент
		# переступает от стенки к стенке, и мерка должна отличать «едет»
		# от «ушёл по этажу», а не ловить его шаги.
		if absf(WorldSpace.to_plane(agent.global_position).x - shaft.x) <= rules.shaft_width:
			aboard += 1
	assert_gt(moved, 0, "кабина с агентом внутри продолжает ходить сама")
	assert_eq(aboard, 240, "агент все эти кадры ехал в кабине, а не ушёл по этажу")


## Стоит ли в шахте [param x] кабина вровень с этажом [param index].
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
