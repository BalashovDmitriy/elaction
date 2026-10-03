extends GutTest

## Building dress: the shaft and the machine room. The helicopter intro is
## in `test_roof_arrival.gd`.
##
## Dress parts are boxes without a body, and the test recognises them by extent: the same one
## [BuildingShafts] and [GreyboxLevel] build them with. A grey box has no other
## feature, and the shaft leaves and the hut share one material.
##
## The test measures in the rule plane: each box is converted into a [Rect2] with its origin
## at the top left corner — that is how the layout counted, and how this same test counted before
## the move to 3D. The assertions did not change in the move (ADR-0021).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many frames the building is given to settle into place.
const SETTLE_FRAMES: int = 4

## How close a part counts as standing in its place, m: a centimetre.
const TOLERANCE: float = 0.01


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## The building is real: thirty floors, five shafts, a roof on top.
func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## Dress parts of the required kind, as rectangles in the rule plane.
##
## Searched both in the level itself and in [BuildingShafts]: the shaft dress lives in its own node
## (over fifty parts per building, and they must not fall under every walk of the
## children), while the machine room is a direct child of the level.
func _parts(level: GreyboxLevel, kind: String) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var hosts: Array[Node] = [level]
	hosts.append_array(level.find_children("*", "BuildingShafts", false, false))
	for host: Node in hosts:
		for child: Node in host.get_children():
			var part := child as MeshInstance3D
			if part == null:
				continue
			var box := part.mesh as BoxMesh
			if box == null or not _is_a(kind, box.size):
				continue
			var size := Vector2(box.size.x, box.size.y)
			var centre := WorldSpace.to_plane(part.global_position)
			found.append(Rect2(centre - size * 0.5, size))
	return found


## Recognises a part by extent — the same one it was built with.
static func _is_a(kind: String, size: Vector3) -> bool:
	match kind:
		"shaft_rail":
			return is_equal_approx(size.x, BuildingShafts.RAIL_WIDTH)
		"shaft_door":
			# Shaft portal opening: the full shaft width and the door height (ADR-0031).
			return (
				is_equal_approx(size.x, Proportions.SHAFT)
				and is_equal_approx(size.y, Proportions.DOOR.y)
			)
		"shaft_buffer":
			return is_equal_approx(size.y, BuildingShafts.BUFFER_HEIGHT)
		"machine_room":
			return (
				is_equal_approx(size.x, BuildingShafts.MACHINE_ROOM_SIZE.x)
				and is_equal_approx(size.y, BuildingShafts.MACHINE_ROOM_SIZE.y)
			)
	return false


## Where Otto stands in the rule plane.
func _otto_at(level: GreyboxLevel) -> Vector2:
	return WorldSpace.to_plane(level.otto.global_position)


## Each shaft has both guide rails over its full height.
##
## A shaft used to be a hole in the slab, and it was barely in the frame (ADR-0017,
## decision 3). What is checked is not "there is something" but that the rails run along the edges
## of the opening and end together with the shaft: a short rail fools the eye more
## than its absence.
##
## A rail is searched by edge and bottom at once: shafts do not run through, and one column
## holds several of them — one below another.
func test_every_shaft_wears_both_rails() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var rules := level.rules
		var rails := _parts(level, "shaft_rail")
		for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
			var half := rules.shaft_width * 0.5
			var bottom := rules.floor_surface(shaft.bottom)
			var span := bottom - rules.floor_surface(shaft.top)
			var sides: Array[float] = [shaft.x - half, shaft.x + half - BuildingShafts.RAIL_WIDTH]
			for left: float in sides:
				var found := false
				for rail: Rect2 in rails:
					if absf(rail.position.x - left) > TOLERANCE:
						continue
					if absf(rail.end.y - bottom) > TOLERANCE:
						continue
					# The rail runs from the ceiling of the shaft's top floor, that is, above
					# its floor: it is never shorter than the run.
					assert_gt(
						rail.size.y,
						span,
						"seed %d: the post is shorter than its shaft" % building_seed
					)
					found = true
				assert_true(
					found,
					(
						"seed %d: shaft %d–%d at %.2f m has no post at %.2f m"
						% [building_seed, shaft.top, shaft.bottom, shaft.x, left]
					)
				)

		_drop(level)


## A portal stands on every floor the shaft serves — and only there. On
## the roof there is no portal: there the shaft goes into the machine room.
func test_shaft_doors_stand_on_every_floor_it_serves() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var doors := _parts(level, "shaft_door")
	var served := 0
	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		for index: int in range(maxi(shaft.top, 0), shaft.bottom + 1):
			served += 1
			var surface := rules.floor_surface(index)
			var found := false
			for door: Rect2 in doors:
				if absf(door.get_center().x - shaft.x) > TOLERANCE:
					continue
				if absf(door.end.y - surface) <= TOLERANCE:
					found = true
			assert_true(found, "floor %d has no shaft leaves at %.2f m" % [index, shaft.x])

	assert_eq(doors.size(), served, "exactly as many leaves as the shafts have floors")
	_drop(level)


