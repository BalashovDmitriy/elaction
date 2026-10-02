class_name Door
extends Node3D

## Дверь этажа.
##
## Красная прячет документ, обычная — засаду. Створку ведёт [DoorCycle], правила
## визита Otto — [DoorVisit]; узел отвечает за коврик, вид и выдачу документа.
##
## Дверью пользуются двое, и по-разному. Otto стучится сам, створка закрывается
## за ним и открывается, выпуская, ровно через 70 тиков ROM (ADR-0038, решение 2).
## Агента дверь выпускает по просьбе уровня, и открывается перед ним заметно
## дольше: створка — это предупреждение (ADR-0020, решение 2).
##
## Створка висит в задней стене коридора, порог — в плоскости игры (ADR-0021,
## решение 1). Проём в стене за створкой режет сам уровень.
##
## Над створкой табло: красное у красной двери, тёплое у обычной. Это и есть
## читаемость двери на погашенном этаже — сама створка больше не светится
## (ADR-0023, решение 6).

## Документ взят, дверь перестала быть красной. Как в ROM — на выходе Otto,
## а не на входе (ADR-0038, решение 2).
signal document_taken

## Otto ушёл внутрь и створка пошла за ним. По этому уровень ведёт агентов к
## двери ([DoorWatch]).
signal otto_hid

## Otto вышел наружу.
signal otto_came_out

## Габарит створки, м: 40% × 70% просвета, как в оригинале ([Proportions]).
## Уровень режет по нему проём в задней стене, а коробка створки собирается
## из него же в [method Node._ready], а не лежит в сцене вторым числом.
const LEAF_SIZE := Proportions.DOOR

## Ход створки перед агентом по умолчанию, с — [member agent_open_time].
const AGENT_OPEN_TIME: float = 0.7

## Толщина створки, м.
const LEAF_THICKNESS: float = 0.08

## На сколько створка отстоит от стены. Чуть больше нуля: лежащая в одной
## плоскости со стеной, она мерцала бы с ней на каждом кадре.
const LEAF_STANDOFF: float = 0.05

## Докуда слышно створку, м. Дверей в здании полсотни, и хлопок каждой на всё
## здание превратился бы в стук без остановки: слышно только ближние.
const DOOR_REACH: float = 14.4

## Табло над створкой: габарит и на сколько его середина выше верха створки, м.
const SIGN_SIZE := Vector3(0.4, 0.13, 0.04)

## Детали двери (ADR-0031, решение 3): филёнки на створке, ручка, отбойная
## пластина и наличник вокруг проёма, м.
const PANEL_SIZE := Vector2(0.84, 0.78)
const PANEL_RELIEF: float = 0.02
const HANDLE := Vector3(0.15, 0.025, 0.04)
const ROSETTE := Vector3(0.06, 0.12, 0.02)
const HANDLE_RISE: float = 1.0
const KICK_PLATE := Vector2(1.08, 0.2)
const FRAME_WIDTH: float = 0.08
const FRAME_DEPTH: float = 0.05
const SIGN_RISE: float = 0.2
## Пока Otto за красной дверью, закрытая створка в тени коридора сливалась с
## темнотой (кадр `door_02_inside_closed`). Теперь створка чуть светится сама —
## красным, как была, — а табло над ней медленно дышит: раз в столько секунд,
## от своей обычной яркости до этой доли сверху. Источников света не прибавляет.
const OCCUPIED_PULSE: float = 1.6
const OCCUPIED_GLOW: float = 1.8
## Насколько занятая створка светится сама: доля её цвета. Маркер
## ([method GreyboxLook.marker]) горел плоским розовым пятном ярче всех дверей.
const OCCUPIED_LEAF_GLOW: float = 0.14

