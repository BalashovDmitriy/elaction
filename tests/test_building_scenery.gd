extends GutTest

## Окружение здания (ADR-0029): погода и город по сиду, обстановка не мешает
## читаемости, скаты крыши — силуэт, а не пол.
##
## Раскладка обстановки и города — без сцены, на любом сиде. Сцена собирается
## один раз: у декора нет тел, и источников света он не добавляет.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5]


func after_all() -> void:
	GameState.instance().reset()


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


## Погода повторяется по сиду, и на тридцати зданиях выпадают все три.
func test_weather_follows_the_seed_and_varies() -> void:
	var seen: Dictionary = {}
	for building_seed: int in range(1, 31):
		var kind := Weather.of_seed(building_seed)
		assert_eq(
			Weather.of_seed(building_seed), kind, "сид %d: погода не повторилась" % building_seed
		)
		seen[kind] = true
	assert_eq(seen.size(), Weather.Kind.size(), "на тридцати зданиях выпала не всякая погода")


## Город повторяется по сиду и различается между сидами.
func test_the_city_follows_the_seed() -> void:
	var first := CityPlan.generate(1, 0.0, 40.0)
	var again := CityPlan.generate(1, 0.0, 40.0)
	var other := CityPlan.generate(2, 0.0, 40.0)
	assert_eq(_fingerprint(first), _fingerprint(again), "тот же сид — тот же город")
	assert_ne(_fingerprint(first), _fingerprint(other), "другой сид — другой город")


## Каждый ряд закрывает здание по ширине целиком: иначе в просвет между домами
## видна пустота, ради которой город и затевался.
func test_every_row_covers_the_building() -> void:
	var width := BuildingRules.new().width
	var blocks := CityPlan.generate(3, 0.0, width)
	for row: int in CityPlan.ROWS.size():
		var from := INF
		var to := -INF
		for block in blocks:
			if block.row != row:
				continue
			from = minf(from, block.x - block.width * 0.5)
			to = maxf(to, block.x + block.width * 0.5)
		assert_lt(from, 0.0, "ряд %d не доходит до левого края" % row)
		assert_gt(to, width, "ряд %d не доходит до правого края" % row)


## Горящие окна лежат на фасаде своего дома.
func test_lit_windows_stay_on_their_facade() -> void:
	for block in CityPlan.generate(5, 0.0, 30.0):
		var grid := CityPlan.window_grid(block)
		for window: Vector2i in block.lit:
			assert_between(window.x, 0, grid.x - 1, "окно за краем фасада по ширине")
			assert_between(window.y, 0, grid.y - 1, "окно за краем фасада по высоте")


## Обстановка не встаёт на место двери, лампы, шахты, эскалатора и выхода и
## не жмётся к глухой стене — на любом сиде и навыке.
func test_props_keep_off_doors_lamps_shafts_and_walls() -> void:
	var total := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var step := rules.slot_x(1) - rules.slot_x(0)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed)
			total += dressing.props.size()
			for prop in dressing.props:
				var where := (
					"навык %d, сид %d, этаж %d, x=%.1f"
					% [skill, building_seed, prop.floor_index, prop.x]
				)
				assert_gt(prop.floor_index, BuildingRules.ROOF, where + ": обстановка на крыше")
				assert_true(
					plan.safe_spots(rules, prop.floor_index).has(prop.x),
					where + ": предмет на шахте, эскалаторе или выходе"
				)
				for door in plan.doors:
					if door.floor_index == prop.floor_index:
						assert_gte(absf(door.x - prop.x), step * 0.5, where + ": на месте двери")
				for lamp in plan.lamps:
					if lamp.floor_index == prop.floor_index:
						assert_gte(absf(lamp.x - prop.x), step * 0.5, where + ": под лампой")
				# Нижнюю площадку эскалатора safe_spots не держит: на ней стоят.
				for escalator in plan.escalators:
					if escalator.floor_index + 1 == prop.floor_index:
						var landing := escalator.x + escalator.towards * rules.escalator_run
						assert_gte(
							absf(landing - prop.x), step * 0.5, where + ": на площадке эскалатора"
						)
				for wall in plan.walls:
					if wall.floor_index == prop.floor_index:
						assert_gte(
							absf(wall.x - prop.x),
							step * 0.5 + rules.inner_wall_width * 0.5,
							where + ": вплотную к стене"
						)
	assert_gt(total, 0, "ни одного предмета — проверять было нечего")


