class_name Door
extends Node2D

## Дверь этажа.
##
## Красная прячет документ, обычная — засаду. Створку ведёт [DoorCycle], правила
## визита Otto — [DoorVisit]; узел отвечает за коврик, вид и выдачу документа.
##
## Дверью пользуются двое, и по-разному. Otto стучится сам и сидит внутри, пока
## не выйдет время. Агента дверь выпускает по просьбе уровня, и открывается перед
## ним заметно дольше: створка — это предупреждение (ADR-0020, решение 2).

## Документ взят, дверь перестала быть красной.
signal document_taken

## Ассеты створки по ходу: закрыта, приоткрыта, открыта. Состояние двери — это
## не оттенок одного прямоугольника, а разная картинка (ADR-0011).
const CLOSED_ASSET := "door"
const DOCUMENT_ASSET := "door_red"
const OPENING_ASSET := "door_ajar"
const OPEN_ASSET := "door_open"

## Докуда слышно створку, px. Дверей в здании полсотни, и хлопок каждой на всё
## здание превратился бы в стук без остановки: слышно только ближние.
const DOOR_REACH: float = 1440.0

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
var _voice: AudioStreamPlayer2D = null
## Что уже нарисовано: ход створки и ассет закрытой двери. Дверей в здании
## полсотни, и почти всё время все они стоят закрытыми — перерисовывать их
## каждый кадр значит звать сервер отрисовки полсотни раз на ровном месте.
##
## Ассет в паре с ходом, потому что красная дверь, отдавшая документ, меняет
## картинку, не двинув створкой.
var _shown: float = -1.0
var _shown_closed: String = ""

@onready var _mat: Area2D = $Mat
@onready var _panel: TextureRect = $Panel
@onready var _next_panel: TextureRect = $NextPanel
@onready var _mat_visual: TextureRect = $MatVisual


func _ready() -> void:
	_visit.hide_time = hide_time
	_mat_visual.texture = SpriteTextures.tile("door_mat")
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


## Точка, где Otto стоит перед дверью: сюда же его возвращают за документом.
func mat_position() -> Vector2:
	return _mat.global_position


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
	for body: Node2D in _mat.get_overlapping_bodies():
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


## Ведёт картинку створки по ходу [DoorCycle].
##
## Кадра три, а ход непрерывный, поэтому показываются два соседних и между ними
## перегоняется прозрачность. Новых кадров не рисуем: набор уходит вместе с 2D
## (ADR-0020, решение 7).
##
## Стоящая створка не перерисовывается: зовут отсюда каждый кадр и из каждой
## двери здания, а меняется картинка только пока дверь ходит.
func _refresh_look() -> void:
	var along := _cycle.openness() * 2.0
	var closed := _frame_asset(0)
	if is_equal_approx(along, _shown) and closed == _shown_closed:
		return
	_shown = along
	_shown_closed = closed
	var frame := clampi(int(along), 0, 1)
	_panel.texture = SpriteTextures.tile(_frame_asset(frame))
	_next_panel.texture = SpriteTextures.tile(_frame_asset(frame + 1))
	_next_panel.modulate.a = along - frame


func _frame_asset(frame: int) -> String:
	if frame >= 2:
		return OPEN_ASSET
	if frame == 1:
		return OPENING_ASSET
	return DOCUMENT_ASSET if has_document else CLOSED_ASSET


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
