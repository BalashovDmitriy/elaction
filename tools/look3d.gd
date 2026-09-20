extends Node3D

## Проба вида: три этажа здания, собранные в 3D и снятые ортокамерой сбоку.
##
## Отвечает на один вопрос — можно ли в Godot подойти к присланному референсу
## и во что это обойдётся. Ничего из игры здесь не участвует: это макет,
## который живёт ровно до решения.
##
## Масштаб — метрический: 100 единиц мира игры = 1 метр. Тогда наш этаж (360)
## это 3.6 м, дверь (171) — 1.71 м, Otto (126) — 1.26 м. Числа взяты из
## [BuildingRules], чтобы проба меряла нашу геометрию, а не выдуманную.
##
## Запуск:
##     godot --path . res://tools/look3d.tscn
##     godot --path . res://tools/look3d.tscn -- --folder=look3d --dark

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

## Метр в единицах игры.
const UNIT: float = 100.0

## Сколько кадров дать свету и отражениям устояться.
const SETTLE_FRAMES: int = 30

## Ширина этажа в кадре и глубина комнаты, м.
const ROOM: float = 21.0
const DEPTH: float = 7.0

var _folder: String = "look3d"
var _dark: bool = false


func _ready() -> void:
	_read_arguments()
	DirAccess.make_dir_recursive_absolute(_folder_path())
	SCREENSHOTTER.mark_ignored_by_engine(
		ProjectSettings.globalize_path(_folder_path().get_base_dir())
	)
	_build()
	_run()


func _folder_path() -> String:
	return "res://screens/%s" % _folder


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			_folder = argument.trim_prefix("--folder=").strip_edges()
		elif argument == "--dark":
			_dark = true


