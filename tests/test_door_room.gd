extends GutTest

## The room behind a door (ADR-0047, ADR-0055): a hotel room, an office or
## a flat.
##
## The room is the door's draw, so what is checked is not one lucky room but any: over
## a hundred draws of each kind the main item stands in line with the door and is seen through
## the opening, furniture does not go where the leaf swings, and nothing sticks out of
## the room. The door assembles the room when the leaf starts to move, and removes it when
## it has closed.

const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")

## How many draws to check per room kind.
const DRAWS: int = 100
## The main item is in line with the door: its middle is no further than this from the middle of the
## opening, m. The opening is [constant Door.LEAF_SIZE] wide.
const HERO_REACH: float = Door.LEAF_SIZE.x * 0.5
## How many frames to wait for the leaf to open and close.
const PATIENCE: int = 240

## Main items: the bed — in the hotel room and bedroom, the desk or workplace — in
## the office, the sink — in the kitchen, the sofa — in the living room.
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
			assert_eq(heroes.size(), 1, "roll %d: one main prop" % seed)
			if heroes.is_empty():
				continue
			var hero: Dictionary = heroes[0]
			assert_lte(
				absf(float(hero["x"])),
				HERO_REACH,
				"roll %d: %s in the door opening" % [seed, hero["prop"]]
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
					"roll %d: %s does not go under the leaf" % [seed, item["prop"]]
				)


func test_the_room_holds_its_furniture_inside() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS / 4:
			var room := _room(kind, seed)
			var box := PropCatalog.bounds_of(room)
			assert_gte(box.position.y, -0.01, "roll %d: nothing under the floor" % seed)
			assert_lte(
				box.end.y, DoorRoom.HEIGHT + 0.01, "roll %d: nothing above the ceiling" % seed
			)
			assert_gte(
				box.position.z,
				DoorRoom.back_z() - DoorRoom.WALL - 0.01,
				"roll %d: nothing beyond the wall" % seed
			)
			assert_lte(
				box.end.z,
				WorldSpace.BACK_WALL_Z + 0.01,
				"roll %d: nothing sticks out into the corridor" % seed
			)


## Furniture does not go past the room's side walls: in a flat a row of three items is
## wider than half the room, and without a stop the fridge and floor lamp went through the wall
## (M24m shots). A turned TV is wider than its extent — a tolerance for it.
func test_furniture_stays_between_the_side_walls() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for seed: int in DRAWS:
			var room := _room(kind, seed)
			var shell := _shell_of(room)
			for item: Dictionary in room.placed:
				var half := (item["size"] as Vector3).x * 0.5
				var x := float(item["x"])
				var where := "kind %d, roll %d: %s" % [kind, seed, item["prop"]]
				assert_gte(x - half, shell.position.x - 0.12, where + " past the left wall")
				assert_lte(x + half, shell.end.x + 0.12, where + " past the right wall")


## The living-room TV is turned toward the sofa, not into the side wall, and when turned it does not
## go into the sofa with its front corner. A catalogue item faces the camera, and
## rotating by +angle turns it toward +X (M24m code review: the screen faced the wall).
func test_the_tv_faces_the_sofa() -> void:
	var seen := 0
	for seed: int in DRAWS:
		var room := _room(BuildingIdentity.Kind.RESIDENTIAL, seed)
		if room.home != DoorRoom.Home.LIVING:
			continue
		var tv := _placed(room, "tv_old")
		var sofa := _placed(room, "sofa")
		assert_false(tv.is_empty() or sofa.is_empty(), "roll %d: TV and sofa" % seed)
		if tv.is_empty() or sofa.is_empty():
			continue
		seen += 1
		var apart := float(sofa["x"]) - float(tv["x"])
		var yaw := float(tv["yaw"])
		assert_eq(signf(yaw), signf(apart), "roll %d: screen faces the sofa" % seed)
		var size: Vector3 = tv["size"]
		var turn := deg_to_rad(absf(yaw))
		var corner := size.x * 0.5 * cos(turn) + size.z * sin(turn)
		var sofa_edge := absf(apart) - (sofa["size"] as Vector3).x * 0.5
		assert_gte(sofa_edge, corner, "roll %d: the TV corner is not inside the sofa" % seed)
	assert_gt(seen, 0, "living rooms came up")


