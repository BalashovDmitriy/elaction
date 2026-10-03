extends Node3D

## Frame measurement under M17 lighting: a real building, agents, three lamps in the frame.
##
## Answers one question of ADR-0023 (decision 7): whether the air — reflections, fog,
## glow — and the lamp cones fit in the frame budget. GPU time per frame is measured,
## not the process delta: the delta also counts waiting for vertical sync and physics,
## and has nothing to do with lighting.
##
## The render is real, not headless — a screen is needed. The number goes into STATUS.
##
## Since M22 — across the whole building too (ADR-0030, decision 6): `--whole` puts Otto
## on every floor from the roof to the garage at every quality level and writes the
## level's average and worst frame, with the floor where the worst one happened.
##
## Launch:
##     godot --path . res://tools/light_bench.tscn
##     godot --path . res://tools/light_bench.tscn -- --whole
##     godot --path . res://tools/light_bench.tscn -- --whole --seed=2
##     godot --path . res://tools/light_bench.tscn -- --whole --kind=2
##     godot --path . res://tools/light_bench.tscn -- --garage --x=16
##     godot --path . res://tools/light_bench.tscn -- --floors --quality=3 --native
##     godot --path . res://tools/light_bench.tscn -- --floors --quality=3 --time=1
##     godot --path . res://tools/light_bench.tscn -- --shot=screens/bench.png --index=15
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --native
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --corpses=40
##     godot --path . res://tools/light_bench.tscn -- --probe --floor=6 --timeline
##
## `--floors` (M24f) — a per-floor table at one level (`--quality=`, "Ultra" by
## default): render GPU and CPU, the full frame, shadowed sources and draw calls —
## shows what grows toward the bottom of the building. `--native` — a borderless
## full-screen window at native resolution, as for a player in full screen.
##
## The default seed is 1, fog. Rain (M24a) is measured on seed 2.
##
## `--garage` (M24b) measures the bottom floor — the garage with fixtures and other
## people's cars; `--x=` puts Otto at the needed point of the floor, otherwise at a
## safe spot, as on a wide floor.
##
## `--exit=` (M24b) sets the exit frame: the frame's middle is this many metres right of
## the building's left end wall, as in [method ExitBoarding.exit_frame]; `--lift=` — how
## far the frame's bottom is raised above the building's bottom, m, as for a frame
## following the car up the ramp. With them Otto is placed in the garage automatically:
##     godot --path . res://tools/light_bench.tscn -- --exit=3.5
##     godot --path . res://tools/light_bench.tscn -- --exit=-9.45 --lift=3.6

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many physics steps to give the building to assemble, agents to come out and the
## light to settle. Physics steps, not frames: without vertical sync a frame takes a
## millisecond, and doors would not manage to open in a hundred frames.
const SETTLE_STEPS: int = 240
## How many frames to measure.
const MEASURE_FRAMES: int = 240
## Frame budget, ms: 60 frames per second.
const BUDGET_MS: float = 16.6
## Whole building: how many frames to let a floor settle and how many to measure.
const FLOOR_SETTLE: int = 20
const FLOOR_FRAMES: int = 30

## Exit frame (`--exit=`), in the rules plane; empty — the frame follows Otto.
var _exit_bounds := Rect2()


func _ready() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	if level == null:
		push_error("the level scene did not build — check the project import")
		get_tree().quit(1)
		return
	level.rules = BuildingRules.new()
	level.building_seed = 1
	var kind := -1
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			level.building_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--kind="):
			# Building kind (M24o): special-floor halls have their own light and multimeshes.
			kind = argument.trim_prefix("--kind=").to_int()
		elif argument.begins_with("--time="):
			# Time of day (M24j): in the daytime the city is different — sun and glass with sky.
			level.rules.time_of_day = argument.trim_prefix("--time=").to_int() as TimeOfDay.Kind
	# The kind's building is found by the final seed: `--kind` before `--seed` looked it
	# up by the previous one, and the kind came out different.
	if kind >= 0:
		GameState.instance().building = BuildingIdentity.first_of(
			kind as BuildingIdentity.Kind, level.building_seed
		)
	add_child(level)

	# Not the roof but a wide floor: three lamps, doors with indicator boards and agents
	# by them — the building's most expensive frame.
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


