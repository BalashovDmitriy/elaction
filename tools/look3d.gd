extends Node3D

## Look probe: three floors of a building, assembled in 3D and shot by an orthocamera from the side.
##
## Answers one question — whether Godot can get close to the reference sent over
## and what it costs. Nothing from the game takes part here: this is a mock-up
## that lives exactly until the decision.
##
## Scale is metric: 100 game world units = 1 metre. Then our floor (360)
## is 3.6 m, the door (171) — 1.71 m, Otto (126) — 1.26 m. The numbers are taken from
## [BuildingRules] so that the probe measures our geometry, not a made-up one.
##
## Run:
##     godot --path . res://tools/look3d.tscn
##     godot --path . res://tools/look3d.tscn -- --folder=look3d --dark

const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")

## A metre in game units.
const UNIT: float = 100.0

## How many frames to give light and reflections to settle.
const SETTLE_FRAMES: int = 30

## Floor width in the frame and room depth, m.
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


## Material: colour, roughness, metal. Floor reflections are roughness,
## not a separate trick.
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

	# Three floors, as in the reference: one floor gives neither rhythm nor depth.
	for level: int in 3:
		var base := level * floor_height
		_shell(base, floor_height, slab)
		_shaft(rules, base)
		_props(base)
		_lights(base, floor_height)

	_environment()
	_camera(floor_height)


## Floor box: floor, ceiling, back wall, panels and skirting.
##
## Light needs something to fall on: a smooth box gives a flat fill and reads as
## a blurry spot. Pilasters and slab edges give an edge, and an edge is contrast.
func _shell(base: float, height: float, slab: float) -> void:
	var floor_material := _material(Color(0.21, 0.21, 0.23), 0.28, 0.2)
	var wall := _material(Color(0.33, 0.33, 0.35), 0.85)
	var trim := _material(Color(0.52, 0.50, 0.46), 0.4, 0.5)

	_box(Vector3(ROOM, slab, DEPTH), Vector3(0.0, base - slab * 0.5, -DEPTH * 0.5), floor_material)
	_box(Vector3(ROOM, slab, DEPTH), Vector3(0.0, base + height, -DEPTH * 0.5), wall)
	_box(Vector3(ROOM, height, 0.3), Vector3(0.0, base + height * 0.5, -DEPTH), wall)

	# Slab edge: a light strip on the cut. It is what separates floors from each other.
	_box(Vector3(ROOM, slab * 0.35, 0.12), Vector3(0.0, base - slab * 0.2, 0.06), trim)

	# Pilasters along the back wall — a rhythm that catches the lamp light.
	for step: int in 9:
		var x := -ROOM * 0.5 + 1.2 + step * 2.4
		_box(
			Vector3(0.45, height - 0.2, 0.22),
			Vector3(x, base + height * 0.5 - 0.1, -DEPTH + 0.25),
			_material(Color(0.40, 0.40, 0.42), 0.7)
		)

	# Skirting and panel at the bottom: a dark bottom holds the floor, a light top — the ceiling.
	_box(
		Vector3(ROOM, 0.9, 0.16),
		Vector3(0.0, base + 0.45, -DEPTH + 0.2),
		_material(Color(0.17, 0.17, 0.19), 0.6, 0.3)
	)
	_box(Vector3(ROOM, 0.08, 0.2), Vector3(0.0, base + 0.9, -DEPTH + 0.23), trim)


## Shaft: doors, posts, lintel, indicator board and the cab light behind the gap.
func _shaft(rules: BuildingRules, base: float) -> void:
	var dark_metal := _material(Color(0.26, 0.26, 0.28), 0.3, 0.85)
	var shaft := rules.shaft_width / UNIT * 2.2

	# The cab glows from inside: in the reference the warm rectangle of the lift is
	# the main light source of the frame, and the floor reflection comes from it too.
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
		# The doors are ajar: the warm cab light shows through the gap.
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


## Floor dressing: door, sign, planter, vending machine and Otto himself.
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

	# Otto: the same height as in the game after M13 — 1.26 m.
	var body := CSGCylinder3D.new()
	body.radius = 0.24
	body.height = 1.26
	body.position = Vector3(-2.2, base + 0.63, -1.6)
	body.material = _material(Color(0.86, 0.85, 0.82), 0.6)
	add_child(body)


## Floor light.
##
## The main lesson of the probe: the camera is orthographic and looks strictly sideways, so
## the floor is seen only edge-on, and its top plane is a zero-thickness strip.
## A lamp shining straight down lights exactly what is not in the frame.
## Light here is built as in a shop window: grazing along the back wall from above and
## a soft fill of the front faces from the camera side.
func _lights(base: float, height: float) -> void:
	for x: float in [-8.4, -4.8, -1.2, 2.4, 6.0, 9.0]:
		# Fixture housing: without it the lamp hangs as a glowing strip in the air.
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

		# Tilted back: the cone falls on the back wall, not into the invisible floor.
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

		# Front face fill: without it everything facing the camera is black.
		var fill := OmniLight3D.new()
		fill.position = Vector3(x, base + height * 0.62, 1.6)
		fill.light_color = Color(0.86, 0.88, 1.0)
		fill.light_energy = 1.6
		fill.omni_range = 7.0
		fill.omni_attenuation = 1.2
		add_child(fill)

	# Light from the shaft: it does not go out together with the floor — as in the game.
	var shaft_light := OmniLight3D.new()
	shaft_light.position = Vector3(0.0, base + 1.5, -0.7)
	shaft_light.light_color = Color(0.8, 0.9, 1.0)
	shaft_light.light_energy = 4.0
	shaft_light.omni_range = 5.5
	shaft_light.shadow_enabled = true
	add_child(shaft_light)


## The probe's air is the same [Atmosphere] as in the building: reflections, SSAO, fog,
## glow and tonemapping came from here, and keeping them as a second list means
## tuning numbers on a frame other than the one they later work on.
##
## The probe has two things of its own: a blacker sky — no buildings around, and the background
## must not compete with the stand — and a higher overall tone, since there is no round palette.
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
	# A frame of the same height as in the game: 1080 world units = 10.8 m, three floors.
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

	# Frame cost: the reference's is not free either, and it must be known before the decision.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var spent := 0.0
	for frame: int in 180:
		await get_tree().process_frame
		if frame >= 60:
			spent += get_process_delta_time()
	print("  %.2f мс/кадр при бюджете 16.6" % (spent / 120.0 * 1000.0))
	get_tree().quit()
