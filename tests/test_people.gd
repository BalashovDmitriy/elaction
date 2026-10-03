extends GutTest

## Pedestrians at the exit (ADR-0054, decision 3): they walk rather than glide like
## statues, and are not clones of each other; in bad weather they dress for it and
## carry umbrellas.


func _street(weather: Weather.Kind, time: TimeOfDay.Kind = TimeOfDay.Kind.DAY) -> ExitStreet:
	var street := ExitStreet.new()
	add_child_autofree(street)
	street.build(0.0, 0.0, 1, weather, time)
	return street


func _leg(walker: Node) -> Quaternion:
	var skeleton := walker.find_child("Skeleton3D", true, false) as Skeleton3D
	return skeleton.get_bone_pose_rotation(skeleton.find_bone("UpperLeg.L"))


## Walking continues after the first step: it comes from glTF without a loop, and a
## pedestrian who finished a step froze.
func test_walkers_keep_walking() -> void:
	var people := _street(Weather.Kind.CLEAR).people()
	assert_gt(people.count(), 2, "almost nobody on the street by day")
	var walker := people.get_child(0)
	await wait_seconds(2.0)
	var before := _leg(walker)
	await wait_seconds(0.3)
	var after := _leg(walker)
	assert_gt(before.angle_to(after), 0.02, "the legs do not move: the passer-by glides")


## Pedestrians walk only while the exit is in the frame, like the traffic: off frame the
## walk and the umbrella grip stop, and in the frame they go again.
func test_walkers_rest_while_the_street_is_out_of_view() -> void:
	var street := _street(Weather.Kind.RAIN)
	var people := street.people()
	street.show_light(false)
	assert_false(people.is_active(), "passers-by walk off-screen")
	var walker := people.get_child(0) as Node3D
	var before := walker.position
	await wait_seconds(0.2)
	assert_eq(walker.position, before, "the passer-by moved off-screen")
	var grips := people.find_children("Grip", "", true, false)
	assert_gt(grips.size(), 0, "no umbrella in hand in the rain")
	for node in grips:
		assert_false((node as UmbrellaGrip).active, "the umbrella grip is processed off-screen")
	street.show_light(true)
	await wait_seconds(0.2)
	assert_true(people.is_active(), "passers-by stand on screen")
	assert_ne(walker.position, before, "the passer-by does not walk on screen")


## Pedestrians differ: made of parts of different models and in their own colours.
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
	assert_eq(looks.size(), people.count(), "some passers-by look identical")


## There are fewer pedestrians at night than in the daytime; in bad weather many have
## an umbrella.
func test_crowd_follows_time_and_weather() -> void:
	var day := _street(Weather.Kind.CLEAR, TimeOfDay.Kind.DAY).people().count()
	var night := _street(Weather.Kind.CLEAR, TimeOfDay.Kind.NIGHT).people().count()
	assert_lt(night, day, "the street is busier at night than by day")
	var rainy := _street(Weather.Kind.RAIN).people()
	var umbrellas := rainy.find_children("Umbrella", "Node3D", true, false).size()
	assert_gt(umbrellas, 0, "no umbrella in the rain")
	for weather: int in [Weather.Kind.CLEAR, Weather.Kind.RAIN, Weather.Kind.SNOW]:
		for walker in _street(weather as Weather.Kind).people().get_children():
			assert_not_null(
				walker.find_child("Shelter", true, false), "rain falls through the passer-by"
			)
			assert_eq(
				walker.find_children("*Pistol*", "", true, false).size(),
				0,
				"a passer-by with a pistol"
			)


## Dressed for the weather: in snow everyone wears a coat, many in hats and scarves, in
## rain — in raincoats, in clear weather — lightly dressed.
func test_walkers_dress_for_the_weather() -> void:
	assert_eq(Passerby.dress_for(Weather.Kind.SNOW), Passerby.Dress.COLD)
	assert_eq(Passerby.dress_for(Weather.Kind.RAIN), Passerby.Dress.WET)
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR), Passerby.Dress.LIGHT)
	var cold := _street(Weather.Kind.SNOW).people()
	var knits := cold.find_children("Hat", "BoneAttachment3D", true, false).size()
	knits += cold.find_children("Scarf", "BoneAttachment3D", true, false).size()
	assert_gt(knits, 0, "no hat or scarf in the snow")


## Nobody walks under umbrellas in snow: umbrellas — only in rain.
func test_no_umbrellas_in_the_snow() -> void:
	var snowy := _street(Weather.Kind.SNOW).people()
	assert_eq(
		snowy.find_children("Umbrella", "Node3D", true, false).size(), 0, "umbrella in the snow"
	)


## A review over all sixteen combinations of time and weather (the user's request):
## except for clear morning and day, only the head is bare — every pedestrian's torso,
## leg and foot skin is clothed.
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
					"time %d, weather %d: exposed %s" % [time, weather, ", ".join(bare)]
				)
			street.queue_free()
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR, TimeOfDay.Kind.DAY), Passerby.Dress.LIGHT)
	assert_eq(Passerby.dress_for(Weather.Kind.CLEAR, TimeOfDay.Kind.NIGHT), Passerby.Dress.MILD)
	assert_eq(Passerby.dress_for(Weather.Kind.FOG, TimeOfDay.Kind.DAY), Passerby.Dress.MILD)


## Body parts where skin shows under the clothes — colour from the skin tones.
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


## Under an umbrella it is dry from the canopy to the ground: the catcher travels with
## the umbrella rather than standing at the body's middle at human height.
func test_umbrella_keeps_the_column_under_it_dry() -> void:
	var rainy := _street(Weather.Kind.RAIN).people()
	var checked := 0
	for umbrella in rainy.find_children("Umbrella", "Node3D", true, false):
		var dry := umbrella.get_node_or_null("Shelter") as GPUParticlesCollisionBox3D
		assert_not_null(dry, "wet under the umbrella")
		if dry == null:
			continue
		assert_almost_eq(
			dry.size.x, StreetPeople.CANOPY.x * 2.0, 0.01, "dry area does not span the whole canopy"
		)
		var bottom := (umbrella as Node3D).position.y + dry.position.y - dry.size.y * 0.5
		assert_lt(bottom, 0.2, "dry area under the umbrella does not reach the ground")
		checked += 1
	assert_gt(checked, 0, "no umbrella in the rain")
