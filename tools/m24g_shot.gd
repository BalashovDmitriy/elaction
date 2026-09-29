extends Node3D

## Снимки M24g — кабина режет тела, трупы стопкой (ADR-0043, решения 7–11).
##
## Кабина ходит своим расписанием, и сценарий съёмки с выдержками её не
## застаёт. Инструмент кладёт трупы в настоящем здании и снимает по событиям:
## стопка из двух тел; тело поперёк порога стоящей кабины, миг разрыва и
## площадка после ухода кабины; трупы на дне шахты, днище на полпути по ним,
## кабина на полу и дно после её ухода.
##
## Запуск:
##     godot --path . res://tools/m24g_shot.tscn
##     godot --path . res://tools/m24g_shot.tscn -- --folder=M24G --seed=2
##
## Кадры ложатся в screens/<папка>/ (папка локальная, в репозиторий не идёт).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

const DEFAULT_FOLDER := "M24G"

## Сколько кадров дать камере доехать до Otto: сглаживание у неё 8.0.
const SETTLE_FRAMES: int = 60
## Сколько кадров ждать события, прежде чем сдаться.
const PATIENCE: int = 20000
## Во сколько раз ускорять мир, пока ждём кабину.
const HURRY: float = 6.0

var _level: GreyboxLevel = null
var _seed: int = 1
var _folder: String = DEFAULT_FOLDER


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(
		ProjectSettings.globalize_path(_folder_path().get_base_dir())
	)
	_run()


func _folder_path() -> String:
	return "res://screens/%s" % _folder


func _run() -> void:
	Blood.enabled = true
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = _seed
	_level.spawn_agents = false
	add_child(_level)
	await get_tree().physics_frame

	var car := _pick_car()
	if car == null:
		push_error("нет кабины без пары")
		get_tree().quit(1)
		return
	await _escalator()
	await _red_door()
	await _pile()
	await _threshold(car)
	await _bottom(car)
	get_tree().quit()


## Вход в красную дверь вглубь и выход из неё (решение 4).
func _red_door() -> void:
	var door: Door = null
	for node: Node in _level.find_children("*", "Door", true, false):
		if (node as Door).has_document:
			door = node as Door
			break
	if door == null:
		print("нет красной двери")
		return
	await _put_otto(WorldSpace.to_scene(door.mat_position()))
	print("у двери: ", _level.otto.global_position, " открыта ", door.openness())
	Input.action_press(&"move_up")
	await _until(func() -> bool: return door.openness() > 0.55)
	Input.action_release(&"move_up")
	await _shoot("00_door_going_in")
	await _until(func() -> bool: return _level.otto.visible and door.openness() > 0.9)
	await _until(func() -> bool: return door.openness() < 0.5)
	await _shoot("00_door_coming_out")
	await _frames(40)


## Эскалатор из деталей модели и Otto, идущий по ступеням (решения 2 и 3).
func _escalator() -> void:
	var found := _level.find_children("*", "Escalator", true, false)
	if found.is_empty():
		return
	var escalator := found[0] as Escalator
	var top := escalator.get_node("TopPad") as Node3D
	await _put_otto(top.global_position)
	await _shoot("00_escalator_top")
	Input.action_press(&"move_down")
	await _until(func() -> bool: return escalator.is_busy())
	Input.action_release(&"move_down")
	await _frames(28)
	await _shoot("00_escalator_riding")
	await _until(func() -> bool: return not escalator.is_busy())


## Кабина одиночной шахты, которая не ходит в подвал и дно которой светлое:
## на тёмном этаже срез не разглядеть.
func _pick_car() -> ElevatorCar:
	for node: Node in _level.find_children("*", "ElevatorCar", true, false):
		var car := node as ElevatorCar
		if car.is_deck() or car.is_bottom_locked():
			continue
		var shaft := _shaft_of(car)
		if _level.rules.is_unlit(shaft.bottom) or shaft.bottom < 16:
			continue
		return car
	return null


func _pile() -> void:
	var index := 12
	var spot := _level.plan().safe_x(_level.rules, index)
	var feet := WorldSpace.to_scene(Vector2(spot + 2.0, _level.rules.floor_surface(index)))
	await _put_otto(Vector3(feet.x - 2.0, feet.y, 0.0))
	await _corpse(feet + Vector3(0.0, 0.02, 0.0), 1.0)
	await _frames(90)
	await _corpse(feet + Vector3(-0.3, 0.6, 0.0), 1.0)
	await _frames(90)
	await _shoot("01_pile")


