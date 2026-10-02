class_name TimeOfDay
extends RefCounted

## Время суток здания: утро, день, вечер или ночь (ADR-0051).
##
## Одно на здание и выбирается его сидом своим жребием — погода и палитра
## раунда от него не зависят, — а в здании застывает: от вертолёта до машины
## (решения 3 и 4). Ночь выпадает вдвое чаще остальных: ночь — лицо игры.
##
## Класс решает и отдаёт числа вида: небо, солнце, огни, тон кадра. Механику
## от времени суток спрашивает [BuildingRules]: темнота есть только ночью
## (решение 5). Узлы строят [BuildingScenery], [CityBackdrop] и улица.

enum Kind { MORNING, DAY, EVENING, NIGHT }

## Доли жребия по [enum Kind]: ночь 40 %, прочие по 20 % (решение 3).
const WEIGHTS: Array[float] = [0.2, 0.2, 0.2, 0.4]

## Смешивается с сидом: жребий времени не совпадает ни с погодой
## ([constant Weather.SALT]), ни с раскладкой того же сида.
const SALT: int = 0x71_3E0D

## Горизонт в ясную погоду: его долей светится воздух здания днём.
const HORIZON: Array[Color] = [
	Color(0.98, 0.76, 0.6),
	Color(0.6, 0.75, 0.92),
	Color(0.98, 0.56, 0.34),
	Color(0.07, 0.08, 0.15),
]

## Откуда светит солнце: высота над горизонтом, градусы, и сторона — минус
## слева от камеры. Утром низкое справа, днём высокое, вечером низкое слева.
const SUN_ELEVATION: Array[float] = [6.0, 40.0, 5.0, 14.0]
const SUN_SIDE: Array[float] = [1.0, 0.5, -1.0, 0.6]
const SUN_COLOUR: Array[Color] = [
	Color(1.0, 0.86, 0.72),
	Color(1.0, 0.97, 0.9),
	Color(1.0, 0.72, 0.48),
	Color(0.0, 0.0, 0.0),
]
const SUN_ENERGY: Array[float] = [1.3, 1.8, 1.15, 0.0]

## Сколько дня в кадре, 0–1: так тянутся город, окна, воздух здания.
const DAYLIGHT: Array[float] = [0.7, 1.0, 0.55, 0.0]

## Доля горящих окон города от ночной: днём — единицы.
const LIT_WINDOWS: Array[float] = [0.3, 0.06, 0.75, 1.0]

## Сила уличных огней — фонарей, неона, зарева, маяков: утром и вечером
## частично, днём выключены (решение 6).
const STREET_LIGHTS: Array[float] = [0.35, 0.0, 0.85, 1.0]

## Тон кадра — кривые по каналам от теней к свету ([Atmosphere]). Ночной —
## нуар M22, его числа держит [Atmosphere]; утро прохладное с розовым светом,
## день почти нейтральный, вечер — фиолетовые тени и оранжевый свет.
const GRADE_SHADOW: Array[Color] = [
	Color(0.02, 0.03, 0.07),
	Color(0.02, 0.025, 0.04),
	Color(0.05, 0.02, 0.08),
	Atmosphere.NOIR_SHADOW,
]
const GRADE_MIDDLE: Array[Color] = [
	Color(0.33, 0.35, 0.39),
	Color(0.36, 0.36, 0.36),
	Color(0.38, 0.31, 0.33),
	Atmosphere.NOIR_MIDDLE,
]
const GRADE_LIGHT: Array[Color] = [
	Color(1.0, 0.94, 0.9),
	Color(1.0, 0.98, 0.94),
	Color(1.0, 0.86, 0.68),
	Atmosphere.NOIR_LIGHT,
]
const SATURATION: Array[float] = [0.95, 1.0, 1.05, Atmosphere.SATURATION]

