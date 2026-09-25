extends GutTest

## Otto у шахты с кабиной, идущей к его этажу, никогда не застывает вместе с ней
## (ADR-0037, решение 1).
##
## Отзыв после M23: Otto становился пассажиром, едва тело заходило в проём, хотя
## кабина была ещё на пару метров ниже этажа. Занятая кабина без команды стоит,
## невровень с этажом из неё не шагнуть — оба стояли навсегда. Так же — с
## кабиной сверху и с двухэтажной парой. Поэтому проверка идёт на любом здании:
## на нескольких сидах, у каждой шахты, с кабиной снизу и сверху. Исход
## допустим один из двух: Otto может идти (он не в кабине или кабина вровень
## с этажом) или погиб. Застыть в кабине между этажами он не должен.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3]

## Сколько кадров даётся зданию, чтобы встать на места, и Otto — чтобы встать.
const SETTLE_FRAMES: int = 4

## Насколько далеко от этажа кабина, когда Otto трогается к шахте, м.
##
## Две дистанции, по очереди от шахты к шахте. Ближняя — Otto подходит, когда
## кабина уже почти пришла: снизу он шагает на её пол, сверху упирается в днище.
## Дальняя — кабина ещё в метре: снизу он упирается в крышу или падает на пол
## кабины, сверху — в днище. Именно с дальней в M23 Otto и садился в кабину.
const TRIGGERS: Array[float] = [1.3, 0.6]

## На сколько от края шахты стоит Otto, ожидая кабину, м, от края до края тела.
const WAIT_GAP: float = 0.4

## Сколько шагов бота ждать, пока кабина дойдёт до дистанции: пауза на этаже
## и перегон, с запасом.
const APPROACH_STEPS: int = 200

## Сколько шагов Otto идёт к шахте, прежде чем исход считается состоявшимся:
## кабина доходит, стоит паузу, он входит — пара секунд под time_scale 4.
const WALK_STEPS: int = 90

## Сколько шагов подряд пассажир может стоять в кабине между этажами, прежде
## чем это считается застыванием. Кабина в пути не стоит ни шага.
const FROZEN_STEPS: int = 20

## Сколько шагов ждать, пока уровень вернёт погибшего Otto в игру.
const RESPAWN_STEPS: int = 120


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	Input.action_release(&"move_left")
	Input.action_release(&"move_right")
	GameState.instance().reset()


func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## Кабины со своим ходом — по одной на шахту, в порядке шахт.
func _cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck():
			found.append(car)
	return found


## Остановки ведущей кабины — так же, как их считает уровень: верхний ярус пары
## на нижний этаж шахты не спускается.
func _stops(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot) -> PackedFloat32Array:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var stops := PackedFloat32Array()
	for index: int in range(shaft.top, lowest + 1):
		stops.append(level.rules.floor_surface(index))
	return stops


## Где стоит кабина, которая придёт к этажу Otto первой, и какой это этаж.
##
## Снизу — ведущая с нижней своей остановки, на этаж выше неё. Сверху — с
## верхней, на этаж ниже; у пары этажом ниже ведущей стоит ярус, и первым
## к этажу приходит он — поэтому этаж Otto ещё на один ниже. Короткой полосе
## проверять нечего: пустой вектор.
func _approach(shaft: BuildingPlan.ShaftSpot, from_below: bool) -> Vector2i:
	var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
	var deck := 1 if shaft.double_deck else 0
	if from_below:
		var start := lowest
		var target := start - 1 - deck
		return Vector2i(start, target) if target >= shaft.top else Vector2i(-99, -99)
	var target := shaft.top + 1 + deck
	return Vector2i(shaft.top, target) if target <= shaft.bottom else Vector2i(-99, -99)


func _plane(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## Ставит Otto у шахты на этаже [param index], с той стороны, где есть пол.
## Возвращает сторону, -1 или +1, или 0, если пола у шахты нет с обеих сторон.
func _stand_by(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot, index: int) -> float:
	var surface := level.rules.floor_surface(index)
	var aside := level.rules.shaft_width * 0.5 + Proportions.BODY_WIDTH * 0.5 + WAIT_GAP
	for side: float in [-1.0, 1.0]:
		level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x + side * aside, surface))
		level.otto.velocity = Vector3.ZERO
		await wait_physics_frames(SETTLE_FRAMES)
		var at := _plane(level.otto)
		if level.otto.is_grounded() and absf(at.y - surface) < 0.05:
			return side
	return 0.0


