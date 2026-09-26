class_name ActorPose
extends RefCounted

## Какую позу показать актёру. Чистая функция от того, что с ним происходит.
##
## Вынесена из узлов по той же причине, что [OttoStateMachine] и
## [ElevatorMotion]: набор поз обязан покрывать все состояния, и проверять это
## надо без сцены, физики и отрисованного кадра. Списки поз лежат здесь же, и
## тест следит, чтобы выбор позы не выходил за них.
##
## До M15 списки жили у спрайтов: поза и была картинкой. Теперь позу отыгрывает
## [FigureRig] по таблице [FigurePoses], и место списка — рядом с правилом,
## которое позу выбирает, а не рядом с тем, кто её показывает.

## Кадров в цикле ходьбы (ADR-0011, пункт 5).
const WALK_FRAMES: int = 3

## Кадров ходьбы в секунду. На двенадцати шаг читается как бег, а Otto ходит
## (ADR-0011, пункт 5).
const WALK_FPS: float = 10.0

## Позы Otto.
const OTTO_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"crouch",
	"jump",
	"fall",
	"land",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
]

## Позы агента. Он не прыгает и не бьёт ногой — этого не умеет [EnemyBrain].
## «Crouch» служит ему позой «на колене», «prone» — своя (ADR-0016, пункт 3).
const AGENT_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"crouch",
	"prone",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
]

## Поза приседа. Одна на Otto и на агента: у агента это «на колене».
const CROUCH := "crouch"

## Поза агента лёжа. Единственная лежащая поза живого: в [FigurePoses] у неё
## своя запись — лицом вниз, ствол вперёд, — а не труп, положенный набок.
const PRONE := "prone"

## Позы, в которых актёр лежит, — все три вида смерти и уклонение лёжа.
##
## В греев-боксе по этому списку коробка ложилась набок; риг M16 читает позу из
## таблицы и его не спрашивает. Список остаётся фактом о позах, на котором стоят
## тесты выбора: труп обязан лежать, кто бы его ни показывал.
const DOWN: PackedStringArray = ["dead_0", "dead_1", "crushed", PRONE]

## Поза по состоянию для тех состояний, у которых она одна. Константа, а не
## словарь на каждый вызов: поза пересчитывается каждый физический кадр и на
## Otto, и на каждом агенте в кадре.
##
## С M24d удара ногой нет (ADR-0040): на спуске Otto просто летит — клип полёта.
const BY_STATE: Dictionary = {
	OttoStateMachine.State.CROUCH: CROUCH,
	OttoStateMachine.State.JUMP: "jump",
	OttoStateMachine.State.FALL: "fall",
}


## Поза Otto.
##
## [param shooting] и [param falling_over] — не состояния машины, а короткие
## таймеры: выстрел мгновенный, а показать его надо; смерть же показывается
## двумя позами, падением и лежащим телом (ADR-0011, пункт 12). Так же и
## [param landing]: только что приземлившийся и стоящий на месте показывает
## приземление (ADR-0039), шагнул — идёт.
static func of_otto(
	state: OttoStateMachine.State,
	crushed: bool,
	falling_over: bool,
	shooting: bool,
	walk_phase: float,
	landing: bool = false
) -> String:
	if state == OttoStateMachine.State.DEAD:
		return _death(crushed, falling_over)
	if shooting:
		return "shoot"
	if landing and state == OttoStateMachine.State.IDLE:
		return "land"
	if state == OttoStateMachine.State.WALK:
		return walk_frame(walk_phase)
	return BY_STATE.get(state, "idle")


## Поза агента. Он не прыгает и не бьёт ногой — этого не умеет [EnemyBrain], и
## кадры на несуществующие состояния были бы мусором. А уклоняться он умеет
## с M11, и у колена с положением лёжа свои позы (ADR-0016, пункт 3).
##
## Стойка важнее выстрела: выстрел держится 0.18 с, а стойка — пока в агента
## летит пуля, и подменять её позой выстрела значило бы показывать стоящего
## там, где на самом деле лежит. Сам выстрел видно по вспышке пули.
static func of_agent(
	dead: bool,
	walking: bool,
	crushed: bool,
	falling_over: bool,
	shooting: bool,
	walk_phase: float,
	stance: EnemyBrain.Stance = EnemyBrain.Stance.STAND
) -> String:
	if dead:
		return _death(crushed, falling_over)
	if stance == EnemyBrain.Stance.KNEEL:
		return CROUCH
	if stance == EnemyBrain.Stance.PRONE:
		return PRONE
	if shooting:
		return "shoot"
	return walk_frame(walk_phase) if walking else "idle"


## Продвигает фазу ходьбы на один кадр времени.
##
## Живёт рядом с [method walk_frame] нарочно: длину цикла знает один
## [constant WALK_FRAMES]. Со своим `fmod` в каждом актёре цикл замыкался бы не
## там, где считается кадр, и последний кадр ходьбы просто не показывался бы.
static func advance(walk_phase: float, delta: float) -> float:
	return fmod(walk_phase + delta * WALK_FPS, float(WALK_FRAMES))


## Лежит ли актёр в этой позе.
static func is_down(pose: String) -> bool:
	return DOWN.has(pose)


## Кадр ходьбы по фазе: целая часть фазы и есть номер кадра.
static func walk_frame(walk_phase: float) -> String:
	var frame := int(walk_phase) % WALK_FRAMES
	return "walk_%d" % maxi(frame, 0)


## Номер кадра ходьбы из имени позы: обратное к [method walk_frame]. Нужен
## ригу, которому имя кадра приходит строкой, а цикл ходьбы идёт по фазе.
static func walk_frame_index(pose: String) -> int:
	if not pose.begins_with("walk_"):
		return 0
	return clampi(pose.trim_prefix("walk_").to_int(), 0, WALK_FRAMES - 1)


## Как именно убили: раздавленный показан своей картинкой, а падение и лежащее
## тело — двумя разными.
static func _death(crushed: bool, falling_over: bool) -> String:
	if crushed:
		return "crushed"
	return "dead_0" if falling_over else "dead_1"
