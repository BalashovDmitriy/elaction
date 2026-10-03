class_name Downwash
extends GPUParticles3D

## Dust under the helicopter rotor (ADR-0052, decision 6): the rotor downwash drives it
## across the roof in a fan while the helicopter hangs low, and it settles when it leaves.
## The dust band is on the roof under the rotor axis, at the play plane.

## Particle count, their life, s, half-width of the band, where they are lifted from, m,
## spread speed, m/s, and colour.
## Dust rises while the helicopter hangs no higher than [constant DUST_REACH] above the roof.
const DUST_COUNT: int = 70
const DUST_LIFE: float = 1.4
const DUST_HALF_WIDTH: float = 2.6
## Half-depth of the dust band, m: within the roof deck, not in front of the facade.
const DUST_DEPTH: float = 0.5
## Spread direction — up with a hundredth's tilt towards the camera. Straight up,
## Godot puts the [member ParticleProcessMaterial.flatness] fan into the YZ plane —
## towards the camera and into the building — and with a Z tilt the fan lies in the frame
## plane, XY (measured: [method GPUParticles3D.capture_aabb], code review M24l).
const DUST_DIRECTION := Vector3(0.0, 1.0, 0.01)
const DUST_SPEED := Vector2(2.5, 5.0)
const DUST_SIZE: float = 0.5
const DUST_COLOR := Color(0.55, 0.52, 0.48, 0.32)
const DUST_REACH: float = 7.0

## In snow the downwash lifts snow dust off the cover (ADR-0054): thicker, whiter,
## a larger cloud, and it hangs longer.
const POWDER_COUNT: int = 120
const POWDER_LIFE: float = 2.4
const POWDER_SIZE: float = 0.6
const POWDER_COLOR := Color(0.9, 0.93, 0.98, 0.26)

## The rotor downwash drives the rain too: a particle repeller sphere under the rotor axis
## spreads the streaks down and sideways, and they fall slanted, by velocity. Sphere
## radius, m, its strength, m/s², and what share of the helicopter's height above the roof
## it takes — the middle between the rotor and the deck.
const GUST_RADIUS: float = 4.5
const GUST_STRENGTH: float = 60.0
const GUST_RISE: float = 0.5
## Slab under the dust — along the deck: width and depth with a margin for spread, m.
const DECK_PLATE := Vector3(24.0, 1.0, 8.0)

## Roof height under the helicopter, scene; NAN — there is no roof under it.
var deck: float = NAN

var _gust := GPUParticlesAttractorSphere3D.new()
var _deck_plate := GPUParticlesCollisionBox3D.new()


func _init() -> void:
	name = "Downwash"
	amount = DUST_COUNT
	lifetime = DUST_LIFE
	local_coords = false
	emitting = false
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-8.0, -1.0, -8.0), Vector3(16.0, 4.0, 16.0))
	var process := ParticleProcessMaterial.new()
	# A band along the roof, not a ring: a ring carried dust forward past the facade,
	# and it hung in front of the thirtieth floor. The spread is a fan in the frame plane:
	# sideways and up ([member ParticleProcessMaterial.flatness]).
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(DUST_HALF_WIDTH, 0.05, DUST_DEPTH)
	process.direction = DUST_DIRECTION
	process.spread = 80.0
	process.flatness = 1.0
	process.initial_velocity_min = DUST_SPEED.x
	process.initial_velocity_max = DUST_SPEED.y
	process.gravity = Vector3(0.0, 0.3, 0.0)
	process.damping_min = 1.5
	process.damping_max = 2.5
	process.scale_min = 0.6
	process.scale_max = 1.5
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(DUST_COLOR, 0.0), DUST_COLOR, Color(DUST_COLOR, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * DUST_SIZE
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# A soft puff, not a square: without a texture a particle was drawn as a square of
	# colour, and on snow this was visible at once (M24l).
	look.albedo_texture = _puff()
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	look.disable_receive_shadows = true
	quad.material = look
	draw_pass_1 = quad
	_gust.name = "Gust"
	_gust.radius = GUST_RADIUS
	_gust.strength = 0.0
	_gust.attenuation = 1.0
	add_child(_gust)
	# The downwash sphere pushes away from itself and down: without collisions the dust went
	# through the deck by eight metres — in front of the thirtieth floor (measured in code review
	# M24l). It dies on the slab under it — on any roof, in any weather: the roof
	# height map ([RoofCatch]) exists only in rain and snow.
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	collision_base_size = 0.02
	_deck_plate.name = "DeckPlate"
	_deck_plate.size = DECK_PLATE
	_deck_plate.position = Vector3(0.0, -0.05 - DECK_PLATE.y * 0.5, 0.0)
	add_child(_deck_plate)


## Puts the dust band under the rotor axis at [param x] and raises dust while the helicopter
## is at scene height [param height] lower than [constant DUST_REACH] above the roof and
## [param hovering].
func follow(x: float, height: float, hovering: bool) -> void:
	if is_nan(deck):
		return
	global_position = Vector3(x, deck + 0.05, WorldSpace.PLAY_Z - 0.6)
	var low := hovering and height - deck < DUST_REACH
	if emitting != low:
		emitting = low
	# The downwash on rain is the same as on dust: while the helicopter hangs low.
	_gust.position = Vector3(0.0, maxf(height - deck, 0.0) * GUST_RISE, 0.0)
	_gust.strength = -GUST_STRENGTH if low else 0.0


## The dust becomes snowy: the snow cover on the roof lies under the rotor (ADR-0054).
## [param brightness] — snow brightness at the time of day ([method SnowLook.brightness]):
## snow dust glows like the flakes rather than taking the weak roof light.
func lift_snow(brightness: float) -> void:
	amount = POWDER_COUNT
	lifetime = POWDER_LIFE
	var process := process_material as ParticleProcessMaterial
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray(
		[Color(POWDER_COLOR, 0.0), POWDER_COLOR, Color(POWDER_COLOR, 0.0)]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	# Snow is lighter than dust: it flies higher and falls slower.
	process.gravity = Vector3(0.0, 0.6, 0.0)
	var quad := draw_pass_1 as QuadMesh
	quad.size = Vector2.ONE * POWDER_SIZE
	var look := quad.material as StandardMaterial3D
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(SnowLook.TINT * brightness, 1.0)


## The sphere the rotor downwash uses to spread rain and snow.
func gust() -> GPUParticlesAttractorSphere3D:
	return _gust


## A dust puff: a round spot, dense in the middle and fading towards the edge.
static func _puff() -> GradientTexture2D:
	var spot := GradientTexture2D.new()
	spot.fill = GradientTexture2D.FILL_RADIAL
	spot.fill_from = Vector2(0.5, 0.5)
	spot.fill_to = Vector2(1.0, 0.5)
	spot.width = 64
	spot.height = 64
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	fade.colors = PackedColorArray(
		[Color.WHITE, Color(1.0, 1.0, 1.0, 0.45), Color(1.0, 1.0, 1.0, 0.0)]
	)
	spot.gradient = fade
	return spot
