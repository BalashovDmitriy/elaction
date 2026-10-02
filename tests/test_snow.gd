extends GutTest

## Снег — четвёртая погода (ADR-0054): хлопья гаснут о крышу по той же карте
## высот, что и дождь, покров лежит на всём, что смотрит вверх, а город — в
## снегопад. На любом времени суток.

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


## Погод четыре, и каждая — примерно на четверти зданий (решение 1).
func test_snow_falls_on_a_quarter_of_the_buildings() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for building_seed in range(1, 401):
		counts[Weather.of_seed(building_seed)] += 1
	for kind: int in Weather.Kind.size():
		assert_between(counts[kind], 70, 130, "погода %d: %d из 400" % [kind, counts[kind]])


## Хлопья гаснут о крышу, покров лежит сверху на слое крыши, дождя нет, и
## так в любое время суток.
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


## Город — в снегопад: слои хлопьев у камеры города, без шума частиц.
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


## На низком уровне снегопад города реже, как струи дождя: слои пересчитывает
## уровень качества.
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


## Ночью хлопья тусклее, чем днём: свой свет у снега — от города и ламп.
func test_flakes_are_dimmer_at_night() -> void:
	var night := SnowLook.brightness(TimeOfDay.Kind.NIGHT)
	var day := SnowLook.brightness(TimeOfDay.Kind.DAY)
	assert_lt(night, day, "ночной снег ярче дневного")


## Капли и хлопья гаснут о людей, машины и вертолёт, а не идут сквозь них
## ([Shelter]): у каждого тела свой ловец частиц.
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


## На улице выезда капли и хлопья гаснут о маркизы и мостовую по карте высот
## улицы; машины потока в ней не числятся, машина у бордюра — да.
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


## В снег винт поднимает снежную пыль: мягкие клубы, светящиеся, в пределах
## настила по глубине — не перед фасадом.
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
	# Ровно вверх Godot кладёт плоский веер в плоскость YZ — к камере.
	assert_eq(process.flatness, 1.0)
	assert_ne(process.direction.z, 0.0, "веер пыли — к камере, а не в плоскости кадра")
	assert_true(process.attractor_interaction_enabled, "пыль не слушает поток")
	assert_eq(
		process.collision_mode,
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
		"поток уносит снежную пыль сквозь настил"
	)


## Otto идёт по заснеженной крыше — за ним цепочка следов, а отпущенный он не
## встаёт на месте, а проскальзывает (решения 2 и 4). На сухой крыше — сразу.
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


## Снаружи в снег — свой зимний ветер, на этажах — тишина коридора; шаг по
## снегу и шины по каше — в наборе звуков (решение 5).
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


## Ловец осадков — по позе: присевший укрыт по своему росту, а не столбом в
## рост стоящего (авторевью M24l).
func test_the_shelter_fits_the_pose() -> void:
	var body := Node3D.new()
	add_child_autofree(body)
	var shield := Shelter.over(body, Vector3(0.5, Proportions.BODY, 0.4))
	Shelter.fit(shield, Vector3(0.5, Proportions.CROUCH, 0.4))
	assert_almost_eq(shield.size.y, Proportions.CROUCH, 0.001, "присевший укрыт в рост")
	assert_almost_eq(shield.position.y, Proportions.CROUCH * 0.5, 0.001, "ловец оторван от пола")


## Пыль от винта гаснет о плиту настила в любую погоду, а не уходит сквозь
## крышу перед тридцатым этажом.
func test_rotor_dust_stops_at_the_deck_in_any_weather() -> void:
	var wash := Downwash.new()
	add_child_autofree(wash)
	var process := wash.process_material as ParticleProcessMaterial
	assert_eq(process.collision_mode, ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT)
	var plate := wash.get_node_or_null("DeckPlate") as GPUParticlesCollisionBox3D
	assert_not_null(plate, "под пылью нет плиты настила")
	if plate != null:
		assert_lt(plate.position.y + plate.size.y * 0.5, 0.0, "плита выше настила")
