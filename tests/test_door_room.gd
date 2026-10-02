extends GutTest

## Комната за дверью (ADR-0047, ADR-0055): номер отеля, кабинет офиса или
## квартира.
##
## Комната — жребий двери, поэтому проверяется не одна удачная, а любая: на
## сотне жребиев каждого типа главный предмет стоит в створе двери и виден в
## проём, мебель не заходит туда, где ходит створка, и ничто не торчит из
## комнаты. Дверь собирает комнату, когда створка трогается, и убирает, когда
## та закрылась.

const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")

## Сколько жребиев проверять на каждый тип комнаты.
const DRAWS: int = 100
## Главный предмет — в створе двери: его середина не дальше этого от середины
## проёма, м. Проём — [constant Door.LEAF_SIZE] в ширину.
const HERO_REACH: float = Door.LEAF_SIZE.x * 0.5
## Сколько кадров ждать, пока створка откроется и закроется.
const PATIENCE: int = 240

## Главные предметы: кровать — в номере и спальне, стол или рабочее место — в
## кабинете, мойка — на кухне, диван — в гостиной.
const HEROES: PackedStringArray = [
	"bed_hotel", "bed_double", "desk", "workstation_a", "workstation_b", "counter_sink", "sofa"
]


func _room(kind: BuildingIdentity.Kind, seed: int) -> DoorRoom:
	var room := DoorRoom.build(kind, seed)
	add_child_autofree(room)
	return room


func test_the_main_piece_stands_in_the_doorway() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS:
			var room := _room(kind, seed)
			var heroes := room.placed.filter(
				func(item: Dictionary) -> bool: return HEROES.has(item["prop"])
			)
			assert_eq(heroes.size(), 1, "жребий %d: один главный предмет" % seed)
			if heroes.is_empty():
				continue
			var hero: Dictionary = heroes[0]
			assert_lte(
				absf(float(hero["x"])),
				HERO_REACH,
				"жребий %d: %s в створе двери" % [seed, hero["prop"]]
			)


func test_furniture_keeps_clear_of_the_swinging_leaf() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS:
			var room := _room(kind, seed)
			for item: Dictionary in room.placed:
				var size: Vector3 = item["size"]
				var reach := float(item["from_wall"]) + size.z
				assert_lte(
					reach,
					DoorRoom.DEPTH - DoorRoom.LEAF_CLEAR + 0.01,
					"жребий %d: %s не заходит под створку" % [seed, item["prop"]]
				)


func test_the_room_holds_its_furniture_inside() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS / 4:
			var room := _room(kind, seed)
			var box := PropCatalog.bounds_of(room)
			assert_gte(box.position.y, -0.01, "жребий %d: ничего под полом" % seed)
			assert_lte(box.end.y, DoorRoom.HEIGHT + 0.01, "жребий %d: ничего над потолком" % seed)
			assert_gte(
				box.position.z,
				DoorRoom.back_z() - DoorRoom.WALL - 0.01,
				"жребий %d: за стеной ничего" % seed
			)
			assert_lte(
				box.end.z, WorldSpace.BACK_WALL_Z + 0.01, "жребий %d: в коридор не торчит" % seed
			)


## Мебель не уходит за боковые стены комнаты: у квартиры ряд из трёх предметов
## шире половины комнаты, и без упора холодильник и торшер вылезали за стену
## (кадры M24m). Повёрнутый телевизор шире своего габарита — допуск на него.
func test_furniture_stays_between_the_side_walls() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS:
			var room := _room(kind, seed)
			var shell := _shell_of(room)
			for item: Dictionary in room.placed:
				var half := (item["size"] as Vector3).x * 0.5
				var x := float(item["x"])
				var where := "тип %d, жребий %d: %s" % [kind, seed, item["prop"]]
				assert_gte(x - half, shell.position.x - 0.12, where + " за левой стеной")
				assert_lte(x + half, shell.end.x + 0.12, where + " за правой стеной")


## Телевизор гостиной повёрнут к дивану, а не в боковую стену, и повёрнутый не
## входит в диван передним углом. У предмета каталога лицо — к камере, и
## поворот на +угол уводит его к +X (авторевью M24m: экран смотрел в стену).
func test_the_tv_faces_the_sofa() -> void:
	var seen := 0
	for seed: int in DRAWS:
		var room := _room(BuildingIdentity.Kind.RESIDENTIAL, seed)
		if room.home != DoorRoom.Home.LIVING:
			continue
		var tv := _placed(room, "tv_old")
		var sofa := _placed(room, "sofa")
		assert_false(tv.is_empty() or sofa.is_empty(), "жребий %d: телевизор и диван" % seed)
		if tv.is_empty() or sofa.is_empty():
			continue
		seen += 1
		var apart := float(sofa["x"]) - float(tv["x"])
		var yaw := float(tv["yaw"])
		assert_eq(signf(yaw), signf(apart), "жребий %d: экран к дивану" % seed)
		var size: Vector3 = tv["size"]
		var turn := deg_to_rad(absf(yaw))
		var corner := size.x * 0.5 * cos(turn) + size.z * sin(turn)
		var sofa_edge := absf(apart) - (sofa["size"] as Vector3).x * 0.5
		assert_gte(sofa_edge, corner, "жребий %d: угол телевизора не в диване" % seed)
	assert_gt(seen, 0, "гостиные выпадали")


