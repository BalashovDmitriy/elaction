class_name Bullet
extends Area3D

## Пуля.
##
## Летит по горизонтали и гаснет о геометрию, о жертву или на дальности. Высота
## полёта задана точкой выстрела: от высокой пули приседают, низкую перепрыгивают.
## Отдельного правила для уклонения не нужно — всё решают формы коллизии, а они
## у Otto разные стоя и в приседе (ADR-0006, пункт 3).
##
## В кого попадать, решает маска: пуля Otto не задевает его самого, вражеская —
## не задевает других врагов.
##
## Летит в плоскости игры и только в ней: Z не меняется ни на сантиметр
## (ADR-0021, решение 1). Наклон камеры, когда он появится в M17, попадания
## не касается — он свойство камеры, а не мира (ADR-0019, решение 6).
##
## **Путь за кадр проверяется целиком** (ADR-0037, решение 5): с M24a пуля втрое
## быстрее ROM и за кадр физики проходит почти толщину стены, а под
## [member Engine.time_scale] тестов — вчетверо больше. Перекрытия формы [Area3D]
## хватало, пока шаг был короче стены; теперь пуля перед шагом ведёт свою форму
## по всему пути ([method PhysicsDirectSpaceState3D.cast_motion]) и гаснет о первое,
## что на нём встретит, — сквозь стену, дверь, агента или Otto не проскочить.

## Пуля во что-то попала. Разбирается с этим тот, кто её выпустил: он знает, свои
## это или чужие, и ему же идут очки.
signal hit_target(target: Node3D)

## Во что попадает пуля. Слои: 1 — геометрия, 2 — Otto, 4 — враги, 8 — лампы.
##
## Названы по стрелявшему, а не по мишени: пуля Otto бьёт и по агентам, и по
## лампам, и одним словом это не назвать.
const FROM_OTTO: int = 1 | 4 | 8
const FROM_ENEMY: int = 1 | 2

## Слои, попадание в которые слышно ударом по телу, а не стуком по стене.
const LIVING: int = 2 | 4

## Слой ламп: в лампу пуля бьёт без искр и следа — их выбрасывает сама лампа.
const LAMPS: int = 8

## Группа пуль: по ней агент находит то, от чего уклоняется. Перебирать детей
## уровня ему нельзя — их под три сотни, а пуль на экране от силы четыре.
const GROUP := &"bullets"

## Дальность пули по умолчанию, м: столько же тянется и луч прицела агента.
const RANGE: float = 14.4

@export var speed: float = 6.6

## Дальше этого пуля гаснет сама, даже не встретив преграды.
@export var max_range: float = RANGE

## Куда летит: -1 влево, +1 вправо.
var direction: float = 1.0

var _travelled: float = 0.0
var _look: BulletLook = null
## Пуля уже во что-то попала и доживает до конца кадра.
var _spent: bool = false
## Вспышка у ствола уже дана. Даётся первым кадром физики или попаданием в
## упор, если оно раньше, — но не в [method _ready]: стрелок ставит пулю на
## место уже после того, как добавил её в дерево.
var _flashed: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	# Вид — тонкий трассер с хвостом ([BulletLook]); направление стрелок задаёт
	# до того, как пуля попадёт в дерево.
	_look = BulletLook.make(direction)
	add_child(_look)


## Летит ли сейчас хоть одна пуля с маской [param mask]. По пуле Otto в кадре
## агенты поднимают тревогу (ADR-0027, решение 5).
static func any_in_flight(tree: SceneTree, mask: int) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		var bullet := node as Bullet
		if bullet != null and bullet.collision_mask == mask:
			return true
	return false


## Половина длины пули, м.
##
## По ней считают, вышла ли пуля из габарита тела: миновав его середину, она
## ещё перекрывает грудь на эту половину, и распрямившийся под ней всё равно
## её ловит. Берётся у самой формы, а не записывается числом рядом, — иначе
## правка сцены молча разошлась бы с теми, кто от неё уклоняется.
func half_length() -> float:
	return (($Shape as CollisionShape3D).shape as BoxShape3D).size.x * 0.5


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_flash_once()
	# Дальше дальности пуля не идёт и последним шагом: иначе на быстром кадре
	# она доставала бы на полшага дальше своей дальности.
	var length := minf(speed * delta, max_range - _travelled)
	var step := length * signf(direction)
	if not is_zero_approx(step) and _sweep(step):
		return
	position.x += step
	_travelled += absf(step)
	_look.follow(_travelled)
	if _travelled >= max_range - 0.0001:
		queue_free()


