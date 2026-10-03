class_name CityBackdrop
extends Node

## The city behind the building — its own world under a perspective camera, laid in as
## the background of the main frame (ADR-0029, decision 1).
##
## The main camera is orthographic (ADR-0023, decision 1), and houses placed in the same
## world would move at one speed at any depth: there would be no parallax. So the city
## lives in a [SubViewport] with its own [World3D]; its camera repeats the main one's
## movement but looks in perspective — far rows shift more slowly than near ones. The
## picture lies on a canvas behind the scene, and the main environment draws that
## canvas as the background ([constant Environment.BG_CANVAS]): where there is no
## building — behind the tower and above the roof — the city is visible.
##
## Windows are emission without light sources: the city does not touch the frame's lamp
## budget.

## Canvas layer the city lies on. Negative — behind the scene; the main environment
## draws as background everything not above it.
const CANVAS_LAYER: int = -1

## How far the city camera is moved back from the play plane, m. The strength of the
## parallax depends on it: the closer the camera, the faster the near row moves
## sideways relative to the far one.
const CAMERA_DISTANCE: float = 30.0

## Near and far planes of the city camera, m. There is nothing in the city closer than
## sixty metres, and depth precision grows with the near plane.
const LENS_NEAR: float = 1.0
const CITY_FAR: float = 700.0

## City defocus (ADR-0030, decision 2): sharp up to the near row, beyond — blurred, the
## more the farther. The play plane is not touched — the main camera has no depth of
## field.
##
## Distance is counted from the city camera, which is thirty metres in front of the play
## plane: the near row ([constant CityPlan.ROWS]) stands 90 to 102 m from it. With the
## defocus starting at 90 m the boundary cut the near row along its facade, and half its
## windows were sharp, half not (ADR-0037, decision 4).
const BLUR_FROM: float = 106.0
const BLUR_OVER: float = 120.0
const BLUR_AMOUNT: float = 0.035

## Windows of the exit street (`ExitStreet`) — as quads, as the city had before M24j.
const WINDOW_SIZE := Vector2(1.2, 1.5)

## Window brightness by depth row. Windows do not take the haze — in it they went dark
## along with the facades, and the night city came out without lights — so distance is
## set here.
const WINDOW_FADE: Array[float] = [1.0, 0.75, 0.55, 0.4]

## How strongly the panes light up in a lightning flash.
const FLASH_GLASS := Color(0.55, 0.6, 0.75)

## City haze — a share of the weather's density: far rows fade into the sky colour.
const HAZE: float = 0.25
## City exposure: Poly Haven panoramas are brighter than our frame.
const EXPOSURE: float = 0.8
## Window light strength by time of day: in the daytime the room behind the glass is
## darker than the sky.
const WINDOW_GLOW: Array[float] = [0.45, 0.2, 0.6, 0.65]
## City rain strength in the daytime — a share of the night one: against a light sky
## the drops are visible anyway.
const DAY_RAIN: float = 0.25
## Tone of the house tops.
const CROWN := Color(0.32, 0.31, 0.3)

var _view: SubViewport = null
var _camera: Camera3D = null
var _ground: float = 0.0
var _rules: BuildingRules = null
## Rain streaks or snowflakes at the city camera: their share is recomputed by the
## quality level.
var _rain_layers: Array[GPUParticles3D] = []
var _city_air: Environment = null
## Houses material: the share of lit windows and the lightning flash go into it.
var _house_look: ShaderMaterial = null
var _fog_banks: Node3D = null
var _lightning: Lightning = null
## The flash currently on the sky and in the panes.
var _flash_shown: float = 0.0


