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

## Поза приседа. Одна на Otto и на агента: у агента это «на колене».
const CROUCH := "crouch"

## Позы, в которых актёр лежит, — все три вида смерти и уклонение лёжа.
##
## Спрашивают об этом снаружи: греев-бокс кладёт коробку набок, а в M16 на том
## же вопросе будет выбираться анимация. Перечислять их у каждого, кто спросит,
## значит разойтись при первой же новой позе.
const DOWN: PackedStringArray = ["dead_0", "dead_1", "crushed", "prone"]

## Поза по состоянию для тех состояний, у которых она одна. Константа, а не
## словарь на каждый вызов: поза пересчитывается каждый физический кадр и на
## Otto, и на каждом агенте в кадре.
##
## В воздухе Otto бьёт ногой всегда (ADR-0006, пункт 2), поэтому падение и есть
## тот самый удар с разбега — отдельной позы падения нет.
const BY_STATE: Dictionary = {
	OttoStateMachine.State.CROUCH: CROUCH,
	OttoStateMachine.State.JUMP: "jump",
	OttoStateMachine.State.FALL: "kick",
}


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
		return "prone"
	if shooting:
		return "shoot"
	return walk_frame(walk_phase) if walking else "idle"


## Продвигает фазу ходьбы на один кадр времени.
##
## Живёт рядом с [method walk_frame] нарочно: длину цикла знает один
## [constant WALK_FRAMES]. Со своим `fmod` в каждом актёре цикл замыкался бы не
## там, где считается кадр, и последний кадр ходьбы просто не показывался бы.
static func advance(walk_phase: float, delta: float) -> float:
	return fmod(walk_phase + delta * SpriteTextures.WALK_FPS, float(WALK_FRAMES))


## Лежит ли актёр в этой позе.
static func is_down(pose: String) -> bool:
	return DOWN.has(pose)


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
