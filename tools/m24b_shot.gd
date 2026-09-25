extends Node

## Кадры M24b, до которых сценарий съёмки по времени не доходит (ADR-0038):
## красная дверь, запертый подвал и выход через машину.
##
## Инструмент собирает настоящую партию — [code]src/main.tscn[/code] с HUD и
## затемнением, — меняет её здание на здание нужного сида и снимает по
## состоянию, а не секундомером:
##
## 1. Красная дверь: Otto входит (створка открывается), Otto внутри (створка
##    закрыта, у двери ждёт агент), Otto выходит.
## 2. Подвал: над подвалом, у шахты вниз — створки закрыты; все документы
##    собраны — створки расходятся и разошлись.
## 3. Выход: Otto у машины, садится, фары и ворота, машина уезжает, бонус на
##    HUD, затемнение.
##
## Otto ставится по раскладке, как в [code]garage_shot.gd[/code]; к двери и к
## машине его подводят игровыми действиями. Агент у двери ставится руками: жребий
## [DoorWatch] бросается агенту раз за визит, и не пошедший ждать заменяется
## новым, пока не пойдёт.
##
## Рендер настоящий, не headless — нужен экран.
##
## Запуск:
##     godot --path . res://tools/m24b_shot.tscn
##     godot --path . res://tools/m24b_shot.tscn -- --seed=3 --folder=M24b --quality=2
##
## Кадры ложатся в screens/<папка>/ — папка локальная, в репозиторий не идёт.

const MAIN_SCENE := preload("res://src/main.tscn")
const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24b"
## Сколько кадров дать камере догнать Otto после переноса.
const SETTLE_FRAMES: int = 45
## Сколько кадров ждать события, прежде чем сдаться.
const PATIENCE: int = 900
## Где агент появляется от двери, м: дальше места ожидания, чтобы было видно,
## что он к ней подошёл.
const AGENT_OFFSET: float = 3.2
## Насколько правее водительской двери Otto встаёт перед посадкой, м.
const CAR_APPROACH: float = 2.8
## Насколько от края шахты Otto стоит над подвалом, м.
const SHAFT_GAP: float = 0.5

var _main: Node = null
var _level: GreyboxLevel = null
var _hud: Hud = null
var _curtain: FadeCurtain = null
var _seed: int = 1
var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
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
	await _door()
	await _basement()
	await _exit()
	get_tree().quit()


## Партия в main, как у игрока, но здание — своего сида: main строит здание по
## номеру и соли партии, а съёмке нужно здание по `--seed`. Своё здание
## подключается к main теми же вызовами, что в [method Main._enter_building].
func _start() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	_main.call("_start_game")
	_main.call("_drop_level")
	_hud = _main.get_node("Hud") as Hud
	_curtain = _main.get(&"_curtain") as FadeCurtain
	GameState.instance().start_game()
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


## Красная дверь: вход, внутри с агентом у двери, выход.
func _door() -> void:
	var door := _red_door()
	if door == null:
		push_error("в здании нет красной двери")
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
	# Ждём, пока агент встанет на место, но не дольше, чем Otto сидит внутри.
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
		push_error("Otto вышел раньше, чем агент встал у двери")
	await _until(func() -> bool: return not _level.otto.is_hidden())
	await _frames(2)
	await _shoot("door_03_out")
	# Агент своё отснял: дальше он только стрелял бы в Otto.
	for enemy: Enemy in _level.agents():
		enemy.queue_free()
	await _until(func() -> bool: return _level.otto.is_on_foot())


