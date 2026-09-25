class_name AimLaser
extends Node3D

## Луч прицела агента: тонкая красная нить от ствола по линии будущего выстрела
## (ADR-0037, решение 5; решение пользователя).
##
## С M24a пуля агента втрое быстрее ROM, и уклониться от неё, увидев саму пулю,
## уже нельзя. Время на ответ даёт замах ROM: пока агент замахивается, от ствола
## идёт луч на высоте будущей пули — высокий: присесть или прыгнуть, низкий —
## прыгнуть. В тени луч — единственный знак, поэтому он светится сам.
##
## Источником света луч не служит: только эмиссия, без [Light3D] — источников на
## здание и так десятки. Кончается там, куда придёт пуля: на стене, на Otto или
## на дальности пули; в конце — красная точка.
##
## Узел стоит у ствола: его ставит агент, и луч идёт вдоль +X узла в сторону
## [member direction].

## Толщина луча и размер точки на конце, м.
const THICKNESS: float = 0.026
const DOT_SIZE: float = 0.16

const COLOR := Color(1.0, 0.02, 0.02)
## Насколько ярко светится луч: заметно и на погашенном этаже.
const GLOW: float = 2.2
## Дрожание луча: насколько он гаснет в худший кадр, из 1, и как часто, Гц.
const FLICKER: float = 0.35
const FLICKER_RATE: float = 23.0

static var _beam_material: StandardMaterial3D = null
static var _dot_material: StandardMaterial3D = null

## Куда смотрит луч: −1 влево, +1 вправо.
var direction: float = 1.0
## Во что луч упирается: маска пули агента — геометрия и Otto.
var mask: int = 1 | 2
## Дальше этого луч не тянется: дальность пули.
var reach: float = 14.4
## Сколько ещё до вылета пули, с, и с какой скоростью она полетит, м/с. Ставит
## агент каждый кадр замаха: по ним видно, когда пуля придёт.
var shot_in: float = 0.0
var shot_speed: float = 1.0

var _beam: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _length: float = 0.0
var _clock: float = 0.0


## Собирает погашенный луч.
static func make() -> AimLaser:
	var laser := AimLaser.new()
	laser.name = "AimLaser"
	laser._build()
	laser.visible = false
	return laser


## Зажигает луч в сторону [param towards] и тянет его до первого препятствия.
## Зовётся каждый кадр замаха: Otto двигается, и конец луча идёт за ним.
func aim(towards: float) -> void:
	direction = signf(towards) if not is_zero_approx(towards) else 1.0
	visible = true
	_length = _trace()
	_beam.scale.x = maxf(_length, 0.001)
	_beam.position.x = direction * _length * 0.5
	_dot.position.x = direction * _length


## Гасит луч: выстрел ушёл, замах сорван или агент убит.
func put_out() -> void:
	visible = false


## Горит ли луч.
func is_on() -> bool:
	return visible


## Через сколько секунд пуля долетит на [param distance] метров от ствола:
## остаток замаха и полёт.
func time_to(distance: float) -> float:
	return shot_in + distance / maxf(shot_speed, 0.01)


## Длина луча, м: до стены, до Otto или до дальности пули.
func length() -> float:
	return _length if visible else 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	# Дрожание — две несоразмерные синусоиды: ровное мигание читалось бы
	# сигналом, а не лучом.
	var wave := sin(_clock * TAU * FLICKER_RATE) * sin(_clock * TAU * FLICKER_RATE * 0.37)
	_beam.transparency = FLICKER * absf(wave)


## Длина луча по лучу физики — тем же, во что упрётся пуля.
func _trace() -> float:
	if not is_inside_tree():
		return reach
	var from := global_position
	var to := from + Vector3(direction * reach, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return reach
	return absf((hit["position"] as Vector3).x - from.x)


func _build() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var quad := QuadMesh.new()
	# Единичная длина: луч тянется масштабом по X.
	quad.size = Vector2(1.0, THICKNESS)
	_beam.mesh = quad
	_beam.material_override = _beam_mat()
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)

	_dot = MeshInstance3D.new()
	_dot.name = "Dot"
	var star := QuadMesh.new()
	star.size = Vector2(DOT_SIZE, DOT_SIZE)
	_dot.mesh = star
	_dot.material_override = _dot_mat()
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)


## Луч: чёрное альбедо и красная эмиссия. Свет сцены его не красит, а эмиссия
## видна и в темноте; не unshaded — у unshaded Godot 4 эмиссию не берёт.
static func _beam_mat() -> StandardMaterial3D:
	if _beam_material == null:
		_beam_material = StandardMaterial3D.new()
		_beam_material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
		_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_beam_material.emission_enabled = true
		_beam_material.emission = COLOR
		_beam_material.emission_energy_multiplier = GLOW
	return _beam_material


## Точка на конце: мягкое красное пятно лицом к камере, поверх стены — луч
## упирается в торец, а торец камере виден ребром.
static func _dot_mat() -> StandardMaterial3D:
	if _dot_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 0.75, 0.7, 1.0))
		gradient.set_color(1, Color(COLOR, 0.0))
		gradient.add_point(0.3, Color(COLOR, 0.9))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 32
		texture.height = 32
		_dot_material = StandardMaterial3D.new()
		_dot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dot_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dot_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_dot_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_dot_material.no_depth_test = true
		_dot_material.render_priority = 1
		_dot_material.albedo_texture = texture
	return _dot_material