## Bedroom nightstands are right against the bed. The row measures the bed as it
## stands: a double one is squashed in depth by a quarter, and by the catalogue extent
## the nightstands stood forty centimetres away from it (M24m code review).
func test_the_night_stands_flank_the_bed() -> void:
	var seen := 0
	for seed: int in DRAWS:
		var room := _room(BuildingIdentity.Kind.RESIDENTIAL, seed)
		if room.home != DoorRoom.Home.BEDROOM:
			continue
		var bed := _placed(room, "bed_double")
		assert_false(bed.is_empty(), "roll %d: bed" % seed)
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
			assert_between(gap, -0.01, 0.2, "roll %d: %s at the bed" % [seed, stand_name])
	assert_gt(seen, 0, "bedrooms came up")


## What was placed in the room under the name [param prop]; empty — if none.
func _placed(room: DoorRoom, prop: String) -> Dictionary:
	for item: Dictionary in room.placed:
		if item["prop"] == prop:
			return item
	return {}


## The room shell — its boxes: floor, ceiling and walls.
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


## At the outermost slot of a floor there is less room to the outer wall than the shifted room
## extends from the opening: the room stops at the wall and does not stick out of the building
## silhouette (M24i code review). Furniture stands from the opening, not the walls — what is
## measured is the room itself, its shell.
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
				assert_gte(
					shell.position.x, span.x - 0.001, "roll %d: not past the left wall" % seed
				)
				assert_lte(shell.end.x, span.y + 0.001, "roll %d: not past the right wall" % seed)


func test_every_room_has_its_light_and_window() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var room := _room(kind, 7)
		assert_not_null(room.find_child("RoomLight", true, false), "room light")
		assert_not_null(room.find_child("Window", true, false), "window to the city")
		var light := room.find_child("RoomLight", true, false) as OmniLight3D
		assert_false(light.shadow_enabled, "room light without a shadow - within the frame budget")


## The door assembles the room when the leaf starts to move and removes it when it has closed.
## Without [method Door.furnish] — as in the door tests — it is still dark behind it.
func test_the_door_builds_its_room_only_while_open() -> void:
	var ground := StaticBody3D.new()
	add_child_autofree(ground)
	var door := DOOR_SCENE.instantiate() as Door
	door.furnish(BuildingIdentity.new(), 11)
	add_child_autofree(door)
	await wait_physics_frames(2)
	assert_null(door.room(), "a closed door has no room")
	assert_true(door.summon_agent(), "the door opens for an agent")
	var opened := false
	for _frame: int in PATIENCE:
		await wait_physics_frames(1)
		if door.openness() > 0.0 and door.room() != null:
			opened = true
			break
	assert_true(opened, "the room is visible through an open door")
	door.dismiss_agent()
	var closed := false
	for _frame: int in PATIENCE:
		await wait_physics_frames(1)
		if door.openness() <= 0.0:
			await wait_physics_frames(1)
			closed = door.room() == null
			break
	assert_true(closed, "closed - no room")


func test_a_bare_door_stays_dark() -> void:
	var door := DOOR_SCENE.instantiate() as Door
	add_child_autofree(door)
	assert_true(door.summon_agent())
	for _frame: int in 30:
		await wait_physics_frames(1)
	assert_gt(door.openness(), 0.0)
	assert_null(door.room(), "no building - no room")


## On a dark floor the room has no light of its own: only the window with the city glows
## (user's decision, M24i).
func test_a_room_on_a_dark_floor_keeps_the_dark() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var room := DoorRoom.build(kind, 5, null, Vector2(-INF, INF), true)
		add_child_autofree(room)
		assert_eq(room.find_children("*", "Light3D", true, false).size(), 0, "no light of its own")
		assert_not_null(room.find_child("Window", true, false), "the window to the city is there")
