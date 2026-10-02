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
	assert_true(process.attractor_interaction_enabled, "пыль не слушает поток")