## The superstructure stands over the top shaft and does not take the spot where Otto appears.
##
## It has no body on purpose: under it is the opening of the very shaft the descent
## starts with. But Otto must not stand on it — otherwise he would start the building inside
## the hut.
func test_machine_room_stands_over_the_top_shaft() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var rooms := _parts(level, "machine_room")
		assert_eq(rooms.size(), 1, "seed %d: one machine room" % building_seed)
		if rooms.is_empty():
			_drop(level)
			continue

		var room := rooms[0]
		var centre := room.get_center().x
		var top_shaft := level.plan().roof_shaft()
		assert_not_null(
			top_shaft, "seed %d: the building has a shaft up to the roof" % building_seed
		)
		assert_eq(
			top_shaft.top,
			BuildingRules.ROOF,
			"seed %d: the top shaft reaches the roof" % building_seed
		)
		assert_almost_eq(
			centre, top_shaft.x, TOLERANCE, "seed %d: the housing above the shaft" % building_seed
		)

		var landing := level.plan().safe_x(level.rules, BuildingRules.ROOF)
		var gap := absf(landing - centre)
		assert_gt(
			gap,
			room.size.x * 0.5,
			(
				"seed %d: Otto appears inside the housing (%.2f m from its middle)"
				% [building_seed, gap]
			)
		)
		_drop(level)


## Each shaft has buffers at the top and bottom: they show where the run ends.
##
## The vertical position is checked too, not only the count: the bottom buffer once slid
## into the depth of the slab — it was counted in the same place as before, but in the frame it
## was not there at all. The count did not notice.
func test_every_shaft_is_capped_at_both_ends() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var buffers := _parts(level, "shaft_buffer")
	var shafts := level.plan().shafts.size()
	assert_eq(buffers.size(), shafts * 2, "one buffer at each end of each shaft")

	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		var mine := 0
		# The bottom of a shaft is the floor of its bottom level: the buffer stands on it, not under
		# it.
		var floor_surface := level.rules.floor_surface(shaft.bottom)
		# Its own shaft is identified by column and height at once. A column alone is not enough
		# since M18: shafts overlap, a grid slot goes to several of them
		# at different heights, and by x alone others' buffers got mixed in (ADR-0024).
		var top_edge := level.rules.story_top(shaft.top)
		var capped_below := false
		for buffer: Rect2 in buffers:
			if absf(buffer.get_center().x - shaft.x) > TOLERANCE:
				continue
			var middle := buffer.get_center().y
			if middle < top_edge - TOLERANCE or middle > floor_surface + TOLERANCE:
				continue
			mine += 1
			assert_lte(
				buffer.end.y,
				floor_surface + TOLERANCE,
				"the buffer of the shaft at %.2f m is not sunk into the slab" % shaft.x
			)
			if absf(buffer.end.y - floor_surface) <= TOLERANCE:
				capped_below = true
		assert_eq(mine, 2, "both ends of the shaft at %.2f m are marked" % shaft.x)
		assert_true(capped_below, "the buffer of the shaft at %.2f m rests on its bottom" % shaft.x)
	_drop(level)


## A number on every floor, as in the original: at the right wall, under the ceiling, and
## the top floor has the highest number (ADR-0026, decision 9).
##
## The sign must not hang over a shaft opening: there a cab would cover it, and
## on any seed a shaft can stand in the rightmost slot.
func test_every_floor_wears_its_number() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var signs := level.get_node("FloorSigns")
	assert_eq(signs.get_child_count(), rules.floors, "one plate per floor, none at the roof")
	var half := Proportions.FLOOR_SIGN * 0.5
	for index in rules.floors:
		var number := FloorSigns.label_of(rules, index)
		var plate := signs.get_node("Floor%s" % number) as Node3D
		assert_not_null(plate, "floor %s has no plate" % number)
		if plate == null:
			continue
		var label := plate.get_child(1) as Label3D
		assert_eq(label.text, number, "the plate has its own number")
		var at := WorldSpace.to_plane(plate.position)
		var span := rules.floor_span(index)
		assert_lt(at.x + half.x, span.y - BuildingShell.WALL_WIDTH, "inside the walls")
		# Below the band hidden by the slab edge — otherwise the digits are not visible.
		assert_gt(
			at.y - half.y, rules.story_top(index) + FloorSigns.hidden_band(), "not under the edge"
		)
		# Right of the outermost slot: there is neither a door, nor an indicator above it, nor a
		# lamp.
		var last := rules.slot_x(rules.slot_range(index).y)
		assert_gt(at.x - half.x, last + Proportions.SLOT * 0.5, "beyond the last spot")
		for shaft in level.plan().shafts:
			if shaft.top <= index and index <= shaft.bottom:
				assert_gt(
					at.x - half.x,
					shaft.x + rules.shaft_width * 0.5,
					"floor %s: plate above the shaft" % number
				)
	assert_eq(FloorSigns.number_of(rules, 0), rules.floors, "the top floor has the highest number")
	assert_eq(FloorSigns.number_of(rules, rules.floors - 2), 2, "above the parking: the second")
	assert_eq(FloorSigns.label_of(rules, rules.floors - 1), "P", "the lowest is the parking, 'P'")
	assert_eq(FloorSigns.label_of(rules, rules.floors - 2), "2", "the rest did not shift")
	_drop(level)
