class_name OttoInput
extends RefCounted

## Снимок ввода за один кадр.
##
## Отделяет [OttoStateMachine] от синглтона [Input]: в игре снимок собирается
## из действий, в тестах — заполняется руками.

## Направление по горизонтали: -1 влево, +1 вправо, 0 стоим.
var move: float = 0.0

## Удерживается ли приседание.
var crouch: bool = false

## Нажат ли прыжок именно в этом кадре.
var jump_pressed: bool = false


## Перечитывает снимок из карты действий проекта.
##
## Метод, а не фабрика: снимок переиспользуется кадр за кадром, чтобы не
## выделять по объекту на каждый физический кадр.
func read_actions() -> void:
	move = Input.get_axis("move_left", "move_right")
	crouch = Input.is_action_pressed("move_down")
	jump_pressed = Input.is_action_just_pressed("jump")
