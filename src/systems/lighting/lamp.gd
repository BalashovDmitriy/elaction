class_name Lamp
extends StaticBody2D

## Лампа под потолком этажа.
##
## Сбитая пулей, падает и убивает агента, оказавшегося под ней, — 300 очков, самый
## дорогой способ убийства в оригинале. Упав, гасит свой этаж (ADR-0007).
##
## Otto лампа не трогает: источники говорят только об агентах, поэтому зона удара
## смотрит лишь на их слой.

## Лампа задела агента по дороге вниз. Убивает его и считает очки уровень.
signal crushed(agent: Enemy)

## Лампа долетела до пола. Уровень по этому сигналу гасит этаж.
signal fell(lamp: Lamp)

const LIT_COLOR := Color(0.95, 0.90, 0.55)
const FALLING_COLOR := Color(0.72, 0.66, 0.38)

@export var fall_speed: float = 260.0

## Сколько лететь до пола, px. Ставит уровень, когда вешает лампу.
@export var fall_distance: float = 74.0

var _falling: bool = false
var _fallen: float = 0.0

@onready var _crush_zone: Area2D = $CrushZone
@onready var _visual: ColorRect = $Visual


func _ready() -> void:
	_visual.color = LIT_COLOR


func _physics_process(delta: float) -> void:
	if not _falling:
		return

	var step := minf(fall_speed * delta, fall_distance - _fallen)
	position.y += step
	_fallen += step
	# Проверяем каждый кадр падения: лампа сбивает всех, кого прошла насквозь.
	_crush_agents()

	if _fallen >= fall_distance:
		_land()


## Сбита выстрелом. Повторные попадания ничего не меняют.
func shoot_down() -> void:
	if _falling:
		return
	_falling = true
	_visual.color = FALLING_COLOR


## Горит ли лампа ещё.
func is_lit() -> bool:
	return not _falling


func _crush_agents() -> void:
	for body: Node2D in _crush_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		crushed.emit(agent)


func _land() -> void:
	_falling = false
	fell.emit(self)
	# Осколки не оставляем: тёмный этаж и так виден, а тело на полу ловило бы
	# пули игрока, которым положено лететь дальше.
	queue_free()
