class_name OttoStateMachine
extends RefCounted

## Логика переходов состояний Otto.
##
## Не знает ни про узлы, ни про физику движка: принимает снимок ввода и факты
## о теле, возвращает новое состояние. Поэтому тестируется без сцены.

enum State { IDLE, WALK, CROUCH, JUMP, FALL, DEAD }

## Ниже этого порога наклон стика считается покоем.
const MOVE_THRESHOLD: float = 0.1

## Имена состояний собираются один раз: [method state_name] зовут каждый кадр.
static var _state_names: PackedStringArray = PackedStringArray(State.keys())

var state: State = State.IDLE
var previous_state: State = State.IDLE


## Имя состояния для отладочного вывода.
static func state_name(value: State) -> String:
	return _state_names[value]


func reset() -> void:
	state = State.IDLE
	previous_state = State.IDLE


## Переводит Otto в терминальное состояние. Выйти из него можно только [method reset].
func kill() -> void:
	previous_state = state
	state = State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## Вошли ли мы в состояние именно в последнем [method update].
func just_entered(value: State) -> bool:
	return state == value and previous_state != value


func update(input: OttoInput, on_floor: bool, vertical_velocity: float) -> State:
	previous_state = state
	if state != State.DEAD:
		state = _resolve(input, on_floor, vertical_velocity)
	return state


func _resolve(input: OttoInput, on_floor: bool, vertical_velocity: float) -> State:
	if not on_floor:
		return State.JUMP if vertical_velocity < 0.0 else State.FALL
	# Присев, Otto не прыгает — как в оригинале.
	if input.jump_pressed and not input.crouch:
		return State.JUMP
	if input.crouch:
		return State.CROUCH
	if absf(input.move) > MOVE_THRESHOLD:
		return State.WALK
	return State.IDLE
