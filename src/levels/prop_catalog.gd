class_name PropCatalog
extends RefCounted

## Каталог моделей обстановки (ADR-0033, решение 3).
##
## Модели паков лежат в `assets/models/props/` как пришли: у каждой свой рост и
## свой фасад. Запись каталога приводит модель к игре — рост в метрах, поворот
## лицом к камере, где она висит и в каком здании уместна. Рост ставится при
## сборке по габариту модели, а не числом масштаба: переснятый пак с другими
## единицами не разойдётся с игрой.
##
## Авторство — в `assets/models/props/credits.json` и `CREDITS.md`; тест сверяет,
## что у каждой записи оно есть.

## Где предмет: стоит на полу у стены, висит на стене, стоит на крыше, стоит
## только поверх другого (лампа на комоде — в жребий сама не идёт).
enum Place { FLOOR, WALL, ROOF, TOP }

## Для какого здания: отель, офис, любое.
enum Fit { HOTEL, OFFICE, ANY }

const DIR := "res://assets/models/props"

## Мебель стоит в стольких метрах от задней стены: перед пилястрами
## ([constant BuildingRibs.PILASTER_DEPTH]) и панелью, с зазором. Так широкий
## диван проходит перед пилястрой, а не сквозь неё.
const FLOOR_OFFSET: float = 0.24

## Глубже этого мебель не бывает, м: от [constant FLOOR_OFFSET] до тела актёра,
## которое начинается в 0.2 м от плоскости игры. Модель глубже сжимается по
## глубине, как машина у выхода (ADR-0032): сбоку этого не видно.
const MAX_DEPTH: float = 0.54

## Предмет на стене не шире этого, м: висит между пилястрами. Шире —
## уменьшается целиком, а не сплющивается.
const WALL_MAX_WIDTH: float = 0.7

## На какой высоте середина предмета на стене, м, если запись не говорит иного.
const WALL_CENTRE: float = 1.65


## Запись каталога.
class Entry:
	extends RefCounted

	var name: String
	var place: Place = Place.FLOOR
	var fit: Fit = Fit.ANY
	## Рост в метрах: модель приводится к нему одним масштабом.
	var height: float = 1.0
	## Поворот вокруг вертикали, градусы: фасад модели — к камере (+Z).
	var yaw: float = 0.0
	## Наклон вокруг X, градусы: картина, пришедшая плашмя, встаёт на стену.
	var pitch: float = 0.0
	## Что стоит сверху: лампа на столике, на комоде.
	var top: String = ""
	## Середина предмета на стене над полом, м.
	var centre: float = WALL_CENTRE

	static func of(
		prop_name: String, where: Place, which: Fit, tall: float, turn: float = 0.0
	) -> Entry:
		var entry := Entry.new()
		entry.name = prop_name
		entry.place = where
		entry.fit = which
		entry.height = tall
		entry.yaw = turn
		return entry

	## Наклон вокруг X. Возвращает себя: записи собираются цепочкой.
	func tilted(degrees: float) -> Entry:
		pitch = degrees
		return self

	## Что поставить сверху.
	func topped(with_prop: String) -> Entry:
		top = with_prop
		return self

	## Висит выше или ниже обычного.
	func raised(middle: float) -> Entry:
		centre = middle
		return self


static var _entries: Dictionary = _build()
## Габариты собранных предметов по имени: жребий раскладки спрашивает их на
## каждом месте, а модель грузится один раз.
static var _footprints: Dictionary = {}


## Все записи каталога.
static func entries() -> Array[Entry]:
	var all: Array[Entry] = []
	for entry: Entry in _entries.values():
		all.append(entry)
	return all


## Запись по имени или null.
static func entry(prop_name: String) -> Entry:
	return _entries.get(prop_name) as Entry


## Записи для места и здания.
static func pick(where: Place, which: Fit) -> Array[Entry]:
	var found: Array[Entry] = []
	for item: Entry in _entries.values():
		if item.place == where and (item.fit == which or item.fit == Fit.ANY):
			found.append(item)
	found.sort_custom(func(a: Entry, b: Entry) -> bool: return a.name < b.name)
	return found