## Бра красной двери (ADR-0042, решение 8): красная дверь в тени коридора
## терялась, и её легко было пройти. Конус без тени, перед створкой у её верха,
## смотрит вниз и к стене — пятно ложится на створку и пол перед ней. Горит и при
## сбитой лампе, гаснет с документом. Дальше своего пола не светит: от высоты
## бра до пола — меньше дальности, до плиты под полом — больше.
const RED_LIGHT_COLOR := Color(1.0, 0.32, 0.26)
const RED_LIGHT_ENERGY: float = 1.3
const RED_LIGHT_RANGE: float = 3.0
const RED_LIGHT_ANGLE: float = 42.0
## Насколько бра перед стеной, м, и на сколько оно наклонено к ней от отвеса.
const RED_LIGHT_OUT: float = 0.7
const RED_LIGHT_TILT: float = 0.35

## Стекло офисной створки: размер, м, и тон — светлое матовое.
const VISION := Vector2(0.62, 0.5)
const FROSTED := Color(0.78, 0.84, 0.88)
## Табличка «Не беспокоить» на ручке: размер, м, и цвет.
const HANGER := Vector3(0.09, 0.22, 0.008)
const HANGER_COLOR := Color(0.72, 0.1, 0.12)
## Соль жребия мелочей у двери: свой, чтобы не ходить в ногу с комнатой.
const LITTLE_SALT: int = 0x7A_B1E5
## Глазок квартиры: размер и высота над низом створки, м.
const PEEPHOLE := Vector3(0.035, 0.035, 0.02)
const PEEPHOLE_RISE: float = 1.55
## Коврик у порога квартиры, м, и его цвета.
const DOORMAT := Vector3(0.9, 0.015, 0.5)
const DOORMAT_RIM := Color(0.12, 0.11, 0.1)
const DOORMAT_TONES: Array[Color] = [
	Color(0.36, 0.26, 0.16), Color(0.2, 0.26, 0.2), Color(0.34, 0.14, 0.12), Color(0.28, 0.28, 0.3)
]
## Пакет с покупками, м, и его начинка.
const BAG := Vector3(0.3, 0.38, 0.2)
const BAG_COLOR := Color(0.62, 0.48, 0.3)
const LOAF_COLOR := Color(0.78, 0.6, 0.34)
const GREENS_COLOR := Color(0.24, 0.46, 0.18)

## Краски занятой створки по тону: их две на все двери (створка и филёнки).
static var _occupied_paints: Dictionary = {}

## Сколько Otto сидит внутри, с: 70 тиков ROM, считая от стука.
@export var hide_time: float = Arcade.seconds(Arcade.ROOM_TICKS)

## Сколько открывается створка перед гостем, с: 7 тиков ROM — столько Otto
## идёт в дверь, прежде чем пропасть (@3BDA–3C25, ADR-0043, решение 4).
@export var open_time: float = Arcade.seconds(7)

## Сколько открывается створка перед агентом, с.
##
## Дольше, чем перед Otto, и нарочно: игрок обязан успеть увидеть створку и уйти.
## Сверкой не подтверждено — ADR-0020, решение 2. Число — в [constant
## AGENT_OPEN_TIME]: по нему уровень заранее знает, когда звать дверь, чтобы
## агент вышел к концу смены (ADR-0028, решение 7).
@export var agent_open_time: float = AGENT_OPEN_TIME

## Красная дверь: за ней документ.
@export var has_document: bool = false