func _threshold(car: ElevatorCar) -> void:
	await _until(func() -> bool: return car.is_aligned() and is_zero_approx(car.speed_now()))
	car.hold(4.0)
	var wall := car.global_position.x - car.width() * 0.5
	var floor_y := car.global_position.y
	await _put_otto(Vector3(wall - 2.6, floor_y, 0.0))
	await _corpse(Vector3(wall + 0.35, floor_y + 0.02, 0.0), 1.0)
	await _frames(40)
	await _shoot("02_across_the_threshold")
	var start := car.global_position.y
	await _until(func() -> bool: return absf(car.global_position.y - start) > 0.25)
	await _shoot("03_torn")
	await _until(func() -> bool: return absf(car.global_position.y - start) > 2.5)
	await _frames(20)
	await _shoot("04_left_on_the_landing")


func _bottom(car: ElevatorCar) -> void:
	var shaft := _shaft_of(car)
	var bottom_y := (
		WorldSpace.to_scene(Vector2(shaft.x, _level.rules.floor_surface(shaft.bottom))).y
	)
	# Трупы кладутся, пока кабина далеко наверху: иначе они легли бы на неё.
	_hurry(true)
	await _until(func() -> bool: return car.bottom() > bottom_y + Proportions.FLOOR * 2.0)
	_hurry(false)
	var middle := car.global_position.x
	var half := car.width() * 0.5
	var side := 1.0 if _has_floor(middle + half + 2.4, bottom_y) else -1.0
	await _put_otto(Vector3(middle + side * (half + 2.4), bottom_y, 0.0))
	# Одно тело целиком под кабиной, второе поперёк её стенки со стороны Otto.
	await _corpse(Vector3(middle + side * 0.75, bottom_y + 0.02, 0.0), side)
	await _corpse(Vector3(middle + side * (half + 1.1), bottom_y + 0.02, 0.0), side)
	await _frames(60)
	await _shoot("05_bottom_before")
	_hurry(true)
	await _until(func() -> bool: return car.bottom() < bottom_y + 1.2 and car.speed_now() > 0.0)
	_hurry(false)
	await _until(func() -> bool: return car.bottom() < bottom_y + 0.25)
	await _shoot("06_bottom_cutting")
	await _until(func() -> bool: return is_zero_approx(car.speed_now()))
	await _shoot("07_bottom_on_the_floor")
	_hurry(true)
	await _until(func() -> bool: return car.bottom() > bottom_y + 2.8)
	_hurry(false)
	await _frames(20)
	await _shoot("08_bottom_after")


## Есть ли пол этажа на высоте [param y] под точкой [param x].
func _has_floor(x: float, y: float) -> bool:
	var from := Vector3(x, y + 0.5, WorldSpace.PLAY_Z)
	var query := PhysicsRayQueryParameters3D.create(from, from - Vector3(0.0, 1.0, 0.0), 1)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Ускоряет мир, пока ждём кабину, — вместе с частотой шагов физики: на
## длинном шаге суставы трупов разлетались бы (docs/testing.md).
func _hurry(on: bool) -> void:
	Engine.time_scale = HURRY if on else 1.0
	Engine.physics_ticks_per_second = int(60.0 * Engine.time_scale)


func _shaft_of(car: ElevatorCar) -> BuildingPlan.ShaftSpot:
	var best: BuildingPlan.ShaftSpot = null
	for shaft: BuildingPlan.ShaftSpot in _level.plan().shafts:
		var x := WorldSpace.to_scene(Vector2(shaft.x, 0.0)).x
		if (
			best == null
			or (
				absf(x - car.global_position.x)
				< absf(WorldSpace.to_scene(Vector2(best.x, 0.0)).x - car.global_position.x)
			)
		):
			best = shaft
	return best


func _put_otto(at: Vector3) -> void:
	_level.otto.global_position = Vector3(at.x, at.y, WorldSpace.PLAY_Z)
	await _frames(SETTLE_FRAMES)


func _corpse(at: Vector3, facing: float) -> Enemy:
	var agent := ENEMY_SCENE.instantiate() as Enemy
	agent.apply_rules(_level.rules)
	agent.walk_speed = 0.0
	_level.add_child(agent)
	agent.global_position = Vector3(at.x, at.y, WorldSpace.PLAY_Z)
	agent.setup(null, facing)
	while agent.is_emerging():
		await get_tree().physics_frame
	agent.held_facing = facing
	agent.held = true
	agent.held = false
	agent.kill()
	return agent


func _frames(count: int) -> void:
	for _frame: int in count:
		await get_tree().physics_frame


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
	var path := "%s/%s_seed%d.png" % [_folder_path(), label, _seed]
	image.save_png(path)
	print("  %s" % path)