## Материал: цвет, шероховатость, металл. Отражения в полу — это roughness,
## а не отдельный приём.
func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _box(size: Vector3, origin: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = origin
	node.material_override = material
	add_child(node)
	return node


func _build() -> void:
	var rules := BuildingRules.new()
	var floor_height := rules.floor_height / UNIT
	var slab := rules.slab_height / UNIT

	# Три этажа, как на референсе: один этаж не даёт ни ритма, ни глубины.
	for level: int in 3:
		var base := level * floor_height
		_shell(base, floor_height, slab)
		_shaft(rules, base)
		_props(base)
		_lights(base, floor_height)

	_environment()
	_camera(floor_height)


## Коробка этажа: пол, потолок, задняя стена, панели и плинтус.
##
## Свету нужно на что ложиться: гладкий бокс отдаёт ровную заливку и читается
## размытым пятном. Пилястры и торцы плит дают ребро, а ребро — это контраст.
func _shell(base: float, height: float, slab: float) -> void:
	var floor_material := _material(Color(0.21, 0.21, 0.23), 0.28, 0.2)
	var wall := _material(Color(0.33, 0.33, 0.35), 0.85)
	var trim := _material(Color(0.52, 0.50, 0.46), 0.4, 0.5)

	_box(Vector3(ROOM, slab, DEPTH), Vector3(0.0, base - slab * 0.5, -DEPTH * 0.5), floor_material)
	_box(Vector3(ROOM, slab, DEPTH), Vector3(0.0, base + height, -DEPTH * 0.5), wall)
	_box(Vector3(ROOM, height, 0.3), Vector3(0.0, base + height * 0.5, -DEPTH), wall)

	# Торец плиты: светлая полоса на срезе. Ею этажи и отбиваются друг от друга.
	_box(Vector3(ROOM, slab * 0.35, 0.12), Vector3(0.0, base - slab * 0.2, 0.06), trim)

	# Пилястры по задней стене — ритм, который ловит свет ламп.
	for step: int in 9:
		var x := -ROOM * 0.5 + 1.2 + step * 2.4
		_box(
			Vector3(0.45, height - 0.2, 0.22),
			Vector3(x, base + height * 0.5 - 0.1, -DEPTH + 0.25),
			_material(Color(0.40, 0.40, 0.42), 0.7)
		)

	# Плинтус и панель по низу: тёмный низ держит пол, светлый верх — потолок.
	_box(
		Vector3(ROOM, 0.9, 0.16),
		Vector3(0.0, base + 0.45, -DEPTH + 0.2),
		_material(Color(0.17, 0.17, 0.19), 0.6, 0.3)
	)
	_box(Vector3(ROOM, 0.08, 0.2), Vector3(0.0, base + 0.9, -DEPTH + 0.23), trim)


## Шахта: створки, стойки, перемычка, табло и свет кабины за щелью.
func _shaft(rules: BuildingRules, base: float) -> void:
	var dark_metal := _material(Color(0.26, 0.26, 0.28), 0.3, 0.85)
	var shaft := rules.shaft_width / UNIT * 2.2

	# Кабина светится изнутри: на референсе тёплый прямоугольник лифта —
	# главный источник кадра, и от него же идёт отражение в полу.
	_box(
		Vector3(shaft * 0.9, 2.15, 0.1),
		Vector3(0.0, base + 1.08, -1.75),
		_material(Color(0.42, 0.34, 0.26), 0.7)
	)
	_box(
		Vector3(shaft * 0.62, 0.08, 0.3),
		Vector3(0.0, base + 2.0, -1.5),
		_glow(Color(1.0, 0.86, 0.62), 1.1)
	)
	var car_light := OmniLight3D.new()
	car_light.position = Vector3(0.0, base + 1.8, -1.45)
	car_light.light_color = Color(1.0, 0.84, 0.6)
	car_light.light_energy = 3.2
	car_light.omni_range = 3.0
	add_child(car_light)
	for side: float in [-1.0, 1.0]:
		# Створки приоткрыты: сквозь щель и виден тёплый свет кабины.
		_box(
			Vector3(shaft * 0.44, 2.2, 0.12),
			Vector3(side * shaft * 0.28, base + 1.1, -1.0),
			_material(Color(0.44, 0.41, 0.36), 0.25, 0.95)
		)
		_box(
			Vector3(0.12, 2.35, 0.2),
			Vector3(side * (shaft * 0.5 + 0.1), base + 1.18, -1.0),
			dark_metal
		)
	_box(Vector3(shaft + 0.5, 0.3, 0.24), Vector3(0.0, base + 2.35, -1.0), dark_metal)
	_box(
		Vector3(1.2, 0.18, 0.06), Vector3(0.0, base + 2.6, -0.9), _glow(Color(1.0, 0.45, 0.14), 1.6)
	)


## Обстановка этажа: дверь, табличка, кадка, автомат и сам Otto.
func _props(base: float) -> void:
	_box(
		Vector3(0.95, 1.71, 0.14),
		Vector3(-5.6, base + 0.855, -DEPTH + 0.45),
		_material(Color(0.19, 0.17, 0.15), 0.5)
	)
	_box(
		Vector3(1.15, 1.9, 0.08),
		Vector3(-5.6, base + 0.95, -DEPTH + 0.38),
		_material(Color(0.30, 0.28, 0.25), 0.6)
	)
	_box(
		Vector3(0.4, 0.13, 0.04),
		Vector3(-5.6, base + 2.02, -DEPTH + 0.53),
		_glow(Color(0.3, 1.0, 0.5), 1.4)
	)

	_box(
		Vector3(1.8, 0.5, 0.7),
		Vector3(3.4, base + 0.25, -1.9),
		_material(Color(0.15, 0.15, 0.16), 0.6)
	)
	_box(
		Vector3(0.9, 1.9, 0.5),
		Vector3(6.2, base + 0.95, -2.2),
		_material(Color(0.13, 0.13, 0.15), 0.35, 0.6)
	)
	_box(
		Vector3(0.8, 1.5, 0.06),
		Vector3(6.2, base + 1.1, -1.94),
		_material(Color(0.45, 0.42, 0.4), 0.45, 0.6)
	)
	_box(
		Vector3(0.66, 1.34, 0.06),
		Vector3(6.2, base + 1.1, -1.9),
		_glow(Color(0.85, 0.25, 0.55), 0.8)
	)

	# Otto: рост тот же, что в игре после M13, — 1.26 м.
	var body := CSGCylinder3D.new()
	body.radius = 0.24
	body.height = 1.26
	body.position = Vector3(-2.2, base + 0.63, -1.6)
	body.material = _material(Color(0.86, 0.85, 0.82), 0.6)
	add_child(body)


## Свет этажа.
##
## Главный урок пробы: камера ортографическая и смотрит строго вбок, поэтому
## пол виден только торцом, а его верхняя плоскость — нулевой толщины полоска.
## Лампа, светящая вертикально вниз, освещает ровно то, чего в кадре нет.
## Свет здесь строится как в витрине: скользящий по задней стене сверху и
## мягкая подсветка передних граней со стороны камеры.
func _lights(base: float, height: float) -> void:
	for x: float in [-8.4, -4.8, -1.2, 2.4, 6.0, 9.0]:
		# Корпус светильника: без него лампа висит светящейся полоской в воздухе.
		_box(
			Vector3(1.1, 0.14, 0.5),
			Vector3(x, base + height - 0.55, -2.2),
			_material(Color(0.22, 0.22, 0.24), 0.4, 0.7)
		)
		_box(
			Vector3(0.95, 0.06, 0.36),
			Vector3(x, base + height - 0.64, -2.2),
			_glow(Color(1.0, 0.94, 0.86), 1.2)
		)

		# Наклон назад: конус ложится на заднюю стену, а не в невидимый пол.
		var spot := SpotLight3D.new()
		spot.position = Vector3(x, base + height - 0.7, -2.2)
		spot.rotation_degrees = Vector3(-52.0, 0.0, 0.0)
		spot.light_energy = 0.0 if _dark else 9.0
		spot.light_color = Color(1.0, 0.93, 0.84)
		spot.spot_range = 8.0
		spot.spot_angle = 46.0
		spot.spot_attenuation = 0.7
		spot.shadow_enabled = true
		add_child(spot)

		# Подсветка передних граней: без неё всё, что смотрит в камеру, чёрное.
		var fill := OmniLight3D.new()
		fill.position = Vector3(x, base + height * 0.62, 1.6)
		fill.light_color = Color(0.86, 0.88, 1.0)
		fill.light_energy = 1.6
		fill.omni_range = 7.0
		fill.omni_attenuation = 1.2
		add_child(fill)

	# Свет из шахты: он не гаснет вместе с этажом — как и в игре.
	var shaft_light := OmniLight3D.new()
	shaft_light.position = Vector3(0.0, base + 1.5, -0.7)
	shaft_light.light_color = Color(0.8, 0.9, 1.0)
	shaft_light.light_energy = 4.0
	shaft_light.omni_range = 5.5
	shaft_light.shadow_enabled = true
	add_child(shaft_light)


## Воздух пробы — тот же [Atmosphere], что и в здании: отражения, SSAO, туман,
## свечение и тонмаппинг пришли отсюда, и держать их вторым списком значит
## подбирать числа не на том кадре, на котором они потом работают.
##
## Своего у пробы два: чернее небо — здания вокруг нет, и фон не должен спорить
## со стендом, — и общий тон выше, потому что палитры раунда здесь нет.
func _environment() -> void:
	var air := Atmosphere.environment(Color(0.09, 0.11, 0.16))
	air.background_color = Color(0.008, 0.01, 0.016)
	air.ambient_light_energy = 0.8

	var world := WorldEnvironment.new()
	world.environment = air
	add_child(world)


func _camera(floor_height: float) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Кадр той же высоты, что и в игре: 1080 единиц мира = 10.8 м, три этажа.
	camera.size = 10.8
	camera.position = Vector3(0.0, floor_height * 1.5, 9.0)
	camera.near = 0.05
	camera.far = 60.0
	add_child(camera)
	camera.current = true


func _run() -> void:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var shot := "02_dark" if _dark else "01_lit"
	var path := "%s/%s.png" % [_folder_path(), shot]
	image.save_png(path)
	print("  %s" % path)

	# Цена кадра: у референса она тоже не бесплатная, и знать её надо до решения.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var spent := 0.0
	for frame: int in 180:
		await get_tree().process_frame
		if frame >= 60:
			spent += get_process_delta_time()
	print("  %.2f мс/кадр при бюджете 16.6" % (spent / 120.0 * 1000.0))
	get_tree().quit()
