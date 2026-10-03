class_name RoofSnow
extends Node3D

## Снег над крышей (ADR-0054, решения 2 и 5): хлопья идут со сносом ветра и
## гаснут о крышу — по той же карте высот, что и дождь ([RoofCatch]), — а
## покров уже лежит на всём, что смотрит вверх: настиле, ступенях, отливах
## парапетов, машинном отделении и технике. Покров не растёт: снег лёг до
## того, как Otto спустился, и за здание его не прибавится.
##
## Перед этажами снега нет, как и дождя ([RoofRain]): здание в разрезе, и
## хлопья перед этажом читались бы снегом в комнате.
##
## Покров — наклейка сверху на слой крыши [constant RoofCatch.LAYER]: она
## ложится только на грани, которые смотрят вверх, и только на неподвижное —
## Otto, агенты и вертолёт на слое не числятся и остаются без снега.

## Хлопьев на «высоком» ([method Graphics.rain_share]) — на жизнь по одной
## скорости падения [code]FALL.x[/code], — высота неба над настилом, скорость
## падения, м/с, ветер вбок, м/с, размер хлопка.
const FLAKES: int = 1400
const HEIGHT: float = 8.0
const FALL := Vector2(1.1, 1.9)
const WIND: float = 0.7
const FLAKE: float = 0.11

## Где по глубине идёт снег — там же, где дождь.
const BACK_Z: float = RoofRain.BACK_Z
const FRONT_Z: float = RoofRain.FRONT_Z

## Шаг частиц: хлопок медленный, хватает шестидесяти в секунду.
const TICKS: int = 60

## Покров: на сколько он поднимается над настилом, м, — выше машинного
## отделения и техники; цвет снега и плотных мест, проплешин; с какого наклона
## грань уже без снега (доля [member Decal.normal_fade]).
const COVER_HEIGHT: float = 7.5
const COVER := Color(0.88, 0.9, 0.95, 1.0)
const COVER_THIN := Color(0.8, 0.83, 0.88, 0.55)
const COVER_NORMAL_FADE: float = 0.55

var _flakes: GPUParticles3D = null
var _catcher: GPUParticlesCollisionHeightField3D = null
var _cover: Decal = null
var _tracks: SnowTracks = null
var _box := AABB()


## Собирает снег над крышей здания по правилам и плану во время суток
## [param time].
func build(rules: BuildingRules, plan: BuildingPlan, time: TimeOfDay.Kind) -> void:
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	_box = RoofCatch.box(rules, BACK_Z, FRONT_Z, HEIGHT)
	_catcher = RoofCatch.catcher(_box, "SnowCatcher")
	add_child(_catcher)
	for lid in RoofCatch.lids(rules, plan, _box, FALL.y / float(TICKS)):
		add_child(lid)
	_snow(rules, deck, time)
	_lay(rules, deck)
	_tracks = SnowTracks.new()
	add_child(_tracks)
	var bounds := rules.floor_span(BuildingRules.ROOF)
	# Над проёмами шахт под ногами кабина — металл, а не снег.
	_tracks.watch(deck, bounds.x, bounds.y, plan.gaps_on(rules, BuildingRules.ROOF))
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Переводит на слой крыши неподвижное на крыше под [param roots]: по нему
## снимается карта высот, на него ложится покров.
func catch_on(roots: Array[Node]) -> void:
	RoofCatch.mark(roots, _box)


## Сколько хлопьев по уровню качества — та же доля, что у капель.
func apply_graphics() -> void:
	RainLook.scale_amount(_flakes, Graphics.rain_share())


## Хлопья, которые гаснут о крышу, — для теста.
func flakes() -> GPUParticles3D:
	return _flakes


## Карта высот снега — для теста.
func catcher() -> GPUParticlesCollisionHeightField3D:
	return _catcher


## Покров — для теста.
func cover() -> Decal:
	return _cover


## Следы на настиле — для теста.
func tracks() -> SnowTracks:
	return _tracks


## Хлопья сыплются над настилом со сдвигом против ветра: снесённые, они ложатся
## на крышу, а не уходят за парапет вниз по фасаду. Сдвиг — на меньший снос с
## левого края и на больший с правого ([method SnowLook.slant]): иначе у левого
## парапета до настила не долетал ни один хлопок, а у правого часть уходила
## за отлив (авторевью M24l).
func _snow(rules: BuildingRules, deck: float, time: TimeOfDay.Kind) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var fall := HEIGHT + 0.3
	var slant := SnowLook.slant(FALL, WIND)
	# Вынос карниза — своего здания (ADR-0058), как у дождя ([RoofRain]).
	var overhang := BuildingShell.coping_overhang(rules.kind)
	var from := bounds.x - overhang - fall * slant.x
	var to := bounds.y + overhang - fall * slant.y
	# Жизнь — до настила и самому косому хлопку; хлопьев — на тот же поток, что
	# при жизни по одной скорости падения: дольше живущий дольше лежит погасшим.
	var slowest := SnowLook.slowest_fall(FALL, WIND)
	_flakes = SnowLook.flakes(
		roundi(FLAKES * FALL.x / slowest),
		(HEIGHT + 1.0) / slowest,
		Vector3((to - from) * 0.5, 0.3, (FRONT_Z - BACK_Z) * 0.5),
		FALL,
		WIND,
		FLAKE,
		SnowLook.brightness(time)
	)
	_flakes.name = "Flakes"
	_flakes.position = Vector3((from + to) * 0.5, deck + HEIGHT, (FRONT_Z + BACK_Z) * 0.5)
	_flakes.fixed_fps = TICKS
	_flakes.interpolate = true
	_flakes.collision_base_size = 0.02
	_flakes.visibility_aabb = AABB(
		Vector3(-(to - from), -HEIGHT - 1.0, -3.0), Vector3((to - from) * 2.0, HEIGHT + 2.0, 6.0)
	)
	var process := _flakes.process_material as ParticleProcessMaterial
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	add_child(_flakes)


## Покров: наклейка сверху на всю крышу с отливами и техникой. Плотнее в
## середине, с проплешинами по шуму — ровный белый лист читался бы краской.
func _lay(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var edge := BuildingShell.COPING_OVERHANG + 0.1
	var width := bounds.y - bounds.x + edge * 2.0
	var depth := FRONT_Z - BACK_Z + 0.6
	var noise := FastNoiseLite.new()
	noise.seed = hash(["snow", bounds])
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.42, 1.0])
	gradient.colors = PackedColorArray([COVER_THIN, COVER_THIN, COVER, COVER])
	var texture := NoiseTexture2D.new()
	texture.width = 1024
	texture.height = maxi(int(1024.0 * depth / width), 32)
	texture.noise = noise
	texture.color_ramp = gradient
	_cover = Decal.new()
	_cover.name = "SnowCover"
	_cover.size = Vector3(width, COVER_HEIGHT, depth)
	_cover.position = Vector3(
		(bounds.x + bounds.y) * 0.5, deck - 0.2 + COVER_HEIGHT * 0.5, (FRONT_Z + BACK_Z) * 0.5
	)
	_cover.cull_mask = RoofCatch.LAYER
	_cover.texture_albedo = texture
	_cover.normal_fade = COVER_NORMAL_FADE
	_cover.upper_fade = 0.02
	_cover.lower_fade = 0.02
	add_child(_cover)
