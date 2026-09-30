extends Node3D

## Замер кадра под светом M17: настоящее здание, агенты, три лампы в кадре.
##
## Отвечает на один вопрос ADR-0023 (решение 7): укладывается ли воздух —
## отражения, туман, свечение — и конусы ламп в бюджет кадра. Меряется время
## GPU на кадр, а не дельта процесса: дельта считает и ожидание вертикальной
## синхронизации, и физику, и к свету отношения не имеет.
##
## Рендер настоящий, не headless — нужен экран. Число пишется в STATUS.
##
## С M22 — и по всему зданию (ADR-0030, решение 6): `--whole` ставит Otto на
## каждый этаж от крыши до гаража на каждом уровне качества и пишет средний и
## худший кадр уровня, с этажом, где худший случился.
##
## Запуск:
##     godot --path . res://tools/light_bench.tscn
##     godot --path . res://tools/light_bench.tscn -- --whole
##     godot --path . res://tools/light_bench.tscn -- --whole --seed=2
##     godot --path . res://tools/light_bench.tscn -- --garage --x=16
##     godot --path . res://tools/light_bench.tscn -- --floors --quality=3 --native
##     godot --path . res://tools/light_bench.tscn -- --shot=screens/bench.png --index=15
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --native
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --corpses=40
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --timeline
##
## `--floors` (M24f) — таблица по этажам на одном уровне (`--quality=`, по
## умолчанию «Ультра»): GPU и CPU рендера, полный кадр, источники с тенью и
## вызовы отрисовки — видно, что растёт к низу здания. `--native` — окно без
## рамки во весь экран, в родном разрешении, как у игрока в полном экране.
##
## Сид по умолчанию — 1, туман. Дождь (M24a) меряется на сиде 2.
##
## `--garage` (M24b) меряет нижний этаж — паркинг со светильниками и чужими
## машинами; `--x=` ставит Otto в нужную точку этажа, иначе — на безопасное
## место, как на широком этаже.
##
## `--exit=` (M24b) ставит кадр выезда: середина кадра — на столько метров правее
## левого торца здания, как у [method ExitBoarding.exit_frame]; `--lift=` —
## насколько низ кадра поднят над низом здания, м, как у кадра, едущего за
## машиной по пандусу. С ними Otto ставится в паркинг сам:
##     godot --path . res://tools/light_bench.tscn -- --exit=3.5
##     godot --path . res://tools/light_bench.tscn -- --exit=-9.45 --lift=3.6

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько шагов физики дать зданию собраться, агентам выйти и свету
## устояться. Шаги физики, а не кадры: без вертикальной синхронизации кадр
## идёт миллисекунду, и двери за сто кадров не успели бы открыться.
const SETTLE_STEPS: int = 240
## Сколько кадров мерить.
const MEASURE_FRAMES: int = 240
## Бюджет кадра, мс: 60 кадров в секунду.
const BUDGET_MS: float = 16.6
## По всему зданию: сколько кадров дать этажу устояться и сколько мерить.
const FLOOR_SETTLE: int = 20
const FLOOR_FRAMES: int = 30

## Кадр выезда (`--exit=`), в плоскости правил; пустой — кадр по Otto.
var _exit_bounds := Rect2()


func _ready() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	if level == null:
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return
	level.rules = BuildingRules.new()
	level.building_seed = 1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			level.building_seed = argument.trim_prefix("--seed=").to_int()
	add_child(level)

	# Не крыша, а широкий этаж: три лампы, двери с табло и агенты у них —
	# самый дорогой кадр здания.
	if OS.get_cmdline_user_args().has("--whole"):
		_run_whole(level)
		return
	if OS.get_cmdline_user_args().has("--floors"):
		_run_floors(level)
		return
	if OS.get_cmdline_user_args().has("--probe"):
		_run_probe(level)
		return
	var index := level.rules.floors - 3
	var x := NAN
	var exit_shift := NAN
	var lift := 0.0
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--garage":
			index = level.rules.floors - 1
		elif argument.begins_with("--x="):
			x = argument.trim_prefix("--x=").to_float()
		elif argument.begins_with("--exit="):
			exit_shift = argument.trim_prefix("--exit=").to_float()
			index = level.rules.floors - 1
		elif argument.begins_with("--lift="):
			lift = argument.trim_prefix("--lift=").to_float()
		elif argument.begins_with("--index="):
			index = argument.trim_prefix("--index=").to_int()
	if is_nan(x):
		x = level.plan().safe_x(level.rules, index)
	level.otto.global_position = WorldSpace.to_scene(Vector2(x, level.rules.floor_surface(index)))
	if not is_nan(exit_shift):
		var rules := level.rules
		var centre := rules.floor_span(rules.floors - 1).x + exit_shift
		_exit_bounds = Rect2(centre - 0.5, 0.0, 1.0, rules.total_height() - lift)
	_run(level)


