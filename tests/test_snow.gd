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
		assert_between(counts[kind], 70, 130, "погода %d: %d из 400" % [kind, counts[kind]])


## Flakes die on the roof, the cover lies on top on the roof layer, there is no rain, and
## so at any time of day.
func test_the_roof_is_snowed_at_every_time() -> void:
	for time: int in TimeOfDay.Kind.size():
		var level := _snowy(time as TimeOfDay.Kind)
		var scenery := level.get_node("Scenery") as BuildingScenery
		assert_null(scenery.roof_rain(), "в снег идёт дождь")
		var snow := scenery.roof_snow()
		assert_not_null(snow, "время %d: снега над крышей нет" % time)
		if snow == null:
			continue
		var process := snow.flakes().process_material as ParticleProcessMaterial
		assert_eq(
			process.collision_mode,
			ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
			"хлопья гаснут по таймеру, а не о крышу"
		)
		assert_false(process.turbulence_enabled, "шум частиц держит хлопья у неба")
		assert_eq(snow.catcher().heightfield_mask, RoofCatch.LAYER, "карта высот не с крыши")
		var cover := snow.cover()
		assert_eq(cover.cull_mask, RoofCatch.LAYER, "покров ложится не только на крышу")
		assert_gt(cover.normal_fade, 0.0, "покров ложится и на стены")
		var marked := 0
		for node in level.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).layers & RoofCatch.LAYER:
				marked += 1
		assert_gt(marked, 10, "на слое крыши почти ничего: покрову не на что лечь")
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
		assert_false(process.turbulence_enabled, "шум частиц держит хлопья у неба")
		layers += 1
	assert_eq(layers, SnowLook.CITY_LAYERS.size(), "слоёв снегопада в городе")


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
	assert_false(layers.is_empty(), "в городе нет снегопада")
	for node in layers:
		var layer := node as GPUParticles3D
		assert_lt(
			layer.amount,
			int(layer.get_meta(RainLook.FULL)),
			"%s на низком в полную силу" % layer.name
		)


## At night flakes are dimmer than by day: snow's own light comes from the city and lamps.
func test_flakes_are_dimmer_at_night() -> void:
	var night := SnowLook.brightness(TimeOfDay.Kind.NIGHT)
	var day := SnowLook.brightness(TimeOfDay.Kind.DAY)
	assert_lt(night, day, "ночной снег ярче дневного")


