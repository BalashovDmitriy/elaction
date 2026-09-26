class_name Takedown
extends RefCounted

## Добивание вплотную (ADR-0040): кого можно добить, с какой стороны, какой
## сценкой и за сколько очков.
##
## С M24d удара ногой нет. Кнопка выстрела вдали стреляет, а вплотную к агенту
## на том же этаже — добивает; упавший на агента сверху — с этажа выше или с
## крыши кабины — добивает сам. Сценка — короткая постановка двоих: кто в какой
## позе с какого момента, где стоит агент, когда он погибает. Вариант берётся
## случайно из подходящих к стороне, без повтора подряд.
##
## Правило без узлов, как [OttoStateMachine]: проверяется без сцены. Ведёт
## сценку в игре [TakedownScene].

## С какой стороны Otto достал агента.
enum Side { FRONT, BACK, ABOVE }

## Как далеко по горизонтали агент ещё «вплотную», м — между осями тел.
## Шире удара ногой ROM (16 px, 0.53 м): вплотную — это шаг, а не касание.
const REACH: float = 0.9
## Насколько могут расходиться полы Otto и агента, м: один этаж, а не соседний.
const SAME_FLOOR: float = 0.3
## Как далеко по горизонтали надо быть над агентом, чтобы напрыгнуть, м.
const POUNCE_REACH: float = 0.45

## Очки по стороне (решение пользователя, ADR-0040): сзади и сверху — вровень с
## лампой и лифтом, спереди — вдвое против выстрела.
const SCORES: Dictionary = {Side.FRONT: 200, Side.BACK: 300, Side.ABOVE: 300}
## Надбавка в темноте и на этажах 11–15 — как у ROM за выстрел и удар, но своя.
const DARK_BONUS: int = 100


## Одна сценка: позы двоих по времени.
class Scene:
	extends RefCounted

	var name: String
	## [enum Takedown.Side]. Числом: GDScript путает тип перечисления в статических
	## функциях класса и во внешнем коде.
	var side: int
	## Сколько идёт сценка, с — в своём темпе, мир вокруг замедлен.
	var duration: float
	## Когда агент погибает, с: до этого сценку можно прервать, и агент живёт.
	var kill_at: float
	## Где стоит агент: столько метров перед Otto, по его взгляду.
	var offset: float
	## Лицом ли агент к Otto. Спереди — да, сзади — нет.
	var faces_otto: bool
	## Позы по времени: [[время, поза], …], по возрастанию времени.
	var otto: Array[Array] = []
	var agent: Array[Array] = []
	## Поза трупа после сценки: в чём агент лёг, в том и лежит.
	var corpse: String = "dead_1"

	## Поза актёра в момент [param time]: последняя начавшаяся.
	static func pose_at(track: Array[Array], time: float) -> String:
		var shown := String(track[0][1]) if not track.is_empty() else ""
		for key: Array in track:
			if float(key[0]) <= time:
				shown = String(key[1])
		return shown


## Достаёт ли Otto агента вплотную: тот же этаж, рядом, и агент перед ним — по
## взгляду Otto. Спиной к агенту Otto стреляет туда, куда смотрит.
##
## Координаты — сцены: X вдоль этажа, Y — ноги, вверх.
static func can_reach(otto: Vector2, facing: float, agent: Vector2) -> bool:
	if absf(agent.y - otto.y) > SAME_FLOOR:
		return false
	var ahead := (agent.x - otto.x) * signf(facing)
	return ahead >= -0.05 and ahead <= REACH


## Стоит ли тело на кабине — на её полу или крыше. Таких не добивают и такие не
## добивают: сценка замораживает обоих, а кабина едет дальше и уезжает из-под
## пары (авторевью M24d).
static func rides_a_car(body: CharacterBody3D) -> bool:
	if not body.is_on_floor():
		return false
	for index in body.get_slide_collision_count():
		if body.get_slide_collision(index).get_collider() is ElevatorCar:
			return true
	return false


## С какой стороны агента Otto: агент смотрит на него — спереди, иначе сзади.
static func side_of(otto_x: float, agent_x: float, agent_facing: float) -> int:
	var towards := signf(otto_x - agent_x)
	if is_zero_approx(towards):
		return Side.FRONT
	return Side.FRONT if towards == signf(agent_facing) else Side.BACK


