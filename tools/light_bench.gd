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


func _ready() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	if level == null:
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child(level)

	# Не крыша, а широкий этаж: три лампы, двери с табло и агенты у них —
	# самый дорогой кадр здания.
	if OS.get_cmdline_user_args().has("--whole"):
		_run_whole(level)
		return
	var index := level.rules.floors - 3
	level.otto.global_position = WorldSpace.to_scene(
		Vector2(level.plan().safe_x(level.rules, index), level.rules.floor_surface(index))
	)
	_run(level)


## Всё здание на каждом уровне качества: худший кадр — этаж, где он случился.
func _run_whole(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
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
		for index in range(BuildingRules.ROOF, rules.floors):
			level.otto.global_position = WorldSpace.to_scene(
				Vector2(level.plan().safe_x(rules, index), rules.floor_surface(index))
			)
			for _frame in FLOOR_SETTLE:
				await get_tree().process_frame
			for _frame in FLOOR_FRAMES:
				await get_tree().process_frame
				var spent := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				total += spent
				samples += 1
				if spent > worst:
					worst = spent
					worst_floor = index
		var mean := total / maxf(float(samples), 1.0)
		failed = failed or worst > BUDGET_MS
		print(
			(
				"  уровень %d: GPU %.2f мс в среднем, худший %.2f на этаже %s, бюджет %.1f"
				% [quality, mean, worst, str(FloorSigns.number_of(rules, worst_floor)), BUDGET_MS]
			)
		)
	get_tree().quit(1 if failed else 0)


func _run(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	for _step: int in SETTLE_STEPS:
		await get_tree().physics_frame

	var gpu := 0.0
	var cpu := 0.0
	var worst := 0.0
	for _frame: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var spent := RenderingServer.viewport_get_measured_render_time_gpu(viewport)
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
