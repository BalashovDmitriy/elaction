class_name Escalator
extends Node3D

## Эскалатор между двумя этажами.
##
## В оригинале на него не заходят по пути: надо встать на площадку у края и
## нажать «вверх» или «вниз» (ADR-0004, пункт 8). Пока везёт — управления нет,
## позицией Otto распоряжается эскалатор, а не физика.
##
## Узел ставится на верхнюю площадку, нижняя и точка перегиба задаются в
## [method setup]. Поездка идёт по тому же пути, который выложен полотном, и
## начинается с того места, где пассажир стоял: иначе его дёргало бы к центру
## площадки, а полотно резало бы перекрытие мимо проёма (найдено авторевью M2).
##
## С M18b эскалатор — конструкция, а не две коробки полотна
## ([ADR-0025](../../../docs/adr/0025-shafts-escalators-and-riders.md), решение 4):
## ступени рельефом, площадки в концах, балюстрада и обрамление проёма. Рельеф,
## а не анимация: свет M17 ложится на геометрию, ради этого пивот и затевался.
##
## С M24g конструкция — из деталей модели, собранной своим скриптом в Blender
## (`tools/build_escalator.py`, ADR-0043, решение 3): рифлёные ступени с жёлтой
## кромкой, стеклянная балюстрада с поручнем, тумбы, площадки с гребёнкой,
## ферма. Пролёт в каждом здании свой, поэтому модель — набор деталей, и
## эскалатор расставляет их по месту: ступени по одной, остальное растягивает
## по длине.

## С M24h эскалатор стоит в глубине, у задней стены (ADR-0044, решение 10):
## пролёт за плоскостью игры, плита перед ним цельная, и мимо эскалатора
## проходят по полу. На площадку встают шагом вглубь, как в красную дверь, и
## сходят шагом обратно к камере.

## Детали эскалатора и их размеры в модели, м: по ним детали растягиваются.
const KIT := preload("res://assets/models/escalator/escalator.glb")
const KIT_STEP_RUN: float = 0.2
const KIT_STEP_HEIGHT: float = 0.45
const KIT_LANDING_RUN: float = 0.42

## Докуда слышен стрёкот полотна, м.
const HUM_REACH: float = 9.0

## Докуда от камеры плита под эскалатором цельная, м по Z: проём — только за
## этим краем, в задней полосе коридора. Тело идущего мимо Otto — перед ним.
const HOLE_FRONT_Z: float = -WorldSpace.BODY_DEPTH * 0.5 - 0.04

## Толщина и глубина полотна, м. Тела у полотна нет: везёт эскалатор, а не пол.
const BELT_THICKNESS: float = 0.15
const BELT_DEPTH: float = 0.72

## Середина полотна по Z: за краем цельной плиты, у задней стены. По ней же
## едет пассажир.
const BELT_Z: float = HOLE_FRONT_Z - BELT_DEPTH * 0.5 - 0.01

## Сколько полотно проходит по горизонтали за одну ступень, м.
##
## Ступень и есть то, чем эскалатор отличается от пандуса: на пролёте в 1.6 м
## их выходит полдюжины, и зубчатый край читается с любого этажа.
const STEP_RUN: float = 0.2

## Балюстрады по краям полотна — у задней стены и со стороны камеры, м по Z.
## Спереди с M24h тоже стекло с поручнем, а не низкий борт: перила
## должны читаться, а едущего Otto за стеклом видно (ADR-0044, решение 10).
const RAIL_Z: float = BELT_Z - BELT_DEPTH * 0.5 + 0.03
const FRONT_RAIL_Z: float = BELT_Z + BELT_DEPTH * 0.5 - 0.03
const RAIL_THICKNESS: float = 0.1
const RAIL_HEIGHT: float = 0.96

## Поручень поверх балюстрады: квадратный в сечении, м.
const HANDRAIL_SIZE: float = 0.1

## Огонёк на конце поручня: ребро куба, м.
const END_LIGHT_SIZE: float = 0.16

