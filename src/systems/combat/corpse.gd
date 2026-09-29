class_name Corpse
extends RefCounted

## Лежащее тело: труп агента или оторванный от него кусок (ADR-0042,
## решение 1; ADR-0043, решения 7–11).
##
## Физическое тело, пока под ним не плита. На полу кабины оно едет с ней, как
## на платформе, — это делает [method CharacterBody3D.move_and_slide], а не
## перенос в узел кабины: тот вёз тело сквозь перекрытия, если оно лежало
## туловищем на площадке. Ушла кабина — тело падает в шахту; серединой над
## пустотой или над другой опорой, чем концы, — съезжает на опору середины.
## Засыпает только на неподвижной опоре: лежащие до конца здания трупы ничего
## не стоят кадру.
##
## Трупы лежат на своём слое [constant LAYER] и видят друг друга: убитый рядом
## с лежащим ложится на него (решение 10). Живые и Otto на этот слой не
## смотрят и проходят сквозь.
##
## Кабина режет тело двумя способами. Днищем сверху — [method cut_under]: что
## под днищем, пропадает. Стенкой — [method tear]: тело поперёк порога едущей
## кабины рвётся по стенке, и часть внутри уезжает отдельным [CorpsePiece].
## Без крови тело не рвётся: под днищем оно исчезает целиком, а с порога
## съезжает на опору своей середины, как и раньше.

## Группа всех лежащих тел: по ней кабина ищет, кого рвать стенкой.
const GROUP := &"corpses"
## Слой трупов в `project.godot`.
const LAYER: int = 5
## Слой геометрии: по нему, а не по трупам, тело ищет, есть ли где лечь.
const GEOMETRY_MASK: int = 1
## Порядок шага физики трупа: после кабин, у которых он нулевой.
const PRIORITY: int = 1
## Как быстро труп съезжает с края на опору середины, м/с.
const SLIDE_SPEED: float = 1.5
## Насколько высоко над лежащим ищутся те, кто лежит на нём, м.
const PILE_REACH: float = 1.0
## Длина брызг лужицы у порога, м.
const TEAR_PUDDLE: float = 0.3

## Тело легло и больше не двигается: физика уснула.
var at_rest: bool = false
## Тело упало и лежит формой по длине, а не стоячей.
var lying: bool = false
## Тела больше нет: зажато или срезано целиком.
var gone: bool = false
## Раздавлено лампой: засыпает сразу, где лежит, без физики.
var crushed: bool = false
## Срез днищем кабины, если он начался.
var cut: CarCut = null

var _body: CharacterBody3D
var _shape: CollisionShape3D
var _figure: FigureRig
var _gravity: float
var _max_fall: float
## Кабина, на которой лежит тело (или та, на которой лежит его опора), и
## высота тела над ней, м.
var _car: ElevatorCar = null
var _car_offset: float = 0.0
## Формы у тела не осталось: всё, что от него есть, — под днищем кабины.
var _shapeless: bool = false


func _init(
	body: CharacterBody3D,
	shape: CollisionShape3D,
	figure: FigureRig,
	gravity: float,
	max_fall: float
) -> void:
	_body = body
	_shape = shape
	_figure = figure
	_gravity = gravity
	_max_fall = max_fall


## Труп при теле [param node] — агента или куска, — или null у живого.
static func of(node: Object) -> Corpse:
	var agent := node as Enemy
	if agent != null:
		return agent.corpse
	var piece := node as CorpsePiece
	if piece != null:
		return piece.corpse
	return null


## Делает тело трупом: слой трупов вместо прежнего, маска — пол и трупы. Пули
## сквозь труп пролетают, а сам он лежит на полу и на других трупах.
func enter() -> void:
	_body.collision_layer = 1 << (LAYER - 1)
	_body.set_collision_mask_value(LAYER, true)
	# Шаг трупа — после шага кабин: лежащий на кабине берёт её высоту этого
	# кадра, а не прошлого.
	_body.process_physics_priority = PRIORITY
	_body.add_to_group(GROUP)


## Шаг лежащего. [param settled] — тело уже упало и может ложиться формой по
## длине; ложится оно ногами к [param facing] — голова там, куда упала.
func step(delta: float, settled: bool, facing: float) -> void:
	if at_rest:
		return
	if crushed:
		at_rest = settled
		return
	if not _body.is_on_floor():
		_body.velocity.y = maxf(_body.velocity.y - _gravity * delta, -_max_fall)
	var supports := _supports()
	_body.velocity.x = _slide(supports) if _body.is_on_floor() else 0.0
	_body.move_and_slide()
	_body.velocity.z = 0.0
	_body.global_position.z = WorldSpace.PLAY_Z
	_ride(_carrier(supports[1]))
	if not settled:
		return
	if not lying:
		lie_down(facing)
		return
	if _body.is_on_floor() and _body.is_on_ceiling():
		# Зажало между крышей кабины и верхом шахты: тела больше нет.
		vanish()
		return
	if _body.is_on_floor() and _still(supports):
		at_rest = true
		_body.velocity = Vector3.ZERO


