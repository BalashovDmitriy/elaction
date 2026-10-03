extends GutTest

## Time of day for everything that stayed night-only in M24j (ADR-0052): music and the
## outdoor ambience, the building sign, the room behind the door, the exit street and
## its traffic.
##
## The time of day falls to the building by a draw, so every rule is checked at all
## four times, and the street and traffic — on several seeds as well.

const LEFT: float = 0.0
const STREET: float = 40.0
const SEEDS: Array[int] = [1, 2, 3, 7]


func _times() -> Array[TimeOfDay.Kind]:
	var all: Array[TimeOfDay.Kind] = []
	for kind: int in TimeOfDay.Kind.size():
		all.append(kind as TimeOfDay.Kind)
	return all


func _rules(time: TimeOfDay.Kind) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.time_of_day = time
	return rules


## The building theme is its own for each time of day, at night — the old noir; each
## theme has files, and morning, day and evening have two or more tracks for the draw.
func test_each_time_of_day_has_its_own_theme() -> void:
	var themes: Array[String] = []
	for time: TimeOfDay.Kind in _times():
		var theme := Sounds.theme_for(time)
		assert_false(themes.has(theme), "тема %s уже у другого времени" % theme)
		themes.append(theme)
		var tracks := Sounds.variants(theme).size()
		if TimeOfDay.is_night(time):
			assert_eq(theme, Sounds.THEME, "ночью — прежняя тема")
		else:
			# In the daytime the hotel has three tracks since M24o (ADR-0057, decision 7).
			assert_gte(tracks, 2, "%s: два трека и больше на жребий" % theme)
		assert_true(Sounds.LOOPED.has(theme), "%s звучит петлёй" % theme)


## The outdoor ambience is its own per time of day, at night — the old city; inside the
## building the time of day does not change the ambience.
func test_the_street_sounds_by_the_time_of_day() -> void:
	var streets: Array[String] = []
	for time: TimeOfDay.Kind in _times():
		var outside := Sounds.weather_loops(Weather.Kind.CLEAR, true, time)
		var city := Sounds.city_for(time)
		assert_true(outside.has(city), "снаружи звучит %s" % city)
		assert_false(streets.has(city), "%s уже у другого времени" % city)
		streets.append(city)
		assert_eq(
			Sounds.weather_loops(Weather.Kind.CLEAR, false, time),
			Sounds.weather_loops(Weather.Kind.CLEAR, false),
			"внутри фон от времени не зависит"
		)
	assert_eq(Sounds.city_for(TimeOfDay.Kind.NIGHT), Sounds.CITY, "ночью — прежний город")


## Building sign: in the morning and daytime the neon is off — does not glow, hum or
## blink; in the evening and at night it is lit.
func test_the_building_sign_is_dark_by_day() -> void:
	for time: TimeOfDay.Kind in _times():
		var board := VerticalSign.new()
		add_child_autofree(board)
		board.hang(_rules(time), BuildingIdentity.new())
		var lit := board.is_lit()
		assert_eq(lit, not TimeOfDay.is_daytime(time), "время %d: горит ли вывеска" % time)
		var glows := board.find_children("NeonGlow", "OmniLight3D", true, false).size()
		var buzz := board.find_children("*", "AudioStreamPlayer3D", true, false).size()
		assert_eq(glows, 1 if lit else 0, "время %d: отсвет неона" % time)
		assert_eq(buzz, 1 if lit else 0, "время %d: гудение неона" % time)
		assert_eq(board.text().is_empty(), false, "время %d: буквы на месте" % time)


## The room behind the door: in the daytime — sun from the window and the light off, in
## the evening and at night — room light, as in M24i; on a dark floor at night — neither.
func test_the_room_behind_the_door_follows_the_daylight() -> void:
	for time: TimeOfDay.Kind in _times():
		for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
			var room := DoorRoom.build(
				kind, 17, null, Vector2(-INF, INF), false, time, Weather.Kind.CLEAR
			)
			autofree(room)
			var sun := room.find_children("WindowSun", "SpotLight3D", true, false).size()
			var lamp := room.find_children("RoomLight", "OmniLight3D", true, false).size()
			var glow := room.find_children("LampGlow", "OmniLight3D", true, false).size()
			var day := TimeOfDay.is_daytime(time)
			var tag := "время %d, тип %d" % [time, kind]
			assert_eq(sun, 1 if day else 0, "%s: солнце из окна" % tag)
			assert_eq(lamp, 0 if day else 1, "%s: свет комнаты" % tag)
			if day:
				assert_eq(glow, 0, "%s: лампа на тумбе погашена" % tag)
	var dark := DoorRoom.build(
		BuildingIdentity.Kind.HOTEL, 17, null, Vector2(-INF, INF), true, TimeOfDay.Kind.NIGHT
	)
	autofree(dark)
	assert_eq(dark.find_children("*", "Light3D", true, false).size(), 0, "тёмный этаж без света")


