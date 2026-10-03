extends GutTest

## City details and M22 weather: building tops and signs by seed, lightning — a series
## of flashes that fades.


## Tops and signs repeat by seed, while the block layout is the same as before
## the details: the details have their own draw.
func test_crowns_follow_the_seed_and_do_not_move_the_blocks() -> void:
	var first := CityPlan.generate(4, 0.0, 40.0)
	var again := CityPlan.generate(4, 0.0, 40.0)
	assert_eq(first.size(), again.size())
	var crowns := {}
	var signs := 0
	var beacons := 0
	for index in first.size():
		assert_eq(first[index].crown, again[index].crown, "crown repeats by seed")
		assert_eq(first[index].x, again[index].x)
		crowns[first[index].crown] = true
		if first[index].sign_colour.a > 0.0:
			signs += 1
			assert_lte(
				first[index].sign_y,
				first[index].height,
				"sign is on the facade, not above the house"
			)
			assert_lte(
				first[index].sign_size.x, first[index].width, "sign is not wider than the house"
			)
		if first[index].beacon:
			beacons += 1
	assert_gt(crowns.size(), 2, "the city is not all flat roofs")
	assert_gt(signs, 0, "the city has no signs")
	assert_gt(beacons, 0, "no lights on the tops")


func test_the_sign_colours_are_not_game_signs() -> void:
	var reserved: Array[Color] = [
		GreyboxLook.SIGN_WARM, GreyboxLook.SIGN_RED, GreyboxLook.SIGN_GREEN
	]
	for colour in CityPlan.SIGN_COLOURS:
		for game_sign in reserved:
			var gap := Vector3(
				colour.r - game_sign.r, colour.g - game_sign.g, colour.b - game_sign.b
			)
			assert_gt(gap.length(), 0.3, "city sign %s looks like light %s" % [colour, game_sign])


## Lightning is a series of flashes with a pause, and after the series the sky is dark again.
func test_lightning_flashes_and_goes_dark() -> void:
	var lightning := Lightning.new()
	add_child_autofree(lightning)
	lightning.setup(3, Vector2(0.0, 40.0), 0.0)
	lightning.set_process(false)
	var brightest := 0.0
	for _step in int(Lightning.PAUSE.y * 60.0) + 120:
		lightning.advance(1.0 / 60.0)
		brightest = maxf(brightest, lightning.level())
	assert_gt(brightest, 0.5, "at least one flash within the longest pause")
	for _step in 120:
		lightning.advance(1.0 / 60.0)
		if lightning.level() < 0.01:
			break
	assert_lt(lightning.level(), 0.2, "and fades")


## The strike is visible from the city camera: the polyline goes top to bottom, its triangles
## face away from the camera, and with back-face culling it was not drawn at all.
func test_the_bolt_is_drawn_from_both_sides() -> void:
	var lightning := Lightning.new()
	add_child_autofree(lightning)
	lightning.setup(3, Vector2(0.0, 40.0), 0.0)
	lightning.set_process(false)
	var bolt: MeshInstance3D = null
	for _step in int(Lightning.PAUSE.y * 60.0) * 6:
		lightning.advance(1.0 / 60.0)
		var found := lightning.find_children("*", "MeshInstance3D", false, false)
		if not found.is_empty():
			bolt = found[0] as MeshInstance3D
			break
	assert_not_null(bolt, "no bolt in six long pauses")
	if bolt == null:
		return
	var look := bolt.material_override as BaseMaterial3D
	assert_eq(look.cull_mode, BaseMaterial3D.CULL_DISABLED, "the bolt is culled by its face")


## Lightning, lights and neon — without light sources: the frame's lamp budget does not grow.
func test_the_city_details_add_no_lights() -> void:
	var blocks := CityPlan.generate(2, 0.0, 40.0)
	var nodes: Array[Node] = [
		CityDetails.crowns(blocks, 0.0, StandardMaterial3D.new()),
		CityDetails.beacons(blocks, 0.0),
		CityDetails.signs(blocks, 0.0),
		CityDetails.street_glow(0.0, 0.0, 40.0),
		CityDetails.fog_banks(2, 0.0, 40.0, 0.0),
	]
	for node in nodes:
		add_child_autofree(node)
		assert_eq(
			node.find_children("*", "Light3D", true, false).size(), 0, "%s emits light" % node.name
		)
		assert_false(node is Light3D)