## Всё здание на каждом уровне качества: худший кадр — этаж, где он случился.
func _run_whole(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# Город рисуется своим видом (ADR-0029): его кадр меряется отдельно и
	# прибавляется — в замере корневого окна его нет (M24a).
	var city := level.get_node_or_null("Scenery/City/CityView") as SubViewport
	var city_rid := city.get_viewport_rid() if city != null else RID()
	if city_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(city_rid, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	level.spawn_agents = false
	var rules := level.rules
	var failed := false
	for quality: int in Graphics.Quality.size():
		Graphics.broadcast(quality as Graphics.Quality)
		# Шейдеры уровня компилируются на первых кадрах: их не меряем.
		for _frame in 60:
			await get_tree().process_frame
		var total := 0.0
		var samples := 0
		var worst := 0.0
		var worst_floor := 0
		# Крыша — отдельной строкой: на ней город, погода и дождь (M24a), и в
		# среднем по тридцати этажам она тонет.
		var roof := 0.0
		for index in range(BuildingRules.ROOF, rules.floors):
			level.otto.global_position = WorldSpace.to_scene(
				Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
			)
			for _frame in FLOOR_SETTLE:
				await get_tree().process_frame
			for _frame in FLOOR_FRAMES:
				await get_tree().process_frame
				var spent := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				if (
					city_rid.is_valid()
					and city.render_target_update_mode != SubViewport.UPDATE_DISABLED
				):
					spent += RenderingServer.viewport_get_measured_render_time_gpu(city_rid)
				total += spent
				samples += 1
				if index == BuildingRules.ROOF:
					roof += spent / float(FLOOR_FRAMES)
				if spent > worst:
					worst = spent
					worst_floor = index
		var mean := total / maxf(float(samples), 1.0)
		failed = failed or worst > BUDGET_MS
		print(
			(
				(
					"  уровень %d: GPU %.2f мс в среднем, худший %.2f на этаже %s, крыша %.2f,"
					+ " бюджет %.1f"
				)
				% [
					quality,
					mean,
					worst,
					str(FloorSigns.number_of(rules, worst_floor)),
					roof,
					BUDGET_MS,
				]
			)
		)
	get_tree().quit(1 if failed else 0)


## По этажам на одном уровне качества: строка на этаж.
func _run_floors(level: GreyboxLevel) -> void:
	var quality := Graphics.Quality.ULTRA
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--quality="):
			quality = argument.trim_prefix("--quality=").to_int() as Graphics.Quality
		elif argument == "--native":
			DisplayModes.apply_window(DisplayModes.Mode.BORDERLESS, Vector2i.ZERO)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var city := level.get_node_or_null("Scenery/City/CityView") as SubViewport
	var city_rid := city.get_viewport_rid() if city != null else RID()
	if city_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(city_rid, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	level.spawn_agents = false
	Graphics.broadcast(quality)
	for _frame in 60:
		await get_tree().process_frame
	var rules := level.rules
	print("  окно %s, уровень %d" % [str(get_viewport().get_visible_rect().size), quality])
	print("  этаж  GPU мс  CPU мс  кадр мс  светит  с тенью  вызовов")
	for index in range(BuildingRules.ROOF, rules.floors):
		level.otto.global_position = WorldSpace.to_scene(
			Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
		)
		for _frame in FLOOR_SETTLE:
			await get_tree().process_frame
		var gpu := 0.0
		var cpu := 0.0
		var frame := 0.0
		var calls := 0.0
		for _frame in FLOOR_FRAMES:
			await get_tree().process_frame
			var spent := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			if (
				city_rid.is_valid()
				and city.render_target_update_mode != SubViewport.UPDATE_DISABLED
			):
				spent += RenderingServer.viewport_get_measured_render_time_gpu(city_rid)
			gpu += spent
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)
			frame += get_process_delta_time() * 1000.0
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var n := float(FLOOR_FRAMES)
		print(
			(
				"  %4s  %6.2f  %6.2f  %7.2f  %6d  %7d  %7d"
				% [
					str(FloorSigns.number_of(rules, index)),
					gpu / n,
					cpu / n,
					frame / n,
					_lit(level),
					_shadowed(level),
					int(calls / n),
				]
			)
		)
	get_tree().quit(0)


## Разбор кадра одного этажа (`--probe --floor=N`, M24h): кадр целиком, а
## затем без одного слагаемого за раз — видно, что сколько стоит. Слагаемые
## выключаются и включаются обратно, по одному; этаж — по номеру на табло.
##
## `--corpses=N` кладёт на этаж N трупов; `--timeline` — развёртка физики и
## GPU по полсекунды с числом едущих кабин; `--scripts` — шаг физики по
## скриптам, каждый выключен на цикл кабин; `--cars` и `--nodes` — кабины и
## узлы уровня по очереди. Окно строки меньше цикла кабин (они ходят в ногу),
## поэтому физику меряют развёрткой, а не одной строкой.
func _run_probe(level: GreyboxLevel) -> void:
	var number := 6
	var corpses := 0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--floor="):
			number = argument.trim_prefix("--floor=").to_int()
		elif argument.begins_with("--corpses="):
			corpses = argument.trim_prefix("--corpses=").to_int()
		elif argument == "--native":
			DisplayModes.apply_window(DisplayModes.Mode.BORDERLESS, Vector2i.ZERO)
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	level.spawn_agents = false
	Graphics.broadcast(Graphics.Quality.ULTRA)
	var rules := level.rules
	var index := rules.floors - 1 - number
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
	)
	# Трупы на этаже: столько убитых агентов вокруг Otto, улёгшихся телом.
	var at := WorldSpace.to_plane(level.otto.global_position)
	for body: int in corpses:
		var agent := ENEMY_SCENE.instantiate() as Enemy
		agent.walk_speed = 0.0
		level.add_child(agent)
		var span := rules.floor_span(index)
		var x := clampf(at.x + (float(body % 10) - 4.5) * 0.9, span.x + 1.0, span.y - 1.0)
		agent.global_position = WorldSpace.to_scene(Vector2(x, at.y - 0.3 - float(body / 10) * 0.8))
		agent.setup(null, 1.0)
		while agent.is_emerging():
			await get_tree().physics_frame
		agent.kill()
	for _frame in FLOOR_SETTLE * 2 + (600 if corpses > 0 else 0):
		await get_tree().process_frame
	var environment := get_viewport().world_3d.environment
	if environment == null:
		var found := level.find_children("*", "WorldEnvironment", true, false)
		environment = (found[0] as WorldEnvironment).environment if not found.is_empty() else null
	print(
		(
			"  этаж %d, окно %s, трупов %d (застыли %d), физика %.2f мс"
			% [
				number,
				str(get_viewport().get_visible_rect().size),
				corpses,
				_frozen_bodies(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			]
		)
	)
	print("  %-26s  GPU мс  вызовов  физика мс" % "что выключено")
	await _probe_line(viewport, "ничего", func(_on: bool) -> void: pass)
	await _probe_line(viewport, "ничего, ещё раз", func(_on: bool) -> void: pass)
	if OS.get_cmdline_user_args().has("--scripts"):
		var by_script: Dictionary = {}
		for node: Node in get_tree().root.find_children("*", "Node", true, false):
			if not node.is_physics_processing():
				continue
			var script := node.get_script() as Script
			var key := script.resource_path.get_file() if script != null else node.get_class()
			if not by_script.has(key):
				by_script[key] = []
			(by_script[key] as Array).append(node)
		print("  %-30s  узлов  физика мс (цикл 240 кадров)" % "скрипт")
		print("  %-30s  %5d  %6.2f" % ["всё включено", 0, await _physics_over(240)])
		for key: String in by_script:
			var nodes: Array = by_script[key]
			for node: Node in nodes:
				node.set_physics_process(false)
			var spent := await _physics_over(240)
			for node: Node in nodes:
				if is_instance_valid(node):
					node.set_physics_process(true)
			print("  %-30s  %5d  %6.2f" % [key, nodes.size(), spent])
		print("  %-30s  %5d  %6.2f" % ["всё включено", 0, await _physics_over(240)])
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--timeline"):
		var all_cars := level.find_children("*", "ElevatorCar", true, false)
		for _slice in 40:
			var physics := 0.0
			var gpu := 0.0
			var moving := 0
			for _frame in 30:
				await get_tree().process_frame
				physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
			for car: Node in all_cars:
				if not is_zero_approx((car as ElevatorCar).speed_now()):
					moving += 1
			print(
				(
					"  %5.1f с  физика %6.2f  GPU %6.2f  едут %2d из %d  тел %d"
					% [
						Time.get_ticks_msec() / 1000.0,
						physics / 30.0,
						gpu / 30.0,
						moving,
						all_cars.size(),
						Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
					]
				)
			)
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--cars"):
		var cars := level.find_children("*", "ElevatorCar", true, false)
		for _pass in 2:
			await _probe_line(
				viewport,
				"зоны кабин",
				func(on: bool) -> void:
					for car: Node in cars:
						for area: Node in car.find_children("*", "Area3D", false, false):
							(area as Area3D).monitoring = on
			)
			await _probe_line(
				viewport,
				"тела кабин",
				func(on: bool) -> void:
					for car: Node in cars:
						for shape: Node in car.find_children("*", "CollisionShape3D", false, false):
							(shape as CollisionShape3D).disabled = not on
			)
			await _probe_line(
				viewport,
				"маска кабин 0",
				func(on: bool) -> void:
					for car: Node in cars:
						(car as ElevatorCar).collision_mask = 1 if on else 0
			)
			await _probe_line(viewport, "ничего", func(_on: bool) -> void: pass)
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--nodes"):
		var groups: Dictionary = {}
		for child: Node in level.get_children() + level.get_node("Scenery").get_children():
			var key := child.get_class() if child.name.begins_with("@") else String(child.name)
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(child)
		for key: String in groups:
			var nodes: Array = groups[key]
			await _probe_line(
				viewport,
				"%s ×%d" % [key, nodes.size()],
				func(on: bool) -> void:
					for node: Node in nodes:
						node.process_mode = (
							Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
						)
			)
		get_tree().quit(0)
		return
	if corpses > 0:
		await _probe_line(
			viewport, "шаг кабин", func(on: bool) -> void: _pause(level, "ElevatorCar", on)
		)
		await _probe_line(
			viewport,
			"шаг ограничителей трупов",
			func(on: bool) -> void: _pause(level, "Node", on, true)
		)
		await _probe_line(viewport, "кости все статичны", func(on: bool) -> void: _still_bones(on))
	await _probe_line(viewport, "тени ламп", func(on: bool) -> void: _lamp_shadows(level, on))
	await _probe_line(
		viewport, "тени конусов", func(on: bool) -> void: _lamp_shadows(level, on, "SpotLight3D")
	)
	await _probe_line(
		viewport, "тени заливки", func(on: bool) -> void: _lamp_shadows(level, on, "OmniLight3D")
	)
	await _probe_line(
		viewport, "лампы целиком", func(on: bool) -> void: _lights_of(level, "Lamp", on)
	)
	await _probe_line(
		viewport, "свет, кроме ламп", func(on: bool) -> void: _other_lights(level, on)
	)
	for part: String in ["Scenery/Props", "Scenery/FloorDetail", "Scenery/City", "Ribs"]:
		var node := level.get_node_or_null(part) as Node3D
		if node != null:
			await _probe_line(viewport, part, func(on: bool) -> void: node.visible = on)
	for dressing: Node in level.find_children("*", "BuildingDressing", true, false):
		await _probe_line(
			viewport, "обстановка", func(on: bool) -> void: (dressing as Node3D).visible = on
		)
	if environment != null:
		await _probe_line(
			viewport,
			"объёмный туман",
			func(on: bool) -> void: environment.volumetric_fog_enabled = on
		)
		await _probe_line(viewport, "SSR", func(on: bool) -> void: environment.ssr_enabled = on)
		await _probe_line(viewport, "SSIL", func(on: bool) -> void: environment.ssil_enabled = on)
		await _probe_line(viewport, "SSAO", func(on: bool) -> void: environment.ssao_enabled = on)
		await _probe_line(
			viewport, "свечение", func(on: bool) -> void: environment.glow_enabled = on
		)
	get_tree().quit(0)


## Останавливает шаг физики узлов класса [param kind]; [param limiters] —
## только ограничителей рэгдолла.
func _pause(level: GreyboxLevel, kind: String, on: bool, limiters: bool = false) -> void:
	for node: Node in level.find_children("*", kind, true, false):
		if limiters and not node is Ragdoll.SpeedLimit:
			continue
		node.set_physics_process(on)


## Делает все кости трупов статичными и возвращает как было.
func _still_bones(on: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := Corpse.of(node)
		if corpse == null or corpse.ragdoll == null or corpse.ragdoll.is_frozen():
			continue
		for part: PhysicalBone3D in corpse.ragdoll.parts.values():
			PhysicsServer3D.body_set_mode(
				part.get_rid(),
				PhysicsServer3D.BODY_MODE_RIGID if on else PhysicsServer3D.BODY_MODE_STATIC
			)


## Среднее время физики за [param frames] кадров, мс.
func _physics_over(frames: int) -> float:
	var total := 0.0
	for _frame in frames:
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / float(frames)


## Сколько тел застыло ([method Ragdoll.freeze]).
func _frozen_bodies() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := Corpse.of(node)
		if corpse != null and corpse.ragdoll != null and corpse.ragdoll.is_frozen():
			count += 1
	return count


## Строка разбора: слагаемое выключено [param toggle] и после замера включено.
func _probe_line(viewport: RID, label: String, toggle: Callable) -> void:
	var before := {}
	toggle.call(false)
	for _frame in FLOOR_SETTLE:
		await get_tree().process_frame
	var gpu := 0.0
	var calls := 0.0
	var physics := 0.0
	for _frame in FLOOR_FRAMES:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	toggle.call(true)
	before.clear()
	var n := float(FLOOR_FRAMES)
	print("  %-26s  %6.2f  %7d  %6.2f" % [label, gpu / n, int(calls / n), physics / n])


func _lamp_shadows(level: GreyboxLevel, on: bool, kind: String = "Light3D") -> void:
	for node: Node in level.find_children("*", "Lamp", true, false):
		for light: Node in node.find_children("*", kind, true, false):
			if on:
				(light as Light3D).shadow_enabled = bool(light.get_meta(&"probe_shadow", false))
			else:
				light.set_meta(&"probe_shadow", (light as Light3D).shadow_enabled)
				(light as Light3D).shadow_enabled = false


func _lights_of(level: GreyboxLevel, owner_class: String, on: bool) -> void:
	for node: Node in level.find_children("*", owner_class, true, false):
		for light: Node in node.find_children("*", "Light3D", true, false):
			_hold_light(light as Light3D, on)


func _other_lights(level: GreyboxLevel, on: bool) -> void:
	for node: Node in level.find_children("*", "Light3D", true, false):
		var owner_lamp := false
		var up := node.get_parent()
		while up != null and up != level:
			if up is Lamp:
				owner_lamp = true
				break
			up = up.get_parent()
		if not owner_lamp:
			_hold_light(node as Light3D, on)


## Гасит источник на время строки и возвращает ему прежнюю видимость.
func _hold_light(light: Light3D, on: bool) -> void:
	if on:
		light.visible = bool(light.get_meta(&"probe_visible", light.visible))
	else:
		light.set_meta(&"probe_visible", light.visible)
		light.visible = false


func _run(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# Город — своим видом, как в замере по зданию: с кадра выезда он виден.
	var city := level.get_node_or_null("Scenery/City/CityView") as SubViewport
	var city_rid := city.get_viewport_rid() if city != null else RID()
	if city_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(city_rid, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	for _step: int in SETTLE_STEPS:
		# Вступление, отпустив камеру, возвращает ей границы здания: кадр выезда
		# ставится заново, пока здание устаивается.
		if _exit_bounds.has_area():
			level.otto.apply_camera_bounds(_exit_bounds)
		await get_tree().physics_frame

	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--shot="):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--shot="))
	var gpu := 0.0
	var cpu := 0.0
	var worst := 0.0
	for _frame: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var spent := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
		if city_rid.is_valid() and city.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			spent += RenderingServer.viewport_get_measured_render_time_gpu(city_rid)
		gpu += spent
		worst = maxf(worst, spent)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport)

	var mean := gpu / float(MEASURE_FRAMES)
	print("  источников в кадре: %d, живых агентов: %d" % [_lit(level), _alive(level)])
	print(
		(
			"  GPU %.2f мс/кадр (худший %.2f), CPU рендера %.2f мс, бюджет %.1f"
			% [mean, worst, cpu / float(MEASURE_FRAMES), BUDGET_MS]
		)
	)
	get_tree().quit(0 if mean <= BUDGET_MS else 1)


func _lit(level: GreyboxLevel) -> int:
	var count := 0
	for node: Node in level.find_children("*", "Light3D", true, false):
		if (node as Light3D).is_visible_in_tree():
			count += 1
	return count


func _shadowed(level: GreyboxLevel) -> int:
	var count := 0
	for node: Node in level.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.is_visible_in_tree() and light.shadow_enabled:
			count += 1
	return count


func _alive(level: GreyboxLevel) -> int:
	var count := 0
	for agent in level.agents():
		if not agent.is_dead():
			count += 1
	return count