## Ведёт форму пули по пути [param step] за этот кадр и гасит её о первое тело на
## нём. Возвращает, было ли попадание.
##
## Дважды спрашивает физику: сперва — на какой доле пути форма впервые касается
## чего-то, потом — чего именно, уже на этом месте. Этого хватает, потому что
## пуля летит только по X и только в плоскости игры.
func _sweep(step: float) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ($Shape as CollisionShape3D).shape
	query.transform = global_transform
	query.motion = Vector3(step, 0.0, 0.0)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return false
	# Что задето, спрашивается на месте касания, но пуля туда переставляется,
	# только когда тело нашлось: иначе она ушла бы на долю пути и сверх неё
	# ещё на целый шаг — сквозь ту самую тонкую стену.
	var unsafe: float = fractions[1]
	var contact := global_transform.translated(Vector3(step * unsafe, 0.0, 0.0))
	query.transform = contact
	query.motion = Vector3.ZERO
	var point := contact.origin + Vector3(signf(step) * half_length(), 0.0, 0.0)
	var body: Node3D = null
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		body = instance_from_id(int(rest.get("collider_id", 0))) as Node3D
		point = rest.get("point", point)
	if body == null:
		# Касание мельче порога [method PhysicsDirectSpaceState3D.get_rest_info]:
		# тот же вопрос перекрытием, без глубины.
		var touching := space.intersect_shape(query, 1)
		if not touching.is_empty():
			body = touching[0].get("collider") as Node3D
	if body == null:
		return false
	# Встаёт туда, где коснулась, — брызги и искры ложатся по месту удара.
	global_position = contact.origin
	_travelled += absf(step * unsafe)
	_look.follow(_travelled)
	_hit(body, point)
	return true


## Вспышка и дымок — у ствола, откуда пуля вышла: вешаются на хозяина пули и
## остаются на месте, пока она летит (ADR-0037, решение 5). Один раз на пулю.
func _flash_once() -> void:
	if _flashed:
		return
	_flashed = true
	ShotFx.muzzle(get_parent(), global_position, direction)


func _on_body_entered(body: Node3D) -> void:
	_hit(body, global_position)


## Попадание в [param body] в точке [param point].
func _hit(body: Node3D, point: Vector3) -> void:
	# queue_free() убирает узел только в конце кадра, а тел за один кадр можно
	# задеть несколько: без этой отметки одна пуля убивала бы двоих сразу и
	# приносила очки за каждого.
	if _spent:
		return
	# В упор пуля попадает раньше своего первого кадра физики: перекрытие ловится
	# уже на шаге, в котором её выпустили. Вспышка у ствола — и тогда.
	_flash_once()
	_spent = true
	# Слой, а не класс: [Otto] и [Enemy] сами грузят сцену пули, и ссылка отсюда
	# на них замкнула бы загрузку в кольцо — сцена переставала бы читаться вовсе.
	var target := body as CollisionObject3D
	if target != null and (target.collision_layer & LIVING) != 0:
		# Своего звука у попадания нет (ADR-0036): его слышно смертью того, в
		# кого попали.
		# Брызги у самой пули, по её ходу (ADR-0031): остаются на месте, даже
		# когда пуля уже убрана. Неуязвимого пуля не ранит — брызги показали бы
		# попадание, которого нет, а неуязвимость видно только миганием. Спрашивается
		# свойством, а не классом: ссылка на [Otto] замкнула бы загрузку в кольцо.
		# У агента такого свойства нет, и [method Object.get] отдаёт null.
		if body.get(&"invulnerable") != true:
			Blood.spray(get_parent(), global_position, direction)
	elif target == null or (target.collision_layer & LAMPS) == 0:
		# Стена, дверь, кабина: искры, пыль и след на передней грани (ADR-0037,
		# решение 5). В лампу — без них: искры выбрасывает сама лампа.
		ShotFx.impact(
			get_parent(), Vector3(point.x, global_position.y, global_position.z), direction, body
		)
	# Геометрия просто гасит пулю, живых разбирает стрелявший.
	hit_target.emit(body)
	queue_free()
