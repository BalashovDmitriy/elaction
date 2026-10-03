extends GutTest

## Snow is the fourth weather (ADR-0054): flakes die on the roof by the same height map
## as rain, the cover lies on everything facing up, and the city is in a snowfall. At any
## time of day.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_all() -> void:
	GameState.instance().reset()


func _snowy(time: TimeOfDay.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.rules.time_of_day = time
	level.rules.forced_weather = Weather.Kind.SNOW
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


## There are four weathers, and each falls on roughly a quarter of buildings (decision 1).
func test_snow_falls_on_a_quarter_of_the_buildings() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for building_seed in range(1, 401):
		counts[Weather.of_seed(building_seed)] += 1
	for kind: int in Weather.Kind.size():
		assert_between(counts[kind], 70, 130, "weather %d: %d of 400" % [kind, counts[kind]])


## Flakes die on the roof, the cover lies on top on the roof layer, there is no rain, and
## so at any time of day.
func test_the_roof_is_snowed_at_every_time() -> void:
	for time: int in TimeOfDay.Kind.size():
		var level := _snowy(time as TimeOfDay.Kind)
		var scenery := level.get_node("Scenery") as BuildingScenery
		assert_null(scenery.roof_rain(), "rain falls during snow")
		var snow := scenery.roof_snow()
		assert_not_null(snow, "time %d: no snow above the roof" % time)
		if snow == null:
			continue
		var process := snow.flakes().process_material as ParticleProcessMaterial
		assert_eq(
			process.collision_mode,
			ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
			"flakes die by timer, not on the roof"
		)
		assert_false(process.turbulence_enabled, "particle noise holds the flakes up in the sky")
		assert_eq(
			snow.catcher().heightfield_mask, RoofCatch.LAYER, "heightfield is not from the roof"
		)
		var cover := snow.cover()
		assert_eq(cover.cull_mask, RoofCatch.LAYER, "the cover lands on more than the roof")
		assert_gt(cover.normal_fade, 0.0, "the cover also lands on walls")
		var marked := 0
		for node in level.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).layers & RoofCatch.LAYER:
				marked += 1
		assert_gt(marked, 10, "almost nothing on the roof layer: the cover has nothing to land on")
		level.queue_free()
		await wait_physics_frames(1)


## The city is in a snowfall: flake layers at the city camera, without particle noise.
func test_the_city_snows() -> void:
	var city := CityBackdrop.new()
	add_child_autofree(city)
	city.build(BuildingRules.new(), 1, Weather.Kind.SNOW, TimeOfDay.Kind.NIGHT)
	var layers := 0
	for node in city.find_children("Snow*", "GPUParticles3D", true, false):
		var process := (node as GPUParticles3D).process_material as ParticleProcessMaterial
		assert_false(process.turbulence_enabled, "particle noise holds the flakes up in the sky")
		layers += 1
	assert_eq(layers, SnowLook.CITY_LAYERS.size(), "snowfall layers in the city")


## On the low level the city snowfall is sparser, like the rain streaks: the quality
## level recalculates the layers.
func test_the_city_snow_follows_quality() -> void:
	var was := Graphics.quality
	Graphics.quality = Graphics.Quality.LOW
	var city := CityBackdrop.new()
	add_child_autofree(city)
	city.build(BuildingRules.new(), 1, Weather.Kind.SNOW, TimeOfDay.Kind.NIGHT)
	Graphics.quality = was
	var layers := city.find_children("Snow*", "GPUParticles3D", true, false)
	assert_false(layers.is_empty(), "no snowfall in the city")
	for node in layers:
		var layer := node as GPUParticles3D
		assert_lt(
			layer.amount,
			int(layer.get_meta(RainLook.FULL)),
			"%s at full strength on low" % layer.name
		)


## At night flakes are dimmer than by day: snow's own light comes from the city and lamps.
func test_flakes_are_dimmer_at_night() -> void:
	var night := SnowLook.brightness(TimeOfDay.Kind.NIGHT)
	var day := SnowLook.brightness(TimeOfDay.Kind.DAY)
	assert_lt(night, day, "night snow is brighter than day snow")


