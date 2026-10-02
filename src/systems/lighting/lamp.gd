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
## Насколько конус без тени заходит в плиту под своим полом, м: меньше плиты.
const FLOOR_REACH: float = 0.1

## Заливка вокруг: слабая и широкая. Один конус оставлял бы между лампами
## черноту при всех горящих — а зона считается освещённой целиком.
##
## С тенью, хотя тень на второй источник каждой лампы и стоит денег. Без неё
## заливка радиусом больше высоты этажа (3 м) светит сквозь перекрытия: на
## кадре погашенного этажа его пол подсвечивали лампы этажа снизу, и темнота
## переставала быть темнотой (авторевью M17). Резать радиус нельзя — он и
## нужен, чтобы дотянуться до краёв зоны.
const FILL_RANGE: float = 7.0
## Радиус заливки без тени — на низком и среднем качестве: не дальше этажа.
const FILL_RANGE_UNSHADOWED: float = 3.0
## Сколько ламп в кадре разом кладут тень заливкой: столько, сколько бывает
## в кадре наверху здания, где кадр в бюджете.
const FILL_SHADOW_CAP: int = 4
const FILL_ENERGY: float = 1.5
## Мигание: пауза между сериями и длина одного провала, с, насколько гаснет
## свет в провале и соль жребия, какая лампа мигает.
const FLICKER_PAUSE := Vector2(2.5, 7.0)
const FLICKER_BLINK := Vector2(0.04, 0.12)
const FLICKER_LOW: float = 0.15
const FLICKER_SALT: int = 0xF11C

## Тёплый цвет лампы против холодного общего тона палитры (ADR-0023, решение 3) —
## у лампы без стиля здания. Свет по типу — [constant BuildingAir.LAMP_LIGHT].
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
## Офисный светильник (ADR-0048): короб лампы дневного света и рассеиватель
## под ним, м. Шире абажура не выходит — в ширину формы лампы: мишень та же.
const PANEL_BOX := Vector3(0.6, 0.1, 0.34)
const PANEL_DIFFUSER := Vector3(0.56, 0.05, 0.38)
const PANEL_COLOR := Color(0.82, 0.84, 0.86)
## Тарелка жилого дома (ADR-0055): радиус и глубина стекла, латунная чашка над
## ним, м. Шире абажура не выходит — мишень та же.
const DOME := Vector2(0.24, 0.1)
const DOME_CAP := Vector2(0.07, 0.04)
const DOME_CAP_COLOR := Color(0.55, 0.46, 0.28)
## Голая лампочка: радиус и высота колбы, патрон, м; соль жребия, у какой
## лампы плафон побит.
const BULB := Vector2(0.075, 0.17)
const BULB_SOCKET := Vector2(0.03, 0.07)
const BULB_SALT: int = 0xB01B
## Люстра: радиус кольца, м; свечи — сколько и какие (радиус и высота колбы).
## Шире абажура не выходит — в ширину формы лампы: мишень та же. Штанга — от
## кольца до шнура, как трубка тарелки.
const CHANDELIER: float = 0.24
const CHANDELIER_BRASS := Color(0.72, 0.56, 0.26)
const CANDLES: int = 6
const CANDLE := Vector2(0.05, 0.13)
## Чаша с хрусталём под кольцом — светится вместе со свечами: сбоку люстра
## тонка, и мишень без неё читалась чертой под потолком (кадры M24n).
const CHANDELIER_BOWL := Vector2(0.17, 0.11)

## Свечи и чаша люстры одним мешем — один на все люстры: собирать его заново
## на каждую лампу отеля значило бы полсотни сборок на загрузке здания.
static var _chandelier_glow: ArrayMesh = null

@export var fall_speed: float = 7.8

