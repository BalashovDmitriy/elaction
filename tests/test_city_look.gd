extends GutTest

## The new M24j city (ADR-0051, decisions 10–12): facades from the pack's baked atlas, the sky is an
## HDRI panorama by time and weather, the sky's sun is where the light is.
##
## Rules — without a scene and on any seed; the scene — the city on every combination.

const LAYOUT := "res://assets/textures/city/facade_layout.json"


func after_all() -> void:
	GameState.instance().reset()


## Every combination of time and weather gets a panorama, and it is in place.
func test_every_time_and_weather_has_a_sky() -> void:
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var look := CitySky.look(time as TimeOfDay.Kind, weather as Weather.Kind)
			assert_true(ResourceLoader.exists(look.path), "no panorama %s" % look.path)
			assert_gt(CitySky.energy(time as TimeOfDay.Kind, weather as Weather.Kind), 0.0)


## Night is darker than day: the sky and the moon are weaker than the sun.
func test_night_is_darker_than_day() -> void:
	for weather: int in Weather.Kind.size():
		var kind := weather as Weather.Kind
		assert_lt(
			CitySky.energy(TimeOfDay.Kind.NIGHT, kind),
			CitySky.energy(TimeOfDay.Kind.DAY, kind),
			"weather %d: night sky is not darker than the day sky" % weather
		)
		var moon := CitySky.light(TimeOfDay.Kind.NIGHT, kind)
		var sun := CitySky.light(TimeOfDay.Kind.DAY, kind)
		assert_lt(moon.light_energy, sun.light_energy, "moon is not weaker than the sun")
		moon.free()
		sun.free()


## The panorama's sun rises where the city light comes from: in the direction toward the sun the sky
## shader reads the panorama exactly at the azimuth of its sun.
func test_the_sky_sun_sits_where_the_light_comes_from() -> void:
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var kind := time as TimeOfDay.Kind
			var look := CitySky.look(kind, weather as Weather.Kind)
			var sky := CitySky.material(kind, weather as Weather.Kind)
			var shift := float(sky.get_shader_parameter("shift"))
			var toward := TimeOfDay.sun_direction(kind)
			var u := fposmod(atan2(toward.x, -toward.z) / TAU + shift, 1.0)
			assert_almost_eq(u, look.azimuth / 360.0, 0.001, "time %d: sun is out of place" % time)


## The city light looks away from the sun: it goes where the lamp's minus z looks.
func test_the_city_light_points_away_from_the_sun() -> void:
	for time: int in TimeOfDay.Kind.size():
		var kind := time as TimeOfDay.Kind
		var light := CitySky.light(kind, Weather.Kind.CLEAR)
		var shine := -light.basis.z
		assert_almost_eq(shine.dot(-TimeOfDay.sun_direction(kind)), 1.0, 0.001)
		light.free()


## The facade style is from the styles of its own house kind, on any seed.
func test_houses_take_styles_of_their_kind() -> void:
	for building_seed: int in [1, 2, 3, 5, 8]:
		for block in CityPlan.generate(building_seed, 0.0, 40.0):
			var custom := CityLook.building_custom(block)
			var style := int(custom.r)
			assert_has(CityLook.STYLES_OF[block.kind], style, "house is not of its own style")
			assert_between(custom.g, 0.0, 1.0, "house seed outside 0-1")


## The atlas the game draws with matches what `build_city.py` assembled.
func test_the_atlas_matches_its_build() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	assert_eq((layout["styles"] as Array).size(), CityLook.Style.size(), "wrong number of styles")
	assert_eq(float(layout["density"]), CityLook.ATLAS_DENSITY)
	assert_eq(float(layout["tile_width"]), CityLook.TILE_WIDTH)
	var rows: Array = layout["rows"]
	var heights: Array[float] = [CityLook.ROW_TOP, CityLook.ROW_FLOOR, CityLook.ROW_GROUND]
	var total := 0.0
	for index in rows.size():
		assert_eq(float((rows[index] as Dictionary)["height"]), heights[index], "row %d" % index)
		total += heights[index]
	var albedo := load("res://assets/textures/city/facade_albedo.png") as Texture2D
	assert_eq(float(albedo.get_width()), CityLook.ATLAS_SIZE.x, "atlas width")
	# A style column is a tile plus margins on the sides: without margins the distant mip mixed
	# neighbouring styles and drew a line every 4 m (M24j code review).
	assert_eq(float(layout["gutter"]), CityLook.GUTTER, "column gutter")
	assert_gt(CityLook.GUTTER, 0.0, "atlas without gutters")
	var column := (CityLook.TILE_WIDTH + CityLook.GUTTER * 2.0) * CityLook.ATLAS_DENSITY
	assert_eq(CityLook.ATLAS_SIZE.x, column * CityLook.Style.size(), "columns with gutters")
	assert_eq(float(albedo.get_height()), total * CityLook.ATLAS_DENSITY, "atlas height")


## The city is assembled on every combination: houses as one multimesh for the whole plan, the city
## light in its own world, by day fewer windows are lit than at night.
func test_the_city_builds_at_every_time() -> void:
	var rules := BuildingRules.new()
	var lit: Array[float] = []
	for time: int in TimeOfDay.Kind.size():
		for weather: int in Weather.Kind.size():
			var city := CityBackdrop.new()
			add_child(city)
			city.build(rules, 1, weather as Weather.Kind, time as TimeOfDay.Kind)
			var houses := city.find_child("Buildings", true, false) as MultiMeshInstance3D
			assert_not_null(houses, "time %d, weather %d: no houses" % [time, weather])
			if houses != null:
				var blocks := CityPlan.generate(1, 0.0, rules.width)
				assert_eq(houses.multimesh.instance_count, blocks.size(), "not all houses")
				if weather == Weather.Kind.CLEAR:
					var look := (houses.multimesh.mesh as BoxMesh).material as ShaderMaterial
					lit.append(float(look.get_shader_parameter("lit_share")))
			var lights := city.find_children("*", "DirectionalLight3D", true, false)
			assert_eq(lights.size(), 1, "the city does not have exactly one sky light")
			city.queue_free()
			await wait_physics_frames(1)
	assert_lt(
		lit[TimeOfDay.Kind.DAY], lit[TimeOfDay.Kind.NIGHT], "windows lit by day are not fewer"
	)
	assert_lt(
		lit[TimeOfDay.Kind.DAY], lit[TimeOfDay.Kind.EVENING], "windows lit by day are not fewer"
	)