## The whole building at every quality level: the worst frame — the floor where it happened.
func _run_whole(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# The city is drawn by its own viewport (ADR-0029): its frame is measured separately
	# and added — it is not in the root window's measurement (M24a).
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
		# The level's shaders compile in the first frames: those are not measured.
		for _frame in 60:
			await get_tree().process_frame
		var total := 0.0
		var samples := 0
		var worst := 0.0
		var worst_floor := 0
		# The roof gets its own row: it has the city, weather and rain (M24a), and in the
		# average over thirty floors it drowns.
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
					"  level %d: GPU %.2f ms on average, worst %.2f on floor %s, roof %.2f,"
					+ " budget %.1f"
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


## Per floor at one quality level: a row per floor.
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
	print("  window %s, level %d" % [str(get_viewport().get_visible_rect().size), quality])
	print("  floor  GPU ms  CPU ms  frame ms  lit  shadowed  calls")
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


## Breakdown of one floor's frame (`--probe --floor=N`, M24h): the whole frame, then
## without one term at a time — shows what costs how much. Terms are turned off and
## back on, one by one; the floor — by the number on the indicator board.
##
## `--corpses=N` puts N corpses on the floor; `--timeline` — a physics and GPU timeline
## in half-second steps with the number of moving cabs; `--scripts` — the physics step
## by script, each turned off for a cab cycle; `--cars` and `--nodes` — cabs and level
## nodes in turn. A row's window is shorter than a cab cycle (they move in step), so
## physics is measured by a timeline rather than a single row.
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
	# Corpses on the floor: this many killed agents around Otto, settled as bodies.
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
			"  floor %d, window %s, corpses %d (frozen %d), physics %.2f ms"
			% [
				number,
				str(get_viewport().get_visible_rect().size),
				corpses,
				_frozen_bodies(),
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			]
		)
	)
	print("  %-26s  GPU ms  calls  physics ms" % "what is off")
	await _probe_line(viewport, "nothing", func(_on: bool) -> void: pass)
	await _probe_line(viewport, "nothing, again", func(_on: bool) -> void: pass)
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
		print("  %-30s  nodes  physics ms (240-frame cycle)" % "script")
		print("  %-30s  %5d  %6.2f" % ["all on", 0, await _physics_over(240)])
		for key: String in by_script:
			var nodes: Array = by_script[key]
			for node: Node in nodes:
				node.set_physics_process(false)
			var spent := await _physics_over(240)
			for node: Node in nodes:
				if is_instance_valid(node):
					node.set_physics_process(true)
			print("  %-30s  %5d  %6.2f" % [key, nodes.size(), spent])
		print("  %-30s  %5d  %6.2f" % ["all on", 0, await _physics_over(240)])
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
					"  %5.1f s  physics %6.2f  GPU %6.2f  moving %2d of %d  bodies %d"
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
				"cab zones",
				func(on: bool) -> void:
					for car: Node in cars:
						for area: Node in car.find_children("*", "Area3D", false, false):
							(area as Area3D).monitoring = on
			)
			await _probe_line(
				viewport,
				"cab bodies",
				func(on: bool) -> void:
					for car: Node in cars:
						for shape: Node in car.find_children("*", "CollisionShape3D", false, false):
							(shape as CollisionShape3D).disabled = not on
			)
			await _probe_line(
				viewport,
				"cab mask 0",
				func(on: bool) -> void:
					for car: Node in cars:
						(car as ElevatorCar).collision_mask = 1 if on else 0
			)
			await _probe_line(viewport, "nothing", func(_on: bool) -> void: pass)
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
			viewport, "cab step", func(on: bool) -> void: _pause(level, "ElevatorCar", on)
		)
		await _probe_line(
			viewport, "corpse limiter step", func(on: bool) -> void: _pause(level, "Node", on, true)
		)
		await _probe_line(viewport, "all bones static", func(on: bool) -> void: _still_bones(on))
	await _probe_line(viewport, "lamp shadows", func(on: bool) -> void: _lamp_shadows(level, on))
	await _probe_line(
		viewport, "cone shadows", func(on: bool) -> void: _lamp_shadows(level, on, "SpotLight3D")
	)
	await _probe_line(
		viewport, "fill shadows", func(on: bool) -> void: _lamp_shadows(level, on, "OmniLight3D")
	)
	await _probe_line(
		viewport, "whole lamps", func(on: bool) -> void: _lights_of(level, "Lamp", on)
	)
	await _probe_line(
		viewport, "light other than lamps", func(on: bool) -> void: _other_lights(level, on)
	)
	for part: String in ["Scenery/Props", "Scenery/FloorDetail", "Scenery/City", "Ribs"]:
		var node := level.get_node_or_null(part) as Node3D
		if node != null:
			await _probe_line(viewport, part, func(on: bool) -> void: node.visible = on)
	for dressing: Node in level.find_children("*", "BuildingDressing", true, false):
		await _probe_line(
			viewport, "dressing", func(on: bool) -> void: (dressing as Node3D).visible = on
		)
	if environment != null:
		await _probe_line(
			viewport,
			"volumetric fog",
			func(on: bool) -> void: environment.volumetric_fog_enabled = on
		)
		await _probe_line(viewport, "SSR", func(on: bool) -> void: environment.ssr_enabled = on)
		await _probe_line(viewport, "SSIL", func(on: bool) -> void: environment.ssil_enabled = on)
		await _probe_line(viewport, "SSAO", func(on: bool) -> void: environment.ssao_enabled = on)
		await _probe_line(viewport, "glow", func(on: bool) -> void: environment.glow_enabled = on)
	get_tree().quit(0)


