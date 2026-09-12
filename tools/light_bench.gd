extends SceneTree

## Замер бюджета 2D-освещения: сколько источников света держит кадр.
##
## Долг, заведённый ещё в M0 и записанный в STATUS: потолок источников в Godot
## не проверялся ни разу, а вся M6 на него опирается. Гадать нельзя — меряем.
##
## Считается время кадра, а не FPS: FPS упирается в вертикальную синхронизацию
## и до самого обвала показывает ровно 60, то есть врёт как раз там, где важно.
## Поэтому синхронизация выключается и меряется, сколько кадр стоит на самом деле.
##
## Запуск (без --headless: нужен настоящий GPU):
##     godot --path . --script res://tools/light_bench.gd
##
## Сцена нарочно похожа на здание: перекрытия-окклюдеры поперёк экрана и лампы
## под ними. Синтетика из ламп в пустоте померила бы не то, что будет в игре.

## Сколько источников проверяем.
const COUNTS: Array[int] = [0, 4, 8, 12, 16, 24, 32, 48]

## Кадров на замер и сколько первых выбрасывается на прогрев.
const FRAMES: int = 90
const WARMUP: int = 30

## Размер окна замера — тот же, что у игры.
const VIEW := Vector2i(1280, 720)

## Радиус лампы, px. Примерно высота этажа: свет не должен бить на два этажа.
const LIGHT_RADIUS: float = 140.0

var _root: Node2D = null
var _lights: Array[PointLight2D] = []
var _texture: Texture2D = null
var _environment: WorldEnvironment = null

var _cases: Array[Dictionary] = []
var _case: int = 0
var _frame: int = 0
var _spent: float = 0.0
var _results: Array[String] = []


func _initialize() -> void:
	# Кадр должен считаться так быстро, как может: иначе замер упрётся в 16.6 мс
	# и все конфигурации покажут одно и то же число.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(VIEW)
	Engine.max_fps = 0

	_texture = _light_texture()
	_root = Node2D.new()
	root.add_child(_root)
	_build_building()
	_build_environment()
	_build_cases()
	_start_case()


func _process(delta: float) -> bool:
	_frame += 1
	if _frame > WARMUP:
		_spent += delta
	if _frame < WARMUP + FRAMES:
		return false

	_finish_case()
	_case += 1
	if _case >= _cases.size():
		_report()
		return true
	_start_case()
	return false


## Готовит очередную конфигурацию: сколько ламп зажечь и с тенями ли.
func _start_case() -> void:
	var settings := _cases[_case]
	var count: int = settings["lights"]
	var shadows: bool = settings["shadows"]
	_environment.environment.glow_enabled = settings["glow"]

	for index: int in _lights.size():
		var light := _lights[index]
		light.visible = index < count
		light.shadow_enabled = shadows

	_frame = 0
	_spent = 0.0


func _finish_case() -> void:
	var settings := _cases[_case]
	if settings["warmup"]:
		# Первый прогон оплачивает создание окна и компиляцию шейдеров.
		return

	var per_frame := _spent / float(FRAMES) * 1000.0
	var line := (
		"%3d источников, тени %-3s, bloom %-3s — %6.2f мс/кадр, %5.0f FPS%s"
		% [
			settings["lights"],
			"да" if settings["shadows"] else "нет",
			"да" if settings["glow"] else "нет",
			per_frame,
			1000.0 / per_frame if per_frame > 0.0 else 0.0,
			"" if per_frame <= 16.6 else "   ← не держит 60",
		]
	)
	_results.append(line)


func _build_cases() -> void:
	_cases.append(_case_of(0, false, false, true))
	for shadows: bool in [false, true]:
		for count: int in COUNTS:
			_cases.append(_case_of(count, shadows, false, false))
	# Пост-обработка в 2D обычно дороже самих источников: она платит за весь
	# экран, а не за пятна света. Меряем её отдельно и на тех же раскладах.
	for count: int in [0, 12, 24]:
		_cases.append(_case_of(count, true, true, false))


static func _case_of(lights: int, shadows: bool, glow: bool, warmup: bool) -> Dictionary:
	return {"lights": lights, "shadows": shadows, "glow": glow, "warmup": warmup}


## Пост-обработка кадра. Режим фона — canvas: в 2D свечение берётся с холста,
## а не с трёхмерного неба, которого здесь нет вовсе.
func _build_environment() -> void:
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CANVAS
	settings.glow_enabled = false
	settings.glow_intensity = 0.6
	settings.glow_bloom = 0.1
	settings.glow_hdr_threshold = 0.9

	_environment = WorldEnvironment.new()
	_environment.environment = settings
	_root.add_child(_environment)


## Здание в миниатюре: перекрытия поперёк экрана и лампа под каждым.
##
## Перекрытия — окклюдеры: именно они делают тени дорогими, и без них замер
## показал бы цену голого источника, которой в игре не будет.
func _build_building() -> void:
	var ambient := CanvasModulate.new()
	ambient.color = Color(0.25, 0.25, 0.32)
	_root.add_child(ambient)

	var floors := 6
	var height := float(VIEW.y) / float(floors)
	for index: int in floors:
		var top := height * float(index)
		_add_slab(Vector2(0.0, top), Vector2(float(VIEW.x), 16.0))
		_add_room(Vector2(0.0, top + 16.0), Vector2(float(VIEW.x), height - 16.0))

	# Порядок важен: [method _start_case] зажигает первые count источников, и при
	# обходе этаж за этажом расклад на четыре лампы весь оседал бы на верхнем
	# этаже — поверх одних и тех же окклюдеров. Меряли бы не то, что в игре.
	var per_floor := int(ceil(float(COUNTS[COUNTS.size() - 1]) / float(floors)))
	var step := float(VIEW.x) / float(per_floor + 1)
	for slot: int in per_floor:
		for index: int in floors:
			var top := height * float(index) + 24.0
			_lights.append(_add_light(Vector2(step * float(slot + 1), top)))


func _add_slab(at: Vector2, size: Vector2) -> void:
	var panel := ColorRect.new()
	panel.position = at
	panel.size = size
	panel.color = Color(0.30, 0.32, 0.38)
	_root.add_child(panel)

	var occluder := LightOccluder2D.new()
	var shape := OccluderPolygon2D.new()
	shape.polygon = PackedVector2Array(
		[
			at,
			at + Vector2(size.x, 0.0),
			at + size,
			at + Vector2(0.0, size.y),
		]
	)
	occluder.occluder = shape
	_root.add_child(occluder)


func _add_room(at: Vector2, size: Vector2) -> void:
	var panel := ColorRect.new()
	panel.position = at
	panel.size = size
	panel.color = Color(0.16, 0.17, 0.22)
	_root.add_child(panel)


func _add_light(at: Vector2) -> PointLight2D:
	var light := PointLight2D.new()
	light.position = at
	light.texture = _texture
	light.energy = 1.0
	light.color = Color(1.0, 0.93, 0.75)
	light.shadow_enabled = true
	_root.add_child(light)
	return light


## Круглое пятно света. Своё, а не из ассетов: их ещё нет, а замеру нужна
## та же текстура, что будет в игре, — градиент от центра к краю.
func _light_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = int(LIGHT_RADIUS * 2.0)
	texture.height = int(LIGHT_RADIUS * 2.0)
	return texture


func _report() -> void:
	print("")
	print("Бюджет 2D-освещения, окно %d×%d" % [VIEW.x, VIEW.y])
	print("Видеокарта: %s" % RenderingServer.get_video_adapter_name())
	print("")
	for line: String in _results:
		print(line)
	print("")
