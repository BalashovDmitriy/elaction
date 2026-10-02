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


## Прохожие идут, только пока выезд в кадре, как поток машин: вне кадра ходьба
## и хват зонта стоят, а в кадре идут снова.
func test_walkers_rest_while_the_street_is_out_of_view() -> void:
	var street := _street(Weather.Kind.RAIN)
	var people := street.people()
	street.show_light(false)
	assert_false(people.is_active(), "вне кадра прохожие идут")
	var walker := people.get_child(0) as Node3D
	var before := walker.position
	await wait_seconds(0.2)
	assert_eq(walker.position, before, "вне кадра прохожий сдвинулся")
	var grips := people.find_children("Grip", "", true, false)
	assert_gt(grips.size(), 0, "в дождь ни одного зонта в руке")
	for node in grips:
		assert_false((node as UmbrellaGrip).active, "хват зонта считается вне кадра")
	street.show_light(true)
	await wait_seconds(0.2)
	assert_true(people.is_active(), "в кадре прохожие стоят")
	assert_ne(walker.position, before, "в кадре прохожий не идёт")


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
			assert_not_null(
				walker.find_child("Shelter", true, false), "дождь идёт сквозь прохожего"
			)
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
	var knits := cold.find_children("Hat", "BoneAttachment3D", true, false).size()
	knits += cold.find_children("Scarf", "BoneAttachment3D", true, false).size()
	assert_gt(knits, 0, "в снег ни шапки, ни шарфа")


## В снег под зонтами не ходят: зонты — только в дождь.
func test_no_umbrellas_in_the_snow() -> void:
	var snowy := _street(Weather.Kind.SNOW).people()
	assert_eq(snowy.find_children("Umbrella", "Node3D", true, false).size(), 0, "зонт в снег")


## Ревизия по всем шестнадцати сочетаниям времени и погоды (просьба
## пользователя): кроме ясных утра и дня, открыта только голова — у каждого
## прохожего кожа корпуса, ног и ступней одета.
func test_no_bare_skin_unless_its_light_weather() -> void:
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var dress := Passerby.dress_for(weather as Weather.Kind, time as TimeOfDay.Kind)
			var street := _street(weather as Weather.Kind, time as TimeOfDay.Kind)
			for walker in street.people().get_children():
				var bare := _bare_parts(walker)
				if dress == Passerby.Dress.LIGHT:
					continue
				assert_true(
					bare.is_empty(),
					"время %d, погода %d: открыто %s" % [time, weather, ", ".join(bare)]
				)
			street.queue_free()
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR, TimeOfDay.Kind.DAY), Passerby.Dress.LIGHT)
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR, TimeOfDay.Kind.NIGHT), Passerby.Dress.MILD)
	assert_eq(Passerby.dress_for(Weather.Kind.FOG, TimeOfDay.Kind.DAY), Passerby.Dress.MILD)


## Части тела, где под одеждой видна кожа — цвет из тонов кожи.
func _bare_parts(walker: Node) -> PackedStringArray:
	var found := PackedStringArray()
	for node in walker.find_children("*", "MeshInstance3D", true, false):
		var shape := node as MeshInstance3D
		if shape.name.ends_with("_Head") or shape.mesh == null:
			continue
		for surface in shape.mesh.get_surface_count():
			var source := shape.mesh.surface_get_material(surface)
			if source == null or not source.resource_name.begins_with("Skin"):
				continue
			var look := shape.get_surface_override_material(surface) as BaseMaterial3D
			for tone in Passerby.SKINS:
				if (
					look != null
					and (
						look.albedo_color.is_equal_approx(tone)
						or look.albedo_color.is_equal_approx(tone * 0.85)
					)
				):
					found.append(shape.name)
	return found


## Под зонтом сухо от купола до земли: ловец едет с зонтом, а не стоит серединой
## тела в рост человека.
func test_umbrella_keeps_the_column_under_it_dry() -> void:
	var rainy := _street(Weather.Kind.RAIN).people()
	var checked := 0
	for umbrella in rainy.find_children("Umbrella", "Node3D", true, false):
		var dry := umbrella.get_node_or_null("Shelter") as GPUParticlesCollisionBox3D
		assert_not_null(dry, "под зонтом мокро")
		if dry == null:
			continue
		assert_almost_eq(dry.size.x, StreetPeople.CANOPY.x * 2.0, 0.01, "сухо не во весь купол")
		var bottom := (umbrella as Node3D).position.y + dry.position.y - dry.size.y * 0.5
		assert_lt(bottom, 0.2, "под зонтом сухо не до земли")
		checked += 1
	assert_gt(checked, 0, "в дождь ни одного зонта")
