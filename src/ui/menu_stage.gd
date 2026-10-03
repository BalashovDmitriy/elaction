class_name MenuStage
extends Node3D

## The night city behind the main menu (ADR-0035, decision 1).
##
## There is no building here — only [CityBackdrop] with its own camera. The city can live
## by itself: weather, lightning, blinking lights — and it drives its camera by the current camera
## of the root world. So it is enough to place the ortho camera the way
## [SideCamera] places it above the roof, and move it slowly along the street: the city provides
## the parallax of the blocks itself.
##
## The building is deliberately not built: [GreyboxLevel] drags Otto, the game and
## the quality measurement along with it, while the menu needs a view, not a game.

## Camera pan speed along the street, m/s. Slow: a background, not a ride.
const DRIFT_SPEED: float = 0.35
## How far above the roof the middle of the frame is, in frame fractions: the sky and house tops
## take more than half, the streets below fade in the haze.
const LIFT: float = 0.18
## How many times wider the menu frame is than the game one. In the game the city is seen as a band
## behind the building; behind the menu there is no building, and with the game frame the windows
## filled the whole screen — there was no city silhouette, only blurred squares.
const WIDEN: float = 3.0

var weather: Weather.Kind = Weather.Kind.RAIN

var _rules: BuildingRules = null
var _camera: Camera3D = null
var _city: CityBackdrop = null
var _time: float = 0.0


## Assembles the scene. Weather — by [param stage_seed]: the same draw as a building's.
func build(stage_seed: int) -> void:
	_rules = BuildingRules.new()
	weather = Weather.of_seed(stage_seed)
	# The menu stands on the street: ambience at full strength, as on the roof (ADR-0036, decision
	# 5).
	Sounds.set_outdoors(true)

	var air := WorldEnvironment.new()
	air.environment = Environment.new()
	# The root world has nothing in it, and it draws the canvas as background — the city on layer
	# −1.
	CityBackdrop.show_behind(air.environment)
	add_child(air)

	_camera = Camera3D.new()
	_camera.name = "StageCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation = Vector3(-deg_to_rad(SideCamera.TILT_DEGREES), 0.0, 0.0)
	_camera.size = SideCamera.DEFAULT_HALF_HEIGHT * 2.0 * WIDEN
	_camera.near = 0.05
	_camera.far = SideCamera.DISTANCE * 2.0
	add_child(_camera)
	_camera.make_current()
	_place_camera()

	_city = CityBackdrop.new()
	_city.name = "City"
	add_child(_city)
	_city.build(_rules, stage_seed, weather)


## The scene camera — so a test can check that it drives the city.
func camera() -> Camera3D:
	return _camera


func _process(delta: float) -> void:
	_time += delta
	_place_camera()


## The camera sways along the street back and forth by a sine: at the edge it turns around
## smoothly rather than hitting a stop.
func _place_camera() -> void:
	if _camera == null:
		return
	var half := _rules.width * 0.5
	var swing := half * 0.8
	var x := half + swing * sin(_time * DRIFT_SPEED / maxf(swing, 0.01))
	var roof := WorldSpace.height_to_scene(_rules.floor_surface(BuildingRules.ROOF))
	var y := roof + _camera.size * LIFT
	var tilt := deg_to_rad(SideCamera.TILT_DEGREES)
	_camera.global_position = Vector3(x, y + SideCamera.DISTANCE * tan(tilt), SideCamera.DISTANCE)
