class_name Lamp
extends AnimatableBody2D

## Лампа под потолком этажа.
##
## Сбитая пулей, падает и убивает агента, оказавшегося под ней, — 300 очков, самый
## дорогой способ убийства в оригинале. Упав, гасит свой этаж (ADR-0007).
##
## Otto лампа не трогает: источники говорят только об агентах, поэтому зона удара
## смотрит лишь на их слой.
##
## Узел двигает себя сам, поэтому [AnimatableBody2D], а не [StaticBody2D] — как и
## кабина лифта. Само падение считает [LampFall], без узлов и физики.

## Лампа задела агента по дороге вниз. Убивает его и считает очки уровень.
signal crushed(agent: Enemy)

## Лампа долетела до пола. Уровень по этому сигналу гасит этаж: какой именно,
## он знает сам — этаж привязан к обработчику, когда лампу вешали.
signal fell

const LIT_COLOR := Color(0.95, 0.90, 0.55)
const FALLING_COLOR := Color(0.72, 0.66, 0.38)

## Пятно света под лампой: радиус, цвет и сила.
##
## Свет — ребёнок лампы, поэтому падает вместе с ней и гаснет, когда её
## убирают с пола. Этаж при этом гасит не он, а заливка (ADR-0010, пункт 3):
## лампа светит собой, а «на этаже есть свет» — это отдельный источник.
const LIGHT_RADIUS: float = 96.0
const LIGHT_COLOR := Color(1.0, 0.93, 0.72)
const LIGHT_ENERGY: float = 1.1

@export var fall_speed: float = 260.0

var _fall := LampFall.new()
var _light: PointLight2D = null

@onready var _crush_zone: Area2D = $CrushZone
@onready var _visual: ColorRect = $Visual
@onready var _shape: CollisionShape2D = $Shape


func _ready() -> void:
	_fall.speed = fall_speed
	_visual.color = LIT_COLOR
	_light = _make_light()
	add_child(_light)


func _physics_process(delta: float) -> void:
	var step := _fall.advance(delta)
	if is_zero_approx(step):
		return

	position.y += step
	# Проверяем каждый кадр падения: лампа сбивает всех, кого прошла насквозь.
	_crush_agents()

	if _fall.has_landed():
		_land()


## Вешает лампу: [param hang_height] — на сколько её середина выше пола этажа.
##
## Сколько лететь, лампа считает по своей же высоте: иначе уровню пришлось бы
## держать копию размера из lamp.tscn и следить, чтобы та не разъехалась.
## Звать после добавления в дерево — форма берётся из узла.
func hang(hang_height: float) -> void:
	var box := _shape.shape as RectangleShape2D
	_fall.distance = maxf(hang_height - box.size.y * 0.5, 0.0)


## Сбита выстрелом. Повторные попадания ничего не меняют, в том числе и по уже
## упавшей: [method queue_free] убирает её лишь в конце кадра, и до тех пор она
## продолжает ловить пули.
func shoot_down() -> void:
	if not _fall.start():
		return
	_visual.color = FALLING_COLOR


## Гасит или зажигает пятно лампы. Зовёт уровень, отбирая видимые этажи:
## пятно кладёт тени и стоит дороже заливки, поэтому за кадром ему гореть
## незачем (ADR-0010, пункт 8). Сама лампа при этом остаётся как была.
func set_light_visible(on: bool) -> void:
	_light.visible = on


## Пятно под лампой. Тени включены: свет упирается в перекрытия и в стены
## шахты, и именно это показывает, что светит лампа, а не воздух.
func _make_light() -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = LightTextures.spot()
	light.color = LIGHT_COLOR
	light.energy = LIGHT_ENERGY
	light.shadow_enabled = true
	light.scale = Vector2.ONE * (LIGHT_RADIUS * 2.0 / float(LightTextures.SIZE))
	return light


func _crush_agents() -> void:
	for body: Node2D in _crush_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		crushed.emit(agent)


func _land() -> void:
	fell.emit()
	# Осколки не оставляем: тёмный этаж и так виден, а тело на полу ловило бы
	# пули игрока, которым положено лететь дальше.
	queue_free()
