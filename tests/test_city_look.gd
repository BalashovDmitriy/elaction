extends GutTest

## Новый город M24j (ADR-0051, решения 10–12): фасады из запечённого атласа
## пака, небо — HDRI-панорама по времени и погоде, солнце неба там же, где свет.
##
## Правила — без сцены и на любом сиде; сцена — город на каждом сочетании.

const LAYOUT := "res://assets/textures/city/facade_layout.json"


func after_all() -> void:
	Weather.forced = -1
	GameState.instance().reset()


## Каждое сочетание времени и погоды получает панораму, и она на месте.
func test_every_time_and_weather_has_a_sky() -> void:
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var look := CitySky.look(time as TimeOfDay.Kind, weather as Weather.Kind)
			assert_true(ResourceLoader.exists(look.path), "нет панорамы %s" % look.path)
			assert_gt(CitySky.energy(time as TimeOfDay.Kind, weather as Weather.Kind), 0.0)


## Ночь темнее дня: небо и луна слабее солнца.
func test_night_is_darker_than_day() -> void:
	for weather: int in Weather.Kind.size():
		var kind := weather as Weather.Kind
		assert_lt(
			CitySky.energy(TimeOfDay.Kind.NIGHT, kind),
			CitySky.energy(TimeOfDay.Kind.DAY, kind),
			"погода %d: ночное небо не темнее дневного" % weather
		)
		var moon := CitySky.light(TimeOfDay.Kind.NIGHT, kind)
		var sun := CitySky.light(TimeOfDay.Kind.DAY, kind)
		assert_lt(moon.light_energy, sun.light_energy, "луна не слабее солнца")
		moon.free()
		sun.free()


## Солнце панорамы встаёт туда, откуда светит свет города: в направлении к
## солнцу шейдер неба читает панораму ровно на азимуте её солнца.
func test_the_sky_sun_sits_where_the_light_comes_from() -> void:
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var kind := time as TimeOfDay.Kind
			var look := CitySky.look(kind, weather as Weather.Kind)
			var sky := CitySky.material(kind, weather as Weather.Kind)
			var shift := float(sky.get_shader_parameter("shift"))
			var toward := TimeOfDay.sun_direction(kind)
			var u := fposmod(atan2(toward.x, -toward.z) / TAU + shift, 1.0)
			assert_almost_eq(u, look.azimuth / 360.0, 0.001, "время %d: солнце не на месте" % time)


## Свет города смотрит от солнца: он идёт туда, куда смотрит минус z лампы.
func test_the_city_light_points_away_from_the_sun() -> void:
	for time: int in TimeOfDay.Kind.size():
		var kind := time as TimeOfDay.Kind
		var light := CitySky.light(kind, Weather.Kind.CLEAR)
		var shine := -light.basis.z
		assert_almost_eq(shine.dot(-TimeOfDay.sun_direction(kind)), 1.0, 0.001)
		light.free()


## Стиль фасада — из стилей своего типа дома, на любом сиде.
func test_houses_take_styles_of_their_kind() -> void:
	for building_seed: int in [1, 2, 3, 5, 8]:
		for block in CityPlan.generate(building_seed, 0.0, 40.0):
			var custom := CityLook.building_custom(block)
			var style := int(custom.r)
			assert_has(CityLook.STYLES_OF[block.kind], style, "дом не своего стиля")
			assert_between(custom.g, 0.0, 1.0, "сид дома вне 0–1")


## Атлас, которым рисует игра, совпадает с тем, что собрал `build_city.py`.
func test_the_atlas_matches_its_build() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	assert_eq((layout["styles"] as Array).size(), CityLook.Style.size(), "стилей не столько")
	assert_eq(float(layout["density"]), CityLook.ATLAS_DENSITY)
	assert_eq(float(layout["tile_width"]), CityLook.TILE_WIDTH)
	var rows: Array = layout["rows"]
	var heights: Array[float] = [CityLook.ROW_TOP, CityLook.ROW_FLOOR, CityLook.ROW_GROUND]
	var total := 0.0
	for index in rows.size():
		assert_eq(float((rows[index] as Dictionary)["height"]), heights[index], "ряд %d" % index)
		total += heights[index]
	var albedo := load("res://assets/textures/city/facade_albedo.png") as Texture2D
	assert_eq(float(albedo.get_width()), CityLook.ATLAS_SIZE.x, "ширина атласа")
	assert_eq(float(albedo.get_height()), total * CityLook.ATLAS_DENSITY, "высота атласа")


## Город собирается на каждом сочетании: дома одним мультимешем на весь план,
## свет города в своём мире, днём горит меньше окон, чем ночью.
func test_the_city_builds_at_every_time() -> void:
	var rules := BuildingRules.new()
	var lit: Array[float] = []
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var city := CityBackdrop.new()
			add_child(city)
			city.build(rules, 1, weather as Weather.Kind, time as TimeOfDay.Kind)
			var houses := city.find_child("Buildings", true, false) as MultiMeshInstance3D
			assert_not_null(houses, "время %d, погода %d: домов нет" % [time, weather])
			if houses != null:
				var blocks := CityPlan.generate(1, 0.0, rules.width)
				assert_eq(houses.multimesh.instance_count, blocks.size(), "не все дома")
				if weather == Weather.Kind.CLEAR:
					var look := (houses.multimesh.mesh as BoxMesh).material as ShaderMaterial
					lit.append(float(look.get_shader_parameter("lit_share")))
			var lights := city.find_children("*", "DirectionalLight3D", true, false)
			assert_eq(lights.size(), 1, "у города не один свет неба")
			city.queue_free()
			await wait_physics_frames(1)
	assert_lt(lit[TimeOfDay.Kind.DAY], lit[TimeOfDay.Kind.NIGHT], "днём окон горит не меньше")
	assert_lt(lit[TimeOfDay.Kind.DAY], lit[TimeOfDay.Kind.EVENING], "днём окон горит не меньше")