## Этаж, на котором лампа висит. Записывает уровень, когда вешает её.
##
## Выводить этаж обратно из координаты нельзя: до M18c лампа висела ровно
## посередине пролёта, между двумя полами, и [method BuildingRules.floor_index_near]
## на этой середине решал по последнему биту дроби — на пикселях он падал на один
## этаж, на метрах на другой. Под потолком она ближе к полу этажа выше, чем
## к своему, и вывод из координаты ошибался бы уже всегда.
var floor_index: int = 0
## Вид светильника по типу здания: плафон отеля или короб офиса. Ставит
## уровень до добавления в дерево ([BuildingStyle]).
var fixture: BuildingStyle.Fixture = BuildingStyle.Fixture.PENDANT
## Лампа мигает (ADR-0055, решение 4): трубка вот-вот сдохнет. Только вид —
## зона светла, пока лампа цела, как в ROM; темноты мигание не делает.
var flicker: bool = false
## Цвет и сила света по типу здания ([BuildingAir], ADR-0056): ставит
## [method dress_as] до входа в дерево.
var light_colour := LIGHT_COLOR
var light_gain: float = 1.0

var _fall := LampFall.new()
var _spot: SpotLight3D = null
var _fill: OmniLight3D = null
## Этаж лампы в кадре: свет с тенью. Иначе — запасной, конус до пола без тени.
var _shadowed: bool = true
## Кладёт ли тень заливка ([method set_light_visible]).
var _fill_shadowed: bool = true
## На какой высоте над своим полом висит лампа, м: [method hang].
var _above_floor: float = SPOT_RANGE
var _cord: MeshInstance3D = null
## Рассеиватель абажура: светится, пока лампа цела (ADR-0031, решение 3).
var _diffuser: MeshInstance3D = null
## Мигание: часы до следующей вспышки, сколько гаснуть ещё и тусклый
## рассеиватель на время, пока лампа погасла.
var _flicker_wait: float = 0.0
var _flicker_left: int = 0
var _flicker_rng := RandomNumberGenerator.new()
var _dim: StandardMaterial3D = null

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
	set_process(flicker)
	if flicker:
		_flicker_rng.seed = hash([floor_index, roundi(position.x * 10.0)])
		_flicker_wait = _flicker_rng.randf_range(FLICKER_PAUSE.x, FLICKER_PAUSE.y)
		_dim = GreyboxLook.surface(GreyboxLook.LAMP.darkened(0.45))


## Вид лампы по стилю здания [param style]: светильник и, на доле ламп жилого
## дома, мигание — жребий по этажу и месту, одна лампа мигает всегда. Звать
## до [method Node.add_child], когда [member floor_index] и место уже стоят.
func dress_as(style: BuildingStyle) -> void:
	fixture = style.fixture
	if (
		hash([floor_index, roundi(position.x * 10.0), BULB_SALT]) % 1000
		< int(style.bulb_share * 1000.0)
	):
		fixture = BuildingStyle.Fixture.BULB
	light_colour = style.lamp_light
	light_gain = style.lamp_gain
	var roll := hash([floor_index, roundi(position.x * 10.0), FLICKER_SALT]) % 1000
	flicker = roll < int(style.flicker_share * 1000.0)


## Мигание: долгая пауза, затем серия коротких провалов. Сбитая не мигает.
func _process(delta: float) -> void:
	if not is_hanging():
		# Свет — во всю силу до конца падения, а рассеиватель уже погасила
		# [method shoot_down]: зажжённый заново, он светился бы на лету.
		_glow(true)
		set_process(false)
		return
	_flicker_wait -= delta
	if _flicker_wait > 0.0:
		return
	if _flicker_left == 0:
		_flicker_left = _flicker_rng.randi_range(2, 5) * 2
	_flicker_left -= 1
	# Чётный шаг — тьма, нечётный — снова свет; последний — свет и пауза.
	_show_lit(_flicker_left % 2 == 0)
	_flicker_wait = _flicker_rng.randf_range(FLICKER_BLINK.x, FLICKER_BLINK.y)
	if _flicker_left == 0:
		_flicker_wait = _flicker_rng.randf_range(FLICKER_PAUSE.x, FLICKER_PAUSE.y)