## Drops and flakes die on people, cars and the helicopter instead of going through them
## ([Shelter]): each body has its own particle catcher.
func test_bodies_shelter_from_rain_and_snow() -> void:
	var otto := preload("res://src/actors/otto/otto.tscn").instantiate() as Otto
	add_child_autofree(otto)
	var agent := preload("res://src/actors/enemy/enemy.tscn").instantiate() as Enemy
	add_child_autofree(agent)
	for body: Node3D in [otto, agent]:
		var shield := body.get_node_or_null("Shelter") as GPUParticlesCollisionBox3D
		assert_not_null(shield, "%s без ловца: дождь идёт сквозь него" % body.name)
		if shield != null:
			assert_almost_eq(shield.size.y, Proportions.BODY, 0.01, "ловец не в рост")
	var car := CarModel.build()
	autofree(car)
	assert_not_null(car.get_node_or_null("Shelter"), "у машины нет ловца")
	var helicopter := Helicopter.new()
	add_child_autofree(helicopter)
	var hull := helicopter.find_child("Shelter", true, false) as GPUParticlesCollisionBox3D
	assert_not_null(hull, "у вертолёта нет ловца")
	if hull != null:
		assert_lt(hull.size.x, 9.0, "ловец вертолёта во весь винт — под ним сухая коробка")


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
		assert_not_null(catcher, "погода %d: улица не ловит осадки" % weather)
		if catcher == null:
			continue
		assert_eq(catcher.heightfield_mask, StreetSnow.LAYER)
		for node in street.traffic().find_children("*", "GeometryInstance3D", true, false):
			assert_eq(
				(node as GeometryInstance3D).layers & StreetSnow.LAYER,
				0,
				"машина потока в карте высот: по ней снег скользил бы"
			)
		var parked := street.get_node("ParkedCar")
		var on_layer := 0
		for node in parked.find_children("*", "GeometryInstance3D", true, false):
			if (node as GeometryInstance3D).layers & StreetSnow.LAYER:
				on_layer += 1
		assert_gt(on_layer, 0, "машина у бордюра не ловит снег")
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
	assert_not_null(look.albedo_texture, "пыль — квадратами")
	assert_eq(look.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "снежная пыль серая")
	var process := wash.process_material as ParticleProcessMaterial
	assert_eq(process.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_BOX)
	assert_lte(process.emission_box_extents.z, 0.6, "пыль выходит за настил к камере")
	# Straight up, Godot lays a flat fan in the YZ plane, toward the camera.
	assert_eq(process.flatness, 1.0)
	assert_ne(process.direction.z, 0.0, "веер пыли — к камере, а не в плоскости кадра")
	assert_true(process.attractor_interaction_enabled, "пыль не слушает поток")
	assert_eq(
		process.collision_mode,
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
		"поток уносит снежную пыль сквозь настил"
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
		assert_true(await level.wait_for_the_landing(), "Otto не встал на крышу")
		var otto := level.otto
		Input.action_press(&"move_right")
		await wait_physics_frames(50)
		var walking := absf(otto.velocity.x)
		Input.action_release(&"move_right")
		await wait_physics_frames(1)
		var after := absf(otto.velocity.x)
		var scenery := level.get_node("Scenery") as BuildingScenery
		if snowy:
			assert_true(otto.icy, "на заснеженном настиле Otto не скользит")
			assert_gt(scenery.roof_snow().tracks().count(), 2, "за Otto нет следов")
			assert_gt(after, walking * 0.5, "отпущенный на снегу встал как вкопанный")
		else:
			assert_false(otto.icy, "сухая крыша скользкая")
			assert_almost_eq(after, 0.0, 0.01, "на сухой крыше Otto проскальзывает")
		level.queue_free()
		await wait_physics_frames(1)


## Outside in snow there is its own winter wind, on the floors the corridor silence;
## footsteps in snow and tires in slush are in the sound set (decision 5).
func test_snow_has_its_own_sound() -> void:
	var outside := Sounds.weather_loops(Weather.Kind.SNOW, true)
	assert_has(outside, Sounds.WIND_SNOW, "в снег снаружи не метель")
	assert_does_not_have(outside, Sounds.WIND, "в снег дует обычный ветер")
	var inside := Sounds.weather_loops(Weather.Kind.SNOW, false)
	assert_does_not_have(inside, Sounds.WIND_SNOW, "метель слышна в коридоре")
	for name: String in [Sounds.STEP_SNOW, Sounds.CAR_PASS_SLUSH, Sounds.WIND_SNOW]:
		assert_true(
			(
				ResourceLoader.exists("res://assets/audio/%s.wav" % name)
				or ResourceLoader.exists("res://assets/audio/%s.ogg" % name)
			),
			"нет файла звука %s" % name
		)


## The precipitation catcher follows the pose: a crouching one is covered by his own
## height, not by a column of a standing one's height (M24l code review).
func test_the_shelter_fits_the_pose() -> void:
	var body := Node3D.new()
	add_child_autofree(body)
	var shield := Shelter.over(body, Vector3(0.5, Proportions.BODY, 0.4))
	Shelter.fit(shield, Vector3(0.5, Proportions.CROUCH, 0.4))
	assert_almost_eq(shield.size.y, Proportions.CROUCH, 0.001, "присевший укрыт в рост")
	assert_almost_eq(shield.position.y, Proportions.CROUCH * 0.5, 0.001, "ловец оторван от пола")


## Rotor dust dies on the deck slab in any weather instead of going through the roof in
## front of the thirtieth floor.
func test_rotor_dust_stops_at_the_deck_in_any_weather() -> void:
	var wash := Downwash.new()
	add_child_autofree(wash)
	var process := wash.process_material as ParticleProcessMaterial
	assert_eq(process.collision_mode, ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT)
	var plate := wash.get_node_or_null("DeckPlate") as GPUParticlesCollisionBox3D
	assert_not_null(plate, "под пылью нет плиты настила")
	if plate != null:
		assert_lt(plate.position.y + plate.size.y * 0.5, 0.0, "плита выше настила")
