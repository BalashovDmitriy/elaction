class_name CitySky
extends RefCounted

## Небо города по времени суток и погоде (ADR-0051, решение 11): HDRI-панорама
## Poly Haven, выбранная пользователем, и свет солнца — или луны — оттуда же,
## где оно на панораме.
##
## Панорамы качает [code]tools/build_sky.py[/code]; он же печатает, где на каждой
## солнце, — эти числа здесь. Панорама поворачивается так, чтобы её солнце
## стояло по [method TimeOfDay.sun_direction]: за спиной камеры и сбоку, иначе
## фасады города стояли бы против света.

const SHADER := preload("res://src/levels/city_sky.gdshader")

## Сила неба ночью и в непогоду вечером — доля дневной: панорамы Poly Haven
## выставлены на дневную экспозицию, а ночь у нас — ночь.
const NIGHT_ENERGY: float = 0.05
const DUSK_ENERGY: float = 0.35

## Свет луны — холодный и слабый.
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY: float = 0.12


## Панорама: файл, где на ней солнце — азимут и высота, градусы, — и во
## сколько раз приглушить её, чтобы город стоял в кадре, а не в засветке.
class Look:
	extends RefCounted
	var path: String = ""
	var azimuth: float = 0.0
	var elevation: float = 0.0
	var energy: float = 1.0

	func _init(file: String, sun_azimuth: float, sun_elevation: float, gain: float) -> void:
		path = "res://assets/sky/%s.hdr" % file
		azimuth = sun_azimuth
		elevation = sun_elevation
		energy = gain


## Панорамы по случаям (`tools/build_sky.py`). Ночная — с луной: её свет
## ставится на место солнца.
static var _looks: Dictionary = {}


static func _all() -> Dictionary:
	if _looks.is_empty():
		_looks = {
			"morning_clear": Look.new("morning_clear", 215.0, 3.3, 0.55),
			"day_clear": Look.new("day_clear", 216.0, 40.3, 0.5),
			"evening_clear": Look.new("evening_clear", 217.8, 1.9, 0.5),
			"night_clear": Look.new("night_clear", 216.0, 13.9, NIGHT_ENERGY),
			"fog": Look.new("fog", 169.3, 28.7, 0.45),
			"rain": Look.new("rain", 91.9, 64.2, 0.5),
			"dusk_overcast": Look.new("dusk_overcast", 215.3, 3.3, DUSK_ENERGY),
		}
	return _looks


## Какая панорама у этого времени и погоды. В туман и дождь утром и днём —
## свои, в снег — туманная, белёсая; вечером и ночью — одна пасмурная, ночью
## приглушённая.
static func key_of(time: TimeOfDay.Kind, weather: Weather.Kind) -> String:
	if weather == Weather.Kind.CLEAR:
		return ["morning_clear", "day_clear", "evening_clear", "night_clear"][time]
	if time == TimeOfDay.Kind.MORNING or time == TimeOfDay.Kind.DAY:
		return "rain" if weather == Weather.Kind.RAIN else "fog"
	return "dusk_overcast"


static func look(time: TimeOfDay.Kind, weather: Weather.Kind) -> Look:
	return _all()[key_of(time, weather)]


## Сила неба: ночью пасмурная панорама приглушена как ночная.
static func energy(time: TimeOfDay.Kind, weather: Weather.Kind) -> float:
	var chosen := look(time, weather)
	if TimeOfDay.is_night(time) and weather != Weather.Kind.CLEAR:
		return NIGHT_ENERGY * 1.4
	return chosen.energy


## Материал неба: панорама, повёрнутая солнцем к [method TimeOfDay.sun_direction].
static func material(time: TimeOfDay.Kind, weather: Weather.Kind) -> ShaderMaterial:
	var chosen := look(time, weather)
	var sky := ShaderMaterial.new()
	sky.shader = SHADER
	sky.set_shader_parameter("panorama", load(chosen.path) as Texture2D)
	sky.set_shader_parameter("energy", energy(time, weather))
	var toward := TimeOfDay.sun_direction(time)
	var target := atan2(toward.x, -toward.z) / TAU
	sky.set_shader_parameter("shift", fposmod(chosen.azimuth / 360.0 - target, 1.0))
	return sky


## Свет над городом: солнце, а ночью луна — с панорамы, там же, где на ней.
static func light(time: TimeOfDay.Kind, weather: Weather.Kind) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var toward := TimeOfDay.sun_direction(time)
	sun.basis = Basis.looking_at(-toward, Vector3.UP)
	if TimeOfDay.is_night(time):
		sun.light_color = MOON_COLOUR
		sun.light_energy = MOON_ENERGY if weather == Weather.Kind.CLEAR else MOON_ENERGY * 0.4
	else:
		sun.light_color = TimeOfDay.sun_colour(time)
		sun.light_energy = TimeOfDay.sun_energy(time, weather)
	return sun
