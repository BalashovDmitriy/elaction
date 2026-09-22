extends GutTest

## Каждая кабина здания слушается игрока.
##
## Отзыв после игры: «на некоторых лифтах не работало управление — кабина
## не слушалась команд и стояла, а стоило сойти, как она уезжала». Проверка
## поэтому не про одну кабину из сцены, а про все, какие соберёт генератор:
## баг был не у всех.
##
## Высоты сравниваются в плоскости правил, где вниз — это рост Y: так считала
## кабина в 2D, и так утверждения ниже остались нетронутыми при переезде.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров даётся зданию, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Сколько кадров держать команду. Кабина идёт 1.8 м/с, этаж — 3.6 м:
## за полсекунды она обязана сдвинуться заметно.
const DRIVE_FRAMES: int = 30

## Насколько кабина должна уехать, чтобы это считалось «слушается», м.
const MOVED: float = 0.2

## Допуск на совпадение координат, м: на дробную арифметику, и только на неё.
const TOLERANCE: float = 0.01


func before_all() -> void:
	Engine.time_scale = 1.0


func after_all() -> void:
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
##
## Ярусы двухэтажных пар ([method ElevatorCar.is_deck]) сюда не идут: у них
## своего хода нет, они держатся за ведущим, и ставить их на остановки руками
## бессмысленно. С M18b их в дереве на одну-две больше, чем шахт, и счёт
## по порядку без этого отбора разъезжался (ADR-0025, решение 1).
func _cars(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck():
			found.append(car)
	return found


## Ярусы пар: по одному на двухэтажную шахту.
func _decks(level: GreyboxLevel) -> Array[ElevatorCar]:
	var found: Array[ElevatorCar] = []
	for child: Node in level.get_children():
		var car := child as ElevatorCar
		if car != null and car.is_deck():
			found.append(car)
	return found


## Высота кабины в плоскости правил.
func _height(car: ElevatorCar) -> float:
	return WorldSpace.to_plane(car.global_position).y


## Насколько виден указатель: коробка гасится прозрачностью.
func _alpha(arrow: MeshInstance3D) -> float:
	return 1.0 - arrow.transparency


## Ставит Otto внутрь кабины и ждёт, пока она его заметит.
func _get_in(level: GreyboxLevel, car: ElevatorCar) -> void:
	level.otto.global_position = car.global_position
	level.otto.velocity = Vector3.ZERO
	await wait_physics_frames(SETTLE_FRAMES)


## Ставит кабину на нужный этаж её полосы.
##
## Через [method ElevatorCar.setup], а не через координату: у хода кабины своё
## состояние, и переставленная руками она возвращается туда, где себя считает.
func _park(
	level: GreyboxLevel, car: ElevatorCar, shaft: BuildingPlan.ShaftSpot, index: int
) -> void:
	var stops := PackedFloat32Array()
	for floor_index: int in range(shaft.top, shaft.bottom + 1):
		stops.append(level.rules.floor_surface(floor_index))
	car.setup(stops, index - shaft.top)
	# Кабина переносит себя в координату своим кадром: пока он не прошёл, она
	# стоит там, где стояла, и вошедший в неё оказался бы у прежнего места.
	await wait_physics_frames(1)


func _drive(action: StringName) -> void:
	Input.action_press(action)
	await wait_physics_frames(DRIVE_FRAMES)
	Input.action_release(action)
	await wait_physics_frames(1)


func test_every_car_obeys_the_player() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var shafts := level.plan().shafts
		var cars := _cars(level)
		# Кабины стоят в дереве в порядке шахт — уровень их так и ставит. Порядок
		# нигде не обещан, а тест на нём держится: перепутанная пара молча
		# поставила бы кабину на чужие остановки, и проверка стала бы зелёной,
		# ничего не проверяя.
		assert_eq(
			cars.size(), shafts.size(), "сид %d: кабин не столько, сколько шахт" % building_seed
		)
		var pairs := 0
		for shaft in shafts:
			if shaft.double_deck:
				pairs += 1
		assert_eq(
			_decks(level).size(),
			pairs,
			"сид %d: ярусов не столько, сколько двухэтажных шахт" % building_seed
		)
		for index: int in cars.size():
			var shaft: BuildingPlan.ShaftSpot = shafts[index]
			var number := index + 1
			assert_almost_eq(
				WorldSpace.to_plane(cars[index].global_position).x,
				shaft.x,
				TOLERANCE,
				"сид %d, кабина %d: встала не в своей шахте" % [building_seed, number]
			)
			# Кабина ставится на верх своей полосы, а не берётся там, где её
			# застал прогон. Пустая кабина катается сама, и застать её можно
			# на нижнем упоре — тогда «не поехала вниз по команде» означало бы
			# «ехать было некуда», то есть тест падал бы по очереди на разных
			# сидах без всякой поломки.
			var car: ElevatorCar = cars[index]
			await _park(level, car, shaft, shaft.top)
			await _get_in(level, car)
			assert_true(
				level.otto.is_riding(),
				(
					"сид %d, кабина %d: Otto внутри, а кабина этого не заметила"
					% [building_seed, number]
				)
			)

			var before := _height(car)
			await _drive(&"move_down")
			var moved := _height(car) - before
			assert_gt(
				moved,
				MOVED,
				(
					"сид %d, кабина %d на %.2f: не поехала вниз по команде (сдвинулась на %.2f м)"
					% [building_seed, number, before, moved]
				)
			)
		_drop(level)


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## Кабина у края своей полосы дальше не едет — и это не поломка, а устройство
## шахт: они не сквозные (ADR-0008). Но вверх она обязана пойти.
##
## Отзыв после игры выглядел именно так: «не слушается и стоит, сошёл — уехала».
## Стоящая у предела кабина ведёт себя ровно так, и тест держит это поведение
## описанным, чтобы в следующий раз его не чинили как баг.
func test_car_at_the_end_of_its_band_still_goes_the_other_way() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	# Ставим кабину на нижний этаж её полосы и Otto в неё.
	await _park(level, car, shaft, shaft.bottom)
	await _get_in(level, car)

	var before := _height(car)
	await _drive(&"move_down")
	assert_almost_eq(_height(car), before, MOVED, "ниже своей полосы кабина не идёт")

	await _drive(&"move_up")
	assert_lt(_height(car), before - MOVED, "а вверх — идёт")
	_drop(level)


## Otto входит в кабину шагом, как игрок, а не появляется в ней.
##
## Вход шагом — единственный, какой бывает в игре, и именно на нём кабина
## однажды переставала слушаться: занятой она себя считала, а команд не получала.
func test_car_obeys_after_otto_walks_in() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	# Кабина встаёт на верхний этаж полосы, Otto — рядом с проёмом на том же полу.
	var index := maxi(shaft.top, 0)
	var surface := rules.floor_surface(index)
	await _park(level, car, shaft, index)
	level.otto.global_position = WorldSpace.to_scene(Vector2(shaft.x - rules.shaft_width, surface))
	await wait_physics_frames(SETTLE_FRAMES)

	# Идём вправо, пока не окажемся в кабине.
	Input.action_press(&"move_right")
	var left := 120
	while not level.otto.is_riding() and left > 0:
		await wait_physics_frames(1)
		left -= 1
	Input.action_release(&"move_right")
	await wait_physics_frames(1)
	assert_true(level.otto.is_riding(), "Otto вошёл в кабину шагом")

	var before := _height(car)
	await _drive(&"move_down")
	assert_gt(_height(car) - before, MOVED, "вошедшего шагом кабина слушается так же")
	_drop(level)


## Указатель в кабине гаснет там, где полоса кончается.
##
## Это вторая половина ответа на «лифт не слушается»: упор в шахте показывает
## предел снаружи, стрелка — изнутри кабины, где упора не видно.
func test_car_arrow_goes_dark_at_the_end_of_the_band() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var shaft := level.plan().shafts[0]
	var car := _cars(level)[0]
	var down := car.get_node("DownArrow") as MeshInstance3D
	var up := car.get_node("UpArrow") as MeshInstance3D

	await _park(level, car, shaft, shaft.bottom)
	await wait_physics_frames(1)
	assert_lt(_alpha(down), 0.5, "внизу полосы стрелка вниз погасла")
	assert_almost_eq(_alpha(up), 1.0, 0.01, "а вверх — горит")

	await _park(level, car, shaft, shaft.top)
	await wait_physics_frames(1)
	assert_lt(_alpha(up), 0.5, "наверху полосы гаснет стрелка вверх")
	assert_almost_eq(_alpha(down), 1.0, 0.01, "а вниз — горит")
	_drop(level)
