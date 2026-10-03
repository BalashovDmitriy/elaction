extends GutTest

## The cab indicator board and the buttons at the portals (ADR-0033, decision 7) and the building's
## vertical sign (decision 2): what they show, not how they look.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_all() -> void:
	GameState.instance().reset()


func _level(building: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = building
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	return level


func _shafts(level: GreyboxLevel) -> BuildingShafts:
	for child in level.get_children():
		if child is BuildingShafts:
			return child as BuildingShafts
	return null


## The cab goes down — the "down" button is lit on floors below it, "up" — on floors above it if it
## goes up. Standing — nothing is lit. Indices grow downward.
func test_the_button_lights_where_the_car_is_heading() -> void:
	var down := Intent.DOWN
	var up := Intent.UP
	assert_eq(BuildingShafts.coming(down, 5, 9), down, "goes down to a lower floor")
	assert_eq(BuildingShafts.coming(down, 5, 2), 0.0, "went down away from a higher floor")
	assert_eq(BuildingShafts.coming(up, 5, 2), up, "goes up to a higher floor")
	assert_eq(BuildingShafts.coming(up, 5, 9), 0.0, "went up away from a lower floor")
	assert_eq(BuildingShafts.coming(0.0, 5, 9), 0.0, "standing — calls nobody")


## The board's direction is taken from the cab's real velocity. Its y grows downward, and until the
## M21b code review the board read a cab going down as going up: it lit "▲" on the floors it was
## leaving.
func test_the_heading_follows_the_real_speed_of_the_car() -> void:
	var motion := ElevatorMotion.new()
	motion.setup(PackedFloat32Array([10.0, 13.6, 17.2]), 1)
	motion.update(0.1, ElevatorMotion.DOWN, true)
	assert_eq(BuildingShafts.heading_of(motion.velocity), Intent.DOWN, "goes down")
	motion.setup(PackedFloat32Array([10.0, 13.6, 17.2]), 1)
	motion.update(0.1, ElevatorMotion.UP, true)
	assert_eq(BuildingShafts.heading_of(motion.velocity), Intent.UP, "goes up")
	assert_eq(BuildingShafts.heading_of(0.0), 0.0, "stands")


## The boards on all portals of a shaft show the floor where its cab is — the floor plate number,
## not the index; on the roof — R. First all cabs are updated, then all boards are checked: one
## column can have several shafts (on seed 1 — the shaft from the roof and shaft 15..22), and the
## boards must not show someone else's cab.
##
## The cab gets to its floor only with the first physics step: for a body with sync_to_physics the
## position before it rolls back to zero, and all cabs would read as standing on the roof.
func test_every_board_of_a_shaft_shows_where_its_car_is() -> void:
	var level := _level()
	var shafts := _shafts(level)
	assert_not_null(shafts, "no shafts")
	if shafts == null:
		return
	await wait_physics_frames(3)
	var watched: Array[ElevatorCar] = []
	for car: ElevatorCar in level._cars:
		if shafts.watches(car):
			shafts.refresh(car)
			watched.append(car)
	var checked := 0
	var shared := 0
	for car in watched:
		var shaft := shafts._watched[car] as BuildingPlan.ShaftSpot
		if _column_is_shared(level, shaft):
			shared += 1
		var where := shafts._nearest_floor(car)
		var height := WorldSpace.to_plane(car.global_position).y
		assert_eq(where, level.rules.floor_index_near(height), "cab is not on its own floor")
		var label := BuildingShafts.floor_label(level.rules, where)
		for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
			var text := shafts.board_text(shaft.x, index)
			assert_true(
				text.ends_with(label),
				"shaft x=%.1f, floor %d: '%s' instead of %s" % [shaft.x, index, text, label]
			)
			checked += 1
	assert_gt(checked, 0, "no boards at all")
	assert_gt(shared, 0, "seed 1 has no shafts in a shared column — the test catches nothing")
	remove_child(level)


## A cab on the roof shows R on the board, not a number one greater than the top floor.
func test_the_roof_is_not_a_floor_number() -> void:
	var rules := BuildingRules.new()
	assert_eq(BuildingShafts.floor_label(rules, BuildingRules.ROOF), BuildingShafts.ROOF_LABEL)
	assert_eq(BuildingShafts.floor_label(rules, 0), str(rules.floors))


## The bottom floor is the garage: the shaft boards write "P", like the floor plate and the garage
## columns, and the floor above it remains the second (ADR-0038, decision 3).
func test_the_parking_is_p_on_the_boards() -> void:
	var rules := BuildingRules.new()
	var bottom := rules.floors - 1
	assert_eq(BuildingShafts.floor_label(rules, bottom), "P")
	assert_eq(BuildingShafts.floor_label(rules, bottom - 1), "2")
	assert_eq(Garage.LEVEL_MARK, "P", "parking columns are P-01, P-02...")


## Everything the board writes as text exists in the game's font: a glyph missing from Exo 2 is
## drawn by the system fallback font, and on a machine without it — an empty box. That is how it was
## with the ▲▼ arrows before they were made geometry.
func test_every_board_label_is_in_the_game_font() -> void:
	var font := NeonStyle.scene_font(700)
	var rules := BuildingRules.new()
	for index in range(BuildingRules.ROOF, rules.floors):
		var label := BuildingShafts.floor_label(rules, index)
		for at in label.length():
			assert_true(
				font.has_char(label.unicode_at(at)),
				"floor %d: glyph '%s' is not in the font" % [index, label[at]]
			)


## The direction arrow is a triangle next to the digits: shown while the cab moves, pointing where
## it goes; the digits shift next to it, the board text is only the floor.
func test_the_heading_arrow_is_geometry() -> void:
	var level := _level()
	var shafts := _shafts(level)
	assert_not_null(shafts, "no shafts")
	if shafts == null:
		return
	var column := shafts._boards.values()[0] as Dictionary
	var board := column.values()[0] as BuildingShafts.ShaftBoard
	assert_not_null(board.arrow, "board has no arrow")
	shafts._show(board, "7", Intent.UP, 0.0)
	assert_true(board.arrow.visible, "going up — arrow is visible")
	assert_almost_eq(board.arrow.rotation.z, 0.0, 0.001, "up — tip pointing up")
	assert_eq(board.digits.text, "7", "the text is only the floor")
	assert_gt(board.digits.position.x, board.center.x, "digits made room for the arrow")
	shafts._show(board, "7", Intent.DOWN, 0.0)
	assert_almost_eq(board.arrow.rotation.z, PI, 0.001, "down — tip pointing down")
	shafts._show(board, "7", 0.0, 0.0)
	assert_false(board.arrow.visible, "standing — no arrow")
	assert_almost_eq(board.digits.position.x, board.center.x, 0.001, "digits in the middle")
	remove_child(level)


## The button panel does not overlap the door casing of the neighbouring place or its plate — in any
## building. Since M24b there is no exit opening in the back wall: the exit is the garage gate in
## the end wall ([GarageGate]).
func test_the_call_panel_keeps_off_doors() -> void:
	var door_left := Door.LEAF_SIZE.x * 0.5 + Door.FRAME_WIDTH
	var door_right := Door.LEAF_SIZE.x * 0.5 + BuildingProps.PLATE_GAP + BuildingProps.PLATE.x
	var panels := 0
	for skill: int in [0, 5]:
		var rules := BuildingRules.new()
		rules.skill = skill
		for building_seed: int in [1, 2, 3, 5, 8, 13, 21, 34]:
			var plan := BuildingPlan.generate(rules, building_seed)
			for shaft in plan.shafts:
				for index in range(maxi(shaft.top, 0), shaft.bottom + 1):
					var panel := BuildingShafts.call_panel_span(rules, plan, shaft.x, index)
					if panel.y <= panel.x:
						continue
					panels += 1
					var busy: Array[Vector2] = []
					for door in plan.doors:
						if door.floor_index == index:
							busy.append(Vector2(door.x - door_left, door.x + door_right))
					for zone in busy:
						assert_true(
							panel.y <= zone.x or panel.x >= zone.y,
							(
								"seed %d, floor %d: panel %s on door %s"
								% [building_seed, index, panel, zone]
							)
						)
	assert_gt(panels, 0, "no panels — nothing to check")


func _column_is_shared(level: GreyboxLevel, shaft: BuildingPlan.ShaftSpot) -> bool:
	for other in level.plan().shafts:
		if other != shaft and absf(other.x - shaft.x) < 0.01:
			return true
	return false


## The sign hangs outside the building, above the top floors, and shows the building's name.
func test_the_sign_spells_the_building_and_hangs_outside() -> void:
	for building: int in [1, 2, 3, 4]:
		var level := _level(building)
		var sign_board := level.get_node_or_null("Scenery/VerticalSign") as VerticalSign
		assert_not_null(sign_board, "no sign")
		if sign_board == null:
			remove_child(level)
			continue
		var identity := BuildingIdentity.of(building, 1)
		assert_eq(sign_board.text(), "".join(identity.sign_lines()), "building %d" % building)
		var outer := level.rules.floor_span(0).y
		for label in sign_board.find_children("*", "Label3D", true, false):
			assert_gt((label as Node3D).global_position.x, outer, "letter inside the building")
		remove_child(level)


## Labels in the scene use mipmaps, HUD and menu do not (ADR-0053, decision 9): a distant plate does
## not flicker, and the interface text stays sharp.
func test_scene_text_has_mipmaps_and_the_hud_does_not() -> void:
	var scene := NeonStyle.scene_font(700).base_font as FontFile
	var hud := NeonStyle.font(700).base_font as FontFile
	assert_true(scene.generate_mipmaps, "scene lettering has no mipmaps")
	assert_false(hud.generate_mipmaps, "mipmaps leaked into the HUD")
	assert_ne(scene, hud, "scene and HUD share one font")
