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


func _alive(level: GreyboxLevel) -> int:
	var count := 0
	for agent in level.agents():
		if not agent.is_dead():
			count += 1
	return count