## Труба видна: висит ниже полосы, которую закрывает кромка перекрытия, и не
## проходит сквозь шахту, полотно эскалатора, вывеску и табличку этажа.
func test_pipes_show_below_the_slab_edge_and_skip_what_they_would_cover() -> void:
	var laid := 0
	var front := BuildingProps.pipe_z() + BuildingProps.PIPE_THICKNESS * 0.5
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed)
			for index: int in dressing.pipes:
				var where := "навык %d, сид %d, этаж %d" % [skill, building_seed, index]
				assert_gte(
					BuildingProps.pipe_top(rules, index),
					rules.story_top(index) + FloorSigns.hidden_band(front),
					where + ": труба за кромкой перекрытия"
				)
				var covered := _pipe_blockers(rules, plan, dressing, index)
				for span: Vector2 in BuildingProps.pipe_spans(rules, plan, dressing, index):
					laid += 1
					for blocker: Vector2 in covered:
						assert_true(
							span.y <= blocker.x + 0.001 or span.x >= blocker.y - 0.001,
							where + ": труба сквозь %s" % blocker
						)
	assert_gt(laid, 0, "ни одной трубы — проверять было нечего")


## Вывески обстановки не носят цвета огоньков игры: табло двери, двери с
## документом и выхода (ADR-0023, решение 6).
func test_neon_signs_do_not_wear_the_colours_of_game_signs() -> void:
	var reserved: Array[Color] = [
		GreyboxLook.SIGN_WARM, GreyboxLook.SIGN_RED, GreyboxLook.SIGN_GREEN
	]
	for neon: Color in BuildingProps.NEON:
		for sign_colour: Color in reserved:
			var gap := Vector3(
				neon.r - sign_colour.r, neon.g - sign_colour.g, neon.b - sign_colour.b
			)
			assert_gt(gap.length(), 0.3, "вывеска %s похожа на огонёк %s" % [neon, sign_colour])


