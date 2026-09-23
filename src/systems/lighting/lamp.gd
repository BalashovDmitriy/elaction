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
## Лампа — единственный источник света своей зоны (ADR-0021, решение 4;
## ADR-0023, решение 3): конус вниз с мягкой тенью и слабая заливка вокруг,
## оба её дети. «Зона горит» значит ровно «лампа висит».

## Лампа задела агента по дороге вниз. Убивает его и считает очки уровень.
signal crushed(agent: Enemy)

## Лампа долетела до пола. Уровень по этому сигналу гасит этаж: какой именно,
## он знает сам — этаж привязан к обработчику, когда лампу вешали.
signal fell

## Конус вниз: даёт пятно на полу и рёбра теней, как светильники на референсе.
## Тени мягкие: свет упирается в перекрытия и стены, и именно это показывает,
## что светит лампа, а не воздух.
const SPOT_RANGE: float = 6.0
const SPOT_ANGLE: float = 60.0
const SPOT_ENERGY: float = 9.0
const SPOT_BLUR: float = 1.6

## Заливка вокруг: слабая и широкая. Один конус оставлял бы между лампами
## черноту при всех горящих — а зона считается освещённой целиком.
##
## С тенью, хотя тень на второй источник каждой лампы и стоит денег. Без неё
## заливка радиусом больше высоты этажа (3 м) светит сквозь перекрытия: на
## кадре погашенного этажа его пол подсвечивали лампы этажа снизу, и темнота
## переставала быть темнотой (авторевью M17). Резать радиус нельзя — он и
## нужен, чтобы дотянуться до краёв зоны.
const FILL_RANGE: float = 7.0
const FILL_ENERGY: float = 1.5

## Тёплый цвет лампы против холодного общего тона палитры (ADR-0023, решение 3).
const LIGHT_COLOR := Color(1.0, 0.9, 0.7)

## Шнур подвеса, м: толщина. Длина — от патрона до потолка, и её знает уровень.
const CORD_WIDTH: float = 0.03

## Абажур: радиус верха, радиус низа и высота; чашка подвеса — радиус и
## высота, м (ADR-0031, решение 3).
const SHADE := Vector3(0.1, 0.3, 0.26)
const CANOPY := Vector2(0.08, 0.05)
const SHADE_COLOR := Color(0.42, 0.4, 0.36)
## Чаша рассеивателя под абажуром: радиус и глубина, м.
const BOWL := Vector2(0.27, 0.13)

@export var fall_speed: float = 7.8

## Этаж, на котором лампа висит. Записывает уровень, когда вешает её.
##
## Выводить этаж обратно из координаты нельзя: до M18c лампа висела ровно
## посередине пролёта, между двумя полами, и [method BuildingRules.floor_index_near]
## на этой середине решал по последнему биту дроби — на пикселях он падал на один
## этаж, на метрах на другой. Под потолком она ближе к полу этажа выше, чем
## к своему, и вывод из координаты ошибался бы уже всегда.
var floor_index: int = 0

var _fall := LampFall.new()
var _spot: SpotLight3D = null
var _fill: OmniLight3D = null
var _cord: MeshInstance3D = null
## Рассеиватель абажура: светится, пока лампа цела (ADR-0031, решение 3).
var _diffuser: MeshInstance3D = null

@onready var _crush_zone: Area3D = $CrushZone
@onready var _visual: MeshInstance3D = $Visual
@onready var _shape: CollisionShape3D = $Shape


## Габарит лампы по [Proportions]. Зона удара шире и выше самой лампы: агент
## гибнет, если лампа задела его краем, а не только серединой.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var body := Vector3(Proportions.LAMP.x, Proportions.LAMP.y, 0.4)
	Proportions.fit_box($Shape as CollisionShape3D, body, false)
	Proportions.fit_mesh($Visual as MeshInstance3D, body)
	Proportions.fit_box(
		$CrushZone/CrushShape as CollisionShape3D, body * Vector3(1.2, 1.13, 1.0), false
	)


func _ready() -> void:
	_fall.speed = fall_speed
	# Светильник и есть источник: он светится сам и виден с любого этажа.
	_visual.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_dress_fixture()
	_spot = _make_spot()
	add_child(_spot)
	_fill = _make_fill()
	add_to_group(Graphics.GROUP)
	apply_graphics()
	add_child(_fill)


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


