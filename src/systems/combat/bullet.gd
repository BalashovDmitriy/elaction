class_name Bullet
extends Area2D

## Пуля.
##
## Летит по горизонтали и гаснет о геометрию, о жертву или на дальности. Высота
## полёта задана точкой выстрела: от высокой пули приседают, низкую перепрыгивают.
## Отдельного правила для уклонения не нужно — всё решают формы коллизии, а они
## у Otto разные стоя и в приседе (ADR-0006, пункт 3).
##
## В кого попадать, решает маска: пуля Otto не задевает его самого, вражеская —
## не задевает других врагов.

## Пуля во что-то попала. Разбирается с этим тот, кто её выпустил: он знает, свои
## это или чужие, и ему же идут очки.
signal hit_target(target: Node2D)

## Во что попадает пуля. Слои: 1 — геометрия, 2 — Otto, 4 — враги, 8 — лампы.
##
## Названы по стрелявшему, а не по мишени: пуля Otto бьёт и по агентам, и по
## лампам, и одним словом это не назвать.
const FROM_OTTO: int = 1 | 4 | 8
const FROM_ENEMY: int = 1 | 2

@export var speed: float = 220.0

## Дальше этого пуля гаснет сама, даже не встретив преграды.
@export var max_range: float = 480.0

## Куда летит: -1 влево, +1 вправо.
var direction: float = 1.0

var _travelled: float = 0.0
## Пуля уже во что-то попала и доживает до конца кадра.
var _spent: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step := speed * delta * signf(direction)
	position.x += step
	_travelled += absf(step)
	if _travelled >= max_range:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	# queue_free() убирает узел только в конце кадра, а тел за один кадр можно
	# задеть несколько: без этой отметки одна пуля убивала бы двоих сразу и
	# приносила очки за каждого.
	if _spent:
		return
	_spent = true
	# Геометрия просто гасит пулю, живых разбирает стрелявший.
	hit_target.emit(body)
	queue_free()
