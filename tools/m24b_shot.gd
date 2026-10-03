extends Node

## M24b shots that the timed capture script does not reach (ADR-0038):
## the red door, the locked basement and the exit by car.
##
## The tool assembles a real game — [code]src/main.tscn[/code] with the HUD and
## the fade — swaps its building for a building of the required seed and shoots by
## state, not by stopwatch:
##
## 1. Red door: Otto enters (the leaf opens), Otto inside (the leaf
##    closed, an agent waits at the door), Otto comes out.
## 2. Basement: above the basement, at the shaft down — the leaves are closed; all documents
##    collected — the leaves part and have parted.
## 3. Exit: Otto at the car, gets in — the door is open, he steps to the side —
##    headlights and the gate, the car drives off up the ramp, the frame follows it to the street,
##    the bonus on the HUD, the fade.
##
## Otto is placed by the layout, as in [code]garage_shot.gd[/code]; to the door and to
## the car he is led by game actions. The agent at the door is placed by hand: the [DoorWatch]
## draw is rolled for an agent once per visit, and one that did not go to wait is replaced
## by a new one until one does.
##
## Real rendering, not headless — a screen is needed.
##
## Run:
##     godot --path . res://tools/m24b_shot.tscn
##     godot --path . res://tools/m24b_shot.tscn -- --seed=3 --folder=M24b --quality=2
##
## Shots go to screens/<folder>/ — the folder is local and does not go into the repository.

