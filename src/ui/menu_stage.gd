class_name MenuStage
extends Node3D

## Ночной город за главным меню (ADR-0035, решение 1).
##
## Здания здесь нет — только [CityBackdrop] со своей камерой. Город умеет жить
## сам: погода, молнии, мигающие огни, — а камеру ведёт по текущей камере
## корневого мира. Поэтому достаточно поставить ортокамеру так, как её ставит
## [SideCamera] над крышей, и медленно вести вдоль улицы: параллакс кварталов
## город даёт сам.
##
## Здание не строится нарочно: [GreyboxLevel] тянет за собой Otto, партию и
## замер качества, а меню нужен вид, а не игра.

## Скорость проезда камеры вдоль улицы, м/с. Медленно: фон, а не аттракцион.
const DRIFT_SPEED: float = 0.35
## Насколько выше крыши середина кадра, в долях кадра: небо и верхи домов
## занимают больше половины, улицы внизу тают в дымке.
const LIFT: float = 0.18
## Во сколько раз кадр меню шире игрового. В игре город виден полосой за
## зданием; за меню здания нет, и при игровом кадре окна вставали во весь экран
## — силуэта города не было, одни размытые квадраты.
const WIDEN: float = 3.0

var weather: Weather.Kind = Weather.Kind.RAIN

var _rules: BuildingRules = null
var _camera: Camera3D = null
var _city: CityBackdrop = null
var _time: float = 0.0


## Собирает сцену. Погода — по [param stage_seed]: тот же жребий, что у здания.
func build(stage_seed: int) -> void:
	_rules = BuildingRules.new()
	weather = Weather.of_seed(stage_seed)

	var air := WorldEnvironment.new()
	air.environment = Environment.new()
	# В корневом мире ничего нет, и он рисует фоном холст — город на слое −1.
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


## Камера сцены — чтобы тест мог проверить, что она ведёт город.
func camera() -> Camera3D:
	return _camera


func _process(delta: float) -> void:
	_time += delta
	_place_camera()


## Камера качается вдоль улицы туда и обратно по синусу: у края она плавно
## разворачивается, а не упирается.
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
