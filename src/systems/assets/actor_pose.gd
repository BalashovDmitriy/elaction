class_name ActorPose
extends RefCounted

## Какую позу показать актёру. Чистая функция от того, что с ним происходит.
##
## Вынесена из узлов по той же причине, что [OttoStateMachine] и
## [ElevatorMotion]: набор поз обязан покрывать все состояния, и проверять это
## надо без сцены, физики и отрисованного кадра. Имена поз — те же, что в
## [constant SpriteTextures.OTTO_POSES], и тест следит, чтобы они не разошлись.

## Кадров в цикле ходьбы (ADR-0011, пункт 5).
const WALK_FRAMES: int = 3


## Поза Otto.
##
## [param shooting] и [param falling_over] — не состояния машины, а короткие
## таймеры: выстрел мгновенный, а показать его надо; смерть же показывается
## двумя позами, падением и лежащим телом (ADR-0011, пункт 12).
static func of_otto(
	state: OttoStateMachine.State,
	crushed: bool,
	falling_over: bool,
	shooting: bool,
	walk_phase: float
) -> String:
	if state == OttoStateMachine.State.DEAD:
		return _death(crushed, falling_over)
	if shooting:
		return "shoot"

	# В воздухе Otto бьёт ногой всегда (ADR-0006, пункт 2), поэтому падение и
	# есть тот самый удар с разбега — отдельной позы падения нет.
	var by_state: Dictionary = {
		OttoStateMachine.State.CROUCH: "crouch",
		OttoStateMachine.State.JUMP: "jump",
		OttoStateMachine.State.FALL: "kick",
	}
	if state == OttoStateMachine.State.WALK:
		return walk_frame(walk_phase)
	return by_state.get(state, "idle")


## Поза агента. Он не приседает, не прыгает и не бьёт ногой — этого не умеет
## [EnemyBrain], и кадры на несуществующие состояния были бы мусором.
static func of_agent(
	dead: bool, walking: bool, crushed: bool, falling_over: bool, shooting: bool, walk_phase: float
) -> String:
	if dead:
		return _death(crushed, falling_over)
	if shooting:
		return "shoot"
	return walk_frame(walk_phase) if walking else "idle"


## Кадр ходьбы по фазе: целая часть фазы и есть номер кадра.
static func walk_frame(walk_phase: float) -> String:
	var frame := int(walk_phase) % WALK_FRAMES
	return "walk_%d" % maxi(frame, 0)


## Как именно убили: раздавленный показан своей картинкой, а падение и лежащее
## тело — двумя разными.
static func _death(crushed: bool, falling_over: bool) -> String:
	if crushed:
		return "crushed"
	return "dead_0" if falling_over else "dead_1"