## Builds the city along the building by the rules and the seed, with weather
## [param weather] at time of day [param time] (ADR-0051).
func build(
	rules: BuildingRules,
	building_seed: int,
	weather: Weather.Kind,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
) -> void:
	_rules = rules
	_ground = WorldSpace.height_to_scene(rules.floor_surface(rules.floors - 1))
	# The city sounds like what it shows: street, rain or wind (ADR-0036).
	Sounds.set_weather(weather, time)
	_view = SubViewport.new()
	_view.name = "CityView"
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	var air := WorldEnvironment.new()
	_city_air = _air(weather, time)
	air.environment = _city_air
	_view.add_child(air)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_FRUSTUM
	_camera.near = LENS_NEAR
	_camera.far = CITY_FAR
	_camera.current = true
	var focus := CameraAttributesPractical.new()
	focus.dof_blur_far_enabled = true
	focus.dof_blur_far_distance = BLUR_FROM
	focus.dof_blur_far_transition = BLUR_OVER
	focus.dof_blur_amount = BLUR_AMOUNT
	_camera.attributes = focus
	_view.add_child(_camera)

	var blocks := CityPlan.generate(building_seed, 0.0, rules.width)
	var houses := _buildings(blocks)
	_view.add_child(houses)
	_house_look = (houses.multimesh.mesh as BoxMesh).material as ShaderMaterial
	_house_look.set_shader_parameter("lit_share", CityPlan.LIT_SHARE * TimeOfDay.lit_windows(time))
	_house_look.set_shader_parameter("window_glow", WINDOW_GLOW[time])
	_house_look.set_shader_parameter("snow", 1.0 if Weather.is_snowing(weather) else 0.0)
	_view.add_child(CitySky.light(time, weather))
	# City details (M22): tops, lights, neon, street glow.
	_view.add_child(CityDetails.crowns(blocks, _ground, _crown_look()))
	var lights := TimeOfDay.street_lights(time, weather)
	var signs := CityDetails.signs(blocks, _ground)
	var neon := (signs.multimesh.mesh as QuadMesh).material as ShaderMaterial
	neon.set_shader_parameter("power", lights)
	neon.set_shader_parameter("daylight", TimeOfDay.daylight(time))
	_view.add_child(signs)
	if lights > 0.0:
		_view.add_child(CityDetails.beacons(blocks, _ground))
		var glow := CityDetails.street_glow(_ground, 0.0, rules.width)
		((glow.mesh as QuadMesh).material as StandardMaterial3D).albedo_color.a = lights
		_view.add_child(glow)
	match weather:
		Weather.Kind.FOG:
			_fog_banks = CityDetails.fog_banks(building_seed, 0.0, rules.width, _ground)
			_view.add_child(_fog_banks)
		Weather.Kind.RAIN:
			# Streak layers at the camera and curtains between the rows (ADR-0037, decision 3).
			var share := lerpf(1.0, DAY_RAIN, TimeOfDay.daylight(time))
			_view.add_child(RainLook.city(_camera, _ground, 0.0, rules.width, share))
			_rain_layers = RainLook.city_layers(_camera)
			# Thunderstorm — only in the evening and at night (ADR-0051, decision 7).
			if TimeOfDay.has_thunder(time):
				_lightning = Lightning.new()
				_lightning.setup(building_seed, Vector2(0.0, rules.width), _ground)
				_view.add_child(_lightning)
		Weather.Kind.SNOW:
			# Flake layers at the camera, like rain streaks (ADR-0054); the share is by
			# quality level, as for rain.
			_rain_layers = SnowLook.city(_camera, time)

	var layer := CanvasLayer.new()
	layer.name = "CityLayer"
	layer.layer = CANVAS_LAYER
	add_child(layer)
	var picture := TextureRect.new()
	picture.name = "City"
	picture.texture = _view.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(picture)

	get_viewport().size_changed.connect(_fit_view)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Sets up the main environment so that it draws the city as the background.
static func show_behind(environment: Environment) -> void:
	environment.background_mode = Environment.BG_CANVAS
	environment.background_canvas_max_layer = CANVAS_LAYER


## Repeats the main camera's movement: the same x, y and tilt, its own depth and field
## of view at which the play plane is seen at the same scale.
func _process(delta: float) -> void:
	if _fog_banks != null:
		CityDetails.drift(_fog_banks, delta, 0.0, _rules.width)
	if _lightning != null:
		var flash := _lightning.level()
		# Between flashes the sky and panes are not rewritten every frame.
		if flash != _flash_shown:
			_flash_shown = flash
			(_city_air.sky.sky_material as ShaderMaterial).set_shader_parameter("flash", flash)
			# Lightning glint in the panes: the windows light up with the reflected sky.
			_house_look.set_shader_parameter("flash", flash)
	var main := get_viewport().get_camera_3d()
	if main == null or _camera == null:
		return
	# The building covered the whole frame — the city is not visible, and the second
	# frame is not drawn (ADR-0030, decision 7).
	var side := main as SideCamera
	# An open room shows the city in its window (ADR-0052, decision 5).
	var visible := side == null or is_visible_around(_rules, side.view()) or DoorRoom.open_count > 0
	_view.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	)
	if not visible:
		return
	follow(main)


