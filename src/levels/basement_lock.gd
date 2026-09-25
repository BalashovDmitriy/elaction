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

## Вид створок: тяжёлая сталь, а не пол. Серые створки в цвет отделки читались
## плиткой пола вровень с ним (кадр `basement_01_locked`), и запертой шахты
## было не видно. Теперь — тёмные стальные плиты с рёбрами, по кромке
## жёлто-чёрная «зебра», шов посередине и красные огоньки, пока заперто.
const STEEL := Color(0.15, 0.16, 0.18)
const RIB := Color(0.1, 0.105, 0.12)
const HAZARD_YELLOW := Color(0.95, 0.7, 0.08)
const HAZARD_BLACK := Color(0.04, 0.04, 0.045)
const LAMP_RED := Color(1.0, 0.12, 0.08)
## Зебра: шаг полос в мире, м, полоса на лицевой кромке сверху и снизу, м, и
## полоса по краю верха створок, м. Верх с камеры — узкая полоса: кромка у
## плоскости игры видна всегда.
const HAZARD_PITCH: float = 0.34
const HAZARD_TOP: float = 0.17
const HAZARD_BOTTOM: float = 0.09
const HAZARD_EDGE: float = 0.3
## Зазор шва между створками и рёбра на лице: сколько на створку, сечение, м.
const SEAM: float = 0.03
const RIBS: int = 2
const RIB_SIZE := Vector2(0.06, 0.025)
## Огонёк замка на лице у каждого края проёма: размер, м. Эмиссия, не источник.
const LAMP_SIZE := Vector3(0.1, 0.07, 0.03)
## Насколько светится зебра сама: читается и на погашенном этаже.
const HAZARD_GLOW: float = 0.35
## Сторона картинки зебры, текселей: полоса — половина периода по диагонали.
const HAZARD_TEXELS: int = 32

## Материал зебры один на все здания: картинка полос собирается кодом раз.
static var _hazard: StandardMaterial3D = null

var _cars: Array[ElevatorCar] = []
var _hatches: Array[StaticBody3D] = []
var _lamps: Array[MeshInstance3D] = []
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
	for lamp in _lamps:
		if is_instance_valid(lamp):
			lamp.visible = false
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
			# Огоньки висят на теле рядом со створками и остаются на месте.
			if part == null or _lamps.has(part):
				continue
			# Каждая створка уходит в свою сторону, в толщу перекрытия.
			var aside := part.position.x * 3.0
			tween.tween_property(part, "position:x", aside, OPEN_TIME)
	tween.chain().tween_callback(_drop_hatches)


## Створки на месте прямоугольника правил: тело во всю глубину перекрытия, как у
## плит оболочки, и две стальные створки поверх — они и расходятся. На лице
## створок — зебра по кромкам и рёбра, по краям проёма — красные огоньки.
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
	var width := half - SEAM * 0.5
	var height := rect.size.y - LID_SINK
	for side: float in [-1.0, 1.0]:
		var leaf := GreyboxLook.box(Vector3(width, height, depth), GreyboxLook.metal(STEEL))
		leaf.name = "Leaf"
		leaf.position = Vector3(side * (half + SEAM * 0.5) * 0.5, -LID_SINK * 0.5, 0.0)
		body.add_child(leaf)
		_dress_leaf(leaf, width, height, depth)
	# Огоньки — на теле, не на створках: створки уходят, огоньки гаснут на месте.
	for side: float in [-1.0, 1.0]:
		var lamp := GreyboxLook.box(LAMP_SIZE, GreyboxLook.light(LAMP_RED))
		lamp.name = "LockLamp"
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(
			side * (half - LAMP_SIZE.x * 0.5 - 0.06), 0.0, depth * 0.5 + LAMP_SIZE.z * 0.5 + 0.004
		)
		body.add_child(lamp)
		_lamps.append(lamp)
	add_child(body)
	return body


## Лицо створки: зебра по верхней и нижней кромке и по краю верха, рёбра между
## ними. Всё — детьми створки: уходит в перекрытие вместе с ней.
func _dress_leaf(leaf: MeshInstance3D, width: float, height: float, depth: float) -> void:
	var front := depth * 0.5 + 0.004
	var top := height * 0.5
	var bands: Array[Vector2] = [
		Vector2(top - HAZARD_TOP * 0.5, HAZARD_TOP),
		Vector2(-top + HAZARD_BOTTOM * 0.5, HAZARD_BOTTOM)
	]
	for band in bands:
		var strip := GreyboxLook.box(Vector3(width, band.y, 0.008), hazard_material())
		strip.name = "Hazard"
		strip.position = Vector3(0.0, band.x, front)
		leaf.add_child(strip)
	# Край верха у плоскости игры — та полоса верха, которую камера видит.
	var edge := GreyboxLook.box(Vector3(width, 0.008, HAZARD_EDGE), hazard_material())
	edge.name = "HazardEdge"
	edge.position = Vector3(0.0, top + 0.002, depth * 0.5 - HAZARD_EDGE * 0.5)
	leaf.add_child(edge)
	var middle := (HAZARD_BOTTOM - HAZARD_TOP) * 0.5
	var rib_height := height - HAZARD_TOP - HAZARD_BOTTOM
	for index in RIBS:
		var rib := GreyboxLook.box(
			Vector3(RIB_SIZE.x, rib_height, RIB_SIZE.y), GreyboxLook.metal(RIB)
		)
		rib.name = "Rib"
		rib.position = Vector3(
			width * (float(index + 1) / float(RIBS + 1) - 0.5), middle, front + RIB_SIZE.y * 0.5
		)
		leaf.add_child(rib)


## Жёлто-чёрная зебра: полосы наискось по мировым координатам, чтобы шли
## ровно через все створки и грани, и чуть светятся сами.
static func hazard_material() -> StandardMaterial3D:
	if _hazard != null:
		return _hazard
	var image := Image.create(HAZARD_TEXELS, HAZARD_TEXELS, false, Image.FORMAT_RGBA8)
	for y in HAZARD_TEXELS:
		for x in HAZARD_TEXELS:
			var yellow := (x + y) % HAZARD_TEXELS * 2 < HAZARD_TEXELS
			image.set_pixel(x, y, HAZARD_YELLOW if yellow else HAZARD_BLACK)
	var texture := ImageTexture.create_from_image(image)
	_hazard = StandardMaterial3D.new()
	_hazard.albedo_texture = texture
	_hazard.roughness = 0.7
	_hazard.uv1_triplanar = true
	_hazard.uv1_world_triplanar = true
	_hazard.uv1_scale = Vector3.ONE / HAZARD_PITCH
	_hazard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hazard.emission_enabled = true
	_hazard.emission_texture = texture
	_hazard.emission_energy_multiplier = HAZARD_GLOW
	return _hazard


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
	# «Ноль из нуля» — не последний документ, а сброс партии: запертое здание
	# документы имеет всегда ([method setup]). Новая партия с паузы сбрасывает
	# счёт, пока старое здание ещё в дереве, — и замок открывался бы под снос.
	if total > 0 and collected >= total:
		unlock()
