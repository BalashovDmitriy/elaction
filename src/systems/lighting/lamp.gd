class_name Lamp
extends AnimatableBody3D

## Лампа под потолком этажа.
##
## Сбитая пулей, падает и убивает агента, оказавшегося под ней, — 300 очков, самый
## дорогой способ убийства в оригинале. Упав, гасит свой этаж (ADR-0007).
##
## Otto лампа не трогает: источники говорят только об агентах, поэтому зона удара
## смотрит лишь на их слой.
##
## Узел двигает себя сам, поэтому [AnimatableBody3D], а не [StaticBody3D] — как и
## кабина лифта. Само падение считает [LampFall], без узлов и физики.
##
## С M15 лампа — единственный источник света на этаже (ADR-0021, решение 4):
## заливки этажа больше нет, и «этаж горит» значит ровно «лампа висит».

## Лампа задела агента по дороге вниз. Убивает его и считает очки уровень.
signal crushed(agent: Enemy)

## Лампа долетела до пола. Уровень по этому сигналу гасит этаж: какой именно,
## он знает сам — этаж привязан к обработчику, когда лампу вешали.
signal fell

## Свет лампы: докуда достаёт, цвет и сила.
##
## Свет — ребёнок лампы, поэтому падает вместе с ней и гаснет, когда её
## убирают с пола. Тени включены: свет упирается в перекрытия и стены, и
## именно это показывает, что светит лампа, а не воздух.
const LIGHT_RANGE: float = 2.88
const LIGHT_COLOR := Color(1.0, 0.93, 0.72)
const LIGHT_ENERGY: float = 1.1

@export var fall_speed: float = 7.8

## Этаж, на котором лампа висит. Записывает уровень, когда вешает её.
##
## Выводить этаж обратно из координаты нельзя: лампа висит ровно посередине
## пролёта, между двумя полами, и [method BuildingRules.floor_index_near] на
## этой середине решает по последнему биту дроби — на пикселях он падал на один
## этаж, на метрах упал на другой.
var floor_index: int = 0

var _fall := LampFall.new()
var _light: OmniLight3D = null

@onready var _crush_zone: Area3D = $CrushZone
@onready var _visual: MeshInstance3D = $Visual
@onready var _shape: CollisionShape3D = $Shape


func _ready() -> void:
	_fall.speed = fall_speed
	_visual.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_light = _make_light()
	add_child(_light)


func _physics_process(delta: float) -> void:
	var step := _fall.advance(delta)
	if is_zero_approx(step):
		return

	# Падение у правил — рост Y, у сцены — убывание.
	position.y -= step
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
	var box := _shape.shape as BoxShape3D
	_fall.distance = maxf(hang_height - box.size.y * 0.5, 0.0)


## Сбита выстрелом. Повторные попадания ничего не меняют, в том числе и по уже
## упавшей: [method queue_free] убирает её лишь в конце кадра, и до тех пор она
## продолжает ловить пули.
func shoot_down() -> void:
	if not _fall.start():
		return
	# Сбитая лампа перестаёт светиться сама: корпус тот же, но уже не светильник.
	_visual.material_override = GreyboxLook.surface(GreyboxLook.LAMP)
	Sounds.play(Sounds.LAMP_BREAK)


## Гасит или зажигает свет лампы. Зовёт уровень, отбирая видимые этажи: свет
## кладёт тени и стоит дорого, поэтому за кадром ему гореть незачем
## (ADR-0010, пункт 8). Сама лампа при этом остаётся как была.
func set_light_visible(on: bool) -> void:
	_light.visible = on


func _make_light() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = true
	return light


func _crush_agents() -> void:
	for body: Node3D in _crush_zone.get_overlapping_bodies():
		var agent := body as Enemy
		if agent == null or agent.is_dead():
			continue
		crushed.emit(agent)


func _land() -> void:
	Sounds.play(Sounds.LAMP_CRASH)
	fell.emit()
	# Осколки не оставляем: тёмный этаж и так виден, а тело на полу ловило бы
	# пули игрока, которым положено лететь дальше.
	queue_free()