func _show_lit(lit: bool) -> void:
	_glow(lit)
	if _diffuser != null:
		_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP) if lit else _dim


## Сила света лампы: полная или провал мигания.
func _glow(lit: bool) -> void:
	var gain := light_gain if lit else light_gain * FLICKER_LOW
	_spot.light_energy = SPOT_ENERGY * gain
	_fill.light_energy = FILL_ENERGY * gain


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
	_above_floor = hang_height
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


## Висит ли лампа: не сбита. Сбитую боту целить незачем ([OttoBot]).
func is_hanging() -> bool:
	return not _fall.falling and not _fall.has_landed()


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
##
## [param shadowed] — этаж в кадре. Запасной этаж за кромкой кадра горит только
## конусом, без тени и не дальше своего пола: его тени никто не видит, а внизу
## здания запасные лампы давали треть проходов теней (ADR-0042, решение 2).
## Заливка там не горит: без тени она светила бы сквозь потолок на этаж выше.
##
## [param fill_shadowed] — кладёт ли тень и заливка. Тень заливки кубическая —
## шесть проходов по сцене, — и внизу здания, где в кадре до восьми ламп, она
## одна стоила 7.7 мс из 18 (замер M24h, ADR-0044, решение 11). Поэтому тень
## заливки — только у [constant FILL_SHADOW_CAP] ламп ближе к середине кадра;
## остальные светят заливкой без тени и не дальше своего этажа.
func set_light_visible(on: bool, shadowed: bool = true, fill_shadowed: bool = true) -> void:
	_spot.visible = on
	_fill.visible = on and shadowed
	var fill := shadowed and fill_shadowed
	# Уровень зовёт это всем лампам разом, как только кадр сменил этажи. Запись
	# дальности или тени, даже прежней, помечает карту теней грязной, и лампы, у
	# которых ничего не сменилось, перерисовывали бы тени в тот же кадр.
	if shadowed == _shadowed and fill == _fill_shadowed:
		return
	_shadowed = shadowed
	_fill_shadowed = fill
	apply_graphics()


## Тени ламп по уровню качества (ADR-0030, решение 5): на низком без теней,
## на среднем тень кладёт только конус. На «Ультра» конус виден в воздухе
## коридора (ADR-0034, решение 1); заливка светит в туман на четверть — иначе
## воздух вокруг лампы светился бы шаром, а не конусом.
func apply_graphics() -> void:
	_spot.shadow_enabled = Graphics.spot_shadows() and _shadowed
	# Конус без тени не держится полом: до пола и чуть в плиту, но не сквозь неё.
	_spot.spot_range = SPOT_RANGE if _shadowed else minf(SPOT_RANGE, _above_floor + FLOOR_REACH)
	var fill := Graphics.fill_shadows() and _fill_shadowed
	_fill.shadow_enabled = fill
	_spot.light_volumetric_fog_energy = Graphics.light_in_fog()
	_fill.light_volumetric_fog_energy = Graphics.light_in_fog() * 0.25
	# Заливка без тени не держится перекрытием и светила бы сквозь плиты на
	# соседние, погашенные этажи — темнота переставала бы быть темнотой (как в
	# M17). Без тени её радиус — в этаж (авторевью M20).
	_fill.omni_range = FILL_RANGE if fill else FILL_RANGE_UNSHADOWED


## Светильник вместо коробки: абажур конусом и рассеиватель снизу. Коробка
## корпуса остаётся — по ней считаются попадание и падение, — но не видна.
func _dress_fixture() -> void:
	_visual.transparency = 1.0
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := _shape.shape as BoxShape3D
	if fixture == BuildingStyle.Fixture.PANEL:
		_dress_panel(box)
		return
	if fixture == BuildingStyle.Fixture.DOME:
		_dress_dome(box)
		return
	if fixture == BuildingStyle.Fixture.BULB:
		_dress_bulb(box)
		return
	if fixture == BuildingStyle.Fixture.CHANDELIER:
		_dress_chandelier(box)
		return
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