## Над агентом ли падающий Otto: ноги выше макушки и по горизонтали рядом.
static func is_above(otto_feet: Vector2, agent_feet: Vector2, agent_height: float) -> bool:
	return (
		otto_feet.y > agent_feet.y + agent_height
		and absf(otto_feet.x - agent_feet.x) <= POUNCE_REACH
	)


## Падает ли Otto на агента сверху: последняя опора выше этажа агента — этаж над
## ним или крыша кабины (ADR-0040, решение 4). Свой прыжок с того же пола не в
## счёт: вершина прыжка выше макушки, и он добивал бы сам.
static func fell_onto(support_y: float, agent_y: float) -> bool:
	return support_y - agent_y > SAME_FLOOR


## Очки за добивание.
static func score(side: int, in_the_dark: bool) -> int:
	var base: int = SCORES[side]
	return base + DARK_BONUS if in_the_dark else base


## Сценки стороны.
static func scenes_for(side: int) -> Array[Scene]:
	var found: Array[Scene] = []
	for scene: Scene in all_scenes():
		if scene.side == side:
			found.append(scene)
	return found


## Сценка стороны случайно, но не та же, что была прошлой — если есть другая.
static func pick(side: int, last: String, rng: RandomNumberGenerator) -> Scene:
	var choices := scenes_for(side)
	if choices.size() > 1:
		choices = choices.filter(func(scene: Scene) -> bool: return scene.name != last)
	return choices[rng.randi_range(0, choices.size() - 1)]


## Все сценки. Собираются заново на вызов: их мало, а общая таблица менялась
## бы у всех разом.
static func all_scenes() -> Array[Scene]:
	return [_combo(), _pistol_whip(), _choke(), _neck_snap(), _pounce()]


## Спереди: джеб, кросс — агента отбрасывает на спину.
static func _combo() -> Scene:
	var scene := _scene("combo", Side.FRONT, 1.15, 0.72, 0.72, true)
	scene.otto = [[0.0, "punch_jab"], [0.34, "punch_cross"], [0.95, "idle"]]
	scene.agent = [[0.0, "idle"], [0.12, "hit_head"], [0.46, "hit_chest"], [0.66, "knockback"]]
	scene.corpse = "knocked"
	return scene


## Спереди: замах рукоятью сверху — агент оседает. Позы кодом: бросок UAL,
## пробованный первым, — выпад вниз, и Otto нырял агенту в ноги (кадры M24D).
static func _pistol_whip() -> Scene:
	var scene := _scene("pistol_whip", Side.FRONT, 1.0, 0.42, 0.62, true)
	scene.otto = [[0.0, "whip_raise"], [0.3, "whip_strike"], [0.8, "idle"]]
	scene.agent = [[0.0, "idle"], [0.3, "hit_head"], [0.42, "dead_0"]]
	return scene


## Сзади: захват за шею, агент бьётся и обмякает.
static func _choke() -> Scene:
	var scene := _scene("choke", Side.BACK, 1.35, 1.02, 0.4, false)
	scene.otto = [[0.0, "choke_hold"], [1.12, "idle"]]
	scene.agent = [
		[0.0, "choked"],
		[0.22, "choked_kick"],
		[0.42, "choked"],
		[0.6, "choked_kick"],
		[0.8, "choked"],
		[1.02, "dead_0"],
	]
	return scene


## Сзади: руки на голову — рывок вбок, агент падает камнем.
static func _neck_snap() -> Scene:
	var scene := _scene("neck_snap", Side.BACK, 0.95, 0.46, 0.32, false)
	scene.otto = [[0.0, "snap_grab"], [0.38, "snap_twist"], [0.78, "idle"]]
	scene.agent = [[0.0, "snap_held"], [0.4, "snap_broken"], [0.52, "dead_0"]]
	return scene


## Сверху: упал на агента — тот отлетает на спину, Otto добивает над ним.
static func _pounce() -> Scene:
	var scene := _scene("pounce", Side.ABOVE, 1.0, 0.55, 0.55, true)
	scene.otto = [[0.0, "land"], [0.3, "pounce_strike"], [0.82, "idle"]]
	scene.agent = [[0.0, "knockback"]]
	scene.corpse = "knocked"
	return scene


static func _scene(
	scene_name: String, side: int, length: float, kill: float, gap: float, facing: bool
) -> Scene:
	var scene := Scene.new()
	scene.name = scene_name
	scene.side = side
	scene.duration = length
	scene.kill_at = kill
	scene.offset = gap
	scene.faces_otto = facing
	return scene
