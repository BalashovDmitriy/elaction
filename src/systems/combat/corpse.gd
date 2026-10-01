class_name Corpse
extends RefCounted

## Тело на суставах у агента, Otto и оторванного куска (ADR-0043, решения 7–12).
##
## Рэгдолл ([Ragdoll]) собирается с рождения актёра и ждёт выключенным: живой
## ходит своей формой по правилам аркады, а части тела только повторяют позу и
## ни с чем не сталкиваются. В миг смерти тело падает ([method fall]): части
## включаются и летят от толчка пули, дальше всё решает физика — тело оседает,
## ложится на другие трупы, едет на полу кабины, падает в шахту. Засыпают части
## сами, когда улеглись: лежащие до конца здания трупы ничего не стоят кадру.
##
## Трупы лежат на своём слое [constant LAYER] и видят друг друга (решение 10).
## Живые и Otto на этот слой не смотрят и проходят сквозь.
##
## Кабина режет тело двумя способами. Днищем сверху — [method cut_under]: что
## под днищем, пропадает. Стенкой — [method tear]: тело поперёк порога едущей
## кабины рвётся, и части внутри уезжают отдельным [CorpsePiece]. Без крови
## тело не рвётся: под днищем оно исчезает целиком.

## Через сколько после начала падения тело бьётся о пол, с, и докуда это
## слышно, м.
const THUD_AFTER: float = 0.4
const THUD_REACH: float = 16.0

## Группа упавших тел: по ней кабина ищет, кого рвать стенкой.
const GROUP := &"corpses"
## Слой трупов в `project.godot`.
const LAYER: int = 5
## Слой геометрии: пол, стены, кабины.
const GEOMETRY_MASK: int = 1
## Толчок пули в туловище, Н·с, и насколько он поддаёт вверх. Без пули тело
## толкает назад, от взгляда, вполсилы: обмякший столбом оседал бы сидя.
const HIT_IMPULSE: float = 60.0
const HIT_LIFT: float = 0.15
const SLUMP: float = 1.0
## Длина лужицы у порога, м.
const TEAR_PUDDLE: float = 0.3
## Метки, которыми пуля отмечает удар: куда (−1 влево, +1 вправо) и где.
const HIT_META := &"hit_from"
const HIT_POINT := &"hit_at"

## Тело упало и живёт физикой.
var fallen: bool = false
## Тела больше нет: срезано целиком или зажато.
var gone: bool = false
## Срез днищем кабины, если он начался.
var cut: CarCut = null
var ragdoll: Ragdoll = null
## Тело уже порвано стенкой: второй раз кабина его не рвёт.
var torn: bool = false

var _holder: Node3D
var _figure: FigureRig


## Собирает тело при фигуре [param figure] актёра [param holder]. [param only]
## — только эти части (кусок); пусто — все.
func _init(
	holder: Node3D, figure: FigureRig, only: PackedStringArray = PackedStringArray()
) -> void:
	_holder = holder
	_figure = figure
	ragdoll = Ragdoll.new(figure, only)
	ragdoll.corpse = self


## Тело при узле [param node] — актёре, куске или части тела, — или null.
static func of(node: Object) -> Corpse:
	if node == null:
		return null
	var part := node as PhysicalBone3D
	if part != null:
		if part.has_meta(&"ragdoll"):
			return (part.get_meta(&"ragdoll") as Ragdoll).corpse
		return null
	var found: Variant = node.get(&"corpse")
	if found is Corpse:
		return found as Corpse
	return null


## Тело падает: поза отпускает скелет, части летят со скоростью [param velocity]
## и от толчка пули, если она отметила актёра ([constant HIT_META]). Толчок
## приходит в ту часть, куда попала пуля, и в саму точку: в голову — голову
## запрокидывает, в ноги — их выбивает, в корпус — отбрасывает всё тело.
func fall(velocity: Vector3) -> void:
	if fallen:
		return
	fallen = true
	_figure.set_process(false)
	var facing := signf(sin(_figure.rotation.y))
	var hit := float(_holder.get_meta(HIT_META, -facing * SLUMP))
	var impulse := Vector3(hit, HIT_LIFT * absf(hit), 0.0) * HIT_IMPULSE
	var at: Variant = _holder.get_meta(HIT_POINT) if _holder.has_meta(HIT_POINT) else null
	ragdoll.start(velocity, impulse, at)
	_holder.add_to_group(GROUP)
	# Тело оземь — чуть позже начала падения, когда оно долетело до пола.
	if _holder.is_inside_tree():
		var timer := _holder.get_tree().create_timer(THUD_AFTER, false)
		timer.timeout.connect(_thud)


## Удар тела о пол на месте тела (ADR-0052, решение 7).
func _thud() -> void:
	if is_instance_valid(_holder) and _holder.is_inside_tree():
		var parent := _holder.get_parent()
		Sounds.play_at(parent, Sounds.BODY_FALL, _holder.global_position, THUD_REACH)


## Тело встаёт: Otto воскрес. Скелет собирается заново — отрезанное кабиной
## возвращается, — и поза снова ведёт фигуру.
func rise() -> void:
	ragdoll.dispose()
	ragdoll = Ragdoll.new(_figure)
	ragdoll.corpse = self
	_figure.heal()
	_figure.set_process(true)
	_holder.visible = true
	_holder.remove_from_group(GROUP)
	_holder.remove_meta(HIT_META)
	_holder.remove_meta(HIT_POINT)
	fallen = false
	gone = false
	torn = false
	cut = null


## Тела больше нет: не видно и не сталкивается.
func vanish() -> void:
	if gone:
		return
	gone = true
	_holder.visible = false
	ragdoll.remove(ragdoll.names())
	_holder.remove_from_group(GROUP)


