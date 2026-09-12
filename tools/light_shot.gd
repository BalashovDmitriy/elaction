extends Node2D

## Снимки освещения на настоящем здании — по состоянию, а не по секундомеру.
##
## Свет проверяется глазами, но игровым сценарием съёмки его не поймать: тот
## водится выдержками и снимает то, что успело случиться, а не то, что обещает
## подпись (docs/testing.md). Здесь всё иначе: здание собирается настоящее,
## этаж гаснет настоящей сбитой лампой, и кадр снимается ровно тогда, когда она
## долетела до пола.
##
## Запуск:
##     godot --path . res://tools/light_shot.tscn
##     godot --path . res://tools/light_shot.tscn -- --seed=3 --floor=12
##     godot --path . res://tools/light_shot.tscn -- --bench
##
## Кадры ложатся в screens/M6/. Папка локальная, в репозиторий не идёт.
##
## С [code]--bench[/code] вместо съёмки идёт замер: то же здание, но с агентами
## и перестрелкой, и считается, сколько стоит кадр. Это DoD вехи — синтетический
## замер из light_bench.gd меряет технику, а этот — игру.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const FOLDER := "res://screens/M6"

## Сколько кадров дать камере доехать до Otto: сглаживание у неё 8.0, то есть
## на дорогу уходит доля секунды, а снимок раньше показал бы полпути.
const SETTLE_FRAMES: int = 45

## Сколько кадров ждать падения лампы, прежде чем сдаться.
##
## Ожидание по состоянию лучше выдержки, но у него своя беда: не наступившее
## состояние ждётся вечно. Однажды так и вышло — сцена не собралась, лампы
## не было, и инструмент висел, вместо того чтобы сказать об этом.
const PATIENCE: int = 240

## Кадров на замер и сколько первых уходит на прогрев.
const BENCH_FRAMES: int = 240
const BENCH_WARMUP: int = 60

var _level: GreyboxLevel = null
var _seed: int = 1
var _floor: int = 7
var _bench: bool = false


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(FOLDER)
	_run()


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			_seed = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--floor="):
			_floor = argument.trim_prefix("--floor=").to_int()
		elif argument == "--bench":
			_bench = true


func _run() -> void:
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	if _level == null:
		# Чаще всего это незарегистрированный class_name: скрипт сцены тогда
		# не грузится молча. Лечится python tools/godot_check.py.
		push_error("сцена уровня не собралась — проверьте импорт проекта")
		get_tree().quit(1)
		return
	_level.building_seed = _seed
	# В съёмке агенты не нужны: они ходят и стреляют, и два кадра подряд вышли бы
	# разными. В замере, наоборот, без них мерить нечего — вся цена в перестрелке.
	_level.spawn_agents = _bench
	add_child(_level)
	await get_tree().physics_frame

	await _stand_on(_floor)
	if _bench:
		await _measure()
		get_tree().quit()
		return

	await _shoot("01_lit")

	# Гасим этаж под ногами: в кадре сойдутся горящий и погашенный, а порознь
	# их не сравнить — глаз меряет темноту только относительно соседа.
	var below := _floor + 1
	if await _drop_lamp_on(below):
		await _shoot("02_one_floor_dark")

	if await _drop_lamp_on(_floor):
		await _shoot("03_standing_in_the_dark")

	get_tree().quit()


## Ставит Otto на этаж и ждёт, пока камера доедет.
func _stand_on(index: int) -> void:
	_level.otto.global_position = Vector2(
		_level.plan().safe_x(_level.rules, index), _level.rules.floor_surface(index)
	)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().physics_frame


## Сбивает лампу этажа и ждёт, пока она долетит.
##
## Ждём не выдержку, а исчезновение узла: упавшая лампа убирает себя сама, и это
## тот самый миг, когда этаж гаснет. Возвращает false, если лампы там нет.
func _drop_lamp_on(index: int) -> bool:
	var lamp := _lamp_on(index)
	if lamp == null:
		push_warning("на этаже %d нет лампы" % index)
		return false

	lamp.shoot_down()
	var left := PATIENCE
	while is_instance_valid(lamp) and left > 0:
		left -= 1
		await get_tree().physics_frame
	if is_instance_valid(lamp):
		push_error("лампа на этаже %d не долетела за %d кадров" % [index, PATIENCE])
		return false
	# Ещё кадр: гасит этаж уровень, получив сигнал от лампы.
	await get_tree().physics_frame
	return true


func _lamp_on(index: int) -> Lamp:
	var surface := _level.rules.floor_surface(index)
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and _level.rules.floor_index_near(lamp.global_position.y) == index:
			if lamp.global_position.y < surface:
				return lamp
	return null


## Считает, сколько стоит кадр тёмного этажа с перестрелкой.
##
## Меряется время кадра, а не FPS: FPS упирается в вертикальную синхронизацию
## и до самого обвала показывает ровно 60, то есть врёт там, где важно.
func _measure() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	# Гасим этаж под ногами: тёмный этаж с боем — это и есть DoD вехи.
	await _drop_lamp_on(_floor)

	var spent := 0.0
	for frame: int in BENCH_FRAMES + BENCH_WARMUP:
		# Сигнал ничего не передаёт, длительность кадра спрашиваем отдельно.
		await get_tree().process_frame
		if frame >= BENCH_WARMUP:
			spent += get_process_delta_time()

	var per_frame := spent / float(BENCH_FRAMES) * 1000.0
	print("Видеокарта: %s" % RenderingServer.get_video_adapter_name())
	print(
		(
			"Здание %d, этаж %d, погашен, с агентами: %.2f мс/кадр, %.0f FPS"
			% [_seed, _floor, per_frame, 1000.0 / per_frame if per_frame > 0.0 else 0.0]
		)
	)
	print("Бюджет кадра при 60 FPS — 16.6 мс.")


func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_seed%d.png" % [FOLDER, label, _seed]
	image.save_png(path)
	print("  %s" % path)
