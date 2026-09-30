extends GutTest

## Комната за дверью (ADR-0047): номер отеля или кабинет офиса.
##
## Комната — жребий двери, поэтому проверяется не одна удачная, а любая: на
## сотне жребиев обоих типов главный предмет стоит в створе двери и виден в
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

## Главные предметы: кровать — в номере, стол или рабочее место — в кабинете.
const HEROES: PackedStringArray = [
	"bed_hotel", "bed_double", "desk", "workstation_a", "workstation_b"
]


func _room(is_hotel: bool, seed: int) -> DoorRoom:
	var room := DoorRoom.build(is_hotel, seed)
	add_child_autofree(room)
	return room


func test_the_main_piece_stands_in_the_doorway() -> void:
	for is_hotel: bool in [true, false]:
		for seed: int in DRAWS:
			var room := _room(is_hotel, seed)
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
	for is_hotel: bool in [true, false]:
		for seed: int in DRAWS:
			var room := _room(is_hotel, seed)
			for item: Dictionary in room.placed:
				var size: Vector3 = item["size"]
				var reach := float(item["from_wall"]) + size.z
				assert_lte(
					reach,
					DoorRoom.DEPTH - DoorRoom.LEAF_CLEAR + 0.01,
					"жребий %d: %s не заходит под створку" % [seed, item["prop"]]
				)


func test_the_room_holds_its_furniture_inside() -> void:
	for is_hotel: bool in [true, false]:
		for seed: int in DRAWS / 4:
			var room := _room(is_hotel, seed)
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


func test_every_room_has_its_light_and_window() -> void:
	for is_hotel: bool in [true, false]:
		var room := _room(is_hotel, 7)
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
