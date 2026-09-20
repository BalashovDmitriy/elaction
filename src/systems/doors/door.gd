class_name Door
extends Node3D

## Дверь этажа.
##
## Красная прячет документ, обычная — засаду. Створку ведёт [DoorCycle], правила
## визита Otto — [DoorVisit]; узел отвечает за коврик, вид и выдачу документа.
##
## Дверью пользуются двое, и по-разному. Otto стучится сам и сидит внутри, пока
## не выйдет время. Агента дверь выпускает по просьбе уровня, и открывается перед
## ним заметно дольше: створка — это предупреждение (ADR-0020, решение 2).
##
## Створка висит в задней стене коридора, порог — в плоскости игры (ADR-0021,
## решение 1). Проём в стене за створкой режет сам уровень.

## Документ взят, дверь перестала быть красной.
signal document_taken

## Габарит створки, м. Те же 84×171 прежних пикселя; уровень режет по нему проём
## в задней стене, поэтому число живёт здесь, а не в двух местах — и коробка
## створки собирается из него же в [method Node._ready], а не лежит в сцене
## вторым числом.
const LEAF_SIZE := Vector2(0.84, 1.71)

## Толщина створки, м.
const LEAF_THICKNESS: float = 0.08

## На сколько створка отстоит от стены. Чуть больше нуля: лежащая в одной
## плоскости со стеной, она мерцала бы с ней на каждом кадре.
const LEAF_STANDOFF: float = 0.05

## Докуда слышно створку, м. Дверей в здании полсотни, и хлопок каждой на всё
## здание превратился бы в стук без остановки: слышно только ближние.
const DOOR_REACH: float = 14.4

## Сколько Otto может пересидеть внутри, с.
@export var hide_time: float = 5.0

## Сколько открывается створка перед гостем, с.
@export var open_time: float = 0.25

## Сколько открывается створка перед агентом, с.
##
## Дольше, чем перед Otto, и нарочно: игрок обязан успеть увидеть створку и уйти.
## Сверкой не подтверждено — ADR-0020, решение 2.
@export var agent_open_time: float = 0.7

## Красная дверь: за ней документ.
@export var has_document: bool = false

var _visit := DoorVisit.new()
var _cycle := DoorCycle.new()
var _guest: Otto = null
## Дверь открыта под агента: занята, пока он не выйдет.
var _expecting_agent: bool = false
var _voice: AudioStreamPlayer3D = null
## Что уже показано: ход створки и красная ли дверь. Дверей в здании полсотни,
## и почти всё время все они стоят закрытыми — двигать их каждый кадр значит
## трогать трансформ полсотни раз на ровном месте.
var _shown: float = -1.0
var _shown_red: bool = false

@onready var _mat: Area3D = $Mat
@onready var _leaf: MeshInstance3D = $Leaf
@onready var _mat_visual: MeshInstance3D = $MatVisual


func _ready() -> void:
	_visit.hide_time = hide_time
	_mat_visual.material_override = GreyboxLook.surface(GreyboxLook.SLAB)
	var leaf := BoxMesh.new()
	leaf.size = Vector3(LEAF_SIZE.x, LEAF_SIZE.y, LEAF_THICKNESS)
	_leaf.mesh = leaf
	_leaf.position = Vector3(0.0, LEAF_SIZE.y * 0.5, WorldSpace.BACK_WALL_Z + LEAF_STANDOFF)
	_refresh_look()


func _physics_process(delta: float) -> void:
	_cycle.tick(delta)
	_refresh_look()

	if _guest == null:
		_look_for_visitor()
		return

	if _visit.tick(delta, _guest.horizontal_intent(), _cycle.is_open()):
		_release()


## Осталась ли за дверью добыча. По этому признаку выбирают, куда вернуть Otto.
func is_pending() -> bool:
	return has_document


## Точка, где Otto стоит перед дверью, в координатах правил: сюда же его
## возвращают за документом.
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
		# dismiss_agent]), а отсидка гостя идёт только при открытой двери —
		# пущенный сюда Otto остался бы внутри навсегда.
		return
	for body: Node3D in _mat.get_overlapping_bodies():
		var visitor := body as Otto
		if visitor == null:
			continue
		if not _visit.knock(visitor.is_grounded(), visitor.vertical_intent()):
			continue
		_admit(visitor)
		return


func _admit(visitor: Otto) -> void:
	_guest = visitor
	visitor.global_position = _mat.global_position
	visitor.enter_door()
	_visit.admit()
	_cycle.travel_time = open_time
	_cycle.open()
	Sounds.play(Sounds.DOOR_OPEN)

	if not has_document:
		return
	# Документ достаётся за вход, и дверь сразу перестаёт быть красной.
	has_document = false
	Sounds.play(Sounds.DOCUMENT)
	document_taken.emit()


func _release() -> void:
	_guest.global_position = _mat.global_position
	_guest.leave_door()
	_guest = null
	_visit.release()
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)


## Ведёт створку по ходу [DoorCycle].
##
## В греев-боксе створка сдвигается вбок, в стену, — на всю свою ширину при
## полном ходе. Не кадры и не поворот: коробке без петель уходить в карман
## стены честнее всего, а модель с петлями придёт в M16.
##
## Стоящая створка не трогается: зовут отсюда каждый кадр и из каждой двери
## здания, а меняется положение только пока дверь ходит.
func _refresh_look() -> void:
	var along := _cycle.openness()
	if is_equal_approx(along, _shown) and has_document == _shown_red:
		return
	_shown = along
	_shown_red = has_document
	_leaf.position.x = -along * LEAF_SIZE.x
	var tone := GreyboxLook.DOOR_RED if has_document else GreyboxLook.DOOR
	_leaf.material_override = GreyboxLook.marker(tone)


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
