extends Node3D

## Кадры M18b вблизи: эскалатор, столб света в шахте, двухэтажная пара.
##
## Съёмка вехи ([code]capture.py[/code]) и кадры раскладки ([code]layout_shot.gd[/code])
## снимают этаж целиком — в такой кадр эскалатор влезает полоской в четверть
## высоты, и по нему не видно ни ступеней, ни балюстрады. Здесь камера своя и
## близкая: кадр про конструкцию, а не про этаж.
##
## Это и есть проверка DoD M18b ([ADR-0025](res://docs/adr/0025-shafts-escalators-and-riders.md)):
## эскалатор выглядит эскалатором, шахта читается на погашенном этаже, а пара
## ярусов ходит вместе.
##
## Рендер настоящий, не headless — нужен экран.
##
## Запуск:
##     godot --path . res://tools/geometry_shot.tscn

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Куда складываются кадры.
const FOLDER := "res://screens/M18b"

## Сколько кадров дать зданию, свету и отражениям устояться.
const SETTLE_FRAMES: int = 45

## Потолок ожидания, пока сбитые лампы долетят до пола, шагов физики.
const FALL_STEPS: int = 240

## Сид тот же, что у остальных инструментов вехи: раскладка по нему разобрана
## в статусе, и кадры сравниваются с ней, а не с новым зданием.
const BUILDING_SEED: int = 1

## Как далеко камера стоит от плоскости игры и на сколько наклонена. Числа
## [SideCamera]: кадр обязан быть тем же, что видит игрок, только ближе.
const DISTANCE: float = 20.0
const TILT_DEGREES: float = 10.0

var _level: GreyboxLevel = null
var _camera: Camera3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	GameState.instance().start_game()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.new()
	_level.building_seed = BUILDING_SEED
	# Кадр про конструкцию: ходящая фигура закрывает собой то, ради чего он снят.
	_level.spawn_agents = false
	add_child(_level)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation = Vector3(-deg_to_rad(TILT_DEGREES), 0.0, 0.0)
	_camera.near = 0.05
	_camera.far = DISTANCE * 2.0
	add_child(_camera)
	_run()


func _run() -> void:
	var spot := _escalator_under_a_lamp()
	var rules := _level.rules
	# Кадр охватывает оба пролёта и оба этажа, которые эскалатор связывает.
	var middle := Vector2(
		spot.x + spot.towards * rules.escalator_run * 0.5,
		rules.floor_surface(spot.floor_index) + rules.floor_height * 0.5
	)
	_stand_otto_on_the_top_pad(spot)
	await _shoot("01_escalator", middle, 7.2)

	await _shoot_the_dark_shaft("02_shaft_dark")
	await _shoot_the_pair("03_double_deck")

	print("  кадры геометрии в %s" % FOLDER)
	get_tree().quit(0)


## Кадр двухэтажной пары: оба яруса и тяги между ними.
##
## Кадр берёт два этажа разом — иначе видно один ярус, и пара ничем не
## отличается от обычной кабины.
func _shoot_the_pair(label: String) -> void:
	var rules := _level.rules
	var shaft := _double_deck_shaft()
	if shaft == null:
		push_error("на сиде %d пара не выпала — кадр снять не с чего" % BUILDING_SEED)
		get_tree().quit(1)
		return

	var span := shaft.ride_span()
	var index := span.x
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(shaft.x + rules.shaft_width, rules.floor_surface(index))
	)
	_level.otto.velocity = Vector3.ZERO
	# Середина между этажом верхнего яруса и этажом нижнего: пара стоит через
	# этаж, и в кадр должны попасть оба.
	var middle := rules.floor_surface(index) + rules.floor_height * 0.5
	await _shoot(label, Vector2(shaft.x, middle), 4.2)


func _double_deck_shaft() -> BuildingPlan.ShaftSpot:
	for shaft in _level.plan().shafts:
		if shaft.double_deck:
			return shaft
	return null


## Кадр шахты на погашенном этаже: лампы сбиты, светит только столб.
##
## Это и есть проверка решения 3: шахта обязана читаться всегда, иначе
## погашенное здание перестаёт быть проходимым на глаз.
func _shoot_the_dark_shaft(label: String) -> void:
	var rules := _level.rules
	# Широкий этаж пониже: там шахт на этаже больше всего, и ламп тоже три.
	var index := rules.floors - 3
	var shaft_x := _shaft_x_on(index)
	for lamp in _lamps_on(index):
		lamp.shoot_down()
	await _settle_after_the_fall()

	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(shaft_x + rules.shaft_width, rules.floor_surface(index))
	)
	_level.otto.velocity = Vector3.ZERO
	await _shoot(label, Vector2(shaft_x, rules.floor_surface(index) - rules.floor_height), 5.4)


## Столбец первой шахты, обслуживающей этаж.
func _shaft_x_on(index: int) -> float:
	for shaft in _level.plan().shafts:
		if index >= shaft.top and index <= shaft.bottom:
			return shaft.x
	return 0.0


func _lamps_on(index: int) -> Array[Lamp]:
	var found: Array[Lamp] = []
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.floor_index == index and not lamp.is_queued_for_deletion():
			found.append(lamp)
	return found


## Ждёт, пока сбитые лампы долетят до пола: по состоянию, а не выдержкой.
func _settle_after_the_fall() -> void:
	var left := FALL_STEPS
	while left > 0 and _falling():
		await get_tree().physics_frame
		left -= 1
	await get_tree().physics_frame


func _falling() -> bool:
	for child in _level.get_children():
		var lamp := child as Lamp
		if lamp != null and lamp.is_queued_for_deletion():
			return true
	return false


## Эскалатор, к которому ближе всего лампа его этажа.
##
## Кадр о конструкции: ступени, балюстрада и поручень видны только под светом.
## Эскалаторов на здание пяток, и половина из них стоит в неосвещённой части
## этажа — снятый там, кадр показывал бы зоны ламп M17, а не геометрию M18b.
func _escalator_under_a_lamp() -> BuildingPlan.EscalatorSpot:
	var plan := _level.plan()
	var best: BuildingPlan.EscalatorSpot = plan.escalators[0]
	var best_gap := INF
	for spot in plan.escalators:
		for lamp in plan.lamps:
			if lamp.floor_index != spot.floor_index:
				continue
			var gap := absf(lamp.x - spot.x)
			if gap < best_gap:
				best_gap = gap
				best = spot
	return best


## Ставит Otto на верхнюю площадку: кадр должен показывать и то, что борт со
## стороны камеры его не закрывает (ADR-0025, решение 5).
func _stand_otto_on_the_top_pad(spot: BuildingPlan.EscalatorSpot) -> void:
	var rules := _level.rules
	_level.otto.global_position = WorldSpace.to_scene(
		Vector2(spot.x, rules.floor_surface(spot.floor_index))
	)
	_level.otto.velocity = Vector3.ZERO


## Снимает кадр, наведённый на точку правил, с заданной половиной высоты кадра.
func _shoot(label: String, centre: Vector2, half_height: float) -> void:
	var at := WorldSpace.to_scene(centre)
	_camera.size = half_height * 2.0
	_camera.global_position = Vector3(
		at.x, at.y + DISTANCE * tan(deg_to_rad(TILT_DEGREES)), DISTANCE
	)

	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [FOLDER, label]
	image.save_png(path)
	print("  %s" % path)