## Подвал: над ним у шахты — заперт; последний документ — створки расходятся.
func _basement() -> void:
	var rules := _level.rules
	var bottom := rules.floors - 1
	var above := bottom - 1
	var lock := _level.find_child("BasementLock", false, false) as BasementLock
	var shaft := _basement_shaft()
	if shaft == null or lock == null:
		push_error("нет шахты в подвал или замка")
		return
	var aside := rules.shaft_width * 0.5 + Proportions.BODY_WIDTH * 0.5 + SHAFT_GAP
	_place(_clear_side(above, shaft.x, aside), rules.floor_surface(above))
	await _settle()
	# Кабина над подвалом стоит на створках и закрывает их собой: снимаем, когда
	# она ушла хотя бы на этаж вверх.
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
		push_error("подвал уже открыт — документов в здании нет?")
	var game := GameState.instance()
	while not game.all_documents_collected():
		game.collect_document()
	await _seconds(BasementLock.OPEN_TIME * 0.4)
	await _shoot("basement_02_opening")
	await _seconds(BasementLock.OPEN_TIME + 0.4)
	await _shoot("basement_03_open")


## Выход: у машины, посадка, фары и ворота, отъезд, бонус, затемнение.
func _exit() -> void:
	var rules := _level.rules
	var boarding := _level.get(&"_boarding") as ExitBoarding
	var door := _level.exit_position()
	var bonus := Arcade.building_bonus(GameState.instance().building)
	var floor_y := rules.floor_surface(rules.floors - 1)
	_place(door.x + CAR_APPROACH, floor_y)
	await _settle()
	await _shoot("exit_01_at_the_car")
	Input.action_press(&"move_left")
	var boarded := await _until(func() -> bool: return boarding.is_boarded())
	Input.action_release(&"move_left")
	if not boarded:
		return
	await _shoot("exit_02_boarding")
	await _until(func() -> bool: return boarding.phase == ExitBoarding.Phase.STARTING)
	await _seconds(0.8)
	await _shoot("exit_03_lights_gate")
	await _until(func() -> bool: return boarding.phase == ExitBoarding.Phase.LEAVING)
	await _seconds(0.45)
	await _shoot("exit_04_driving")
	# Бонус досчитан: машина к этому времени уже ушла, здание сдано.
	await _until(func() -> bool: return _hud.bonus_text() == Hud.format_score(bonus))
	await _shoot("exit_05_bonus")
	if await _until(func() -> bool: return _curtain.opacity() >= 0.5):
		await _shoot("exit_06_fade")


## Красная дверь, у которой по обе стороны есть место для агента: без стен и
## проёмов на [constant AGENT_OFFSET] в обе стороны.
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


## Ставит агента на этаже двери, пока жребий [DoorWatch] не пошлёт кого-то ждать.
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
	push_error("ни один агент не пошёл ждать у двери")
	return null


## Дошёл ли агент до места у двери.
func _standing_at(agent: Enemy) -> bool:
	if is_nan(agent.watch_at):
		return false
	return absf(WorldSpace.to_plane(agent.global_position).x - agent.watch_at) <= 0.2


## Нет ли на этаже [param index] ни стены, ни проёма между [param low] и [param high].
func _walkable(index: int, low: float, high: float) -> bool:
	for block: Vector2 in _level.plan().blocks_on(_level.rules, index):
		if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
			return false
	return true


## Сторона шахты в [param x], где на этаже есть пол, на [param aside] от её оси.
func _clear_side(index: int, x: float, aside: float) -> float:
	var half := Proportions.BODY_WIDTH * 0.5
	for side: float in [1.0, -1.0]:
		var spot := x + side * aside
		if _walkable(index, spot - half, spot + half):
			return spot
	return x + aside


## Шахта, которая спускается в подвал.
func _basement_shaft() -> BuildingPlan.ShaftSpot:
	var bottom := _level.rules.floors - 1
	for shaft: BuildingPlan.ShaftSpot in _level.plan().shafts:
		if shaft.bottom == bottom:
			return shaft
	return null


## Ведущая кабина шахты [param shaft].
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
	push_error("не дождался события за %d кадров" % PATIENCE)
	return false


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "res://screens/%s/%s.png" % [_folder, label]
	image.save_png(path)
	print("  %s" % ProjectSettings.globalize_path(path))
