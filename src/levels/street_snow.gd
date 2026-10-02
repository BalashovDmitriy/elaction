class_name StreetSnow
extends Node3D

## Снег на улице у выезда (ADR-0054, решения 2 и 5): хлопья над мостовой и
## тротуаром и покров — сверху на тротуаре, бордюре, маркизах, подоконниках и
## карнизах домов через дорогу. По мостовой — колеи: там, где идёт поток
## машин ([StreetTraffic]), снег раскатан до мокрого асфальта, по бокам колей
## — рыхлый.
##
## Покров — наклейка сверху на слой улицы [constant LAYER]: на него
## [method mark] переводит неподвижное на улице. Машины потока и машина у
## бордюра на нём не числятся: наклейка в мире, и по едущей машине снег
## скользил бы пятнами.

## Слой неподвижного на улице. Девятнадцатый: двадцатый занят крышей
## ([constant RoofCatch.LAYER]), и камеры и свет видят все двадцать.
const LAYER: int = 1 << 18

## Хлопьев на «высоком», высота неба над улицей, м.
const FLAKES: int = 2400
const HEIGHT: float = 16.0

## Колея: полуширина следа колеса, м, и на сколько колёса машины отстоят от
## её оси, м.
const RUT: float = 0.24
const WHEEL_TRACK: float = 0.78

## Снег: цвет рыхлого и раскатанного, цвет мокрой колеи; насколько высоко над
## улицей лежит покров — до карнизов домов через дорогу.
const COVER := Color(0.88, 0.9, 0.95, 1.0)
const PACKED := Color(0.7, 0.72, 0.76, 0.85)
const SLUSH := Color(0.08, 0.085, 0.095, 0.9)
const COVER_HEIGHT: float = 24.0
const COVER_NORMAL_FADE: float = 0.55

## Сколько точек покрова на метр.
const TEXELS_PER_METRE: float = 24.0

var _flakes: GPUParticles3D = null
var _cover: Decal = null


## Собирает снег над улицей от [param from] до [param to] по x, на уровне
## [param street] сцены, по глубине — от [param front] до [param back], во
## время суток [param time].
func build(
	from: float, to: float, street: float, front: float, back: float, time: TimeOfDay.Kind
) -> void:
	name = "Snow"
	_snow(from, to, street, front, back, time)
	_lay(from, to, street, front, back)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Переводит на слой [constant LAYER] неподвижное под [param root], кроме
## того, что под узлами [param moving].
static func mark(root: Node, moving: Array[Node]) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		if node is GPUParticles3D:
			continue
		var still := true
		for skip in moving:
			if skip == node or skip.is_ancestor_of(node):
				still = false
				break
		if still:
			(node as GeometryInstance3D).layers |= LAYER


## Сколько хлопьев по уровню качества — та же доля, что у капель.
func apply_graphics() -> void:
	RainLook.scale_amount(_flakes, Graphics.rain_share())


## Хлопья — для теста.
func flakes() -> GPUParticles3D:
	return _flakes


## Покров — для теста.
func cover() -> Decal:
	return _cover


## Снег, раскатанный колёсами, на глубине [param z]: 1 — колея, 0 — рыхлый.
static func rut_at(z: float) -> float:
	var nearest := INF
	for lane: float in [StreetTraffic.NEAR_LANE_Z, StreetTraffic.FAR_LANE_Z]:
		for side: float in [-1.0, 1.0]:
			nearest = minf(nearest, absf(z - (lane + side * WHEEL_TRACK)))
	return clampf(1.0 - (nearest - RUT) / RUT, 0.0, 1.0)


func _snow(
	from: float, to: float, street: float, front: float, back: float, time: TimeOfDay.Kind
) -> void:
	var drift := HEIGHT / RoofSnow.FALL.x * RoofSnow.WIND
	_flakes = SnowLook.flakes(
		FLAKES,
		(HEIGHT + 1.0) / RoofSnow.FALL.x,
		Vector3((to - from + drift) * 0.5, 0.3, (front - back) * 0.5),
		RoofSnow.FALL,
		RoofSnow.WIND,
		RoofSnow.FLAKE * 1.3,
		SnowLook.brightness(time)
	)
	_flakes.name = "Flakes"
	# Гаснут о маркизы, машины и мостовую по карте высот улицы
	# ([method ExitStreet._catch]), а не по таймеру.
	_flakes.collision_base_size = 0.02
	(_flakes.process_material as ParticleProcessMaterial).collision_mode = (
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	)
	_flakes.position = Vector3((from + to - drift) * 0.5, street + HEIGHT, (front + back) * 0.5)
	_flakes.visibility_aabb = AABB(
		Vector3(-(to - from), -HEIGHT - 1.0, -8.0), Vector3((to - from) * 2.0, HEIGHT + 2.0, 16.0)
	)
	add_child(_flakes)


## Покров: картинка сверху, по x — ровная, по глубине — колеи на мостовой и
## рыхлый снег на тротуаре, с шумом по краям.
func _lay(from: float, to: float, street: float, front: float, back: float) -> void:
	var size := Vector2i(
		clampi(int((to - from) * TEXELS_PER_METRE), 64, 2048),
		clampi(int((front - back) * TEXELS_PER_METRE), 32, 1024)
	)
	var noise := FastNoiseLite.new()
	noise.seed = 0x5_0E
	noise.frequency = 0.08
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for row in size.y:
		# Строка картинки — глубина: верх картинки — дальний край (−Z).
		var z := lerpf(back, front, (float(row) + 0.5) / float(size.y))
		var on_road := z > ExitStreet.FAR_KERB_Z
		for column in size.x:
			var x := lerpf(from, to, (float(column) + 0.5) / float(size.x))
			var wobble := noise.get_noise_2d(x * 3.0, z * 3.0)
			var colour := COVER
			if on_road:
				var rut := rut_at(z + wobble * 0.08)
				colour = PACKED.lerp(SLUSH, rut)
				if rut <= 0.0 and wobble > 0.25:
					colour = COVER
			elif wobble < -0.45:
				colour = PACKED
			image.set_pixel(column, row, colour)
	_cover = Decal.new()
	_cover.name = "SnowCover"
	_cover.size = Vector3(to - from, COVER_HEIGHT, front - back)
	_cover.position = Vector3(
		(from + to) * 0.5, street - 0.2 + COVER_HEIGHT * 0.5, (front + back) * 0.5
	)
	_cover.cull_mask = LAYER
	_cover.texture_albedo = ImageTexture.create_from_image(image)
	_cover.normal_fade = COVER_NORMAL_FADE
	_cover.upper_fade = 0.02
	_cover.lower_fade = 0.02
	add_child(_cover)
