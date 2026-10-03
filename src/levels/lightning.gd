class_name Lightning
extends Node3D

## Lightning in rain (M22, the user's request: "if it rains — lightning too, and
## reflections in the windows").
##
## Every few seconds — a series of flashes: the city sky flares, the dark
## panes of the houses light up with reflected light, and the building's air brightens for
## a moment. Occasionally the bolt itself is visible — a zigzag over the far row. It adds no
## light sources: a flash is the brightness of the sky, the panes and the ambient light, not
## a lamp.
##
## Thunder (M23) follows each series with a delay by distance: a visible bolt
## strikes the far row of the city, an invisible one — beyond the horizon (ADR-0036,
## decision 5).

## Pause between series, s.
const PAUSE := Vector2(5.0, 13.0)
## Flashes of a series: on-times and pauses, s, and the brightness of each flash.
const PULSES: Array[Vector3] = [
	Vector3(0.07, 0.05, 1.0), Vector3(0.05, 0.09, 0.55), Vector3(0.14, 0.0, 0.85)
]
## How fast a flash fades after switching on, 1/s.
const FADE: float = 9.0
## Dimmer than this the flash has already gone out.
const DARK: float = 0.002
## With what chance a series is seen as a bolt.
const BOLT_CHANCE: float = 0.55
const BOLT_COLOUR := Color(0.85, 0.9, 1.0)
## Where an invisible bolt struck, m: beyond the city horizon.
const UNSEEN_DISTANCE := Vector2(1500.0, 3200.0)
## Depth of the far row where a visible bolt appears, m.
const BOLT_DEPTH: float = 560.0

## Where the last series struck, m. Needed by tests.
var last_distance: float = 0.0

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0
var _pulse: int = -1
var _pulse_clock: float = 0.0
var _level: float = 0.0
var _bolt: MeshInstance3D = null
var _span := Vector2(0.0, 40.0)
var _ground: float = 0.0


## Lightning over a city of width [param span] (x of the city scene) with the ground at
## [param ground]. The seed is there so the building's series repeat.
func setup(building_seed: int, span: Vector2, ground: float) -> void:
	name = "Lightning"
	_rng.seed = hash([building_seed, "lightning"])
	_span = span
	_ground = ground
	_wait = _rng.randf_range(1.5, PAUSE.x)


## Flash brightness right now, 0–1.
func level() -> float:
	return _level


## Advances the series by [param delta] seconds.
func advance(delta: float) -> void:
	_level = maxf(_level - _level * FADE * delta, 0.0)
	# The exponential never reaches zero: without a threshold the sky and panes would be
	# rewritten every frame, between series too.
	if _level < DARK:
		_level = 0.0
	if _pulse < 0:
		_wait -= delta
		if _wait <= 0.0:
			_pulse = 0
			_pulse_clock = 0.0
			if _rng.randf() < BOLT_CHANCE:
				last_distance = _strike()
			else:
				last_distance = _rng.randf_range(UNSEEN_DISTANCE.x, UNSEEN_DISTANCE.y)
			Sounds.thunder(last_distance)
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


## A bolt: a zigzag from the sky to the roof of the far row, with a branch. Returns
## how far it is from the middle of the city, m.
func _strike() -> float:
	if _bolt == null:
		_bolt = MeshInstance3D.new()
		_bolt.material_override = bolt_look()
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
	_bolt.position.z = -BOLT_DEPTH
	_bolt.visible = true
	var aside := x - (_span.x + _span.y) * 0.5
	return sqrt(BOLT_DEPTH * BOLT_DEPTH + aside * aside)


## A bolt for shader warm-up ([ShaderWarmup]): the same zigzag with the same
## [ImmediateMesh] and material, in the same city window — otherwise the wrong
## pipeline would warm up. Straight, without a draw: the building's series do not change
## from the warm-up. Returns the node; removing it is the warm-up's job.
func warm_up() -> MeshInstance3D:
	var bolt := MeshInstance3D.new()
	bolt.name = "WarmBolt"
	bolt.material_override = bolt_look()
	var mesh := ImmediateMesh.new()
	var x := (_span.x + _span.y) * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_segment(mesh, Vector2(x, _ground + 420.0), Vector2(x, _ground + CityPlan.ROWS[-1].z), 1.4)
	mesh.surface_end()
	bolt.mesh = mesh
	bolt.position.z = -BOLT_DEPTH
	# As for a real bolt in the middle of a flash: transparency itself changes the pipeline.
	bolt.transparency = 0.5
	add_child(bolt)
	return bolt


## Bolt material. Separate — [ShaderWarmup] warms it up: a bolt is seen
## rarely, and the first one would compile the shader in the middle of a storm.
static func bolt_look() -> StandardMaterial3D:
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = BOLT_COLOUR
	look.disable_fog = true
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# The zigzag goes from top to bottom, and its triangles face away from the camera: with
	# back-face culling the bolt was not drawn at all (code review M22).
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	return look


static func _segment(mesh: ImmediateMesh, a: Vector2, b: Vector2, width: float) -> void:
	var side := (b - a).orthogonal().normalized() * width
	var quad: Array[Vector2] = [a - side, a + side, b + side, b - side]
	for index: int in [0, 1, 2, 0, 2, 3]:
		mesh.surface_add_vertex(Vector3(quad[index].x, quad[index].y, 0.0))
