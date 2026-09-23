class_name Escalator
extends Node3D

## Эскалатор между двумя этажами.
##
## В оригинале на него не заходят по пути: надо встать на площадку у края и
## нажать «вверх» или «вниз» (ADR-0005, пункт 8). Пока везёт — управления нет,
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

## Докуда слышен стрёкот полотна, м.
const HUM_REACH: float = 9.0

## Толщина и глубина полотна, м. Тела у полотна нет: везёт эскалатор, а не пол.
const BELT_THICKNESS: float = 0.15
const BELT_DEPTH: float = 0.8

## На сколько полотно утоплено за плоскость игры: пассажир едет перед ним.
const BELT_Z: float = -0.5

## Сколько полотно проходит по горизонтали за одну ступень, м.
##
## Ступень и есть то, чем эскалатор отличается от пандуса: на пролёте в 1.6 м
## их выходит полдюжины, и зубчатый край читается с любого этажа.
const STEP_RUN: float = 0.24

## Балюстрада у задней стены: где стоит, какой толщины и высоты, м.
const RAIL_Z: float = -1.02
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
const GLOW_ENERGY: float = 2.4
const GLOW_COLOR := Color(1.0, 0.88, 0.68)
const GLOW_Z: float = -0.3

## Борт со стороны камеры: где стоит, какой глубины и высоты, м.
##
## Низкий нарочно (ADR-0025, решение 5). Полноценная балюстрада с этой стороны
## закрыла бы едущего Otto по грудь, а на эскалаторе он беззащитен: ввод не
## действует, уклониться нечем, и поездка длится больше секунды.
const KERB_Z: float = -0.08
const KERB_DEPTH: float = 0.08
const KERB_HEIGHT: float = 0.16

## Площадка в конце полотна: длина по ходу и толщина, м.
##
## Короче, чем была: площадка не заходит в соседнее место, где этажом ниже
## может стоять шахта (ADR-0026, решение 6).
const LANDING_RUN: float = 0.42
const LANDING_THICKNESS: float = 0.12

## Обрамление проёма: ширина стойки по краю дыры и насколько она шире полотна, м.
const FRAME_WIDTH: float = 0.12
const FRAME_MARGIN: float = 0.12

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
		rider.board_escalator()
		return true
	return false


## Путь поездки: от места, где пассажир стоял, через перегиб к дальней площадке.
##
## Перегиб берётся из полотна, поэтому едут ровно там, где выложено. Без
## [method setup] полотна нет — тогда путь прямой, лишь бы не падать по индексу.
func _route_from(start: Vector3, target: Area3D) -> PackedVector3Array:
	if not _has_via:
		return PackedVector3Array([start, target.global_position])
	return PackedVector3Array([start, to_global(_via), target.global_position])


func _carry(delta: float) -> void:
	_progress = minf(_progress + delta / travel_time, 1.0)
	_passenger.global_position = _point_at(_progress)
	if _progress < 1.0:
		return
	_passenger.leave_escalator()
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
	# Нижняя площадка уходит по ходу спуска: с неё сходят, приехав.
	_lay_landing(down, down + Vector3(towards * LANDING_RUN, 0.0, 0.0))
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


## Полотно пролёта: ровная лента вдоль ломаной.
##
## Со стороны её закрывают ступени, но снизу видно именно её: эскалатор проходит
## сквозь перекрытие, и с нижнего этажа смотрят ему в брюхо.
func _lay_belt(from: Vector3, to: Vector3) -> void:
	var span := to - from
	_add_part(
		Vector3(span.length(), BELT_THICKNESS, BELT_DEPTH),
		(from + to) * 0.5 + Vector3(0.0, 0.0, BELT_Z),
		atan2(span.y, span.x),
		GreyboxLook.surface(GreyboxLook.ESCALATOR)
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
	var look := GreyboxLook.metal(GreyboxLook.ESCALATOR)

	for index in count:
		var top := from.y + riser * float(index)
		_add_part(
			Vector3(absf(tread), height, BELT_DEPTH),
			Vector3(from.x + tread * (float(index) + 0.5), top - height * 0.5, BELT_Z),
			0.0,
			look
		)


## Бока пролёта: балюстрада с поручнем у задней стены и низкий борт у камеры.
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

	var panel := GreyboxLook.surface(GreyboxLook.ESCALATOR)
	var trim := GreyboxLook.metal(GreyboxLook.TRIM)
	var over := BELT_THICKNESS * 0.5

	_add_part(
		Vector3(length, RAIL_HEIGHT, RAIL_THICKNESS),
		centre + up * (over + RAIL_HEIGHT * 0.5) + Vector3(0.0, 0.0, RAIL_Z),
		angle,
		panel
	)
	_add_part(
		Vector3(length, HANDRAIL_SIZE, HANDRAIL_SIZE),
		centre + up * (over + RAIL_HEIGHT + HANDRAIL_SIZE * 0.5) + Vector3(0.0, 0.0, RAIL_Z),
		angle,
		trim
	)
	_add_part(
		Vector3(length, KERB_HEIGHT, KERB_DEPTH),
		centre + up * (over + KERB_HEIGHT * 0.5) + Vector3(0.0, 0.0, KERB_Z),
		angle,
		trim
	)

	var cap := up * (over + RAIL_HEIGHT + HANDRAIL_SIZE * 0.5) + Vector3(0.0, 0.0, RAIL_Z)
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
	var run := absf(to.x - from.x)
	if is_zero_approx(run):
		return

	_add_part(
		Vector3(run, LANDING_THICKNESS, BELT_DEPTH),
		Vector3((from.x + to.x) * 0.5, from.y - LANDING_THICKNESS * 0.5, BELT_Z),
		0.0,
		GreyboxLook.metal(GreyboxLook.ESCALATOR)
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
		_add_part(
			Vector3(FRAME_WIDTH, slab, BELT_DEPTH + FRAME_MARGIN * 2.0),
			Vector3(edge, -slab * 0.5, BELT_Z),
			0.0,
			look
		)


## Кусок конструкции: коробка без тела на своём месте и под своим углом.
func _add_part(size: Vector3, at: Vector3, angle: float, material: StandardMaterial3D) -> void:
	var part := GreyboxLook.box(size, material)
	part.position = at
	part.rotation.z = angle
	_ramp.add_child(part)