## Собирает предмет: модель, повёрнутая к камере и приведённая к росту, нуль —
## посередине низа по ширине и у задней грани по глубине. Так предмет ставится
## к стене одним сдвигом, какой бы глубины ни был. Узел без тел.
static func make(prop_name: String) -> Node3D:
	var item := entry(prop_name)
	var path := "%s/%s.glb" % [DIR, prop_name]
	if not ResourceLoader.exists(path):
		push_error("нет модели обстановки: %s" % path)
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	# Поворот — отдельным узлом над моделью: габарит считается уже повёрнутым.
	var turned := Node3D.new()
	turned.add_child(model)
	if item != null:
		turned.rotation = Vector3(deg_to_rad(item.pitch), deg_to_rad(item.yaw), 0.0)
	var box := PropCatalog.bounds_of_turned(turned)
	var height := item.height if item != null else box.size.y
	var factor := height / maxf(box.size.y, 0.001)
	if item != null and item.place == Place.WALL:
		factor = minf(factor, WALL_MAX_WIDTH / maxf(box.size.x, 0.001))
		height = box.size.y * factor
	var squeeze := minf(1.0, MAX_DEPTH / maxf(box.size.z * factor, 0.001))
	if item != null and item.place == Place.ROOF:
		squeeze = 1.0
	var sized := Node3D.new()
	sized.add_child(turned)
	sized.scale = Vector3(factor, factor, factor * squeeze)
	var centre := box.get_center()
	sized.position = Vector3(
		-centre.x * factor, -box.position.y * factor, -box.position.z * factor * squeeze
	)
	var holder := Node3D.new()
	holder.name = prop_name
	holder.add_child(sized)
	if item != null and not item.top.is_empty():
		var on_top := make(item.top)
		if on_top != null:
			# Сверху, по середине глубины низа: лампа стоит на столешнице, а не
			# на её заднем крае.
			var depth := box.size.z * factor * squeeze
			var top_depth := bounds_of(on_top).size.z
			on_top.position = Vector3(0.0, height, (depth - top_depth) * 0.5)
			holder.add_child(on_top)
	return holder


## Габарит собранного предмета, м: ширина, рост, глубина — с лампой сверху.
static func footprint(prop_name: String) -> Vector3:
	if not _footprints.has(prop_name):
		var built := make(prop_name)
		_footprints[prop_name] = bounds_of(built).size if built != null else Vector3.ZERO
		if built != null:
			built.free()
	return _footprints[prop_name]


## Габарит узла с учётом его собственного поворота — как он стоит у родителя.
static func bounds_of_turned(node: Node3D) -> AABB:
	var wrapper_box := AABB()
	var first := true
	for child in node.get_children():
		var inner := child as Node3D
		if inner == null:
			continue
		var part := node.transform * (inner.transform * bounds_of(inner))
		wrapper_box = part if first else wrapper_box.merge(part)
		first = false
	return wrapper_box


## Габарит всех мешей узла в его собственной системе. Узел может быть ещё не в
## дереве: преобразования складываются вручную, а не через global_transform.
static func bounds_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var current := pair[0] as Node3D
		var placed := pair[1] as Transform3D
		var mesh := current as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var part := placed * mesh.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		for child in current.get_children():
			var node_3d := child as Node3D
			if node_3d != null:
				stack.append([node_3d, placed * node_3d.transform])
	return box