## Окружающий свет здания: множитель к ночному и куда тянется его цвет. Днём
## здание светло и без ламп — сбитая лампа зону не гасит и на вид.
const AMBIENT_GAIN: Array[float] = [1.45, 1.6, 1.3, 1.0]
const AMBIENT_TINT: Array[Color] = [
	Color(0.85, 0.82, 0.86),
	Color(0.9, 0.92, 0.95),
	Color(0.9, 0.72, 0.62),
	Color(0.0, 0.0, 0.0),
]
## Насколько цвет окружающего света уходит к [constant AMBIENT_TINT].
const AMBIENT_TINT_SHARE: Array[float] = [0.35, 0.45, 0.35, 0.0]


## Время суток здания по его сиду.
static func of_seed(building_seed: int) -> Kind:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var roll := rng.randf()
	var total := 0.0
	for kind: int in WEIGHTS.size():
		total += WEIGHTS[kind]
		if roll < total:
			return kind as Kind
	return Kind.NIGHT


## Ночь ли: только ночью есть темнота и тёмные этажи (решение 5).
static func is_night(kind: Kind) -> bool:
	return kind == Kind.NIGHT


## Бывает ли гроза: только вечером и ночью (решение 7).
static func has_thunder(kind: Kind) -> bool:
	return kind == Kind.EVENING or kind == Kind.NIGHT


## Откуда идёт свет солнца — направление от сцены к солнцу, мир сцены.
## Солнце за спиной камеры и сбоку: лицом к игроку стоит то, что им освещено.
## Со спины солнца лица фасадов и крыши были бы против света — силуэтом.
static func sun_direction(kind: Kind) -> Vector3:
	var up := deg_to_rad(SUN_ELEVATION[kind])
	var side := SUN_SIDE[kind]
	var flat := Vector3(side, 0.0, 1.0).normalized() * cos(up)
	return Vector3(flat.x, sin(up), flat.z).normalized()


## Сила солнца при погоде: в облачность его почти нет, ночью нет вовсе.
static func sun_energy(kind: Kind, weather: Weather.Kind) -> float:
	var energy := SUN_ENERGY[kind]
	if weather == Weather.Kind.FOG:
		return energy * 0.3
	if weather == Weather.Kind.RAIN:
		return energy * 0.2
	if weather == Weather.Kind.SNOW:
		return energy * 0.35
	return energy


static func sun_colour(kind: Kind) -> Color:
	return SUN_COLOUR[kind]


static func daylight(kind: Kind) -> float:
	return DAYLIGHT[kind]


static func lit_windows(kind: Kind) -> float:
	return LIT_WINDOWS[kind]


## Окно на улицу изнутри здания — в зале офиса, на пожарную лестницу: ночью
## тёмное стекло [param night], в другое время оно светится небом горизонта на
## долю дня. Ночное стекло днём читалось дырой в темноту (авторевью M24n).
static func window_look(kind: Kind, night: Color) -> StandardMaterial3D:
	if is_night(kind):
		return GreyboxLook.polished(night)
	return GreyboxLook.marker(night.lerp(HORIZON[kind], daylight(kind)))


## Сила уличных огней. В непогоду днём их зажигают — темно.
static func street_lights(kind: Kind, weather: Weather.Kind = Weather.Kind.CLEAR) -> float:
	var lights := STREET_LIGHTS[kind]
	if weather != Weather.Kind.CLEAR and kind != Kind.NIGHT:
		lights = maxf(lights, 0.4)
	return lights


## Светло ли снаружи: утро и день. Тогда неон вывески погашен, в комнатах за
## дверью не горит свет — светит солнце из окна (ADR-0052, решения 4 и 5).
static func is_daytime(kind: Kind) -> bool:
	return kind == Kind.MORNING or kind == Kind.DAY


## Горит ли неон вывески здания: вечером и ночью (ADR-0052, решение 4).
static func sign_lit(kind: Kind) -> bool:
	return not is_daytime(kind)


## Окружающий свет здания от ночного [param night]: цвет и множитель силы.
static func ambient(kind: Kind, night: Color) -> Color:
	return night.lerp(AMBIENT_TINT[kind], AMBIENT_TINT_SHARE[kind])


static func ambient_gain(kind: Kind) -> float:
	return AMBIENT_GAIN[kind]
