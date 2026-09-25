class_name OttoStateMachine
extends RefCounted

## Логика переходов состояний Otto.
##
## Не знает ни про узлы, ни про физику движка: принимает снимок ввода и факты
## о теле, возвращает новое состояние. Поэтому тестируется без сцены.

enum State { IDLE, WALK, CROUCH, JUMP, FALL, RIDE, INDOORS, DEAD }

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


## Отдаёт Otto эскалатору: пока тот его не отпустит, ввод игрока не действует.
##
## Мёртвого эскалатор не поднимает: из [constant State.DEAD] выводит только
## [method reset], иначе поездка воскрешала бы Otto.
func ride() -> void:
	if state == State.DEAD:
		return
	previous_state = state
	state = State.RIDE


## Возвращает управление игроку.
func stop_riding() -> void:
	if state != State.RIDE:
		return
	previous_state = state
	state = State.IDLE


## Otto зашёл в дверь: снаружи его нет, ввод игрока не действует.
##
## Мёртвый в дверь не заходит — по той же причине, что не садится на эскалатор.
func go_indoors() -> void:
	if state == State.DEAD:
		return
	previous_state = state
	state = State.INDOORS


## Otto вышел из двери: срок за ней вышел (ADR-0038, решение 2).
func come_out() -> void:
	if state != State.INDOORS:
		return
	previous_state = state
	state = State.IDLE


## Переводит Otto в терминальное состояние. Выйти из него можно только [method reset].
func kill() -> void:
	previous_state = state
	state = State.DEAD


func is_dead() -> bool:
	return state == State.DEAD


## Распоряжается ли состоянием мир, а не игрок.
##
## Смерть, поездка на эскалаторе и комната за дверью снимаются только снаружи:
## [method kill], [method stop_riding], [method come_out]. Пока Otto в одном из
## них, ввод не разбирается вовсе.
func is_world_driven() -> bool:
	return state == State.DEAD or state == State.RIDE or state == State.INDOORS


## Вошли ли мы в состояние именно в последнем [method update].
func just_entered(value: State) -> bool:
	return state == value and previous_state != value


## Пересчитывает состояние по снимку ввода и фактам о теле.
##
## [param can_stand] — есть ли над головой место, чтобы выпрямиться. Без него
## Otto остаётся в приседе: иначе полная форма коллизии включилась бы в низком
## проёме и вытолкнула его сквозь геометрию.
func update(
	input: OttoInput, on_floor: bool, vertical_velocity: float, can_stand: bool = true
) -> State:
	previous_state = state
	if not is_world_driven():
		state = _resolve(input, on_floor, vertical_velocity, can_stand)
	return state


func _resolve(input: OttoInput, on_floor: bool, vertical_velocity: float, can_stand: bool) -> State:
	if not on_floor:
		return State.JUMP if vertical_velocity < 0.0 else State.FALL
	# Из приседа не встать, пока над головой нет места: ни шагом, ни прыжком.
	if previous_state == State.CROUCH and not can_stand:
		return State.CROUCH
	# Присев, Otto не прыгает — как в оригинале.
	if input.jump_pressed and not input.crouch:
		return State.JUMP
	if input.crouch:
		return State.CROUCH
	if absf(input.move) > MOVE_THRESHOLD:
		return State.WALK
	return State.IDLE
