class_name BasementLock
extends Node3D

## Подвал заперт, пока не собраны все документы (M24b, решение пользователя).
##
## В ROM без документов Otto доезжает до подвала, и его возвращают наверх
## (@09B5–0A69). У нас раньше: шахта в подвал закрыта, и пройти туда нельзя
## никак. Кабина встаёт этажом выше и ниже не идёт — ни с пассажиром, ни сама
## ([member ElevatorMotion.bottom_locked]); проём шахты в перекрытии над
## подвалом закрыт створками вровень с полом — телом для всех: Otto, агентов,
## падающего. Иначе туда спрыгивали бы с этажа выше: падение на этаж не убивает.
##
## Последний документ открывает подвал сам: створки расходятся в перекрытие со
## звуком, и нижняя остановка снова доступна. Текстом об этом не говорится.
##
## Дверей в подвале нет ([method BuildingRules.doors_on]), поэтому запертый
## подвал ничего не отрезает: всё, за чем Otto идёт до выхода, — выше.

## Насколько вид створок ниже их тела, м. Тело — вровень с полом, иначе у края
## кабины вырос бы порожек; а вид вровень с полом кабины мерцал бы с ним,
## когда кабина стоит над створками.
const LID_SINK: float = 0.005
## За сколько створки расходятся, с.
const OPEN_TIME: float = 0.6
## Звук створок — зуммер лифта, на месте шахты; докуда слышно, м.
const OPEN_SOUND := Sounds.BASEMENT_OPEN
const SOUND_REACH: float = 24.0

var _cars: Array[ElevatorCar] = []
var _hatches: Array[StaticBody3D] = []
var _locked: bool = false


## Проёмы над подвалом прямоугольниками правил: по одному на каждую шахту,
## которая доходит до подвала, — в перекрытии этажа над ним, где шахта его
## прорезала.
static func hatches(rules: BuildingRules, plan: BuildingPlan) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var bottom := rules.floors - 1
	var above := bottom - 1
	if above <= BuildingRules.ROOF:
		return found
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.bottom == bottom and shaft.top <= above:
			found.append(
				Rect2(
					shaft.x - half, rules.floor_surface(above), rules.shaft_width, rules.slab_height
				)
			)
	return found


## Запирает подвал, если документы ещё не собраны, и открывает его с последним.
##
## [param cars] — все кабины здания: запираются те, что спускаются в подвал
## ([method ElevatorCar.bottom_reach]). Ярусы пар пропускаются — их запирает
## ведущий.
func setup(rules: BuildingRules, plan: BuildingPlan, cars: Array[ElevatorCar]) -> void:
	name = "BasementLock"
	var game := GameState.instance()
	if game.all_documents_collected():
		return
	var basement := rules.floor_surface(rules.floors - 1)
	for car in cars:
		if car.is_deck() or not is_equal_approx(car.bottom_reach(), basement):
			continue
		car.lock_bottom_stop(true)
		_cars.append(car)
	for rect in hatches(rules, plan):
		_hatches.append(_build_hatch(rect))
	_locked = true
	game.documents_changed.connect(_on_documents_changed)


## Заперт ли подвал прямо сейчас.
func is_locked() -> bool:
	return _locked


## Сколько створок ещё закрывает шахты: тела, по которым ходят.
func closed_hatches() -> int:
	var closed := 0
	for hatch in _hatches:
		if is_instance_valid(hatch) and hatch.collision_layer != 0:
			closed += 1
	return closed


## Открывает подвал: кабины спускаются до дна, створки расходятся.
##
## Тело уходит сразу, вид — за [constant OPEN_TIME]: стоявший на створках
## проваливается вместе с ними, а не висит над открытым проёмом.
func unlock() -> void:
	if not _locked:
		return
	_locked = false
	for car in _cars:
		if is_instance_valid(car):
			car.lock_bottom_stop(false)
	if _hatches.is_empty():
		return
	# Источник — на узле замка, а не на створках: створки убираются раньше,
	# чем зуммер доиграет.
	var buzzer := Sounds.source(self, OPEN_SOUND, SOUND_REACH)
	buzzer.position = _hatches[0].position
	buzzer.finished.connect(buzzer.queue_free)
	buzzer.play()
	var tween := create_tween().set_parallel()
	for hatch in _hatches:
		hatch.collision_layer = 0
		hatch.collision_mask = 0
		for leaf in hatch.get_children():
			var part := leaf as MeshInstance3D
			if part == null:
				continue
			# Каждая створка уходит в свою сторону, в толщу перекрытия.
			var aside := part.position.x * 3.0
			tween.tween_property(part, "position:x", aside, OPEN_TIME)
	tween.chain().tween_callback(_drop_hatches)


## Створки на месте прямоугольника правил: тело во всю глубину перекрытия, как у
## плит оболочки, и две металлические створки поверх — они и расходятся.
func _build_hatch(rect: Rect2) -> StaticBody3D:
	var depth := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var body := StaticBody3D.new()
	body.name = "Hatch"
	body.position = WorldSpace.to_scene(rect.get_center())
	body.position.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5

	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x, rect.size.y, depth)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	var half := rect.size.x * 0.5
	for side: float in [-1.0, 1.0]:
		var leaf := GreyboxLook.box(
			Vector3(half, rect.size.y - LID_SINK, depth), GreyboxLook.metal(GreyboxLook.TRIM)
		)
		leaf.name = "Leaf"
		leaf.position = Vector3(side * half * 0.5, -LID_SINK * 0.5, 0.0)
		body.add_child(leaf)
	add_child(body)
	return body


func _drop_hatches() -> void:
	for hatch in _hatches:
		if is_instance_valid(hatch):
			hatch.queue_free()
	_hatches.clear()


func _on_documents_changed(collected: int, total: int) -> void:
	# Здание, вынутое из дерева, ещё слышит счёт: следующее здание сбрасывает
	# его на ноль из нуля, и замок прошлого открывался бы с зуммером в пустоту.
	if not is_inside_tree():
		return
	if collected >= total:
		unlock()