const MAIN_SCENE := preload("res://src/main.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24b"
## How many frames to give the camera to catch up with Otto after a move.
const SETTLE_FRAMES: int = 45
## How many frames to wait for an event before giving up.
const PATIENCE: int = 900
## Where the agent appears relative to the door, m: further than the waiting spot, so that it is
## visible that he walked up to it.
const AGENT_OFFSET: float = 3.2
## How far right of the driver's door Otto stands before boarding, m.
const CAR_APPROACH: float = 2.8
## How far from the shaft edge Otto stands above the basement, m.
const SHAFT_GAP: float = 0.5

var _main: Node = null
var _level: GreyboxLevel = null
var _hud: Hud = null
var _curtain: FadeCurtain = null
var _seed: int = 1
var _folder: String = DEFAULT_FOLDER
## Building number in the game (`--building=`): the exit car draw depends on it —
## the first is always the red sports car ([method CarModel.choose]).
var _building: int = 1
## Exit only (`--only=exit`): boarding and the drive-out without the door and basement.
var _only: String = ""


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument.begins_with("--building="):
			_building = maxi(argument.trim_prefix("--building=").to_int(), 1)
		elif argument.begins_with("--only="):
			_only = argument.trim_prefix("--only=").strip_edges()
		elif argument.begins_with("--quality="):
			var quality := clampi(
				argument.trim_prefix("--quality=").to_int(), 0, Graphics.Quality.size() - 1
			)
			Graphics.broadcast(quality as Graphics.Quality)
	DirAccess.make_dir_recursive_absolute("res://screens/%s" % _folder)
	SCREENSHOTTER.mark_ignored_by_engine(ProjectSettings.globalize_path("res://screens"))
	get_window().size = Vector2i(1920, 1080)
	_run.call_deferred()


func _run() -> void:
	_start()
	if not _level.skip_the_intro():
		await _level.wait_for_the_landing()
	await _frames(10)
	if _only != "exit":
		await _door()
		await _basement()
	await _exit()
	get_tree().quit()


## A game in main, as for the player, but the building is of its own seed: main builds the building
## by the game's number and salt, while the capture needs a building by `--seed`. Its own building
## is connected to main by the same calls as in [method Main._enter_building].
func _start() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_main.call("_start_game")
	_main.call("_drop_level")
	_hud = _main.get_node("Hud") as Hud
	_curtain = _main.get(&"_curtain") as FadeCurtain
	GameState.instance().start_game()
	GameState.instance().building = _building
	# Building kind goes into the car draw, as in the level ([method GreyboxLevel._spawn_car]).
	var car := CarModel.choose(_building, _seed, BuildingIdentity.of(_building, _seed).kind)
	print("car: model %d, paint %d" % [car.model, car.paint])
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = _seed
	_level.spawn_agents = false
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	_main.add_child(_level)
	_main.set(&"_level", _level)
	_level.car_started.connect(Callable(_main, &"_on_car_started"))
	_level.building_cleared.connect(Callable(_main, &"_on_building_cleared"))
	_hud.follow(_level)


## Red door: entry, inside with an agent at the door, exit.
func _door() -> void:
	var door := _red_door()
	if door == null:
		push_error("no red door in the building")
		return
	var mat := door.mat_position()
	_place(mat.x, mat.y)
	await _settle()
	Input.action_press(&"move_up")
	var entering := await _until(func() -> bool: return door.openness() >= 0.45)
	Input.action_release(&"move_up")
	if entering:
		await _shoot("door_01_entering")
	await _until(func() -> bool: return _level.otto.is_hidden() and door.openness() <= 0.0)
	var agent := await _post_agent(door)
	# Wait until the agent takes his spot, but no longer than Otto stays inside.
	await _until(
		func() -> bool:
			return (
				not _level.otto.is_hidden()
				or door.openness() > 0.0
				or (agent != null and _standing_at(agent))
			)
	)
	if _level.otto.is_hidden() and door.openness() <= 0.0:
		await _shoot("door_02_inside_closed")
	else:
		push_error("Otto left before an agent stood at the door")
	await _until(func() -> bool: return not _level.otto.is_hidden())
	await _frames(2)
	await _shoot("door_03_out")
	# The agent has done his part: from here he would only shoot at Otto.
	for enemy: Enemy in _level.agents():
		enemy.queue_free()
	await _until(func() -> bool: return _level.otto.is_on_foot())


## Basement: above it at the shaft — locked; the last document — the leaves part.
func _basement() -> void:
	var rules := _level.rules
	var bottom := rules.floors - 1
	var above := bottom - 1
	var lock := _level.find_child("BasementLock", false, false) as BasementLock
	var shaft := _basement_shaft()
	if shaft == null or lock == null:
		push_error("no shaft to the basement or no lock")
		return
	var aside := rules.shaft_width * 0.5 + Proportions.BODY_WIDTH * 0.5 + SHAFT_GAP
	_place(_clear_side(above, shaft.x, aside), rules.floor_surface(above))
	await _settle()
	# The cab above the basement stands on the leaves and covers them: shoot when
	# it has gone at least one floor up.
	var car := _car_in(shaft)
	var clear := func() -> bool:
		return (
			car == null
			or (
				WorldSpace.to_plane(car.global_position).y
				< rules.floor_surface(above) - rules.floor_height * 0.9
			)
		)
	await _until(clear)
	if lock.is_locked():
		await _shoot("basement_01_locked")
	else:
		push_error("the basement is already open — no documents in the building?")
	var game := GameState.instance()
	while not game.all_documents_collected():
		game.collect_document()
	await _seconds(BasementLock.OPEN_TIME * 0.4)
	await _shoot("basement_02_opening")
	await _seconds(BasementLock.OPEN_TIME + 0.4)
	await _shoot("basement_03_open")


## Exit: at the car, boarding, headlights and gate, departure, bonus, fade.
func _exit() -> void:
	var rules := _level.rules
	var boarding := _level.get(&"_boarding") as ExitBoarding
	var door := _level.exit_position()
	var bonus := Arcade.building_bonus(GameState.instance().building)
	var floor_y := rules.floor_surface(rules.floors - 1)
	var game := GameState.instance()
	while not game.all_documents_collected():
		game.collect_document()
	_place(door.x + CAR_APPROACH, floor_y)
	await _settle()
	await _shoot("exit_01_at_the_car")
	Input.action_press(&"move_left")
	var boarded := await _until(func() -> bool: return boarding.is_boarded())
	Input.action_release(&"move_left")
	if not boarded:
		return
	var car := _level.get(&"_car") as ExitCar
	var step_back := ExitBoarding.STEP_BACK_FROM + ExitBoarding.STEP_BACK_TIME * 0.6
	await _until(func() -> bool: return boarding.phase == ExitBoarding.Phase.GETTING_IN)
	await _seconds(step_back)
	if car.door_openness() > 0.5:
		await _shoot("exit_02_boarding")
	else:
		push_error("the car door is not open at boarding")
	await _until(func() -> bool: return boarding.phase == ExitBoarding.Phase.STARTING)
	await _seconds(0.8)
	await _shoot("exit_03_lights_gate")
	await _until(func() -> bool: return boarding.phase == ExitBoarding.Phase.LEAVING)
	if OS.get_cmdline_user_args().has("--sequence"):
		await _drive_sequence(car)
		return
	await _seconds(0.45)
	await _shoot("exit_04_driving")
	# The frame follows the car: the climb up the ramp and out onto the street.
	await _seconds(0.9)
	if car.is_leaving():
		await _shoot("exit_04b_ramp")
	# At the kerb: waits for a gap with the right turn signal on (ADR-0046, decision 2).
	if await _until(func() -> bool: return car.is_signalling() and car.indicator_lit()):
		await _shoot("exit_04c_signal")
	await _until(func() -> bool: return car.stage == ExitCar.Stage.MERGE)
	await _seconds(0.3)
	if car.is_leaving():
		await _shoot("exit_04d_merge")
	# The bonus has finished counting: by now the car has left, the building is done.
	await _until(func() -> bool: return _hud.bonus_text() == Hud.format_score(bonus))
	await _shoot("exit_05_bonus")
	if await _until(func() -> bool: return _curtain.opacity() >= 0.5):
		await _shoot("exit_06_fade")


## Frame-by-frame analysis of the departure (`--sequence`): a frame every 0.15 s while the car
## drives and the fade has not fallen, and a line about it — where it is, the tilt, whether the
## headlights are on, where the camera is. These lines and frames show where the headlight light
## stops landing on the road.
func _drive_sequence(car: ExitCar) -> void:
	var index := 0
	while car.is_leaving() and _curtain.opacity() < 0.95 and index < 90:
		await _shoot("drive_%02d" % index)
		var camera := get_viewport().get_camera_3d()
		print(
			(
				"  drive_%02d car %s stage %d tilt %.1f° lights %s camera %s dimming %.2f"
				% [
					index,
					WorldSpace.to_plane(car.global_position),
					car.stage,
					rad_to_deg(car.rotation.z),
					car.lights_on(),
					camera.global_position if camera != null else Vector3.ZERO,
					_curtain.opacity(),
				]
			)
		)
		await _seconds(0.15)
		index += 1


## A red door with room for an agent on both sides: no walls or
## openings for [constant AGENT_OFFSET] in both directions.
func _red_door() -> Door:
	var first: Door = null
	for door: Door in _level.doors():
		if not door.is_pending():
			continue
		if first == null:
			first = door
		var mat := door.mat_position()
		var index := _level.rules.floor_index_near(mat.y)
		if _walkable(index, mat.x - AGENT_OFFSET - 0.5, mat.x + AGENT_OFFSET + 0.5):
			return door
	return first


## Places an agent on the door's floor until the [DoorWatch] draw sends someone to wait.
func _post_agent(door: Door) -> Enemy:
	var mat := door.mat_position()
	var index := _level.rules.floor_index_near(mat.y)
	for side: float in [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0]:
		var x := mat.x + side * AGENT_OFFSET
		if not _walkable(index, minf(x, mat.x), maxf(x, mat.x)):
			continue
		var agent := ENEMY_SCENE.instantiate() as Enemy
		agent.apply_rules(_level.rules)
		agent.seed_decisions(_seed)
		_level.add_child(agent)
		agent.global_position = WorldSpace.to_scene(Vector2(x, mat.y))
		agent.setup(_level.otto, -side)
		await _frames(3)
		if not is_nan(agent.watch_at):
			return agent
		agent.queue_free()
		await _frames(1)
	push_error("no agent went to wait at the door")
	return null


## Whether the agent reached the spot at the door.
func _standing_at(agent: Enemy) -> bool:
	if is_nan(agent.watch_at):
		return false
	return absf(WorldSpace.to_plane(agent.global_position).x - agent.watch_at) <= 0.2


## Whether floor [param index] has neither a wall nor an opening between [param low] and [param
## high].
func _walkable(index: int, low: float, high: float) -> bool:
	for block: Vector2 in _level.plan().blocks_on(_level.rules, index):
		if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
			return false
	return true


## The side of the shaft at [param x] where the floor has floor, [param aside] from its axis.
func _clear_side(index: int, x: float, aside: float) -> float:
	var half := Proportions.BODY_WIDTH * 0.5
	for side: float in [1.0, -1.0]:
		var spot := x + side * aside
		if _walkable(index, spot - half, spot + half):
			return spot
	return x + aside


## The shaft that goes down to the basement.
func _basement_shaft() -> BuildingPlan.ShaftSpot:
	var bottom := _level.rules.floors - 1
	for shaft: BuildingPlan.ShaftSpot in _level.plan().shafts:
		if shaft.bottom == bottom:
			return shaft
	return null


## The leading cab of shaft [param shaft].
func _car_in(shaft: BuildingPlan.ShaftSpot) -> ElevatorCar:
	for child: Node in _level.get_children():
		var car := child as ElevatorCar
		if car != null and not car.is_deck() and is_equal_approx(car.global_position.x, shaft.x):
			return car
	return null


func _place(x: float, surface: float) -> void:
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, surface))
	_level.otto.velocity = Vector3.ZERO


func _settle() -> void:
	await _frames(SETTLE_FRAMES)


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


func _seconds(duration: float) -> void:
	await _frames(maxi(roundi(duration * Engine.physics_ticks_per_second), 1))


func _until(done: Callable) -> bool:
	for _frame: int in PATIENCE:
		if done.call():
			return true
		await get_tree().physics_frame
	push_error("event not reached within %d frames" % PATIENCE)
	return false


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://screens/%s/%s.png" % [_folder, label]
	image.save_png(path)
	print("  %s" % ProjectSettings.globalize_path(path))