## Свой источник пролёта: радиус, яркость, цвет и вынос перед ступенями.
##
## Без него от конструкции остаются две рейки в темноте: замер на 24 сидах дал
## 25 эскалаторов из 120 под пятном лампы, в среднем до лампы 5.7 м. Источник
## не гаснет от выстрела и в зонах темноты не участвует — по той же причине,
## что и столб света в шахте (ADR-0025, решение 3): темнота решает, видят ли
## агенты Otto, а путь вниз обязан читаться всегда.
##
## Тени не отбрасывает: пролёт стоит в проёме, ронять их ему не на что, а стоят
## они дороже всего остального в кадре.
const GLOW_RANGE: float = 3.6
const GLOW_ENERGY: float = 1.2
const GLOW_COLOR := Color(1.0, 0.88, 0.68)
const GLOW_Z: float = -0.1

## Площадка в конце полотна: длина по ходу и толщина, м.
##
## Короче, чем была: площадка не заходит в соседнее место, где этажом ниже
## может стоять шахта (ADR-0026, решение 6).
const LANDING_RUN: float = 0.42
const LANDING_THICKNESS: float = 0.12

## Обрамление проёма: ширина стойки по краю дыры, м.
const FRAME_WIDTH: float = 0.12

## Сетки деталей по имени: одни на все эскалаторы здания.
static var _meshes: Dictionary = {}

## Скорость поездки, м/с по пути. До M24g поездка по короткому крутому пролёту
## шла 1.1 с; с пологим пролётом M24g путь длиннее, и время считается по нему
## ([method setup]), а скорость остаётся прежней.
@export var ride_speed: float = 4.3

## Сколько секунд занимает поездка между площадками.
@export var travel_time: float = 1.1

## Этаж, с которого эскалатор спускается. Ставит его уровень: обратно из
## координаты этаж не выводят — узел стоит ровно на полу, где округление
## решает случай. По нему уровень гасит источник пролёта вне кадра.
var floor_index: int = 0

var _passenger: Otto = null
var _path: PackedVector3Array = PackedVector3Array()
var _progress: float = 0.0
## Перегиб полотна в своих координатах. Пустой — [method setup] не звали.
var _via := Vector3.ZERO
var _has_via: bool = false
## Источник пролёта. Пустой — [method setup] не звали.
var _glow: OmniLight3D = null

var _hum: AudioStreamPlayer3D = null
@onready var _top_pad: Area3D = $TopPad
@onready var _bottom_pad: Area3D = $BottomPad
@onready var _ramp: Node3D = $Ramp


func _ready() -> void:
	_hum = Sounds.source(self, Sounds.ESCALATOR_HUM, HUM_REACH)


func _physics_process(delta: float) -> void:
	# Полотно слышно, только пока кто-то едет: в оригинале эскалатор тоже
	# не гудит сам по себе, а здание и без того шумное.
	Sounds.keep_playing(_hum, _passenger != null)

	if _passenger != null:
		_carry(delta)
		return
	# Наверх зовут с нижней площадки, вниз — с верхней.
	if not _try_board(_bottom_pad, _top_pad, Intent.UP):
		_try_board(_top_pad, _bottom_pad, Intent.DOWN)


## Задаёт геометрию в координатах правил. [param descent] — смещение нижней
## площадки от верхней, [param via] — точка перегиба в проёме перекрытия: через
## неё идут и полотно, и сама поездка, поэтому пассажир проходит сквозь дыру,
## а не сквозь плиту. [param gap] — края проёма относительно узла, [param slab] —
## толщина перекрытия: по ним ставится обрамление.
func setup(descent: Vector2, via: Vector2, gap: Vector2, slab: float) -> void:
	var down := WorldSpace.direction_to_scene(descent)
	_via = WorldSpace.direction_to_scene(via)
	_has_via = true
	_bottom_pad.position = down
	# Шаг вглубь на площадку и обратно к камере — тоже путь.
	var depth := absf(BELT_Z) * 2.0
	travel_time = (_via.length() + (down - _via).length() + depth) / ride_speed
	_build(down, gap, slab)