var _visit := DoorVisit.new()
var _cycle := DoorCycle.new()
var _guest: Otto = null
## Otto, который уже снаружи, но ещё выходит: створка закрывается за ним.
var _stepping_out: Otto = null
## Дверь открыта под агента: занята, пока он не выйдет.
var _expecting_agent: bool = false
var _voice: AudioStreamPlayer3D = null
## Что уже показано: ход створки и красная ли дверь. Дверей в здании полсотни,
## и почти всё время все они стоят закрытыми — двигать их каждый кадр значит
## трогать трансформ полсотни раз на ровном месте.
var _shown: float = -1.0
var _shown_red: bool = false
var _shown_occupied: bool = false
var _sign: MeshInstance3D = null
## Бра красной двери; горит, пока за ней документ и этаж в кадре.
var _red_light: SpotLight3D = null
## Этаж двери в полосе горящих: за кадром бра не горит, как и лампы
## ([method set_light_in_view]). Дверь вне уровня — в тестах — считается в кадре.
var _in_view: bool = true
## Своё табло на время, пока Otto внутри: общий материал огонька дышал бы у всех
## красных дверей здания разом. И часы дыхания — по физике: на паузе оно стоит.
var _pulse: StandardMaterial3D = null
var _pulse_clock: float = 0.0
## Филёнки створки: их тон идёт за створкой — красной или обычной.
var _panels: Array[MeshInstance3D] = []
## Комната за дверью ([DoorRoom], ADR-0047): собирается, когда створка
## трогается, и убирается, когда закрылась. Здание и жребий двери даёт уровень
## ([method furnish]); без них — в тестах — за дверью по-прежнему темно.
var _room: DoorRoom = null
var _room_identity: BuildingIdentity = null
var _room_seed: int = 0
var _room_span := Vector2(-INF, INF)
var _furnished: bool = false
var _room_unlit: bool = false
var _room_time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
var _room_weather: Weather.Kind = Weather.Kind.CLEAR
## Вид двери по типу здания (ADR-0048): филёнки и дерево у отеля, стекло и
## алюминий у офиса. Без здания — отель, как до M24i.
var _style := BuildingStyle.new()

@onready var _mat: Area3D = $Mat
@onready var _leaf: MeshInstance3D = $Leaf
@onready var _mat_visual: MeshInstance3D = $MatVisual


## Коврик по [Proportions] — сразу после сборки сцены, как формы актёров.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var mat := Proportions.DOOR_MAT
	Proportions.fit_box($Mat/MatShape as CollisionShape3D, Vector3(mat, 0.3, 0.4))
	Proportions.fit_mesh($MatVisual as MeshInstance3D, Vector3(mat, 0.02, mat))


func _ready() -> void:
	if _furnished:
		_style = BuildingStyle.of(_room_identity)
	_visit.hide_time = hide_time
	_visit.leaf_time = open_time
	_mat_visual.material_override = GreyboxLook.surface(GreyboxLook.SLAB)
	var leaf := BoxMesh.new()
	leaf.size = Vector3(LEAF_SIZE.x, LEAF_SIZE.y, LEAF_THICKNESS)
	_leaf.mesh = leaf
	_leaf.position = Vector3(0.0, LEAF_SIZE.y * 0.5, WorldSpace.BACK_WALL_Z + LEAF_STANDOFF)
	_sign = GreyboxLook.box(SIGN_SIZE, GreyboxLook.light(GreyboxLook.SIGN_WARM))
	_sign.name = "Sign"
	_sign.position = Vector3(
		0.0, LEAF_SIZE.y + SIGN_RISE, WorldSpace.BACK_WALL_Z + SIGN_SIZE.z * 0.5
	)
	add_child(_sign)
	_red_light = _make_red_light()
	add_child(_red_light)
	_dress_leaf()
	_frame_the_opening()
	_refresh_look()


func _physics_process(delta: float) -> void:
	_cycle.tick(delta)
	_refresh_look()
	_breathe(delta)

	if _stepping_out != null:
		# Выходит на камеру, пока створка закрывается.
		_stepping_out.ride_progress = _cycle.openness()
		_see_out()
		return

	if _guest == null:
		_look_for_visitor()
		return
	if _guest.ride_look == Otto.LOOK_DOOR_IN:
		# Уходит вглубь проёма, пока створка открывается.
		_guest.ride_progress = _cycle.openness()

	match _visit.tick(delta, _cycle.is_open()):
		DoorVisit.Cue.HIDE:
			_hide_the_guest()
		DoorVisit.Cue.LET_OUT:
			_cycle.open()
			Sounds.play(Sounds.DOOR_OPEN)
		DoorVisit.Cue.OUT:
			_release()


## Осталась ли за дверью добыча: красная ли она ещё. Документ достаётся на
## выходе (ADR-0038, решение 2), и до выхода дверь остаётся красной.
func is_pending() -> bool:
	return has_document


## Точка, где Otto стоит перед дверью, в координатах правил: сюда он входит
## и отсюда выходит.
func mat_position() -> Vector2:
	return WorldSpace.to_plane(_mat.global_position)