## Может ли тело лежать не дальше [param reach] от [param x] по этажу. Прикидка
## по тазу: целое тело — ни срезанное, ни порванное — держат суставы, и дальше
## роста от таза ни одна его часть не уходит.
func near(x: float, reach: float) -> bool:
	if ragdoll.parts.is_empty():
		return false
	var pelvis := ragdoll.parts.get("Body", ragdoll.parts.values()[0]) as PhysicalBone3D
	return absf(Ragdoll.center_of(pelvis).x - x) < reach + Proportions.BODY


## Где тело лежит по X в мире: от и до.
func span() -> Vector2:
	var box := ragdoll.bounds()
	return Vector2(box.position.x, box.end.x)


## Днище кабины [param car] проходит по телу сверху (решения 7–9). Части, по
## которым оно прошло до середины, пропадают; кабина сквозь тело не толкает —
## иначе вдавливала бы его в пол.
func cut_under(car: ElevatorCar) -> void:
	if not fallen or (gone and (cut == null or cut.done)):
		return
	if not Blood.enabled:
		vanish()
		return
	var left := car.global_position.x - car.width() * 0.5
	var right := car.global_position.x + car.width() * 0.5
	var bottom := car.bottom()
	if cut == null:
		cut = CarCut.new()
		# Режущая кабина тело не толкает вовсе: иначе заталкивала бы лежащее
		# снаружи себе под днище, где его уже не видно.
		for part: PhysicalBone3D in ragdoll.parts.values():
			part.add_collision_exception_with(car)
	# Срез идёт до пола и тогда, когда частей под днищем уже нет: пятно
	# ложится, когда днище дошло до пола.
	var reach := ragdoll.bounds() if not ragdoll.parts.is_empty() else AABB()
	cut.advance(_figure, _holder.get_parent(), left, right, bottom, reach)
	# Дойдя до пола, днище забирает всё, что в створе, — и то, что кабина в
	# последний миг задвинула под себя.
	var under := PackedStringArray()
	for bone_name: String in ragdoll.parts:
		var center := Ragdoll.center_of(ragdoll.parts[bone_name] as PhysicalBone3D)
		if center.x > left and center.x < right and (cut.done or bottom < center.y):
			under.append(bone_name)
	ragdoll.remove(under)
	if ragdoll.parts.is_empty() and not gone:
		gone = true
		_holder.remove_from_group(GROUP)


## Части тела внутри кабины [param car], если оно лежит поперёк порога:
## часть снаружи, между высотами [param low] и [param high], лежит на чём-то
## неподвижном — на площадке. Свесившаяся над пустотой рука — не порог, и
## тело тогда не рвётся. Внутри — всё, что в кабине по всей её высоте до
## [param roof]: поднятая рука, оставшись у тела, утянула бы его за кабиной.
## Пусто, если рвать нечего.
func across(car: ElevatorCar, low: float, high: float, roof: float) -> PackedStringArray:
	var left := car.global_position.x - car.width() * 0.5
	var right := car.global_position.x + car.width() * 0.5
	var inside := PackedStringArray()
	var landed := false
	for bone_name: String in ragdoll.parts:
		var part := ragdoll.parts[bone_name] as PhysicalBone3D
		var center := Ragdoll.center_of(part)
		if center.x > left and center.x < right:
			if center.y >= low and center.y <= roof:
				inside.append(bone_name)
		elif not landed and center.y >= low and center.y <= high:
			landed = _rests_on_ground(part, car)
	if not landed:
		return PackedStringArray()
	# Стопа там же, где её голень: одна она осталась бы на пороге обрубком.
	for foot: String in Ragdoll.ANKLES:
		var leg := String(Ragdoll.ANKLES[foot])
		if inside.has(leg) != inside.has(foot) and ragdoll.parts.has(foot):
			if inside.has(leg):
				inside.append(foot)
			else:
				inside.remove_at(inside.find(foot))
	return inside


## Лежит ли часть [param part] на неподвижном — не на кабине [param car].
func _rests_on_ground(part: PhysicalBone3D, car: ElevatorCar) -> bool:
	var shape := part.get_child(0) as CollisionShape3D
	var reach := (shape.shape as CapsuleShape3D).radius + 0.1
	var from := Ragdoll.center_of(part)
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3(0.0, reach, 0.0), GEOMETRY_MASK
	)
	query.exclude = [car.get_rid()]
	return not part.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Рвёт тело стенкой кабины [param car]: части [param inside] уезжают с ней
## отдельным куском, остальные лежат где лежали (решение 11).
func tear(car: ElevatorCar, inside: PackedStringArray) -> void:
	torn = true
	var host := _holder.get_parent()
	var box := ragdoll.bounds()
	CorpsePiece.tear_off(self, _figure, host, inside)
	ragdoll.remove(inside)
	var middle := car.global_position.x
	var side := 1.0 if box.get_center().x < middle else -1.0
	var wall := middle - side * car.width() * 0.5
	Corpse.bleed(host, Vector3(wall, box.position.y, WorldSpace.PLAY_Z), side)


## Брызги и лужица у стенки, по которой порвалось тело; [param inside] —
## в какую сторону от стенки кабина.
static func bleed(host: Node, at: Vector3, inside: float) -> void:
	var spot := at + Vector3(0.0, Proportions.PRONE, 0.0)
	Blood.spray(host, spot, inside)
	Blood.spray(host, spot, -inside)
	Blood.puddle(host, at - Vector3(inside * TEAR_PUDDLE * 0.5, 0.0, 0.0), TEAR_PUDDLE)