## Вешает лампу: [param hang_height] — на сколько её середина выше пола этажа,
## [param headroom] — высота этажа от пола до потолка: до него идёт шнур.
##
## Сколько лететь, лампа считает по своей же высоте: иначе уровню пришлось бы
## держать копию размера из lamp.tscn и следить, чтобы та не разъехалась.
## Звать после добавления в дерево — форма берётся из узла.
func hang(hang_height: float, headroom: float = 0.0) -> void:
	var box := _shape.shape as BoxShape3D
	_fall.distance = maxf(hang_height - box.size.y * 0.5, 0.0)

	# Прежний шнур снимается до проверки длины: перевешенная лампа не должна
	# оставлять на себе обрывок от прошлой высоты.
	if _cord != null:
		_cord.queue_free()
		_cord = null
	var cord_length := headroom - hang_height - box.size.y * 0.5
	if cord_length <= 0.0:
		return
	_cord = GreyboxLook.box(
		Vector3(CORD_WIDTH, cord_length, CORD_WIDTH), GreyboxLook.surface(GreyboxLook.WALL)
	)
	_cord.position = Vector3(0.0, box.size.y * 0.5 + cord_length * 0.5, 0.0)
	add_child(_cord)
	# Чашка подвеса на потолке — часть шнура: остаётся с ним, когда лампа падает.
	var canopy := _cylinder(CANOPY.x, CANOPY.y, GreyboxLook.metal(SHADE_COLOR))
	canopy.position = Vector3(0.0, cord_length * 0.5 - CANOPY.y * 0.5, 0.0)
	_cord.add_child(canopy)


## Сбита выстрелом. Повторные попадания ничего не меняют, в том числе и по уже
## упавшей: [method queue_free] убирает её лишь в конце кадра, и до тех пор она
## продолжает ловить пули.
func shoot_down() -> void:
	if not _fall.start():
		return
	# Искры в точке попадания: остаются там, пока лампа падает (ADR-0031).
	if get_parent() != null:
		Sparks.burst(get_parent(), global_position)
	# Сбитая лампа перестаёт светиться сама: корпус тот же, но уже не светильник.
	# Шнур остаётся на потолке — оборванный, — а не падает и не исчезает с ней.
	_visual.material_override = GreyboxLook.surface(GreyboxLook.LAMP)
	if _diffuser != null:
		_diffuser.material_override = GreyboxLook.surface(GreyboxLook.LAMP.darkened(0.5))
	if _cord != null:
		_cord.reparent(get_parent())
		_cord = null
	Sounds.play(Sounds.LAMP_BREAK)


## Гасит или зажигает свет лампы. Зовёт уровень, отбирая видимые этажи: конус
## кладёт тени и стоит дорого, поэтому за кадром ему гореть незачем
## (ADR-0010, пункт 8). Сама лампа при этом остаётся как была.
func set_light_visible(on: bool) -> void:
	_spot.visible = on
	_fill.visible = on


## Тени ламп по уровню качества (ADR-0030, решение 5): на низком без теней,
## на среднем тень кладёт только конус.
func apply_graphics() -> void:
	_spot.shadow_enabled = Graphics.spot_shadows()
	_fill.shadow_enabled = Graphics.fill_shadows()


## Светильник вместо коробки: абажур конусом и рассеиватель снизу. Коробка
## корпуса остаётся — по ней считаются попадание и падение, — но не видна.
func _dress_fixture() -> void:
	_visual.transparency = 1.0
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := _shape.shape as BoxShape3D
	var shade := _cylinder(SHADE.x, SHADE.z, GreyboxLook.metal(SHADE_COLOR), SHADE.y)
	shade.position = Vector3(0.0, box.size.y * 0.5 - SHADE.z * 0.5, 0.0)
	# Светильник не отбрасывает тени: источник сидит внутри него, и абажур с
	# чашей глушили бы собственный свет (кадры M20 — этажи потемнели).
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shade)
	# Светящаяся чаша под абажуром: видна сбоку, а не только снизу. Лампа — цель,
	# и в кадре камеры сверху плоский рассеиватель пропадал (кадры M20).
	var bowl := SphereMesh.new()
	bowl.radius = BOWL.x
	bowl.height = BOWL.y * 2.0
	bowl.is_hemisphere = true
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = bowl
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.rotation.x = PI
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3(0.0, box.size.y * 0.5 - SHADE.z, 0.0)
	add_child(_diffuser)


## Цилиндр или усечённый конус: верх [param top], низ [param bottom] (по
## умолчанию как верх), высота [param height].
func _cylinder(
	top: float, height: float, material: StandardMaterial3D, bottom: float = -1.0
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom if bottom >= 0.0 else top
	mesh.height = height
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	return part


func _make_spot() -> SpotLight3D:
	var light := SpotLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = SPOT_ENERGY
	light.spot_range = SPOT_RANGE
	light.spot_angle = SPOT_ANGLE
	light.shadow_enabled = true
	light.shadow_blur = SPOT_BLUR
	# Конус смотрит вниз: свет у Godot идёт вдоль -Z источника.
	light.rotation.x = -PI * 0.5
	return light


func _make_fill() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = LIGHT_COLOR
	light.light_energy = FILL_ENERGY
	light.omni_range = FILL_RANGE
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