## Свободна ли дверь под агента: внутри никого, и створка стоит закрытой.
##
## Спрашивают до выбора двери, а не после: уровень выпускает одного за кадр и
## берёт ближайшую дверь. Ближайшая, ещё закрывающаяся за прошлым агентом,
## забирала бы этот кадр себе — и не выпускала никого, пока не дойдёт створка.
func can_summon() -> bool:
	return _guest == null and not _expecting_agent and _cycle.is_shut()


## Просит дверь открыться, чтобы выпустить агента.
##
## Возвращает false, если дверь занята: внутри гость или створка ещё ходит после
## прошлого. Уровень в этом случае просто попробует в следующий раз.
func summon_agent() -> bool:
	if not can_summon():
		return false
	_expecting_agent = true
	_cycle.travel_time = agent_open_time
	_cycle.open()
	_say(Sounds.DOOR_OPEN)
	return true


## Ход створки, 0..1. По нему видно снаружи, открыта дверь или нет.
func openness() -> float:
	return _cycle.openness()


## Открылась ли створка настолько, что агент может показаться в проёме.
func agent_may_step_out() -> bool:
	return _expecting_agent and _cycle.is_open()


## Агент вышел или дверь передумала: створка идёт обратно.
##
## Otto, вставший перед открывающейся дверью, её не останавливает — дверь не
## передумывает (ADR-0020, решение 5). Зовут отсюда только уровень: либо агент
## освободил проём, либо этаж ушёл из полосы выпуска.
func dismiss_agent() -> void:
	if not _expecting_agent:
		return
	_expecting_agent = false
	_cycle.close()
	_say(Sounds.DOOR_CLOSE)


func _look_for_visitor() -> void:
	if _expecting_agent:
		# Дверь занята выходом агента, и Otto в неё не пускают. Дело не в
		# вежливости: створку за агентом закрывает уровень ([method
		# dismiss_agent]), а визит гостя идёт по створке — прячется он и выходит
		# только в открытую, — и пущенный сюда Otto застрял бы в проёме.
		return
	if not has_document:
		# Как в ROM (@3BDA): игрока пускает только красная дверь, пока документ
		# не забран. Обычная — дверь агентов, и укрытием она не служит
		# (ADR-0044, решение 3).
		return
	for body: Node3D in _mat.get_overlapping_bodies():
		var visitor := body as Otto
		if visitor == null:
			continue
		if not _visit.knock(visitor.is_grounded(), visitor.vertical_intent()):
			continue
		_admit(visitor)
		return


## Впускает Otto: створка открывается, и пока она идёт, он шагает в проём.
##
## Шаг в проём — поездка, как на эскалаторе: ввод снят и достать его нельзя уже
## сейчас — в ROM он неуязвим от первого шага внутрь, — но он ещё на виду.
## Прячется он, когда створка откроется ([method _hide_the_guest]).
func _admit(visitor: Otto) -> void:
	_guest = visitor
	visitor.global_position = _mat.global_position
	visitor.ride_look = Otto.LOOK_DOOR_IN
	visitor.ride(true)
	_visit.admit()
	_cycle.travel_time = open_time
	_cycle.open()
	Sounds.play(Sounds.DOOR_OPEN)


## Створка открылась: Otto внутри, и она закрывается за ним. Коридор отсюда
## слышно глухо — и музыку, и шаги с выстрелами (ADR-0038, решение 2).
func _hide_the_guest() -> void:
	_guest.ride(false)
	_guest.stay_indoors(true)
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)
	_muffle(true)
	otto_hid.emit()


## Выпускает Otto в открытую створку и закрывает её за ним. Документ достаётся
## здесь, на выходе, как в ROM: пока Otto внутри, дверь ещё красная.
##
## Выход кончается, когда створка закрылась: до тех пор Otto на виду, но ввод
## снят и достать его нельзя — в ROM он неуязвим «до полного выхода». Без этого
## агент, дождавшийся у двери, стрелял бы в того, кто ещё стоит в проёме.
func _release() -> void:
	_guest.global_position = _mat.global_position
	_guest.stay_indoors(false)
	_guest.ride_look = Otto.LOOK_DOOR_OUT
	_guest.ride_progress = 1.0
	_guest.ride(true)
	_stepping_out = _guest
	_guest = null
	_visit.release()
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)
	_muffle(false)
	otto_came_out.emit()

	if not has_document:
		return
	has_document = false
	Sounds.play(Sounds.DOCUMENT)
	document_taken.emit()


