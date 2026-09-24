class_name Lightning
extends Node3D

## Молнии в дождь (M22, просьба пользователя: «если дождь — ещё молний, и
## отсветы в окнах»).
##
## Раз в несколько секунд — серия вспышек: небо города вспыхивает, тёмные
## стёкла домов загораются отражённым светом, а воздух здания на миг светлеет.
## Изредка виден сам разряд — ломаная над дальним рядом. Источников света не
## добавляет: вспышка — яркость неба, стёкол и окружающего света, а не лампа.
##
## Гром — M23, вместе со всем звуком.

## Пауза между сериями, с.
const PAUSE := Vector2(5.0, 13.0)
## Вспышки серии: включения и паузы, с, и яркость каждого включения.
const PULSES: Array[Vector3] = [
	Vector3(0.07, 0.05, 1.0), Vector3(0.05, 0.09, 0.55), Vector3(0.14, 0.0, 0.85)
]
## Как быстро гаснет вспышка после включения, 1/с.
const FADE: float = 9.0
## С каким шансом серию видно разрядом.
const BOLT_CHANCE: float = 0.55
const BOLT_COLOUR := Color(0.85, 0.9, 1.0)

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0
var _pulse: int = -1
var _pulse_clock: float = 0.0
var _level: float = 0.0
var _bolt: MeshInstance3D = null
var _span := Vector2(0.0, 40.0)
var _ground: float = 0.0


## Молнии над городом шириной [param span] (x сцены города) с землёй на
## [param ground]. Сид — чтобы серии здания повторялись.
func setup(building_seed: int, span: Vector2, ground: float) -> void:
	name = "Lightning"
	_rng.seed = hash([building_seed, "lightning"])
	_span = span
	_ground = ground
	_wait = _rng.randf_range(1.5, PAUSE.x)


## Яркость вспышки прямо сейчас, 0–1.
func level() -> float:
	return _level


## Ведёт серию на [param delta] секунд.
func advance(delta: float) -> void:
	_level = maxf(_level - _level * FADE * delta, 0.0)
	if _pulse < 0:
		_wait -= delta
		if _wait <= 0.0:
			_pulse = 0
			_pulse_clock = 0.0
			if _rng.randf() < BOLT_CHANCE:
				_strike()
		return
	var pulse := PULSES[_pulse]
	_pulse_clock += delta
	if _pulse_clock < pulse.x:
		_level = maxf(_level, pulse.z)
	elif _pulse_clock >= pulse.x + pulse.y:
		_pulse += 1
		_pulse_clock = 0.0
		if _pulse >= PULSES.size():
			_pulse = -1
			_wait = _rng.randf_range(PAUSE.x, PAUSE.y)
			if _bolt != null:
				_bolt.visible = false
	if _bolt != null:
		_bolt.transparency = 1.0 - clampf(_level, 0.0, 1.0)


func _process(delta: float) -> void:
	advance(delta)


## Разряд: ломаная от неба к крыше дальнего ряда, с отростком.
func _strike() -> void:
	if _bolt == null:
		_bolt = MeshInstance3D.new()
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.albedo_color = BOLT_COLOUR
		look.disable_fog = true
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bolt.material_override = look
		add_child(_bolt)
	var mesh := ImmediateMesh.new()
	var x := _rng.randf_range(_span.x - 80.0, _span.y + 80.0)
	var top := _ground + 420.0
	var bottom := _ground + CityPlan.ROWS[-1].z
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector2] = []
	var y := top
	while y > bottom:
		points.append(Vector2(x, y))
		x += _rng.randf_range(-9.0, 9.0)
		y -= _rng.randf_range(12.0, 30.0)
	points.append(Vector2(x, bottom))
	for index in points.size() - 1:
		_segment(mesh, points[index], points[index + 1], 1.4)
	var fork := points[points.size() / 2]
	_segment(mesh, fork, fork + Vector2(_rng.randf_range(-40.0, 40.0), -60.0), 0.8)
	mesh.surface_end()
	_bolt.mesh = mesh
	_bolt.position.z = -560.0
	_bolt.visible = true


static func _segment(mesh: ImmediateMesh, a: Vector2, b: Vector2, width: float) -> void:
	var side := (b - a).orthogonal().normalized() * width
	var quad: Array[Vector2] = [a - side, a + side, b + side, b - side]
	for index: int in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(Vector3(quad[index].x, quad[index].y, 0.0))
