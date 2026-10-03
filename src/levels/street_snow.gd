class_name StreetSnow
extends Node3D

## Snow on the street at the exit (ADR-0054, decisions 2 and 5): flakes above the roadway and
## sidewalk and cover — on top of the sidewalk, kerb, awnings, window sills and
## cornices of the houses across the road. On the roadway — ruts: where the traffic
## flows ([StreetTraffic]), snow is packed down to wet asphalt, on the sides of the ruts
## — loose.
##
## The cover is a decal from above on the street layer [constant LAYER]: [method mark]
## moves whatever is static on the street onto it. Traffic cars and the car at the
## kerb are not on it: the decal is in the world, and on a moving car snow would
## slide in patches.

## Layer of static things on the street. The nineteenth: the twentieth is taken by the roof
## ([constant RoofCatch.LAYER]), and cameras and lights see all twenty.
const LAYER: int = 1 << 18

## Flakes at "high", sky height above the street, m.
const FLAKES: int = 2400
const HEIGHT: float = 16.0

## Rut: half-width of a wheel track, m, and how far a car's wheels are from
## its axis, m.
const RUT: float = 0.24
const WHEEL_TRACK: float = 0.78
## At what depth the wheels of both traffic lanes run ([StreetTraffic]). As a number,
## not two loops over lanes and sides: [method rut_at] is called for every
## cover point — there are hundreds of thousands — and arrays on every call cost half
## of the cover build, 60 ms of 120 (code review M24l).
const WHEEL_LINES: Array[float] = [
	StreetTraffic.NEAR_LANE_Z - WHEEL_TRACK,
	StreetTraffic.NEAR_LANE_Z + WHEEL_TRACK,
	StreetTraffic.FAR_LANE_Z - WHEEL_TRACK,
	StreetTraffic.FAR_LANE_Z + WHEEL_TRACK,
]

## Snow: colour of loose and packed, colour of the wet rut; how high above the
## street the cover lies — up to the cornices of the houses across the road.
const COVER := Color(0.88, 0.9, 0.95, 1.0)
const PACKED := Color(0.7, 0.72, 0.76, 0.85)
const SLUSH := Color(0.08, 0.085, 0.095, 0.9)
const COVER_HEIGHT: float = 24.0
const COVER_NORMAL_FADE: float = 0.55

## How many cover points per metre.
const TEXELS_PER_METRE: float = 24.0

var _flakes: GPUParticles3D = null
var _cover: Decal = null


## Builds snow above the street from [param from] to [param to] along x, at scene level
## [param street], in depth — from [param front] to [param back], at
## time of day [param time].
func build(
	from: float, to: float, street: float, front: float, back: float, time: TimeOfDay.Kind
) -> void:
	name = "Snow"
	_snow(from, to, street, front, back, time)
	_lay(from, to, street, front, back)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Moves onto layer [constant LAYER] whatever is static under [param root], except
## what is under the nodes [param moving].
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


## How many flakes by quality level — the same fraction as for drops.
func apply_graphics() -> void:
	RainLook.scale_amount(_flakes, Graphics.rain_share())


## Flakes — for the test.
func flakes() -> GPUParticles3D:
	return _flakes


## Cover — for the test.
func cover() -> Decal:
	return _cover


## Snow packed by wheels at depth [param z]: 1 — a rut, 0 — loose.
static func rut_at(z: float) -> float:
	var nearest := INF
	for line: float in WHEEL_LINES:
		nearest = minf(nearest, absf(z - line))
	return clampf(1.0 - (nearest - RUT) / RUT, 0.0, 1.0)


func _snow(
	from: float, to: float, street: float, front: float, back: float, time: TimeOfDay.Kind
) -> void:
	var drift := HEIGHT / RoofSnow.FALL.x * RoofSnow.WIND
# Lifetime — down to the sidewalk even for the most slanted flake, flow — as before, as on the roof
	# ([method RoofSnow._snow]).
	var slowest := SnowLook.slowest_fall(RoofSnow.FALL, RoofSnow.WIND)
	_flakes = SnowLook.flakes(
		roundi(FLAKES * RoofSnow.FALL.x / slowest),
		(HEIGHT + 1.0) / slowest,
		Vector3((to - from + drift) * 0.5, 0.3, (front - back) * 0.5),
		RoofSnow.FALL,
		RoofSnow.WIND,
		RoofSnow.FLAKE * 1.3,
		SnowLook.brightness(time)
	)
	_flakes.name = "Flakes"
	# They die against awnings, cars and the roadway by the street height map
	# ([method ExitStreet._catch]), not by a timer.
	_flakes.collision_base_size = 0.02
	(_flakes.process_material as ParticleProcessMaterial).collision_mode = (
		ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	)
	_flakes.position = Vector3((from + to - drift) * 0.5, street + HEIGHT, (front + back) * 0.5)
	_flakes.visibility_aabb = AABB(
		Vector3(-(to - from), -HEIGHT - 1.0, -8.0), Vector3((to - from) * 2.0, HEIGHT + 2.0, 16.0)
	)
	add_child(_flakes)


## Cover: a picture from above, even along x, in depth — ruts on the roadway and
## loose snow on the sidewalk, with noise at the edges.
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
		# A picture row is depth: the top of the picture is the far edge (−Z).
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