## Drops and flakes die on people, cars and the helicopter instead of going through them
## ([Shelter]): each body has its own particle catcher.
func test_bodies_shelter_from_rain_and_snow() -> void:
	var otto := preload("res://src/actors/otto/otto.tscn").instantiate() as Otto
	add_child_autofree(otto)
	var agent := preload("res://src/actors/enemy/enemy.tscn").instantiate() as Enemy
	add_child_autofree(agent)
	for body: Node3D in [otto, agent]:
		var shield := body.get_node_or_null("Shelter") as GPUParticlesCollisionBox3D
		assert_not_null(shield, "%s without a catcher: rain falls through it" % body.name)
		if shield != null:
			assert_almost_eq(shield.size.y, Proportions.BODY, 0.01, "catcher is not body height")
	var car := CarModel.build()
	autofree(car)
	assert_not_null(car.get_node_or_null("Shelter"), "the car has no catcher")
	var helicopter := Helicopter.new()
	add_child_autofree(helicopter)
	var hull := helicopter.find_child("Shelter", true, false) as GPUParticlesCollisionBox3D
	assert_not_null(hull, "the helicopter has no catcher")
	if hull != null:
		assert_lt(hull.size.x, 9.0, "helicopter catcher spans the whole rotor - a dry box under it")


## On the exit street drops and flakes die on awnings and the pavement by the street
## height map; the traffic cars are not in it, the car at the curb is.
func test_the_street_catches_rain_and_snow() -> void:
	for weather: int in [Weather.Kind.RAIN, Weather.Kind.SNOW]:
		var street := ExitStreet.new()
		add_child_autofree(street)
		street.build(0.0, 0.0, 1, weather as Weather.Kind, TimeOfDay.Kind.NIGHT)
		var catcher := (
			street.get_node_or_null("StreetCatcher") as GPUParticlesCollisionHeightField3D
		)
		assert_not_null(catcher, "weather %d: the street does not catch precipitation" % weather)
		if catcher == null:
			continue
		assert_eq(catcher.heightfield_mask, StreetSnow.LAYER)
		for node in street.traffic().find_children("*", "GeometryInstance3D", true, false):
			assert_eq(
				(node as GeometryInstance3D).layers & StreetSnow.LAYER,
				0,
				"flow car in the heightfield: snow would slide over it"
			)
		var parked := street.get_node("ParkedCar")
		var on_layer := 0
		for node in parked.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).layers & StreetSnow.LAYER:
				on_layer += 1
		assert_gt(on_layer, 0, "car at the kerb does not catch snow")
	var snowy := ExitStreet.new()
	add_child_autofree(snowy)
	snowy.build(0.0, 0.0, 1, Weather.Kind.SNOW, TimeOfDay.Kind.DAY)
	var flakes := snowy.snow().flakes().process_material as ParticleProcessMaterial
	assert_eq(flakes.collision_mode, ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT)


