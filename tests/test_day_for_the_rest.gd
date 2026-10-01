extends GutTest

## Время суток для всего, что в M24j осталось ночным (ADR-0052): музыка и фон
## снаружи, вывеска здания, комната за дверью, улица у выезда и её поток.
##
## Время суток выпадает зданию жребием, поэтому каждое правило проверяется на
## всех четырёх временах, а улица и поток — ещё и на нескольких сидах.

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


## Тема здания своя у каждого времени суток, ночью — прежний нуар; у каждой
## темы есть файлы, и у утра, дня и вечера — по два трека на жребий.
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
			assert_eq(tracks, 2, "%s: два трека на жребий" % theme)
		assert_true(Sounds.LOOPED.has(theme), "%s звучит петлёй" % theme)


## Фон снаружи — свой на время суток, ночью — прежний город; внутри здания
## время суток фон не меняет.
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


## Вывеска здания: утром и днём неон погашен — не светит, не гудит, не мигает;
## вечером и ночью горит.
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


## Комната за дверью: днём — солнце из окна и погашенный свет, вечером и
## ночью — свет комнаты, как в M24i; на тёмном этаже ночью — ни того, ни другого.
func test_the_room_behind_the_door_follows_the_daylight() -> void:
	for time: TimeOfDay.Kind in _times():
		for is_hotel: bool in [true, false]:
			var room := DoorRoom.build(
				is_hotel, 17, null, Vector2(-INF, INF), false, time, Weather.Kind.CLEAR
			)
			autofree(room)
			var sun := room.find_children("WindowSun", "SpotLight3D", true, false).size()
			var lamp := room.find_children("RoomLight", "OmniLight3D", true, false).size()
			var glow := room.find_children("LampGlow", "OmniLight3D", true, false).size()
			var day := TimeOfDay.is_daytime(time)
			var tag := "время %d, %s" % [time, "отель" if is_hotel else "офис"]
			assert_eq(sun, 1 if day else 0, "%s: солнце из окна" % tag)
			assert_eq(lamp, 0 if day else 1, "%s: свет комнаты" % tag)
			if day:
				assert_eq(glow, 0, "%s: лампа на тумбе погашена" % tag)
	var dark := DoorRoom.build(true, 17, null, Vector2(-INF, INF), true, TimeOfDay.Kind.NIGHT)
	autofree(dark)
	assert_eq(dark.find_children("*", "Light3D", true, false).size(), 0, "тёмный этаж без света")


## Улица у выезда на любом сиде и в любое время: дома — фасадом пака, огни горят
## по времени суток, днём в ясную источников нет, фары потока днём в ясную
## погашены, а в дождь горят.
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


## Плотность потока — жребий здания, но время сдвигает его доли: днём плотная
## улица выпадает чаще, чем ночью.
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


## Окно комнаты — проём в задней стене (ADR-0052, решение 5): стена его не
## закрывает, стекло прозрачное, и пока комната открыта, город за зданием
## рисуется — он и виден в окне.
func test_the_room_window_opens_onto_the_city() -> void:
	for is_hotel: bool in [true, false]:
		var room := DoorRoom.build(is_hotel, 23)
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