## Везёт ли эскалатор кого-нибудь прямо сейчас.
func is_busy() -> bool:
	return _passenger != null


## Гасит или зажигает источник пролёта. Зовёт уровень, отбирая видимые этажи —
## тем же правилом, что у ламп и столбов шахт (ADR-0010, пункт 8).
##
## Это не то же самое, что «погас от выстрела»: источник пролёта не участвует
## в зонах темноты и от пули не гаснет (ADR-0025, решение 4), — но светить ему
## положено в кадре, а не во всём здании разом. Светильников на здание за
## полсотни, и не гасившиеся эскалаторы съедали бюджет света целиком.
func set_light_visible(on: bool) -> void:
	if _glow != null:
		_glow.visible = on


func _try_board(pad: Area3D, target: Area3D, towards: float) -> bool:
	for body: Node3D in pad.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or not rider.is_grounded():
			continue
		var intent := rider.vertical_intent()
		if absf(intent) < Intent.PRESS or signf(intent) != towards:
			continue

		_passenger = rider
		_path = _route_from(rider.global_position, target)
		_progress = 0.0
		# По ступеням Otto идёт, лицом по ходу (ADR-0043, решение 2).
		rider.ride_look = Otto.LOOK_WALK
		rider.ride_facing = signf(target.global_position.x - rider.global_position.x)
		rider.ride(true)
		return true
	return false


## Путь поездки: от места, где пассажир стоял, шаг вглубь на полотно, через
## перегиб к дальней площадке и шаг обратно в плоскость игры.
##
## Перегиб берётся из полотна, поэтому едут ровно там, где выложено. Без
## [method setup] полотна нет — тогда путь прямой, лишь бы не падать по индексу.
func _route_from(start: Vector3, target: Area3D) -> PackedVector3Array:
	var finish := target.global_position
	if not _has_via:
		return PackedVector3Array([start, finish])
	var belt := Vector3(0.0, 0.0, BELT_Z - start.z)
	var bend := to_global(_via)
	bend.z = start.z + belt.z
	return PackedVector3Array(
		[start, start + belt, bend, Vector3(finish.x, finish.y, bend.z), finish]
	)


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _point_at(_progress)
	if _progress < 1.0:
		return
	_passenger.ride(false)
	_passenger = null


## Точка на ломаной по доле пути: длина считается по самим отрезкам, поэтому
## на изломе скорость не прыгает.
func _point_at(ratio: float) -> Vector3:
	var total := 0.0
	for index in _path.size() - 1:
		total += _path[index].distance_to(_path[index + 1])
	if is_zero_approx(total):
		return _path[_path.size() - 1]

	var travelled := total * ratio
	for index in _path.size() - 1:
		var length := _path[index].distance_to(_path[index + 1])
		if travelled <= length or index == _path.size() - 2:
			var part := travelled / length if length > 0.0 else 1.0
			return _path[index].lerp(_path[index + 1], minf(part, 1.0))
		travelled -= length
	return _path[_path.size() - 1]


## Собирает конструкцию заново по заданной геометрии.
##
## Ломаная — это площадка по этажу до проёма и один прямой пролёт вниз. Двумя
## пролётами разной крутизны она была до M18b, и в кадре читалась жёлобом:
## пологий вход под 25° упирался в обрыв под 63°, а балюстрады двух пролётов
## расходились на изломе веером.
func _build(down: Vector3, gap: Vector2, slab: float) -> void:
	for part: Node in _ramp.get_children():
		part.queue_free()

	var towards := signf(down.x)
	_lay_landing(Vector3.ZERO, _via)
	_lay_flight(_via, down)
	# Нижняя площадка уходит по ходу спуска: с неё сходят, приехав. Гребёнкой
	# она к ступеням — раскладывается от своего дальнего края к ним.
	_lay_landing(down + Vector3(towards * LANDING_RUN, 0.0, 0.0), down)
	_frame_the_gap(gap, slab)