## Створка закрылась за вышедшим: управление снова у игрока.
func _see_out() -> void:
	if not _cycle.is_shut():
		return
	if is_instance_valid(_stepping_out):
		_stepping_out.ride(false)
	_stepping_out = null


## Глушит коридор за дверью или возвращает его: музыку и звуки мира разом.
func _muffle(on: bool) -> void:
	Sounds.muffle_music(Sounds.MUFFLE_DOOR, on)
	Sounds.muffle_world(on)


## Здание выбросили, пока Otto за дверью, — новая партия с паузы, выход в меню.
## Глухой звук снимает сама дверь: иначе это пришлось бы помнить каждому, кто
## выбрасывает здание.
func _exit_tree() -> void:
	if _guest != null and _visit.is_hiding():
		_muffle(false)


## Ведёт створку по ходу [DoorCycle].
##
## Створка поворачивается на петлях у левого края внутрь комнаты — на четверть
## оборота при полном ходе. До M18c она съезжала вбок по стене на всю свою
## ширину, но при шаге места 1.8 м и створке 1.2 открытая дверь налезала бы на
## соседнее место — на шахту или другую дверь. Повёрнутая, она не выходит за
## свой проём: комната за стеной глубиной 7 м (ADR-0026, решение 3).
##
## Стоящая створка не трогается: зовут отсюда каждый кадр и из каждой двери
## здания, а меняется положение только пока дверь ходит.
func _refresh_look() -> void:
	var along := _cycle.openness()
	var occupied := _occupied()
	if (
		is_equal_approx(along, _shown)
		and has_document == _shown_red
		and occupied == _shown_occupied
	):
		return
	_shown = along
	_shown_red = has_document
	_shown_occupied = occupied
	_open_the_room(along)
	var angle := along * PI * 0.5
	var half := LEAF_SIZE.x * 0.5
	# Поворот вокруг Y на +угол уводит правый край створки в −Z, то есть
	# в комнату; середина ходит по дуге вокруг петли.
	_leaf.rotation.y = angle
	_leaf.position.x = -half + cos(angle) * half
	_leaf.position.z = WorldSpace.BACK_WALL_Z + LEAF_STANDOFF - sin(angle) * half
	var tone := GreyboxLook.DOOR_RED if has_document else _style.leaf_tone
	# Занятая створка светится сама, неярко: маркер, а не краска.
	_leaf.material_override = _paint(tone, occupied)
	var relief := _paint(tone.darkened(0.14), occupied)
	for panel in _panels:
		panel.material_override = relief
	var glow := GreyboxLook.SIGN_RED if has_document else _style.sign_tone
	_sign.material_override = GreyboxLook.light(glow)
	_red_light.visible = has_document and _in_view
	_pulse_clock = 0.0


## Какая комната за дверью: здание [param identity] и жребий двери
## [param seed]. [param span] — этаж от наружной стены до наружной по X от
## середины двери: комната не выходит за него ([method DoorRoom.build]).
##
## [param unlit] — этаж двери тёмный: комната за ней без своего света.
## [param time] и [param weather] — что за окном комнаты (ADR-0052, решение 5).
func furnish(
	identity: BuildingIdentity,
	seed: int,
	span: Vector2 = Vector2(-INF, INF),
	unlit: bool = false,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	weather: Weather.Kind = Weather.Kind.CLEAR
) -> void:
	_room_unlit = unlit
	_room_time = time
	_room_weather = weather
	_room_identity = identity
	_room_seed = seed
	_room_span = span
	_furnished = true


## Комната за дверью, пока створка открыта; иначе null.
func room() -> DoorRoom:
	return _room


