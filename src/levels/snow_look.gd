class_name SnowLook
extends RefCounted

## Вид снега: хлопья над крышей ([RoofSnow]) и снегопад города
## ([CityBackdrop]) (ADR-0054). Одно место на оба, как у дождя ([RainLook]):
## разведи их — и хлопья крыши и города разошлись бы при первой правке.
##
## Хлопок — мягкое пятно, повёрнутое к камере. Падает медленно и со сносом
## ветра, с разбросом направления и скорости: снег, который летит строем,
## читается помехой экрана, а не снегом.

const FLAKE_SHADER := preload("res://src/levels/snow_flake.gdshader")

## Цвет снега: чуть холодный белый.
const TINT := Color(0.84, 0.9, 1.0)

## Яркость хлопьев ночью и днём: ночью снег виден светом города и ламп, сам
## по себе он серый.
const NIGHT_BRIGHTNESS: float = 0.42
const DAY_BRIGHTNESS: float = 1.0
## Какая доля яркости — свет неба; остальное хлопку дают лампы и солнце.
const AMBIENT_SHARE: float = 0.75

## Разброс направления хлопьев, градусы. Шума частиц ([member
## ParticleProcessMaterial.turbulence_enabled]) у снега нет: в Godot он
## подмешивается к скорости каждый шаг, и даже полпроцента за шаг стирали
## падение — хлопья висели у неба кучей (замер M24l).
const SPREAD: float = 10.0

## Слои снегопада в городе, от камеры города вглубь — как у дождя
## ([constant RainLook.CITY_LAYERS]): сколько хлопьев, насколько дальше камеры
## середина слоя и полуглубина, м, размер хлопка. Ближние — крупные, дальние
## — мельче и тонут в дымке.
const CITY_LAYERS: Array[Dictionary] = [
	{"flakes": 900, "depth": 22.0, "reach": 10.0, "size": 0.22},
	{"flakes": 1800, "depth": 52.0, "reach": 18.0, "size": 0.32},
	{"flakes": 1600, "depth": 110.0, "reach": 30.0, "size": 0.5},
]
## Скорость падения в городе, м/с, и ветер вбок, м/с.
const CITY_FALL := Vector2(1.6, 2.6)
const CITY_WIND: float = 1.1


## Хлопья: [param amount] штук из коробки [param extents] падают со скоростью
## [param fall] и ветром [param wind] вбок и живут [param lifetime].
## [param size] — размер хлопка, [param brightness] — его яркость.
static func flakes(
	amount: int,
	lifetime: float,
	extents: Vector3,
	fall: Vector2,
	wind: float,
	size: float,
	brightness: float
) -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	var middle := (fall.x + fall.y) * 0.5
	process.direction = Vector3(wind / middle, -1.0, 0.0).normalized()
	process.spread = SPREAD
	process.initial_velocity_min = fall.x
	process.initial_velocity_max = fall.y
	process.gravity = Vector3.ZERO
	process.scale_min = 0.6
	process.scale_max = 1.4

	var snow := GPUParticles3D.new()
	snow.amount = amount
	snow.set_meta(RainLook.FULL, amount)
	snow.lifetime = lifetime
	snow.preprocess = lifetime
	snow.local_coords = false
	snow.process_material = process
	snow.draw_pass_1 = flake_mesh(size, brightness)
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Солнце светит только на слой снаружи ([Outdoors]): без него днём хлопья
	# были бы плоскими пятнами без света.
	snow.layers |= Outdoors.LAYER
	return snow


## Квад хлопка: рыхлый комок из мягких сгустков, к камере, крутится и
## покачивается ([code]snow_flake.gdshader[/code]). [param brightness] — свет
## неба на нём без ламп.
static func flake_mesh(size: float, brightness: float) -> QuadMesh:
	var look := ShaderMaterial.new()
	look.shader = FLAKE_SHADER
	look.set_shader_parameter("tint", TINT)
	look.set_shader_parameter("ambient", brightness * AMBIENT_SHARE)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = look
	return quad


## Яркость хлопьев во время суток [param time].
static func brightness(time: TimeOfDay.Kind) -> float:
	return lerpf(NIGHT_BRIGHTNESS, DAY_BRIGHTNESS, TimeOfDay.daylight(time))


## Снегопад города: слои хлопьев у камеры. Слои — детьми [param camera]: едут
## с ней, а хлопья падают в мире.
static func city(camera: Camera3D, time: TimeOfDay.Kind) -> void:
	for index in CITY_LAYERS.size():
		var layer := CITY_LAYERS[index]
		var reach := float(layer["depth"])
		var snow := flakes(
			int(layer["flakes"]),
			28.0 / CITY_FALL.x,
			Vector3(reach * 0.9 + 20.0, 2.0, float(layer["reach"])),
			CITY_FALL,
			CITY_WIND,
			float(layer["size"]),
			brightness(time)
		)
		snow.name = "Snow%d" % index
		snow.position = Vector3(0.0, 26.0, -reach)
		snow.visibility_aabb = AABB(
			Vector3(-reach * 2.0 - 40.0, -80.0, -reach - 40.0),
			Vector3(reach * 4.0 + 80.0, 120.0, reach * 2.0 + 80.0)
		)
		camera.add_child(snow)