## Скаты крыши внутри её стен, не заходят на машинное отделение и ниже его.
func test_roof_steps_frame_the_machine_room() -> void:
	var rules := _rules(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var shaft := plan.roof_shaft()
		var bounds := rules.floor_span(BuildingRules.ROOF)
		var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
		var surface := rules.floor_surface(BuildingRules.ROOF)
		var steps := BuildingRoof.steps(rules, plan)
		assert_gt(steps.size(), 0, "сид %d: скатов нет" % building_seed)
		for rect in steps:
			assert_gte(rect.position.x, bounds.x, "сид %d: скат за левой стеной" % building_seed)
			assert_lte(
				rect.end.x, bounds.y + 0.001, "сид %d: скат за правой стеной" % building_seed
			)
			assert_true(
				(
					rect.end.x <= shaft.x - half_room + 0.001
					or rect.position.x >= shaft.x + half_room - 0.001
				),
				"сид %d: скат заходит на машинное отделение" % building_seed
			)
			assert_almost_eq(
				rect.end.y, surface, 0.001, "сид %d: скат не стоит на настиле" % building_seed
			)
			assert_lte(
				rect.size.y,
				BuildingShafts.MACHINE_ROOM_SIZE.y,
				"сид %d: скат выше машинного отделения" % building_seed
			)


## У декора нет тел, а источников в окружении два — лампа над крышей и отсвет
## неоновой вывески (ADR-0031, решение 2): окна города, вывески этажей, огонь
## мачты светятся эмиссией и бюджет ламп кадра не трогают.
func test_scenery_adds_no_bodies_and_no_lights() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var scenery := level.get_node_or_null("Scenery")
	assert_not_null(scenery, "окружения нет")
	if scenery == null:
		remove_child(level)
		return
	var bodies := scenery.find_children("*", "CollisionObject3D", true, false)
	assert_eq(bodies.size(), 0, "у декора есть тела")
	var lights := scenery.find_children("*", "Light3D", true, false)
	assert_eq(lights.size(), 2, "в окружении не два источника света")
	assert_not_null(scenery.get_node_or_null("City"), "города нет")
	remove_child(level)


## Что труба на этаже обязана обходить, парами «левый край, правый край».
## Считается заново, а не берётся у [BuildingProps]: иначе тест проверял бы
## разрывы трубы ими же самими.
func _pipe_blockers(
	rules: BuildingRules, plan: BuildingPlan, dressing: BuildingDressing, index: int
) -> Array[Vector2]:
	var blockers: Array[Vector2] = []
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.top <= index and index <= shaft.bottom:
			blockers.append(Vector2(shaft.x - half, shaft.x + half))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == index:
			blockers.append(escalator.gap(rules))
	for prop in dressing.props:
		if prop.floor_index == index and prop.kind == BuildingDressing.Kind.SIGN:
			var reach := BuildingProps.SIGN.x * 0.5
			blockers.append(Vector2(prop.x - reach, prop.x + reach))
	var plate := FloorSigns.centre_on(rules, index).x
	var plate_half := Proportions.FLOOR_SIGN.x * 0.5
	blockers.append(Vector2(plate - plate_half, plate + plate_half))
	return blockers


func _fingerprint(blocks: Array[CityPlan.Block]) -> String:
	var parts := PackedStringArray()
	for block in blocks:
		parts.append("%d:%.2f:%.2f:%d" % [block.row, block.x, block.height, block.lit.size()])
	return "|".join(parts)


## Машина у выхода встаёт так, что по всей длине не задевает ни проём выхода, ни
## портал шахты (замечание пользователя на кадре гаража M20), ни внутреннюю
## стену, ни пролёт эскалатора, спускающегося в гараж, и стоит в стенах
## здания (авторевью M20).
func test_the_car_parks_clear_of_shafts_and_the_exit() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		var bottom := rules.floors - 1
		var bounds := rules.floor_span(bottom)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var x := ExitCar.spot(plan.exit_x, rules, plan)
			var car := Vector2(x - ExitCar.LENGTH * 0.5, x + ExitCar.LENGTH * 0.5)
			var label := "навык %d, сид %d" % [skill, building_seed]
			var exit_half := BuildingShell.EXIT_WIDTH * 0.5
			var exit := Vector2(plan.exit_x - exit_half, plan.exit_x + exit_half)
			_assert_apart(car, exit, "%s: машина на проёме выхода" % label)
			assert_between(
				x,
				bounds.x + BuildingShell.WALL_WIDTH + ExitCar.LENGTH * 0.5,
				bounds.y - BuildingShell.WALL_WIDTH - ExitCar.LENGTH * 0.5,
				"%s: машина в наружной стене" % label
			)
			for shaft in plan.shafts:
				if shaft.top > bottom or shaft.bottom < bottom:
					continue
				var shaft_half := rules.shaft_width * 0.5
				var column := Vector2(shaft.x - shaft_half, shaft.x + shaft_half)
				_assert_apart(car, column, "%s: машина перед шахтой x=%.1f" % [label, shaft.x])
			for wall in plan.walls:
				if wall.floor_index == bottom:
					_assert_apart(
						car, wall.band(rules), "%s: машина в стене x=%.1f" % [label, wall.x]
					)
			for escalator in plan.escalators:
				if escalator.floor_index != bottom - 1:
					continue
				var landing := escalator.x + escalator.towards * rules.escalator_run
				var gap := escalator.gap(rules)
				var run := Vector2(minf(gap.x, landing), maxf(gap.y, landing))
				_assert_apart(car, run, "%s: машина на эскалаторе x=%.1f" % [label, escalator.x])


## Отрезки [param a] и [param b] не перекрываются (касаться можно).
func _assert_apart(a: Vector2, b: Vector2, message: String) -> void:
	assert_true(a.y <= b.x + 0.001 or a.x >= b.y - 0.001, message)


## Седан стоит между задней стеной и телом Otto: в стену не входит и в плоскость
## игры не выходит, поэтому Otto проходит перед машиной, а не сквозь неё. Седан
## в полтора метра шириной заходил в обе стороны (авторевью M18c и M20).
func test_the_sedan_fits_between_the_wall_and_otto() -> void:
	var sedan: Node3D = autofree(CarModel.build())
	var back := INF
	var front := -INF
	for part: Node in sedan.get_children():
		var mesh := part as MeshInstance3D
		if mesh == null:
			continue
		var box := mesh.transform * mesh.mesh.get_aabb()
		back = minf(back, box.position.z)
		front = maxf(front, box.end.z)
	assert_gt(ExitCar.Z + back, WorldSpace.BACK_WALL_Z, "машина входит в заднюю стену")
	assert_lt(
		ExitCar.Z + front,
		WorldSpace.PLAY_Z - WorldSpace.BODY_DEPTH * 0.5,
		"машина выходит в плоскость игры — Otto пройдёт сквозь неё"
	)


## Стенки кабины стоят на её полу и доходят до крыши. Пол — в нуле кабины, плита
## под ним: стенки, отсчитанные от верха плиты, висели на 18 см выше пола
## (авторевью M20).
func test_the_cabin_walls_stand_on_its_floor() -> void:
	var scene := load("res://src/systems/elevators/elevator_car.tscn") as PackedScene
	var car := scene.instantiate() as ElevatorCar
	add_child_autofree(car)
	car.fit_to_story(Proportions.CLEARANCE, Proportions.SHAFT)
	var half_slab := ElevatorCar.SLAB_THICKNESS * 0.5
	var floor_top := (car.get_node("FloorVisual") as Node3D).position.y + half_slab
	var roof_bottom := (car.get_node("RoofVisual") as Node3D).position.y - half_slab
	var lowest := INF
	var highest := -INF
	for part: Node in car._detail._body.get_children():
		var mesh := part as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
		highest = maxf(highest, box.end.y)
	assert_almost_eq(lowest, floor_top, 0.01, "стенки кабины висят над её полом")
	assert_almost_eq(highest, roof_bottom, 0.01, "стенки кабины не доходят до крыши")
	remove_child(car)


## Уровень качества доходит до здания, которое уже стоит, а не со следующего
## (ADR-0030, решение 5): отражения, контактные тени и туман воздуха здания.
func test_quality_reaches_the_building_already_standing() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var air := (level.get_node("Scenery/Air") as WorldEnvironment).environment
	Graphics.broadcast(Graphics.Quality.LOW)
	var low: Array[bool] = [air.ssr_enabled, air.ssao_enabled, air.volumetric_fog_enabled]
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_eq(low, [false, false, false] as Array[bool], "низкое качество не дошло до воздуха")
	assert_true(air.ssr_enabled, "высокое качество не вернуло отражения")
	remove_child(level)


## Этаж выхода — гараж: дверей на нём нет ни на одном сиде и навыке, как в
## подвале оригинала (ADR-0031, решение 4).
func test_the_exit_floor_is_a_garage_without_doors() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		assert_eq(rules.doors_on(rules.floors - 1), 0, "навык %d: гараж с дверями" % skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for door in plan.doors:
				assert_ne(
					door.floor_index,
					rules.floors - 1,
					"навык %d, сид %d: дверь в гараже" % [skill, building_seed]
				)


## Техника крыши стоит внутри её стен (вывеска — по ширине щита вокруг середины).
func test_roof_kit_stays_on_the_roof() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 2
	add_child_autofree(level)
	var kit := level.get_node_or_null("Scenery/RoofKit")
	assert_not_null(kit, "техники крыши нет")
	if kit == null:
		return
	var bounds := level.rules.floor_span(BuildingRules.ROOF)
	var parts := kit.find_children("*", "VisualInstance3D", true, false)
	assert_gt(parts.size(), 10, "на крыше почти ничего не стоит")
	for part: Node in parts:
		var x := (part as Node3D).global_position.x
		assert_between(
			x, bounds.x - 0.1, bounds.y + 0.1, "деталь крыши за её стенами: %s" % part.name
		)
	remove_child(level)


## Противовес ходит навстречу кабине: кабина внизу — он наверху.
func test_the_counterweight_goes_against_the_car() -> void:
	var detail: CarDetail = autofree(CarDetail.new())
	add_child(detail)
	detail.build(1.8, 3.0)
	detail.hang_cables(0.0, 20.0, 23.0)
	detail.follow(0.0, 5.0)
	var weight := detail._weight.global_position.y
	detail.follow(20.0, 5.0)
	assert_gt(weight, detail._weight.global_position.y, "кабина поднялась — противовес опустился")
	# Выше верха шахты противовес не идёт: у шахты на крышу верх — в машинном
	# отделении, а не над потолком верхней остановки (авторевью M20).
	detail.set_top(21.0)
	detail.follow(0.0, 5.0)
	var weight_top := detail._weight.global_position.y + CarDetail.WEIGHT.y * 0.5
	assert_lte(weight_top, 21.0 + 0.001, "противовес выше верха шахты")
	remove_child(detail)


## Кровь, выключенная в настройках, не брызгает вовсе.
func test_blood_respects_the_setting() -> void:
	var host: Node3D = autofree(Node3D.new())
	add_child(host)
	Blood.enabled = false
	Blood.spray(host, Vector3.ZERO, 1.0)
	assert_eq(host.get_child_count(), 0, "выключенная кровь брызнула")
	Blood.enabled = true
	Blood.spray(host, Vector3.ZERO, 1.0)
	assert_eq(host.get_child_count(), 1, "включённая кровь не брызнула")
	remove_child(host)


## Сбитая лампа выбрасывает искры в точке попадания, и они остаются там, пока
## лампа падает (ADR-0031, решение 3а).
func test_a_shot_lamp_throws_sparks() -> void:
	var host: Node3D = autofree(Node3D.new())
	add_child(host)
	var lamp := (load("res://src/systems/lighting/lamp.tscn") as PackedScene).instantiate() as Lamp
	host.add_child(lamp)
	lamp.shoot_down()
	var sparks := host.find_children("*", "Sparks", false, false)
	assert_eq(sparks.size(), 1, "искр нет или больше одного выброса")
	remove_child(host)