## Собирает комнату, когда створка тронулась, и убирает, когда закрылась.
func _open_the_room(along: float) -> void:
	if not _furnished:
		return
	if along > 0.0 and _room == null:
		var kind := BuildingIdentity.Kind.HOTEL if _room_identity == null else _room_identity.kind
		_room = DoorRoom.build(
			kind, _room_seed, _room_identity, _room_span, _room_unlit, _room_time, _room_weather
		)
		add_child(_room)
	elif along <= 0.0 and _room != null:
		_room.queue_free()
		_room = null


## Этаж двери попал в полосу горящих или ушёл из неё. Зовёт уровень, отбирая
## видимые этажи, как у ламп (ADR-0010, пункт 8).
func set_light_in_view(on: bool) -> void:
	_in_view = on
	if _red_light != null:
		_red_light.visible = has_document and on


## Горит ли бра красной двери. Тестам.
func is_red_light_on() -> bool:
	return _red_light != null and _red_light.visible


func _make_red_light() -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "RedLight"
	light.light_color = RED_LIGHT_COLOR
	light.light_energy = RED_LIGHT_ENERGY
	light.spot_range = RED_LIGHT_RANGE
	light.spot_angle = RED_LIGHT_ANGLE
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.5
	light.position = Vector3(0.0, LEAF_SIZE.y + SIGN_RISE, WorldSpace.BACK_WALL_Z + RED_LIGHT_OUT)
	# Свет у Godot идёт вдоль −Z узла: отвес вниз и наклон к стене.
	light.rotation.x = -PI * 0.5 + RED_LIGHT_TILT
	light.visible = false
	return light


## Краска створки: занятая светится сама, неярко, — красной остаётся и в тени.
static func _paint(tone: Color, occupied: bool) -> StandardMaterial3D:
	var plain := GreyboxLook.surface(tone)
	if not occupied:
		return plain
	var found: Variant = _occupied_paints.get(tone)
	if found != null:
		return found as StandardMaterial3D
	var glowing := plain.duplicate() as StandardMaterial3D
	glowing.emission_enabled = true
	glowing.emission = tone
	glowing.emission_energy_multiplier = OCCUPIED_LEAF_GLOW
	_occupied_paints[tone] = glowing
	return glowing


## Otto за этой дверью: вошёл и ещё не вышел.
func _occupied() -> bool:
	return _guest != null and _visit.is_hiding()


## Табло над занятой дверью медленно дышит, пока Otto внутри.
func _breathe(delta: float) -> void:
	if not _shown_occupied:
		return
	if _pulse == null:
		_pulse = GreyboxLook.light(GreyboxLook.SIGN_RED).duplicate() as StandardMaterial3D
	_pulse_clock += delta
	var phase := 0.5 - 0.5 * cos(_pulse_clock * TAU / OCCUPIED_PULSE)
	_pulse.emission_energy_multiplier = GreyboxLook.LIGHT_GLOW * lerpf(1.0, OCCUPIED_GLOW, phase)
	_sign.material_override = _pulse


## Детали створки: у отеля — две филёнки, у офиса — матовое стекло в верхней
## трети; ручка с розеткой у свободного края и отбойная пластина внизу. Дети
## створки — поворачиваются вместе с ней. У части номеров отеля — табличка «Не
## беспокоить» на ручке и газета или поднос у порога (ADR-0048).
func _dress_leaf() -> void:
	var front := LEAF_THICKNESS * 0.5
	var bottom := -LEAF_SIZE.y * 0.5
	if _style.panels:
		for rise: float in [0.35, 0.78]:
			var panel := GreyboxLook.box(
				Vector3(PANEL_SIZE.x, PANEL_SIZE.y, PANEL_RELIEF),
				GreyboxLook.surface(GreyboxLook.DOOR)
			)
			panel.position = Vector3(0.0, bottom + LEAF_SIZE.y * rise, front + PANEL_RELIEF * 0.5)
			_leaf.add_child(panel)
			_panels.append(panel)
	if _style.vision_glass:
		_leaf.add_child(_vision_glass(front, bottom))
	var chrome := GreyboxLook.metal(_style.handle_tone)
	if _style.peephole:
		var eye := GreyboxLook.box(PEEPHOLE, chrome)
		eye.name = "Peephole"
		eye.position = Vector3(0.0, bottom + PEEPHOLE_RISE, front + PEEPHOLE.z * 0.5)
		_leaf.add_child(eye)
	var handle_x := LEAF_SIZE.x * 0.5 - 0.14
	var rosette := GreyboxLook.box(ROSETTE, chrome)
	rosette.position = Vector3(handle_x, bottom + HANDLE_RISE, front + ROSETTE.z * 0.5)
	_leaf.add_child(rosette)
	var lever := GreyboxLook.box(HANDLE, chrome)
	lever.name = "Lever"
	lever.position = Vector3(
		handle_x - HANDLE.x * 0.4, bottom + HANDLE_RISE, front + ROSETTE.z + HANDLE.z * 0.5
	)
	_leaf.add_child(lever)
	var kick := GreyboxLook.box(Vector3(KICK_PLATE.x, KICK_PLATE.y, 0.01), chrome)
	kick.position = Vector3(0.0, bottom + KICK_PLATE.y * 0.5 + 0.02, front + 0.005)
	_leaf.add_child(kick)
	_little_things(lever)