## In snow the rotor raises snow dust: soft glowing puffs, within the deck in depth,
## not in front of the facade.
func test_the_rotor_lifts_snow_powder() -> void:
	var wash := Downwash.new()
	add_child_autofree(wash)
	wash.lift_snow(SnowLook.brightness(TimeOfDay.Kind.DAY))
	var look := (wash.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert_not_null(look.albedo_texture, "dust is squares")
	assert_eq(look.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "snow dust is grey")
	var process := wash.process_material as ParticleProcessMaterial
	assert_eq(process.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_BOX)
	assert_lte(process.emission_box_extents.z, 0.6, "dust spills past the deck towards the camera")
	# Straight up, Godot lays a flat fan in the YZ plane, toward the camera.
	assert_eq(process.flatness, 1.0)
	assert_ne(process.direction.z, 0.0, "dust fan points at the camera, not in the frame plane")
	assert_true(process.attractor_interaction_enabled, "dust ignores the flow")
	assert_eq(
		process.collision_mode,
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
		"the flow carries snow dust through the deck"
	)


## Otto walks over a snowy roof leaving a trail of footprints, and when released he does
## not stop in place but slides (decisions 2 and 4). On a dry roof he stops at once.
func test_otto_leaves_prints_and_slides_on_the_snowy_roof() -> void:
	for snowy: bool in [true, false]:
		GameState.instance().start_game()
		var level := LEVEL_SCENE.instantiate() as GreyboxLevel
		level.rules = BuildingRules.new()
		level.rules.forced_weather = Weather.Kind.SNOW if snowy else Weather.Kind.CLEAR
		level.building_seed = 1
		level.spawn_agents = false
		add_child_autofree(level)
		assert_true(await level.wait_for_the_landing(), "Otto did not land on the roof")
		var otto := level.otto
		Input.action_press(&"move_right")
		await wait_physics_frames(50)
		var walking := absf(otto.velocity.x)
		Input.action_release(&"move_right")
		await wait_physics_frames(1)
		var after := absf(otto.velocity.x)
		var scenery := level.get_node("Scenery") as BuildingScenery
		if snowy:
			assert_true(otto.icy, "Otto does not slide on the snowy deck")
			assert_gt(scenery.roof_snow().tracks().count(), 2, "no tracks behind Otto")
			assert_gt(after, walking * 0.5, "released on snow, he stopped dead")
			# Off the deck he thaws, and the tracks forget his stride (ADR-0060).
			var tracks := scenery.roof_snow().tracks()
			assert_eq(tracks.remembered(), 1, "the tracks do not follow Otto on the deck")
			var rules := level.rules
			otto.global_position = WorldSpace.to_scene(
				Vector2(level.plan().safe_x(rules, 3), rules.floor_surface(3))
			)
			await wait_physics_frames(3)
			assert_false(otto.icy, "Otto stays icy off the roof")
			assert_eq(tracks.remembered(), 0, "the tracks remember a walker off the deck")
		else:
			assert_false(otto.icy, "dry roof is slippery")
			assert_almost_eq(after, 0.0, 0.01, "Otto slips on a dry roof")
		level.queue_free()
		await wait_physics_frames(1)


## Outside in snow there is its own winter wind, on the floors the corridor silence;
## footsteps in snow and tires in slush are in the sound set (decision 5).
func test_snow_has_its_own_sound() -> void:
	var outside := Sounds.weather_loops(Weather.Kind.SNOW, true)
	assert_has(outside, Sounds.WIND_SNOW, "outside in snow it is not a blizzard")
	assert_does_not_have(outside, Sounds.WIND, "ordinary wind blows in snow")
	var inside := Sounds.weather_loops(Weather.Kind.SNOW, false)
	assert_does_not_have(inside, Sounds.WIND_SNOW, "the blizzard is audible in the corridor")
	for name: String in [Sounds.STEP_SNOW, Sounds.CAR_PASS_SLUSH, Sounds.WIND_SNOW]:
		assert_true(
			(
				ResourceLoader.exists("res://assets/audio/%s.wav" % name)
				or ResourceLoader.exists("res://assets/audio/%s.ogg" % name)
			),
			"no sound file %s" % name
		)


## The precipitation catcher follows the pose: a crouching one is covered by his own
## height, not by a column of a standing one's height (M24l code review).
func test_the_shelter_fits_the_pose() -> void:
	var body := Node3D.new()
	add_child_autofree(body)
	var shield := Shelter.over(body, Vector3(0.5, Proportions.BODY, 0.4))
	Shelter.fit(shield, Vector3(0.5, Proportions.CROUCH, 0.4))
	assert_almost_eq(
		shield.size.y, Proportions.CROUCH, 0.001, "crouching is covered to full height"
	)
	assert_almost_eq(
		shield.position.y, Proportions.CROUCH * 0.5, 0.001, "catcher is detached from the floor"
	)


## Rotor dust dies on the deck slab in any weather instead of going through the roof in
## front of the thirtieth floor.
func test_rotor_dust_stops_at_the_deck_in_any_weather() -> void:
	var wash := Downwash.new()
	add_child_autofree(wash)
	var process := wash.process_material as ParticleProcessMaterial
	assert_eq(process.collision_mode, ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT)
	var plate := wash.get_node_or_null("DeckPlate") as GPUParticlesCollisionBox3D
	assert_not_null(plate, "no deck plate under the dust")
	if plate != null:
		assert_lt(plate.position.y + plate.size.y * 0.5, 0.0, "plate above the deck")