## Возвращает погибшего Otto в игру руками уровня и ждёт, пока тот это сделает.
func _wait_for_respawn(level: GreyboxLevel) -> void:
	var left := RESPAWN_STEPS
	while level.otto.is_dead() and left > 0:
		await wait_physics_frames(1)
		left -= 1


func test_otto_never_freezes_with_an_arriving_car() -> void:
	var checked := 0
	var boarded := 0
	for building_seed: int in SEEDS:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)
		var shafts := level.plan().shafts
		var cars := _cars(level)
		assert_eq(
			cars.size(), shafts.size(), "сид %d: кабин не столько, сколько шахт" % building_seed
		)
		for index: int in cars.size():
			for from_below: bool in [true, false]:
				var shaft: BuildingPlan.ShaftSpot = shafts[index]
				var plan := _approach(shaft, from_below)
				if plan.y == -99:
					continue
				var where := (
					"сид %d, шахта %d, кабина %s, этаж %d"
					% [building_seed, index + 1, "снизу" if from_below else "сверху", plan.y]
				)
				var outcome := await _meet(
					level, cars[index], shaft, plan, TRIGGERS[(index + int(from_below)) % 2], where
				)
				if outcome < 0:
					continue
				checked += 1
				boarded += outcome
		remove_child(level)
	# Проверка, которая ни разу не сработала, ничего не проверяет.
	assert_gt(checked, 10, "встреч с кабиной проверено слишком мало: %d" % checked)
	assert_gt(boarded, 5, "Otto сел в подошедшую кабину слишком редко: %d" % boarded)


## Одна встреча: кабина идёт к этажу Otto, он трогается к шахте на дистанции.
##
## Возвращает 1, если Otto сел в кабину вровень с этажом, 0 — если исход
## другой, но допустимый, и -1, если встречу поставить не удалось.
func _meet(
	level: GreyboxLevel,
	car: ElevatorCar,
	shaft: BuildingPlan.ShaftSpot,
	plan: Vector2i,
	trigger: float,
	where: String
) -> int:
	GameState.instance().lives = GameState.STARTING_LIVES
	await _wait_for_respawn(level)
	var otto := level.otto
	# Сначала Otto встаёт, потом кабина ставится: пока он ищет пол, пустая
	# кабина успела бы уехать.
	var side := await _stand_by(level, shaft, plan.y)
	if side == 0.0:
		return -1
	var stops := _stops(level, shaft)
	car.setup(stops, plan.x - shaft.top)
	await wait_physics_frames(1)

	var surface := level.rules.floor_surface(plan.y)
	var left := APPROACH_STEPS
	while absf(_plane(car).y - surface) > trigger + _deck_drop(level, shaft, plan) and left > 0:
		await wait_physics_frames(1)
		left -= 1
	if left == 0:
		fail_test("%s: кабина не подошла к этажу" % where)
		return -1

	var toward := &"move_left" if side > 0.0 else &"move_right"
	Input.action_press(toward)
	var stuck := 0
	var boarded := false
	for _step: int in WALK_STEPS:
		await wait_physics_frames(1)
		if otto.is_dead():
			break
		if otto.is_riding() and car.is_aligned():
			boarded = true
			break
		if otto.is_riding() and car.speed_now() == 0.0:
			stuck += 1
		else:
			stuck = 0
		if stuck >= FROZEN_STEPS:
			break
	Input.action_release(toward)
	await wait_physics_frames(1)

	var frozen := otto.is_riding() and not car.is_aligned()
	assert_false(
		frozen,
		(
			"%s: Otto застыл в кабине между этажами (кабина в %.2f м от этажа)"
			% [where, _plane(car).y - surface]
		)
	)
	return 1 if boarded else 0


## На сколько ниже ведущей стоит кабина, которая придёт к этажу Otto: у пары
## сверху первым приходит ярус, и дистанцию до этажа считать надо по нему.
func _deck_drop(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot, plan: Vector2i) -> float:
	if not shaft.double_deck or plan.y < plan.x:
		return 0.0
	# Ведущая идёт сверху, ярус — этажом ниже неё: до этажа Otto она на этаж
	# дальше, чем ярус.
	return level.rules.floor_height