## Форма лежащего: коробка по длине тела от ступней туда, куда оно упало.
func lie_down(facing: float) -> void:
	var length := Proportions.BODY * Enemy.LYING_LENGTH
	set_span(minf(0.0, -facing * length), maxf(0.0, -facing * length))


## Лежачая форма от [param from_x] до [param to_x] по X от ступней, м.
func set_span(from_x: float, to_x: float) -> void:
	lying = true
	var own := (_shape.shape as BoxShape3D).duplicate() as BoxShape3D
	own.size = Vector3(to_x - from_x, Proportions.PRONE, own.size.z)
	_shape.shape = own
	_shape.position = Vector3((from_x + to_x) * 0.5, Proportions.PRONE * 0.5, 0.0)
	# Кабина уходит вниз быстрее, чем тело успевает падать: без длинной
	# привязки к полу оно отрывалось бы и догоняло пол прыжками.
	_body.floor_snap_length = Proportions.PRONE


## Кладёт тело на кабину [param car]: едет с ней с этого кадра, а не догоняет.
func ride_on(car: ElevatorCar) -> void:
	_car = car
	_car_offset = _body.global_position.y - car.global_position.y


## Где тело лежит по X в мире: от и до.
func span() -> Vector2:
	var half := (_shape.shape as BoxShape3D).size.x * 0.5
	var middle := _body.global_position.x + _shape.position.x
	return Vector2(middle - half, middle + half)


## Будит уснувшее тело: из-под него ушла опора или его порвало.
func wake() -> void:
	if gone or not at_rest:
		return
	at_rest = false
	crushed = false
	_body.set_physics_process(true)


## Тела больше нет: не видно, не сталкивается, лежавшие на нём падают.
func vanish() -> void:
	if gone:
		return
	gone = true
	at_rest = true
	_body.visible = false
	_body.velocity = Vector3.ZERO
	_shape.set_deferred("disabled", true)
	_figure.set_process(false)
	_body.set_physics_process(false)
	_body.remove_from_group(GROUP)
	_wake_the_pile()


## Днище кабины [param car] проходит по телу сверху (решения 7–9).
func cut_under(car: ElevatorCar) -> void:
	if gone:
		return
	var left := car.global_position.x - car.width() * 0.5
	var right := car.global_position.x + car.width() * 0.5
	var bottom := car.bottom()
	var top := _body.global_position.y + (_shape.shape as BoxShape3D).size.y
	if not Blood.enabled:
		if bottom < top:
			vanish()
		return
	if cut == null:
		cut = CarCut.new()
		_keep(cut.remains_of(span(), left, right))
	cut.advance(_figure, _body.get_parent(), left, right, bottom)
	if cut.done and _shapeless:
		vanish()


## Рвёт тело стенкой кабины [param car] на [param wall_x]: что по сторону
## [param inside] (−1 или +1), уезжает с кабиной отдельным куском, остальное
## лежит где лежало.
func tear(car: ElevatorCar, wall_x: float, inside: float) -> void:
	var whole := span()
	var piece_span := Vector2(wall_x, whole.y) if inside > 0.0 else Vector2(whole.x, wall_x)
	var rest := Vector2(whole.x, wall_x) if inside > 0.0 else Vector2(wall_x, whole.y)
	var host := _body.get_parent()
	CorpsePiece.tear_off(_figure, host, piece_span, car)
	_figure.keep_between(rest.x, rest.y)
	# Снаружи тело кабине больше не принадлежит, даже если ехало с ней.
	_car = null
	_keep(rest)
	Corpse.bleed(host, Vector3(wall_x, _body.global_position.y, WorldSpace.PLAY_Z), inside)


## Брызги и лужица у стенки, по которой порвалось тело.
static func bleed(host: Node, at: Vector3, inside: float) -> void:
	var spot := at + Vector3(0.0, Proportions.PRONE, 0.0)
	Blood.spray(host, spot, inside)
	Blood.spray(host, spot, -inside)
	Blood.puddle(host, at - Vector3(inside * TEAR_PUDDLE * 0.5, 0.0, 0.0), TEAR_PUDDLE)


## Оставляет телу форму только на отрезке [param part] по X в мире; пустой —
## формы нет, тело держится одной картинкой, пока срез не кончится.
func _keep(part: Vector2) -> void:
	if part == Vector2.ZERO:
		_shapeless = true
		_shape.set_deferred("disabled", true)
		at_rest = true
		_body.set_physics_process(false)
		_wake_the_pile()
		return
	var feet := _body.global_position.x
	set_span(part.x - feet, part.y - feet)
	wake()
	_wake_the_pile()