## Пролёт: полотно снизу, ступени сверху, балюстрада и борт по бокам.
func _lay_flight(from: Vector3, to: Vector3) -> void:
	var span := to - from
	if is_zero_approx(span.length()):
		return

	_lay_belt(from, to)
	_lay_steps(from, span)
	_lay_sides(from, to)
	_light_the_flight(from, to)


## Ферма пролёта с обшивкой снизу, вдоль ломаной.
##
## Со стороны её закрывают ступени, но снизу видно именно её: эскалатор проходит
## сквозь перекрытие, и с нижнего этажа смотрят ему в брюхо.
func _lay_belt(from: Vector3, to: Vector3) -> void:
	var span := to - from
	_add_kit(
		"Truss",
		(from + to) * 0.5 + Vector3(0.0, -BELT_THICKNESS, BELT_Z),
		atan2(span.y, span.x),
		Vector3(span.length(), 1.0, 1.0)
	)


## Ступени пролёта: коробки с плоским верхом, каждая ниже предыдущей.
##
## Не повёрнуты вдоль пролёта нарочно — повёрнутая коробка снова даёт пандус.
## Верх ступени лежит на ломаной, низ уходит под неё, и соседние заходят друг
## за друга: силуэт получается зубчатым, а щелей между ступенями нет.
func _lay_steps(from: Vector3, span: Vector3) -> void:
	var count := maxi(int(absf(span.x) / STEP_RUN), 1)
	var tread := span.x / float(count)
	var riser := span.y / float(count)
	var height := absf(riser) + BELT_THICKNESS

	# Жёлтая кромка ступени — по ходу спуска: край, с которого шагают вниз.
	for index in count:
		var top := from.y + riser * float(index)
		_add_kit(
			"Step",
			Vector3(from.x + tread * (float(index) + 0.5), top, BELT_Z),
			0.0,
			Vector3(tread / KIT_STEP_RUN, height / KIT_STEP_HEIGHT, 1.0)
		)