## Офисный светильник: белый короб под шнуром и светящийся рассеиватель под
## ним — видно сбоку полосой.
func _dress_panel(box: BoxShape3D) -> void:
	# Короб — посередине формы лампы на двух штангах: лампа — цель, и под
	# потолком плоский короб читался полоской (кадры M24i).
	var top := PANEL_BOX.y * 0.5
	# Короб матовый: металл отражал тёмный коридор, и спереди светильник
	# читался чёрным квадратом.
	var metal := GreyboxLook.surface(PANEL_COLOR)
	for side: float in [-1.0, 1.0]:
		var rod := GreyboxLook.box(Vector3(0.015, box.size.y * 0.5 - top, 0.015), metal)
		rod.position = Vector3(side * PANEL_BOX.x * 0.38, (box.size.y * 0.5 + top) * 0.5, 0.0)
		add_child(rod)
	var housing := GreyboxLook.box(PANEL_BOX, metal)
	housing.position = Vector3(0.0, 0.0, 0.0)
	housing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(housing)
	var slab := BoxMesh.new()
	slab.size = PANEL_DIFFUSER
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = slab
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3(0.0, top - PANEL_BOX.y - PANEL_DIFFUSER.y * 0.5, 0.0)
	add_child(_diffuser)


## Светильник жилого дома (ADR-0055, решение 4): стеклянная тарелка на короткой
## трубке под латунной чашкой. Висит посередине формы лампы, как и короб офиса:
## мишень та же, а тарелка у самого потолка пряталась бы за кромкой плиты.
func _dress_dome(box: BoxShape3D) -> void:
	var brass := GreyboxLook.metal(DOME_CAP_COLOR)
	var stem := _cylinder(0.012, box.size.y * 0.5, brass)
	stem.position = Vector3(0.0, box.size.y * 0.25, 0.0)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stem)
	var cap := _cylinder(DOME_CAP.x, DOME_CAP.y, brass, DOME_CAP.x * 0.6)
	cap.position = Vector3(0.0, DOME_CAP.y * 0.5, 0.0)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cap)
	var glass := SphereMesh.new()
	glass.radius = DOME.x
	glass.height = DOME.y * 2.0
	glass.is_hemisphere = true
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = glass
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.rotation.x = PI
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_diffuser.position = Vector3.ZERO
	add_child(_diffuser)


## Голая лампочка жилого дома (ADR-0056, решение 5): патрон на проводе и
## колба — светится она одна, как рассеиватель у прочих.
func _dress_bulb(box: BoxShape3D) -> void:
	var socket := _cylinder(BULB_SOCKET.x, BULB_SOCKET.y, GreyboxLook.surface(Color(0.1, 0.1, 0.1)))
	socket.position = Vector3(0.0, BULB.x + BULB_SOCKET.y * 0.5, 0.0)
	_unshadowed(socket)
	var wire := _cylinder(
		0.006, box.size.y * 0.5 - BULB.x, GreyboxLook.surface(Color(0.05, 0.05, 0.05))
	)
	wire.position = Vector3(0.0, (box.size.y * 0.5 + BULB.x) * 0.5, 0.0)
	_unshadowed(wire)
	var glass := SphereMesh.new()
	glass.radius = BULB.x
	glass.height = BULB.y
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = glass
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_diffuser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_diffuser)