## Каталог. Рост — в метрах, как в жизни рядом с Otto в 1.68; поворот — по
## кадру `tools/props_shot.tscn -- --raw`: какие модели пришли боком, спиной
## или плашмя.
static func _build() -> Dictionary:
	var list: Array[Entry] = [
		# Пол, любое здание.
		Entry.of("houseplant_a", Place.FLOOR, Fit.ANY, 0.9),
		Entry.of("houseplant_b", Place.FLOOR, Fit.ANY, 1.0),
		Entry.of("houseplant_c", Place.FLOOR, Fit.ANY, 1.3),
		Entry.of("potted_plant", Place.FLOOR, Fit.ANY, 0.8),
		Entry.of("coat_rack", Place.FLOOR, Fit.ANY, 1.75),
		Entry.of("trashcan", Place.FLOOR, Fit.ANY, 0.6),
		Entry.of("vending_machine", Place.FLOOR, Fit.ANY, 1.85),
		Entry.of("fire_extinguisher", Place.FLOOR, Fit.ANY, 0.6),
		# Пол, отель: гостиная у лифтов, а не склад.
		Entry.of("couch_medium", Place.FLOOR, Fit.HOTEL, 0.8),
		Entry.of("armchair", Place.FLOOR, Fit.HOTEL, 0.9),
		Entry.of("floor_lamp", Place.FLOOR, Fit.HOTEL, 1.6),
		Entry.of("grandfather_clock", Place.FLOOR, Fit.HOTEL, 2.0),
		Entry.of("dresser", Place.FLOOR, Fit.HOTEL, 0.8).topped("table_lamp"),
		Entry.of("end_table", Place.FLOOR, Fit.HOTEL, 0.6).topped("table_lamp"),
		Entry.of("cabinet", Place.FLOOR, Fit.HOTEL, 0.9),
		Entry.of("table_lamp", Place.TOP, Fit.HOTEL, 0.5),
		# Пол, офис.
		Entry.of("water_cooler", Place.FLOOR, Fit.OFFICE, 1.2),
		Entry.of("file_cabinet", Place.FLOOR, Fit.OFFICE, 1.3, -90.0),
		Entry.of("copier", Place.FLOOR, Fit.OFFICE, 1.2),
		Entry.of("cardboard_boxes", Place.FLOOR, Fit.OFFICE, 1.0),
		Entry.of("bins", Place.FLOOR, Fit.OFFICE, 0.9),
		Entry.of("bookshelf", Place.FLOOR, Fit.OFFICE, 1.6),
		# Стены: картины — везде, остальное — по зданию. Wall Art пришли
		# спиной к камере, Painting — плашмя.
		Entry.of("painting", Place.WALL, Fit.ANY, 0.6).tilted(90.0),
		Entry.of("wall_art_02", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_03", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_05", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("wall_art_06", Place.WALL, Fit.ANY, 0.9, 180.0),
		Entry.of("analog_clock", Place.WALL, Fit.OFFICE, 0.4, -90.0),
		Entry.of("whiteboard", Place.WALL, Fit.OFFICE, 0.9),
		Entry.of("message_board", Place.WALL, Fit.OFFICE, 0.9, -90.0),
		Entry.of("corkboard", Place.WALL, Fit.OFFICE, 0.7),
		Entry.of("calendar", Place.WALL, Fit.OFFICE, 0.45),
		Entry.of("vent", Place.WALL, Fit.OFFICE, 0.35),
		Entry.of("air_vent", Place.WALL, Fit.OFFICE, 0.45, 90.0),
		Entry.of("fire_exit_sign", Place.WALL, Fit.ANY, 0.3, -90.0).raised(2.35),
		# Крыша (ADR-0033, решение 8).
		Entry.of("water_tower", Place.ROOF, Fit.ANY, 4.5),
		Entry.of("water_tank", Place.ROOF, Fit.ANY, 2.5),
		Entry.of("air_conditioner", Place.ROOF, Fit.ANY, 0.9),
		Entry.of("antenna", Place.ROOF, Fit.ANY, 0.9),
		Entry.of("antenna_small", Place.ROOF, Fit.ANY, 2.5),
		Entry.of("roof_antenna", Place.ROOF, Fit.ANY, 3.5),
		Entry.of("satellite_dish", Place.ROOF, Fit.ANY, 1.0),
		Entry.of("solar_panel", Place.ROOF, Fit.ANY, 1.4),
		Entry.of("roof_exit", Place.ROOF, Fit.ANY, 2.3),
	]
	var table := {}
	for item in list:
		table[item.name] = item
	return table