## Матовое стекло в створке офиса: светлая полоса в верхней трети, чуть
## светится — за ней кабинет.
func _vision_glass(front: float, bottom: float) -> MeshInstance3D:
	var frosted := StandardMaterial3D.new()
	frosted.albedo_color = FROSTED
	frosted.roughness = 0.2
	frosted.emission_enabled = true
	frosted.emission = FROSTED
	frosted.emission_energy_multiplier = 0.25
	var glass := GreyboxLook.box(Vector3(VISION.x, VISION.y, 0.012), frosted)
	glass.name = "VisionGlass"
	glass.position = Vector3(0.0, bottom + LEAF_SIZE.y * 0.72, front + 0.006)
	return glass


## Мелочи у двери жребием двери: у номера отеля — табличка на ручке и газета
## или поднос у порога, у квартиры — коврик и пакет с покупками (ADR-0055).
## У красной двери и в офисе их нет.
func _little_things(lever: MeshInstance3D) -> void:
	if not _furnished or has_document:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_room_seed, LITTLE_SALT])
	if rng.randf() < _style.door_hanger_share:
		var card := GreyboxLook.box(HANGER, GreyboxLook.surface(HANGER_COLOR))
		card.name = "DoorHanger"
		card.position = Vector3(-HANGER.x * 0.3, -HANGER.y * 0.55, HANGER.z)
		lever.add_child(card)
	if rng.randf() < _style.door_tray_share:
		var tray := _tray() if rng.randf() < 0.5 else _newspaper()
		tray.position = Vector3(LEAF_SIZE.x * 0.5 + 0.28, 0.0, WorldSpace.BACK_WALL_Z + 0.3)
		add_child(tray)
	if rng.randf() < _style.door_mat_share:
		add_child(_doormat(rng))
	if rng.randf() < _style.door_bag_share:
		var bag := _grocery_bag()
		bag.position = Vector3(
			-(LEAF_SIZE.x * 0.5 + 0.3), 0.0, WorldSpace.BACK_WALL_Z + BAG.z * 0.5 + 0.08
		)
		add_child(bag)


## Поднос с посудой после ужина в номере.
func _tray() -> Node3D:
	var tray := Node3D.new()
	tray.name = "Tray"
	var board := GreyboxLook.box(
		Vector3(0.42, 0.02, 0.3), GreyboxLook.metal(Color(0.72, 0.7, 0.66))
	)
	board.position.y = 0.01
	tray.add_child(board)
	var dish := GreyboxLook.box(Vector3(0.2, 0.03, 0.2), GreyboxLook.surface(Color(0.9, 0.9, 0.88)))
	dish.position = Vector3(-0.07, 0.035, 0.0)
	tray.add_child(dish)
	var cloche := GreyboxLook.box(
		Vector3(0.14, 0.09, 0.14), GreyboxLook.metal(Color(0.8, 0.8, 0.82))
	)
	cloche.position = Vector3(0.11, 0.065, 0.02)
	tray.add_child(cloche)
	return tray