## Тумбы спальни — вплотную к кровати. Ряд меряет кровать такой, какой она
## встаёт: двуспальная ужимается по глубине на четверть, и по габариту каталога
## тумбы отходили от неё на сорок сантиметров (авторевью M24m).
func test_the_night_stands_flank_the_bed() -> void:
	var seen := 0
	for seed: int in DRAWS:
		var room := _room(BuildingIdentity.Kind.RESIDENTIAL, seed)
		if room.home != DoorRoom.Home.BEDROOM:
			continue
		var bed := _placed(room, "bed_double")
		assert_false(bed.is_empty(), "жребий %d: кровать" % seed)
		if bed.is_empty():
			continue
		seen += 1
		var bed_half := (bed["size"] as Vector3).x * 0.5
		for stand_name: String in ["night_stand", "night_stand_b"]:
			var stand := _placed(room, stand_name)
			if stand.is_empty():
				continue
			var stand_half := (stand["size"] as Vector3).x * 0.5
			var gap := absf(float(stand["x"]) - float(bed["x"])) - bed_half - stand_half
			assert_between(gap, -0.01, 0.2, "жребий %d: %s у кровати" % [seed, stand_name])
	assert_gt(seen, 0, "спальни выпадали")


## Что поставлено в комнату под именем [param prop]; пусто — если нет.
func _placed(room: DoorRoom, prop: String) -> Dictionary:
	for item: Dictionary in room.placed:
		if item["prop"] == prop:
			return item
	return {}


## Оболочка комнаты — её коробки: пол, потолок и стены.
func _shell_of(room: DoorRoom) -> AABB:
	var shell := AABB()
	var first := true
	for child: Node in room.get_children():
		var box := child as MeshInstance3D
		if box == null or not (box.mesh is BoxMesh):
			continue
		var part := box.transform * box.mesh.get_aabb()
		shell = part if first else shell.merge(part)
		first = false
	return shell


## У крайнего места этажа до наружной стены меньше, чем комната со сдвигом
## уходит от проёма: комната упирается в стену и из силуэта здания не торчит
## (авторевью M24i). Мебель стоит от проёма, а не от стен, — меряется сама
## комната, её оболочка.
func test_a_room_at_the_end_of_the_floor_stays_inside_the_building() -> void:
	var margin := BuildingRules.new().margin
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS / 4:
			for side: float in [-1.0, 1.0]:
				var span := Vector2(-margin, 20.0) if side < 0.0 else Vector2(-20.0, margin)
				var room := DoorRoom.build(kind, seed, null, span)
				autofree(room)
				var shell := AABB()
				var first := true
				for child: Node in room.get_children():
					var box := child as MeshInstance3D
					if box == null or not (box.mesh is BoxMesh):
						continue
					var part := box.transform * box.mesh.get_aabb()
					shell = part if first else shell.merge(part)
					first = false
				assert_gte(shell.position.x, span.x - 0.001, "жребий %d: за левую стену нет" % seed)
				assert_lte(shell.end.x, span.y + 0.001, "жребий %d: за правую стену нет" % seed)


func test_every_room_has_its_light_and_window() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var room := _room(kind, 7)
		assert_not_null(room.find_child("RoomLight", true, false), "свет комнаты")
		assert_not_null(room.find_child("Window", true, false), "окно на город")
		var light := room.find_child("RoomLight", true, false) as OmniLight3D
		assert_false(light.shadow_enabled, "свет комнаты без тени — в бюджете кадра")


## Дверь собирает комнату, когда створка трогается, и убирает, когда закрылась.
## Без [method Door.furnish] — как в тестах двери — за ней по-прежнему темно.
func test_the_door_builds_its_room_only_while_open() -> void:
	var ground := StaticBody3D.new()
	add_child_autofree(ground)
	var door := DOOR_SCENE.instantiate() as Door
	door.furnish(BuildingIdentity.new(), 11)
	add_child_autofree(door)
	await wait_physics_frames(2)
	assert_null(door.room(), "закрытая дверь — без комнаты")
	assert_true(door.summon_agent(), "дверь открывается под агента")
	var opened := false
	for _frame: int in PATIENCE:
		await wait_physics_frames(1)
		if door.openness() > 0.0 and door.room() != null:
			opened = true
			break
	assert_true(opened, "в открытую дверь видна комната")
	door.dismiss_agent()
	var closed := false
	for _frame: int in PATIENCE:
		await wait_physics_frames(1)
		if door.openness() <= 0.0:
			await wait_physics_frames(1)
			closed = door.room() == null
			break
	assert_true(closed, "закрылась — комнаты нет")


func test_a_bare_door_stays_dark() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	add_child_autofree(door)
	assert_true(door.summon_agent())
	for _frame: int in 30:
		await wait_physics_frames(1)
	assert_gt(door.openness(), 0.0)
	assert_null(door.room(), "без здания комнаты нет")


## На тёмном этаже комната без своего света: светится только окно с городом
## (решение пользователя, M24i).
func test_a_room_on_a_dark_floor_keeps_the_dark() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var room := DoorRoom.build(kind, 5, null, Vector2(-INF, INF), true)
		add_child_autofree(room)
		assert_eq(room.find_children("*", "Light3D", true, false).size(), 0, "своего света нет")
		assert_not_null(room.find_child("Window", true, false), "окно на город есть")