## Places the city camera by the main one [param main]: on its axis, farther from the
## play plane, looking straight into depth (ADR-0037, decision 4).
##
## On the main one's axis, because the main camera stands above the target by its tilt,
## and a city camera placed straight opposite the target would shift the city 3.5 m
## down (code review M19). Straight rather than with the main one's tilt: in a tilted
## perspective the verticals converge, window edges step, and on the move the steps
## crawl along the rows of windows. The view from above is given by a lens shift — the
## frame moves down in the same plane, and verticals stay vertical.
func follow(main: Camera3D) -> void:
	var back := main.global_basis.z * (CAMERA_DISTANCE - SideCamera.DISTANCE)
	var place := main.global_position + back
	_camera.global_transform = Transform3D(Basis.IDENTITY, place)
	# Where the main camera's axis looked is the middle of the frame: on the play plane it
	# is below the camera by the depth multiplied by the tilt.
	var ahead := -main.global_basis.z
	var depth := maxf(place.z, 1.0)
	var drop := ahead.y / maxf(-ahead.z, 0.01)
	var height := main.size
	if main.projection != Camera3D.PROJECTION_ORTHOGONAL:
		# The perspective frame on the play plane is from the main camera's distance, not
		# the city's: otherwise the city in the frame is CAMERA_DISTANCE / DISTANCE times
		# smaller.
		height = 2.0 * SideCamera.DISTANCE * tan(deg_to_rad(main.fov) * 0.5)
	_camera.set_frustum(
		height * LENS_NEAR / depth, Vector2(0.0, drop * LENS_NEAR), LENS_NEAR, CITY_FAR
	)


## Whether the city is visible in frame [param view] (rules coordinates): yes if the
## roof or the sky above it got into the frame, or if at least one floor in the frame
## is narrower than the frame.
static func is_visible_around(rules: BuildingRules, view: Rect2) -> bool:
	if view.position.y < rules.floor_surface(BuildingRules.ROOF):
		return true
	var span := VisibleFloors.around(rules, view)
	for index in range(span.x, span.y + 1):
		var bounds := rules.floor_span(clampi(index, 0, rules.floors - 1))
		if view.position.x < bounds.x or view.end.x > bounds.y:
			return true
	return false


## Whether lightning strikes over the city: in rain in the evening and at night.
func has_lightning() -> bool:
	return _lightning != null


## Lightning flash brightness right now, 0–1: the building's air brightens with it.
func flash_level() -> float:
	return _lightning.level() if _lightning != null else 0.0


## Resolution and rain by quality level (ADR-0030, decision 5).
func apply_graphics() -> void:
	_fit_view()
	Graphics.smooth(_view)
	for layer in _rain_layers:
		RainLook.scale_amount(layer, Graphics.rain_share())


func _fit_view() -> void:
	# The level is removed from the tree before it is freed (main.gd, _drop_level), and
	# the window-size subscription lives until freeing: outside the tree there is no viewport.
	if not is_inside_tree():
		return
	var window := get_viewport().get_visible_rect().size
	_view.size = Vector2i(
		maxi(int(window.x * Graphics.city_share()), 1),
		maxi(int(window.y * Graphics.city_share()), 1)
	)


func _air(weather: Weather.Kind, time: TimeOfDay.Kind) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_SKY
	air.sky = Sky.new()
	air.sky.sky_material = CitySky.material(time, weather)
	air.sky.radiance_size = Sky.RADIANCE_SIZE_128
	# Light and reflections come from the sky: shadows go lilac at sunset and grey in rain
	# by themselves.
	air.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	air.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	air.fog_enabled = true
	# The haze takes the sky colour by direction: the distance fades into the sky, not grey.
	air.fog_aerial_perspective = 1.0
	air.fog_sky_affect = 0.0
	air.fog_density = Weather.city_fog(weather) * HAZE
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = EXPOSURE
	# Glow — so antenna lights and neon on far houses bloom in the blur.
	air.glow_enabled = true
	air.glow_intensity = 0.45
	air.glow_hdr_threshold = 1.5
	return air


## Material of the tops: setbacks, spires, tanks — concrete under the same light.
static func _crown_look() -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.albedo_color = CROWN
	look.roughness = 0.85
	return look


## Houses as one multimesh: there are hundreds, and a node per house is not needed. The
## facade is the pack's baked facade by the house's style, windows are in it too
## ([CityLook]).
func _buildings(blocks: Array[CityPlan.Block]) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.material = CityLook.building()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = box
	many.instance_count = blocks.size()
	for index in blocks.size():
		var block := blocks[index]
		var basis := Basis.from_scale(Vector3(block.width, block.height, block.depth))
		var centre := Vector3(block.x, _ground + block.height * 0.5, block.z)
		many.set_instance_transform(index, Transform3D(basis, centre))
		many.set_instance_color(index, CityLook.wall_tint(block))
		many.set_instance_custom_data(index, CityLook.building_custom(block))
	var node := MultiMeshInstance3D.new()
	node.name = "Buildings"
	node.multimesh = many
	return node


## Lit windows as one multimesh: a quad per window, colour per vertex, what is behind the
## glass — in the window data ([CityLook]); past the city haze.
static func window_quads(
	title: String, places: Array[Transform3D], colors: Array[Color], customs: Array[Color]
) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = WINDOW_SIZE
	quad.material = CityLook.windows()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colors[index])
		many.set_instance_custom_data(index, customs[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = many
	return node
