extends GutTest

## Прохожие у выезда (ADR-0054, решение 3): идут, а не плывут статуями, и не
## клоны друг друга; в непогоду одеты по ней и под зонтами.


func _street(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.DAY) -> ExitStreet:
	var street := ExitStreet.new()
	add_child_autofree(street)
	street.build(0.0, 0.0, 1, weather, time)
	return street


func _leg(walker: Node) -> Quaternion:
	var skeleton := walker.find_child("Skeleton3D", true, false) as Skeleton3D
	return skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperLeg.L"))


## Ходьба идёт и после первого шага: из glTF она приходит без петли, и
## доигравший шаг прохожий застывал.
func test_walkers_keep_walking() -> void:
	var people := _street(Weather.Kind.CLEAR).people()
	assert_gt(people.count(), 2, "днём на улице почти никого")
	var walker := people.get_child(0)
	await wait_seconds(2.0)
	var before := _leg(walker)
	await wait_seconds(0.3)
	var after := _leg(walker)
	assert_gt(before.angle_to(after), 0.02, "ноги не двигаются: прохожий плывёт")


## Прохожие разные: из частей разных моделей и в своих цветах.
func test_walkers_differ() -> void:
	var people := _street(Weather.Kind.CLEAR).people()
	var looks: Dictionary = {}
	for walker in people.get_children():
		var signature := ""
		for node in walker.find_children("*", "MeshInstance3D", true, false):
			var shape := node as MeshInstance3D
			if shape.name.ends_with("_Body") or shape.name.ends_with("_Legs"):
				var look := shape.get_surface_override_material(0) as BaseMaterial3D
				signature += "%s%s" % [shape.mesh.resource_name, look.albedo_color if look else ""]
		looks[signature] = true
	assert_eq(looks.size(), people.count(), "среди прохожих есть одинаковые")


## Ночью прохожих меньше, чем днём; в непогоду у многих зонт.
func test_crowd_follows_time_and_weather() -> void:
	var day := _street(Weather.Kind.CLEAR, TimeOfDay.Kind.DAY).people().count()
	var night := _street(Weather.Kind.CLEAR, TimeOfDay.Kind.NIGHT).people().count()
	assert_lt(night, day, "ночью на улице людней, чем днём")
	var rainy := _street(Weather.Kind.RAIN).people()
	var umbrellas := rainy.find_children("Umbrella", "Node3D", true, false).size()
	assert_gt(umbrellas, 0, "в дождь ни одного зонта")
	for weather: int in [Weather.Kind.CLEAR, Weather.Kind.RAIN, Weather.Kind.SNOW]:
		for walker in _street(weather as Weather.Kind).people().get_children():
			assert_not_null(walker.get_node_or_null("Shelter"), "дождь идёт сквозь прохожего")
			assert_eq(
				walker.find_children("*Pistol*", "", true, false).size(), 0, "прохожий с пистолетом"
			)


## Одеты по погоде: в снег все в пальто, многие в шапках и шарфах, в дождь —
## в плащах, в ясную — налегке.
func test_walkers_dress_for_the_weather() -> void:
	assert_eq(Passerby.dress_for(Weather.Kind.SNOW), Passerby.Dress.COLD)
	assert_eq(Passerby.dress_for(Weather.Kind.RAIN), Passerby.Dress.WET)
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR), Passerby.Dress.LIGHT)
	var cold := _street(Weather.Kind.SNOW).people()
	for walker in cold.get_children():
		assert_eq(
			walker.find_children("Coat", "BoneAttachment3D", true, false).size(),
			1,
			"в снег без пальто"
		)
	var knits := cold.find_children("Hat", "BoneAttachment3D", true, false).size()
	knits += cold.find_children("Scarf", "BoneAttachment3D", true, false).size()
	assert_gt(knits, 0, "в снег ни шапки, ни шарфа")
	var light := _street(Weather.Kind.CLEAR).people()
	assert_eq(
		light.find_children("Coat", "BoneAttachment3D", true, false).size(), 0, "в ясную в пальто"
	)