## Газета у порога.
func _newspaper() -> Node3D:
	var paper := GreyboxLook.box(
		Vector3(0.36, 0.025, 0.26), GreyboxLook.surface(Color(0.82, 0.8, 0.74))
	)
	paper.name = "Newspaper"
	paper.position.y = 0.0125
	paper.rotation.y = 0.25
	var holder := Node3D.new()
	holder.add_child(paper)
	return holder


## Коврик у порога квартиры: тёмная кайма, середина своего цвета жребием.
## Лежит перед проёмом, а не в нём: створка ходит над ним.
func _doormat(rng: RandomNumberGenerator) -> Node3D:
	var mat := Node3D.new()
	mat.name = "Doormat"
	mat.position = Vector3(0.0, 0.0, WorldSpace.BACK_WALL_Z + DOORMAT.z * 0.5 + 0.06)
	var rim := GreyboxLook.box(DOORMAT, GreyboxLook.surface(DOORMAT_RIM))
	rim.position.y = DOORMAT.y * 0.5
	mat.add_child(rim)
	var tone := DOORMAT_TONES[rng.randi_range(0, DOORMAT_TONES.size() - 1)]
	var middle := GreyboxLook.box(
		Vector3(DOORMAT.x - 0.08, DOORMAT.y, DOORMAT.z - 0.08), GreyboxLook.surface(tone)
	)
	middle.position.y = DOORMAT.y * 0.5 + 0.002
	mat.add_child(middle)
	return mat


## Бумажный пакет с покупками у двери: сверху торчат батон и зелень.
func _grocery_bag() -> Node3D:
	var bag := Node3D.new()
	bag.name = "GroceryBag"
	var paper := GreyboxLook.box(BAG, GreyboxLook.surface(BAG_COLOR))
	paper.position.y = BAG.y * 0.5
	bag.add_child(paper)
	var loaf := GreyboxLook.box(Vector3(0.07, 0.16, 0.07), GreyboxLook.surface(LOAF_COLOR))
	loaf.position = Vector3(-0.06, BAG.y + 0.03, 0.0)
	loaf.rotation.z = 0.25
	bag.add_child(loaf)
	var greens := GreyboxLook.box(Vector3(0.1, 0.08, 0.08), GreyboxLook.surface(GREENS_COLOR))
	greens.position = Vector3(0.06, BAG.y + 0.02, 0.01)
	bag.add_child(greens)
	return bag


## Наличник вокруг проёма на задней стене: стойки и перемычка.
func _frame_the_opening() -> void:
	var trim := GreyboxLook.metal(GreyboxLook.TRIM.darkened(0.35))
	if _furnished:
		trim = (
			GreyboxLook.surface(_style.frame_tone)
			if _style.panels
			else GreyboxLook.metal(_style.frame_tone)
		)
	var half := LEAF_SIZE.x * 0.5
	var z := WorldSpace.BACK_WALL_Z + FRAME_DEPTH * 0.5
	for side: float in [-1.0, 1.0]:
		var jamb := GreyboxLook.box(Vector3(FRAME_WIDTH, LEAF_SIZE.y, FRAME_DEPTH), trim)
		jamb.position = Vector3(side * (half + FRAME_WIDTH * 0.5), LEAF_SIZE.y * 0.5, z)
		add_child(jamb)
	var head := GreyboxLook.box(
		Vector3(LEAF_SIZE.x + FRAME_WIDTH * 2.0, FRAME_WIDTH, FRAME_DEPTH), trim
	)
	head.position = Vector3(0.0, LEAF_SIZE.y + FRAME_WIDTH * 0.5, z)
	add_child(head)


## Подаёт голос двери. Источник позиционный и один на дверь: поток подменяется,
## потому что открыться и закрыться разом она всё равно не может.
##
## Звук зовётся [param effect], а не `name`: у [Node] поле с таким именем своё,
## и параметр его заслонял бы.
func _say(effect: String) -> void:
	if _voice == null:
		_voice = Sounds.source(self, effect, DOOR_REACH)
	else:
		_voice.stream = Sounds.stream(effect)
	_voice.play()