## Люстра отеля (ADR-0056, решение 5): латунное кольцо на штанге, рожки и
## свечи-лампочки по кругу. Свечи — один меш рассеивателя: сбитая люстра
## гаснет вся разом, как абажур.
func _dress_chandelier(box: BoxShape3D) -> void:
	var brass := GreyboxLook.metal(CHANDELIER_BRASS)
	# Штанга — до верха формы, где начинается шнур ([method hang]): короче — и
	# люстра висела бы в воздухе под обрывком.
	var stem := _cylinder(0.015, box.size.y * 0.5, brass)
	stem.position = Vector3(0.0, box.size.y * 0.25, 0.0)
	_unshadowed(stem)
	var ring := TorusMesh.new()
	ring.inner_radius = CHANDELIER - 0.02
	ring.outer_radius = CHANDELIER
	var hoop := MeshInstance3D.new()
	hoop.mesh = ring
	hoop.material_override = brass
	_unshadowed(hoop)
	var cup := _cylinder(0.05, 0.08, brass, 0.02)
	cup.position = Vector3(0.0, -0.06, 0.0)
	_unshadowed(cup)
	for arm: int in CANDLES:
		var holder := _cylinder(0.018, 0.05, brass)
		holder.position = _candle_at(arm) - Vector3(0.0, 0.045, 0.0)
		_unshadowed(holder)
	_diffuser = MeshInstance3D.new()
	_diffuser.mesh = _chandelier_mesh()
	_diffuser.material_override = GreyboxLook.marker(GreyboxLook.LAMP)
	_unshadowed(_diffuser)


## Где свеча люстры номер [param arm]: по кругу кольца, чуть над ним.
static func _candle_at(arm: int) -> Vector3:
	var angle := TAU * arm / CANDLES
	return Vector3(cos(angle) * CHANDELIER, 0.06, sin(angle) * CHANDELIER)


## Свечи и чаша с хрусталём под кольцом одним мешем ([member _chandelier_glow]).
static func _chandelier_mesh() -> ArrayMesh:
	if _chandelier_glow != null:
		return _chandelier_glow
	var tool := SurfaceTool.new()
	var flame := SphereMesh.new()
	flame.radius = CANDLE.x
	flame.height = CANDLE.y
	# Колба в пять сантиметров: шестьдесят четыре грани по умолчанию — лишние.
	flame.radial_segments = 16
	flame.rings = 8
	for arm: int in CANDLES:
		tool.append_from(flame, 0, Transform3D(Basis.IDENTITY, _candle_at(arm)))
	var bowl := SphereMesh.new()
	bowl.radius = CHANDELIER_BOWL.x
	bowl.height = CHANDELIER_BOWL.y * 2.0
	bowl.is_hemisphere = true
	var under := Basis.from_euler(Vector3(PI, 0.0, 0.0))
	tool.append_from(bowl, 0, Transform3D(under, Vector3(0.0, -0.04, 0.0)))
	_chandelier_glow = tool.commit()
	return _chandelier_glow


## Деталь светильника без тени: источник сидит внутри светильника, и штанга
## с рожками клали бы на стену тёмные дуги (кадры M24n).
func _unshadowed(part: MeshInstance3D) -> void:
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)


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
	light.light_color = light_colour
	light.light_energy = SPOT_ENERGY * light_gain
	light.spot_range = SPOT_RANGE
	light.spot_angle = SPOT_ANGLE
	light.shadow_enabled = true
	light.shadow_blur = SPOT_BLUR
	# Конус смотрит вниз: свет у Godot идёт вдоль -Z источника.
	light.rotation.x = -PI * 0.5
	return light


func _make_fill() -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = light_colour
	light.light_energy = FILL_ENERGY * light_gain
	light.omni_range = FILL_RANGE
	light.shadow_enabled = true
	# Две полусферы, а не куб: вдвое-втрое меньше проходов тени. Заливка слабая
	# и мягкая, шов полусфер на ней не виден, а внизу здания кубы ламп съедали
	# две трети кадра на «Ультра» (ADR-0042, решение 2). Обстановку в свою тень
	# заливка не берёт.
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_caster_mask = ~PropCatalog.RENDER_LAYER
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