## Stops the physics step of nodes of class [param kind]; [param limiters] — only the
## ragdoll's limiters.
func _pause(level: GreyboxLevel, kind: String, on: bool, limiters: bool = false) -> void:
	for node: Node in level.find_children("*", kind, true, false):
		if limiters and not node is Ragdoll.SpeedLimit:
			continue
		node.set_physics_process(on)


## Makes all corpse bones static and restores them as they were.
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


## Average physics time over [param frames] frames, ms.
func _physics_over(frames: int) -> float:
	var total := 0.0
	for _frame in frames:
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	return total / float(frames)


## How many bodies have frozen ([method Ragdoll.freeze]).
func _frozen_bodies() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := Corpse.of(node)
		if corpse != null and corpse.ragdoll != null and corpse.ragdoll.is_frozen():
			count += 1
	return count


## Breakdown row: term [param toggle] is turned off and turned back on after measuring.
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


## Hides a source for the row and restores its previous visibility.
func _hold_light(light: Light3D, on: bool) -> void:
	if on:
		light.visible = bool(light.get_meta(&"probe_visible", light.visible))
	else:
		light.set_meta(&"probe_visible", light.visible)
		light.visible = false


func _run(level: GreyboxLevel) -> void:
	var viewport := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	# The city by its own viewport, as in the building measurement: it is visible from
	# the exit frame.
	var city := level.get_node_or_null("Scenery/City/CityView") as SubViewport
	var city_rid := city.get_viewport_rid() if city != null else RID()
	if city_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(city_rid, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	for _step: int in SETTLE_STEPS:
		# The intro, releasing the camera, gives it back the building's bounds: the exit
		# frame is set again while the building settles.
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
	print("  sources in frame: %d, live agents: %d" % [_lit(level), _alive(level)])
	print(
		(
			"  GPU %.2f ms/frame (worst %.2f), render CPU %.2f ms, budget %.1f"
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
