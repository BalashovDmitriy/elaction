extends GutTest

## Детали города и погода M22: верхи домов и вывески по сиду, молния — серия
## вспышек, которая гаснет.


## Верхи и вывески повторяются по сиду, а раскладка кварталов — та же, что до
## деталей: жребий деталей свой.
func test_crowns_follow_the_seed_and_do_not_move_the_blocks() -> void:
	var first := CityPlan.generate(4, 0.0, 40.0)
	var again := CityPlan.generate(4, 0.0, 40.0)
	assert_eq(first.size(), again.size())
	var crowns := {}
	var signs := 0
	var beacons := 0
	for index in first.size():
		assert_eq(first[index].crown, again[index].crown, "верх повторяется по сиду")
		assert_eq(first[index].x, again[index].x)
		crowns[first[index].crown] = true
		if first[index].sign_colour.a > 0.0:
			signs += 1
			assert_lte(first[index].sign_y, first[index].height, "вывеска на фасаде, не над домом")
			assert_lte(first[index].sign_size.x, first[index].width, "вывеска не шире дома")
		if first[index].beacon:
			beacons += 1
	assert_gt(crowns.size(), 2, "город не из одних плоских крыш")
	assert_gt(signs, 0, "в городе нет ни одной вывески")
	assert_gt(beacons, 0, "ни одного огня на верхах")


func test_the_sign_colours_are_not_game_signs() -> void:
	var reserved: Array[Color] = [
		GreyboxLook.SIGN_WARM, GreyboxLook.SIGN_RED, GreyboxLook.SIGN_GREEN
	]
	for colour in CityPlan.SIGN_COLOURS:
		for game_sign in reserved:
			var gap := Vector3(
				colour.r - game_sign.r, colour.g - game_sign.g, colour.b - game_sign.b
			)
			assert_gt(
				gap.length(), 0.3, "вывеска города %s похожа на огонёк %s" % [colour, game_sign]
			)


## Молния — серия вспышек через паузу, и после серии небо снова тёмное.
func test_lightning_flashes_and_goes_dark() -> void:
	var lightning := Lightning.new()
	add_child_autofree(lightning)
	lightning.setup(3, Vector2(0.0, 40.0), 0.0)
	lightning.set_process(false)
	var brightest := 0.0
	for _step in int(Lightning.PAUSE.y * 60.0) + 120:
		lightning.advance(1.0 / 60.0)
		brightest = maxf(brightest, lightning.level())
	assert_gt(brightest, 0.5, "за самую долгую паузу хоть одна вспышка")
	for _step in 120:
		lightning.advance(1.0 / 60.0)
		if lightning.level() < 0.01:
			break
	assert_lt(lightning.level(), 0.2, "и гаснет")


## Разряд виден с камеры города: ломаная идёт сверху вниз, её треугольники
## обращены от камеры, и с отсечением задних граней она не рисовалась вовсе.
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
	assert_not_null(bolt, "за шесть долгих пауз ни одного разряда")
	if bolt == null:
		return
	var look := bolt.material_override as BaseMaterial3D
	assert_eq(look.cull_mode, BaseMaterial3D.CULL_DISABLED, "разряд отсекается гранью")


## Молния, огни и неон — без источников света: бюджет ламп кадра не растёт.
func test_the_city_details_add_no_lights() -> void:
	var blocks := CityPlan.generate(2, 0.0, 40.0)
	var nodes: Array[Node] = [
		CityDetails.crowns(blocks, 0.0, StandardMaterial3D.new()),
		CityDetails.beacons(blocks, 0.0),
		CityDetails.signs(blocks, 0.0),
		CityDetails.street_glow(0.0, 0.0, 40.0),
		CityDetails.night_sky(2, 0.0, 40.0, 0.0),
		CityDetails.fog_banks(2, 0.0, 40.0, 0.0),
	]
	for node in nodes:
		add_child_autofree(node)
		assert_eq(
			node.find_children("*", "Light3D", true, false).size(), 0, "%s светит" % node.name
		)
		assert_false(node is Light3D)
