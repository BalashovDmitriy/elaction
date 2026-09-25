extends GutTest

## Кабина давит агентов — 300 очков, как в ROM (ADR-0027, решение 6).
##
## Долг M18b: давилась только Otto. Сцена минимальная — пол, кабина над ним и
## агент под её днищем: здание целиком тут ни к чему, проверяется правило
## кабины, а не раскладка.

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")

## Сколько шагов физики ждать, пока кабина доедет вниз: пауза у этажа плюс
## перегон, с запасом.
const RIDE_FRAMES: int = 600


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Пол нижнего этажа на высоте −3.6 м сцены: кабина стоит этажом выше.
func _floor_at(height: float) -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.4, WorldSpace.CORRIDOR_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	ground.add_child(shape)
	add_child_autofree(ground)
	ground.global_position = Vector3(0.0, height, 0.0)


func _agent_under_the_car() -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.walk_speed = 0.0
	add_child_autofree(agent)
	agent.global_position = Vector3(0.0, -Proportions.FLOOR, 0.0)
	agent.setup(null, 1.0)
	return agent


func test_a_descending_car_crushes_the_agent_under_it() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	# Остановки в координатах правил: вниз — рост. Кабина на верхней и поедет
	# к нижней сама, своим расписанием.
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	var agent := _agent_under_the_car()
	var before := GameState.instance().score

	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		if agent.is_dead():
			break

	assert_true(agent.is_dead(), "кабина раздавила агента под днищем")
	assert_eq(GameState.instance().score - before, GameState.CRUSH_SCORE, "300 очков")


## Кабина давит и Otto, который стоит под ней на полу, — он не пассажир.
##
## До M24a Otto становился пассажиром, едва голова заходила в проём опускающейся
## кабины: занятость спасала его от сдавливания, а занятая кабина без команды
## вставала между этажами — оба застывали навсегда (ADR-0037, решение 1).
func test_a_descending_car_crushes_otto_under_it() -> void:
	GameState.instance().start_game()
	_floor_at(-Proportions.FLOOR)
	var car := CAR_SCENE.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.setup(PackedFloat32Array([0.0, Proportions.FLOOR]), 0)
	var otto := OTTO_SCENE.instantiate() as Otto
	add_child_autofree(otto)
	otto.global_position = Vector3(0.0, -Proportions.FLOOR, WorldSpace.PLAY_Z)

	var boarded := false
	for _frame: int in RIDE_FRAMES:
		await wait_physics_frames(1)
		boarded = boarded or otto.is_riding()
		if otto.is_dead() or boarded:
			break

	assert_false(boarded, "стоящий под кабиной — не пассажир")
	assert_true(otto.is_dead(), "кабина раздавила Otto под днищем")
