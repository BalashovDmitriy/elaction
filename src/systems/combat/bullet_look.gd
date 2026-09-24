class_name BulletLook
extends Node3D

## Вид пули: трассер с хвостом и вспышка у ствола (M21, замечание пользователя —
## «пуля выглядит квадратиком»).
##
## Модель пули здесь не помогла бы: настоящая пуля на нашем масштабе меньше
## пикселя. Пулю в кадре видно так же, как в кино, — по трассеру: яркое вытянутое
## ядро и тающий хвост позади. Всё светится эмиссией — пулю видно и на погашенном
## этаже, а источников света она не добавляет, кроме вспышки выстрела у [Bullet].
##
## Только вид: коллизия пули — её `Shape`, и высоты ROM держит она, а не хвост.
##
## Хвост растёт с пройденным путём: сразу после выстрела он торчал бы из стрелка
## назад. Вспышка стоит на месте выстрела — узел едет с пулей, и вспышка
## отодвигается назад ровно на пройденный путь.

## Ядро: длина и толщина, м.
const CORE_LENGTH: float = 0.26
const CORE_RADIUS: float = 0.034
## Хвост: полная длина и толщина у головы, м.
const TRAIL_LENGTH: float = 1.1
const TRAIL_THICKNESS: float = 0.055
## Вспышка у ствола: размер и путь, за который она гаснет, м.
const FLASH_SIZE: float = 0.34
const FLASH_FADE: float = 0.6

const CORE := Color(1.0, 0.96, 0.82)
const TRAIL := Color(1.0, 0.72, 0.35)
const FLASH := Color(1.0, 0.84, 0.5)
## Насколько ярко светится ядро: ярче кадра, чтобы грейдинг его не притушил.
const GLOW: float = 6.0

static var _core_material: StandardMaterial3D = null
static var _trail_material: StandardMaterial3D = null
static var _flash_material: StandardMaterial3D = null

var _direction: float = 1.0
var _trail: MeshInstance3D = null
var _flash: MeshInstance3D = null


## Собирает вид пули, летящей в сторону [param direction] (−1 влево, +1 вправо).
static func make(direction: float) -> BulletLook:
	var look := BulletLook.new()
	look.name = "Look"
	look._direction = signf(direction) if not is_zero_approx(direction) else 1.0
	look._build()
	return look


## Обновляет хвост и вспышку по пройденному пулей пути, м.
func follow(travelled: float) -> void:
	var length := minf(travelled, TRAIL_LENGTH)
	_trail.visible = length > 0.01
	if _trail.visible:
		_trail.scale.x = length
		_trail.position.x = -_direction * (length * 0.5 + CORE_LENGTH * 0.3)
	var left := 1.0 - travelled / FLASH_FADE
	_flash.visible = left > 0.0
	if _flash.visible:
		_flash.position.x = -_direction * travelled
		_flash.scale = Vector3.ONE * (0.6 + 0.4 * left)
		_flash.transparency = 1.0 - left


func _build() -> void:
	var core := MeshInstance3D.new()
	core.name = "Core"
	var capsule := CapsuleMesh.new()
	capsule.radius = CORE_RADIUS
	capsule.height = CORE_LENGTH
	capsule.radial_segments = 8
	capsule.rings = 2
	core.mesh = capsule
	# Капсула растёт по Y; ложится вдоль полёта.
	core.rotation.z = PI * 0.5
	core.material_override = _core()
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	var strip := QuadMesh.new()
	# Единичная длина: хвост тянется масштабом по X.
	strip.size = Vector2(1.0, TRAIL_THICKNESS)
	_trail.mesh = strip
	_trail.material_override = _trail_mat()
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Градиент хвоста идёт по U квада слева направо: у пули, летящей влево,
	# голова хвоста — справа, и квад разворачивается.
	if _direction < 0.0:
		_trail.rotation.y = PI
	add_child(_trail)

	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	var star := QuadMesh.new()
	star.size = Vector2(FLASH_SIZE, FLASH_SIZE)
	_flash.mesh = star
	_flash.material_override = _flash_mat()
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	follow(0.0)


static func _core() -> StandardMaterial3D:
	if _core_material == null:
		_core_material = StandardMaterial3D.new()
		_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_core_material.albedo_color = CORE
		_core_material.emission_enabled = true
		_core_material.emission = CORE
		_core_material.emission_energy_multiplier = GLOW
	return _core_material


## Хвост: от головы к концу гаснет и остывает — градиент по U.
static func _trail_mat() -> StandardMaterial3D:
	if _trail_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(TRAIL, 0.0))
		gradient.set_color(1, Color(CORE, 0.85))
		var texture := GradientTexture1D.new()
		texture.gradient = gradient
		texture.width = 64
		_trail_material = StandardMaterial3D.new()
		_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_material.albedo_texture = texture
		_trail_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return _trail_material


## Вспышка: круглое пятно, мягкое к краю, всегда лицом к камере.
static func _flash_mat() -> StandardMaterial3D:
	if _flash_material == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 0.95, 1.0))
		gradient.set_color(1, Color(FLASH, 0.0))
		gradient.add_point(0.35, Color(FLASH, 0.8))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_material.albedo_texture = texture
	return _flash_material