## The exit street on any seed and at any time: houses with the pack facade, lights lit
## by time of day, no light sources in clear daytime, traffic headlights off in clear
## daytime and on in rain.
func test_the_exit_street_lights_by_the_time_of_day() -> void:
	for building_seed: int in SEEDS:
		for time: TimeOfDay.Kind in _times():
			for weather: Weather.Kind in [Weather.Kind.CLEAR, Weather.Kind.RAIN]:
				var street := ExitStreet.new()
				add_child_autofree(street)
				street.build(LEFT, STREET, building_seed, weather, time)
				var tag := "сид %d, время %d, погода %d" % [building_seed, time, weather]
				var lights := TimeOfDay.street_lights(time, weather)
				assert_eq(street.is_lit(), lights > ExitStreet.LIGHTS_ON, "%s: огни" % tag)
				assert_eq(
					street.find_children("PackFacades", "MultiMeshInstance3D", true, false).size(),
					1,
					"%s: дома фасадом пака" % tag
				)
				if not street.is_lit():
					assert_eq(street.lights().size(), 0, "%s: днём источников нет" % tag)
				assert_eq(street.traffic().headlights, lights > 0.0, "%s: фары потока" % tag)
				remove_child(street)


## Traffic density is the building's draw, but the time shifts its shares: in the
## daytime a dense street comes up more often than at night.
func test_the_day_street_is_busier_than_the_night_one() -> void:
	var heavy := {}
	for time: TimeOfDay.Kind in [TimeOfDay.Kind.DAY, TimeOfDay.Kind.NIGHT]:
		var count := 0
		for building_seed: int in 400:
			if StreetTraffic.density_for(building_seed, time) == StreetTraffic.Density.HEAVY:
				count += 1
		heavy[time] = count
	assert_gt(int(heavy[TimeOfDay.Kind.DAY]), int(heavy[TimeOfDay.Kind.NIGHT]) * 2, "днём плотнее")
	for odds: Array in StreetTraffic.DENSITY_ODDS:
		var total := 0.0
		for share: float in odds:
			total += share
		assert_almost_eq(total, 1.0, 0.001, "доли плотности складываются в единицу")


## The room window is an opening in the back wall (ADR-0052, decision 5): the wall does
## not cover it, the glass is transparent, and while the room is open the city behind
## the building is drawn — that is what is seen in the window.
func test_the_room_window_opens_onto_the_city() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var room := DoorRoom.build(kind, 23)
		var before := DoorRoom.open_count
		add_child_autofree(room)
		assert_eq(DoorRoom.open_count, before + 1, "открытая комната на счету")
		var pane := room.find_child("Window", true, false) as MeshInstance3D
		assert_not_null(pane, "окно есть")
		if pane == null:
			continue
		var glass := pane.mesh.surface_get_material(0) as ShaderMaterial
		assert_eq(glass.shader.get_mode(), Shader.MODE_SPATIAL, "стекло — свой шейдер")
		assert_string_contains(glass.shader.code, "ALPHA", "стекло прозрачное")
		var opening := pane.global_transform * pane.mesh.get_aabb()
		var middle := opening.get_center()
		for node: Node in room.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			if part == pane or part.mesh == null:
				continue
			var box := part.global_transform * part.mesh.get_aabb()
			var behind := box.end.z <= opening.position.z + 0.001
			var covers := box.has_point(Vector3(middle.x, middle.y, box.get_center().z))
			assert_false(behind and covers, "%s закрывает окно" % part.name)
		remove_child(room)
		assert_eq(DoorRoom.open_count, before, "закрытая — снята со счёта")
		room.queue_free()