## Бока пролёта: стеклянные балюстрады с поручнем у задней стены и у камеры.
func _lay_sides(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var angle := atan2(span.y, span.x)
	var centre := (from + to) * 0.5
	var length := span.length()
	# Нормаль к пролёту, всегда вверх: балюстрада стоит на полотне, а не висит
	# под ним, и на спуске влево знак пролёта не должен её переворачивать.
	var up := Vector3(-span.y, span.x, 0.0).normalized()
	if up.y < 0.0:
		up = -up

	var over := BELT_THICKNESS * 0.5
	var stretch := Vector3(length, 1.0, 1.0)
	for z: float in [RAIL_Z, FRONT_RAIL_Z]:
		_add_kit("Balustrade", centre + up * over + Vector3(0.0, 0.0, z), angle, stretch)
		for end: Vector3 in [from, to]:
			_add_kit("Newel", end + up * over + Vector3(0.0, 0.0, z), 0.0, Vector3.ONE)

	var cap := up * (over + RAIL_HEIGHT + HANDRAIL_SIZE * 0.5) + Vector3(0.0, 0.0, FRONT_RAIL_Z)
	_mark_end(from + cap)
	_mark_end(to + cap)


## Свет пролёта: одна лампа посередине, перед ступенями.
##
## Стоит в самом проёме и светит на оба этажа, которые эскалатор связывает, —
## это не протечка, а ровно то, что он и делает.
func _light_the_flight(from: Vector3, to: Vector3) -> void:
	var light := OmniLight3D.new()
	light.omni_range = GLOW_RANGE
	light.light_energy = GLOW_ENERGY
	light.light_color = GLOW_COLOR
	light.shadow_enabled = false
	light.position = (from + to) * 0.5 + Vector3(0.0, 0.0, GLOW_Z)
	_ramp.add_child(light)
	_glow = light


## Огонёк на конце поручня.
##
## Замер на 24 сидах: из 120 эскалаторов под пятном лампы стоит 25, до ближайшей
## лампы в среднем 5.7 м, в худшем 10.5. Мест на этаже мало, эскалатор занимает
## два — и встаёт он там, где лампы нет. Конструкция, которую не видно, ничего
## не даёт, а подсвечивать её источником незачем: проект уже отвечает на это
## огоньками (ADR-0023, решение 6) — так читаются табло дверей, индикаторы
## кабины и вывеска выхода. Два огонька на концах поручня говорят «здесь
## эскалатор» ровно так же.
func _mark_end(at: Vector3) -> void:
	_add_part(
		Vector3(END_LIGHT_SIZE, END_LIGHT_SIZE, END_LIGHT_SIZE),
		at,
		0.0,
		GreyboxLook.light(GreyboxLook.SIGN_WARM)
	)


## Площадка: ровная плита между двумя точками одной высоты.
##
## Утоплена в перекрытие: её верх вровень с полом, наружу смотрит только торец.
## Иначе встающий на неё Otto оказывался бы по щиколотку в плите — он стоит
## на полу этажа, а не на эскалаторе.
func _lay_landing(from: Vector3, to: Vector3) -> void:
	var run := to.x - from.x
	if is_zero_approx(run):
		return

	# Гребёнка площадки — на её конце [param to]; у нижней площадки конец —
	# там, откуда уходят ступени, и она ляжет, если её раскладывать от ступеней.
	_add_kit(
		"Landing",
		Vector3((from.x + to.x) * 0.5, from.y, BELT_Z),
		0.0,
		Vector3(run / KIT_LANDING_RUN, 1.0, 1.0)
	)


## Обрамление проёма: стойки по краям дыры в перекрытии.
##
## Без них дыра читается обрывом плиты — тем же, что и провал шахты, в который
## падают насмерть. Стойки стоят на краях проёма во всю толщину перекрытия и
## тела не имеют: сквозь проём ходят, а не протискиваются.
func _frame_the_gap(gap: Vector2, slab: float) -> void:
	if slab <= 0.0:
		return

	var look := GreyboxLook.metal(GreyboxLook.TRIM)
	for edge: float in [gap.x, gap.y]:
		# Проём — только в задней полосе, от стены до края цельной плиты.
		var depth := HOLE_FRONT_Z - WorldSpace.BACK_WALL_Z
		_add_part(
			Vector3(FRAME_WIDTH, slab, depth),
			Vector3(edge, -slab * 0.5, WorldSpace.BACK_WALL_Z + depth * 0.5),
			0.0,
			look
		)
	# И кромка вдоль цельной плиты: край, за которым пол кончается.
	_add_part(
		Vector3(absf(gap.y - gap.x), slab, FRAME_WIDTH * 0.5),
		Vector3((gap.x + gap.y) * 0.5, -slab * 0.5, HOLE_FRONT_Z - FRAME_WIDTH * 0.25),
		0.0,
		look
	)


## Деталь модели [param part] на своём месте, под своим углом и с растяжкой
## [param stretch]: пролёт у каждого эскалатора свой.
func _add_kit(part: String, at: Vector3, angle: float, stretch: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = Escalator._kit_mesh(part)
	mesh.position = at
	mesh.rotation.z = angle
	mesh.scale = stretch
	_ramp.add_child(mesh)


static func _kit_mesh(part: String) -> Mesh:
	if _meshes.is_empty():
		var model := KIT.instantiate()
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			_meshes[node.name] = (node as MeshInstance3D).mesh
		model.free()
	return _meshes.get(part) as Mesh


## Кусок конструкции: коробка без тела на своём месте и под своим углом.
func _add_part(size: Vector3, at: Vector3, angle: float, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	part.rotation.z = angle
	_ramp.add_child(part)