## Будит уснувших на этом теле: опора под ними поменялась.
func _wake_the_pile() -> void:
	if not _body.is_inside_tree():
		return
	var own := span()
	for node: Node in _body.get_tree().get_nodes_in_group(GROUP):
		var other := Corpse.of(node)
		if other == null or other == self or not other.at_rest:
			continue
		var above := (node as Node3D).global_position.y - _body.global_position.y
		if above < -0.01 or above > PILE_REACH:
			continue
		var theirs := other.span()
		if theirs.y > own.x and theirs.x < own.y:
			other.wake()


## Держит лежащего на кабине [param car] вровень с ней. Тело кабины
## ([member AnimatableBody3D.sync_to_physics]) встаёт на место к концу шага
## физики, и [method move_and_slide] возил бы труп по вчерашнему полу — тот
## парил бы над едущей вниз кабиной. Поэтому высоту, с которой тело на кабину
## легло, держит кабина, а физика решает только, лежит ли оно на ней. Шаг трупа
## идёт после шага кабин ([constant PRIORITY]).
##
## Лежит ли — решает луч под серединой, а не [method is_on_floor]: отставшая на
## шаг кабина уходит из-под тела, и пол на этот шаг пропадает.
func _ride(car: ElevatorCar) -> void:
	if car == null:
		_car = null
		return
	if car != _car:
		if not _body.is_on_floor():
			return
		_car = car
		_car_offset = _body.global_position.y - car.global_position.y
		return
	_body.global_position.y = car.global_position.y + _car_offset
	_body.velocity.y = 0.0


## Кабина, которая везёт опору [param support]: сама кабина или та, на которой
## лежит труп под этим телом.
func _carrier(support: Object) -> ElevatorCar:
	var car := support as ElevatorCar
	if car != null:
		return car
	var under := Corpse.of(support)
	return under._car if under != null else null


## Опоры под левым концом, серединой и правым концом лежащего тела: тело, в
## которое упирается луч вниз, или null. Луч короткий — на толщину тела под
## ступни: длинный цеплял бы кабину, проезжающую под площадкой.
func _supports() -> Array[Object]:
	var found: Array[Object] = []
	var box := _shape.shape as BoxShape3D
	var middle := _body.global_position.x + _shape.position.x
	var half := box.size.x * 0.5 if lying else 0.0
	var space := _body.get_world_3d().direct_space_state
	for x: float in [middle - half, middle, middle + half]:
		var y := _body.global_position.y
		var from := Vector3(x, y + Proportions.PRONE, _body.global_position.z)
		var query := PhysicsRayQueryParameters3D.create(
			from, from - Vector3(0.0, Proportions.PRONE * 2.0, 0.0), _body.collision_mask
		)
		query.exclude = [_body.get_rid()]
		var hit := space.intersect_ray(query)
		found.append(null if hit.is_empty() else hit["collider"])
	return found


## Куда съезжать лежащему, м/с: с конца над пустотой — к опоре середины; с
## середины над пустотой — в пустоту. Конец на другой опоре, чем середина,
## держит тело, пока обе стоят: поперёк порога стоящей кабины оно лежит
## спокойно. Тронулась кабина под одним из концов — тело съезжает на опору
## середины; с кровью его до этого рвёт стенка ([method tear]).
func _slide(supports: Array[Object]) -> float:
	if not lying:
		return 0.0
	var left := supports[0]
	var middle := supports[1]
	var right := supports[2]
	var off_left := left == null or (left != middle and _moving(left, middle))
	var off_right := right == null or (right != middle and _moving(right, middle))
	if middle == null:
		off_left = left != null
		off_right = right != null
	if off_left == off_right:
		return 0.0
	return SLIDE_SPEED if off_left else -SLIDE_SPEED


## Едет ли кабина под одной из двух опор.
static func _moving(one: Object, other: Object) -> bool:
	for support: Object in [one, other]:
		var car := support as ElevatorCar
		if car != null and not is_zero_approx(car.speed_now()):
			return true
	return false


## Лежит ли тело на неподвижном: под обоими концами и серединой опора, и ни
## одна не едет. Кабина везёт, и на ней засыпать нельзя; труп — опора, только
## пока спит сам; люк подвала уходит из-под тела, когда собраны документы.
func _still(supports: Array[Object]) -> bool:
	for ground: Object in supports:
		if ground == null or ground is ElevatorCar:
			return false
		var under := Corpse.of(ground)
		if under != null and not under.at_rest:
			return false
		var node := ground as Node
		if node != null and node.is_in_group(BasementLock.HATCH_GROUP):
			return false
	return true
