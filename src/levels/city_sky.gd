class_name CitySky
extends RefCounted

## City sky by time of day and weather (ADR-0051, decision 11): a Poly Haven HDRI panorama
## chosen by the user, and the light of the sun — or the moon — from the same
## place where it is on the panorama.
##
## Panoramas are downloaded by [code]tools/build_sky.py[/code]; it also prints where the sun is on
## each one — those numbers are here. The panorama is rotated so that its sun
## stands at [method TimeOfDay.sun_direction]: behind the camera and to the side, otherwise
## the city facades would stand against the light.

const SHADER := preload("res://src/levels/city_sky.gdshader")

## Sky energy at night and in bad weather in the evening — a share of the daytime one: Poly Haven
## panoramas are exposed for daytime, while our night is night.
const NIGHT_ENERGY: float = 0.05
const DUSK_ENERGY: float = 0.35

## Moonlight — cold and weak.
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY: float = 0.12


## Panorama: the file, where the sun is on it — azimuth and elevation, degrees — and how
## many times to dim it so that the city stands in the frame rather than blown out.
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


## Panoramas per case (`tools/build_sky.py`). The night one — with the moon: its light
## is put in the place of the sun.
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


## Which panorama this time and weather have. In fog and rain in the morning and daytime —
## their own, in snow — the foggy, whitish one; in the evening and at night — one overcast, at night
## dimmed.
static func key_of(time: TimeOfDay.Kind, weather: Weather.Kind) -> String:
	if weather == Weather.Kind.CLEAR:
		return ["morning_clear", "day_clear", "evening_clear", "night_clear"][time]
	if time == TimeOfDay.Kind.MORNING or time == TimeOfDay.Kind.DAY:
		return "rain" if weather == Weather.Kind.RAIN else "fog"
	return "dusk_overcast"


static func look(time: TimeOfDay.Kind, weather: Weather.Kind) -> Look:
	return _all()[key_of(time, weather)]


## Sky energy: at night the overcast panorama is dimmed like the night one.
static func energy(time: TimeOfDay.Kind, weather: Weather.Kind) -> float:
	var chosen := look(time, weather)
	if TimeOfDay.is_night(time) and weather != Weather.Kind.CLEAR:
		return NIGHT_ENERGY * 1.4
	return chosen.energy


## Sky material: the panorama rotated with its sun toward [method TimeOfDay.sun_direction].
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


## Light over the city: the sun, and at night the moon — from the panorama, where it is on it.
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
