class_name RoofRain
extends Node3D

## Rain over the roof (M24a, ADR-0037, decision 3; the user's decision —
## "the drops naturally hit the roof, and it shows").
##
## Before M24a a drop died by a timer computed for the height down to the deck. The
## lifetime was rounded to particle ticks, and half the drops flew an extra metre —
## under the roof slab, onto the thirtieth floor. Now drops die on the roof itself:
## particle collision against a heightmap captured from above off the deck, steps,
## parapets, machine room and equipment. Where a drop hits, there are splashes; on the
## deck — ripples, the deck itself is wet: darker, with puddles in which, at levels with
## reflections, the machine room and the sign are visible. Water drips from the parapet
## flashing and the machine room canopy.
##
## There is no rain in front of the floors: the building is in cutaway, and streaks in
## front of a floor would read as rain in a room. Drops fall only over the deck, between
## the corridor's front face and the back steps of the roof; next to the tower falls the
## city rain ([RainLook.city]) — it is behind the building.
##
## Rain is seen by light (decision 3, amendment): drops glow from the lamp over the roof
## and carry a blurred copy of the background ([RainLook]); over the deck there is a thin
## haze with water dust right at the deck, in which the lamp's cone is visible, and
## around the lamp a halo broken into streaks. The haze is volumetric fog, absent on low;
## the halo and drops are on any level.
##
## The heightmap, the covers over openings and the roof layer are shared with snow
## ([RoofCatch]).

## Roof layer ([constant RoofCatch.LAYER]): the wet deck lies on it.
const LAYER: int = RoofCatch.LAYER

## Drops on "High" ([method Graphics.rain_share]), sky height above the deck, speed,
## m/s, and drift per metre of fall. They fall faster than real rain: at 9 m/s a streak
## per frame is a dot, and the rain reads as snow.
const DROPS: int = 1100
const HEIGHT: float = 8.0
const SPEED := Vector2(15.0, 19.0)
const SLANT: float = 0.08
const DROP := Vector2(0.018, 0.8)
## Drop look ([RainLook.drop_look]): lamp light doubled and falling off more steeply than
## the lamp — the drops glow near it, not across the whole roof; two running gust waves.
const DROP_LOOK := {"lit_gain": 2.0, "falloff": 2.5, "back_gain": 1.4, "gust_amount": 1.0}
## Splashes and drips: dimmer than drops and without near, wide ones.
const SPRAY_LOOK := {
	"lit_gain": 0.6, "back_gain": 0.6, "base": 0.03, "opacity": 1.0, "near_share": 0.0
}

## Where in depth the rain falls: from the back steps of the roof to the corridor's
## front face — no farther, otherwise drops would appear in front of the roof slab.
const BACK_Z: float = -3.0
const FRONT_Z: float = WorldSpace.CORRIDOR_DEPTH * 0.5 - 0.08

## Particle step: at 120 per second a drop travels 15 cm per step, and splashes rise
## almost where it touched, not under the deck.
const TICKS: int = 120

## Splashes: how many droplets per hit, their size and opacity, rise speed, m/s.
const SPLASH_PER_HIT: int = 4
const SPLASH := Vector2(0.024, 0.12)
## What share of hits gets to splash: with a thousand drops, splashes from each would
## read as boiling.
const SPLASH_SHARE: float = 0.4
const SPLASH_SPEED := Vector2(0.9, 2.1)
const SPLASH_LIFE: float = 0.3

## Ripples on the deck: how many at once, size, life.
const RIPPLES: int = 36
const RIPPLE: float = 0.24
const RIPPLE_LIFE: float = 0.65

## Drips from the parapet flashing and the machine room canopy: how many drops at once
## and over how many points along the edge.
const DRIPS: int = 9
const DRIP_POINTS: int = 48
const DRIP := Vector2(0.02, 0.12)

## Wet deck: tone and roughness of dry and puddle. Puddle roughness is nearly a mirror:
## reflections ([method Graphics.reflections]) fall only into it.
const WET := Color(0.02, 0.022, 0.03, 0.55)
const PUDDLE := Color(0.012, 0.014, 0.02, 0.9)
const WET_ROUGHNESS: float = 0.32
const PUDDLE_ROUGHNESS: float = 0.04

## Haze over the roof: density, how many times denser at the deck, height. The density
## is low on purpose: denser — and the haze would reveal the flat panels behind the roof.
const MIST_DENSITY: float = 0.009
const MIST_SPRAY: float = 4.0
const MIST_HEIGHT: float = 9.0
const MIST_SHADER := preload("res://src/levels/rain_mist.gdshader")
## How much of the roof lamp's light goes into the fog in rain: a cone in the haze.
const LAMP_IN_FOG: float = 2.0

var _drops: GPUParticles3D = null
var _splashes: GPUParticles3D = null
var _ripples: GPUParticles3D = null
var _drips: GPUParticles3D = null
var _mist: FogVolume = null
var _halo: MeshInstance3D = null
var _catcher: GPUParticlesCollisionHeightField3D = null
## Where the rain falls, in scene coordinates: the heightmap is captured from this box.
var _box := AABB()


## Builds the rain over the building's roof by the rules and the plan. [param lamp] — the
## lamp over the roof: it has a halo, its cone is visible in the haze.
func build(rules: BuildingRules, plan: BuildingPlan, lamp: OmniLight3D) -> void:
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	_box = RoofCatch.box(rules, BACK_Z, FRONT_Z, HEIGHT)
	_catcher = RoofCatch.catcher(_box, "RainCatcher")
	add_child(_catcher)
	for lid in RoofCatch.lids(rules, plan, _box, SPEED.y / float(TICKS)):
		add_child(lid)
	_rain(rules, deck)
	_splash()
	_ripple(rules, deck)
	_drip(rules, plan, deck)
	_wet(rules, deck)
	_fog(rules, deck)
	_glow(lamp)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Moves the static things on the roof under [param roots] to layer [constant LAYER]:
## the heightmap is captured from it and the wet deck lies on it.
func catch_on(roots: Array[Node]) -> void:
	RoofCatch.mark(roots, _box)


## How many drops, splashes and ripples by quality level. On low there are no ripples or
## drips: there are four times fewer drops there too, and ripples on the thin strip of
## deck would read as flicker. Haze — only where there is volumetric fog.
func apply_graphics() -> void:
	var share := Graphics.rain_share()
	RainLook.scale_amount(_drops, share)
	RainLook.scale_amount(_splashes, share)
	RainLook.scale_amount(_ripples, share)
	var rich := Graphics.quality > Graphics.Quality.LOW
	_ripples.emitting = rich
	_ripples.visible = rich
	_drips.emitting = rich
	_drips.visible = rich
	_mist.visible = Graphics.volumetric_fog()


## Drops that die on the roof — so a test can check the collision.
func drops() -> GPUParticles3D:
	return _drops


## The rain's heightmap: what it is captured from.
func catcher() -> GPUParticlesCollisionHeightField3D:
	return _catcher


## Haze over the roof — for the test.
func mist() -> FogVolume:
	return _mist


## Halo of the lamp over the roof — for the test.
func halo() -> MeshInstance3D:
	return _halo


func _rain(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	# They fall between the edges of the flashing and shifted against the drift: a drop is
	# not carried past the parapet and does not fall past the roof down the facade.
	var fall := HEIGHT + 0.3
	var spread := fall * tan(deg_to_rad(RainLook.SPREAD))
	# Cornice overhang of its own building (ADR-0058): the office's flashing is narrow, and
	# with the hotel's overhang drops would fall past it.
	var overhang := BuildingShell.coping_overhang(rules.kind)
	var from := bounds.x - overhang + spread
	var to := bounds.y + overhang - fall * SLANT - spread
	_drops = RainLook.streaks(
		DROPS,
		(HEIGHT + 1.0) / SPEED.x,
		Vector3((to - from) * 0.5, 0.3, (FRONT_Z - BACK_Z) * 0.5),
		SPEED,
		SLANT,
		DROP,
		RainLook.drop_look(DROP_LOOK)
	)
	_drops.name = "Drops"
	_drops.position = Vector3((from + to) * 0.5, deck + HEIGHT, (FRONT_Z + BACK_Z) * 0.5)
	_drops.fixed_fps = TICKS
	_drops.interpolate = true
	_drops.collision_base_size = 0.02
	_drops.visibility_aabb = AABB(
		Vector3(-(to - from), -HEIGHT - 1.0, -3.0), Vector3((to - from) * 2.0, HEIGHT + 2.0, 6.0)
	)
	var process := _drops.process_material as ParticleProcessMaterial
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	process.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	process.sub_emitter_amount_at_collision = SPLASH_PER_HIT
	add_child(_drops)


## Splashes at the hit point: a few droplets up and sideways, falling back.
func _splash() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	# A drop dies having gone slightly under the surface — by half a particle step.
	process.emission_shape_offset = Vector3(0.0, SPEED.y / float(TICKS) * 0.5, 0.0)
	process.direction = Vector3.UP
	process.spread = 55.0
	process.initial_velocity_min = SPLASH_SPEED.x
	process.initial_velocity_max = SPLASH_SPEED.y
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	# Splashes fade toward the end of their life, not from the first frame: otherwise on
	# average half as many of them are visible.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var fade_ramp := GradientTexture1D.new()
	fade_ramp.gradient = fade
	process.color_ramp = fade_ramp

	var hits := float(DROPS) / ((HEIGHT + 1.0) / SPEED.x)
	var amount := int(hits * SPLASH_LIFE * float(SPLASH_PER_HIT) * SPLASH_SHARE)
	_splashes = GPUParticles3D.new()
	_splashes.name = "Splashes"
	_splashes.amount = amount
	_splashes.set_meta(RainLook.FULL, amount)
	_splashes.lifetime = SPLASH_LIFE
	_splashes.local_coords = false
	_splashes.fixed_fps = TICKS
	_splashes.interpolate = true
	_splashes.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_splashes.process_material = process
	_splashes.draw_pass_1 = RainLook.streak_mesh(SPLASH, RainLook.drop_look(SPRAY_LOOK))
	_splashes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splashes.visibility_aabb = _local(_box)
	add_child(_splashes)
	_drops.sub_emitter = _drops.get_path_to(_splashes)


## Ripples on the wet deck: across its whole strip between the parapets.
func _ripple(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var front := WorldSpace.CORRIDOR_DEPTH * 0.5
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3((inner.y - inner.x) * 0.5, 0.0, front - 0.05)
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.0
	process.scale_min = 0.6
	process.scale_max = 1.4
	var quad := QuadMesh.new()
	quad.size = Vector2(RIPPLE, RIPPLE)
	quad.orientation = PlaneMesh.FACE_Y
	var look := ShaderMaterial.new()
	look.shader = RainLook.RIPPLE_SHADER
	quad.material = look
	_ripples = GPUParticles3D.new()
	_ripples.name = "Ripples"
	_ripples.amount = RIPPLES
	_ripples.set_meta(RainLook.FULL, RIPPLES)
	_ripples.lifetime = RIPPLE_LIFE
	_ripples.preprocess = RIPPLE_LIFE
	_ripples.local_coords = false
	_ripples.process_material = process
	_ripples.draw_pass_1 = quad
	_ripples.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripples.position = Vector3((inner.x + inner.y) * 0.5, deck + 0.006, 0.0)
	_ripples.visibility_aabb = AABB(
		Vector3(-(inner.y - inner.x), -0.5, -2.0), Vector3((inner.y - inner.x) * 2.0, 1.0, 4.0)
	)
	add_child(_ripples)


## Drips from the edges: the flashing of both parapets and the machine room canopy.
func _drip(rules: BuildingRules, plan: BuildingPlan, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var coping := deck + BuildingShell.PARAPET_HEIGHT
	# The edge follows the cornice overhang of its own building: by the largest one, the
	# office's drips would hang in the air 14 cm from the flashing.
	var overhang := BuildingShell.coping_overhang(rules.kind)
	var edges: Array[PackedVector3Array] = []
	for x: float in [
		bounds.x + BuildingShell.WALL_WIDTH + overhang,
		bounds.y - BuildingShell.WALL_WIDTH - overhang,
	]:
		edges.append(PackedVector3Array([Vector3(x, coping, BACK_Z), Vector3(x, coping, FRONT_Z)]))
	var shaft := plan.roof_shaft()
	if shaft != null:
		var half := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5
		var top := deck + BuildingShafts.MACHINE_ROOM_SIZE.y
		var face := WorldSpace.BACK_WALL_Z + BuildingShafts.MACHINE_ROOM_DEPTH
		edges.append(
			PackedVector3Array(
				[Vector3(shaft.x - half, top, face), Vector3(shaft.x + half, top, face)]
			)
		)
	var points := Image.create(DRIP_POINTS, 1, false, Image.FORMAT_RGBF)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["drips", bounds])
	for index in DRIP_POINTS:
		var line := edges[index % edges.size()]
		var at := line[0].lerp(line[1], rng.randf())
		points.set_pixel(index, 0, Color(at.x, at.y, at.z))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	process.emission_point_texture = ImageTexture.create_from_image(points)
	process.emission_point_count = DRIP_POINTS
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.initial_velocity_min = 0.0
	process.initial_velocity_max = 0.2
	process.direction = Vector3.DOWN
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_drips = GPUParticles3D.new()
	_drips.name = "Drips"
	_drips.amount = DRIPS
	_drips.lifetime = 0.8
	_drips.randomness = 0.6
	_drips.local_coords = false
	_drips.fixed_fps = TICKS
	_drips.interpolate = true
	_drips.collision_base_size = 0.02
	_drips.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_drips.process_material = process
	_drips.draw_pass_1 = RainLook.streak_mesh(DRIP, RainLook.drop_look(SPRAY_LOOK))
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.visibility_aabb = _local(_box)
	add_child(_drips)


## Wet deck: a decal on layer [constant LAYER] — darker and smoother, nearly a mirror in
## puddles.
func _wet(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var noise := FastNoiseLite.new()
	noise.seed = hash(["puddles", bounds])
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var width := bounds.y - bounds.x
	var depth := WorldSpace.CORRIDOR_DEPTH
	var pixels := Vector2i(1024, maxi(int(1024.0 * depth / width), 32))
	var wet := Decal.new()
	wet.name = "WetDeck"
	wet.size = Vector3(width, 0.3, depth)
	wet.position = Vector3((bounds.x + bounds.y) * 0.5, deck, 0.0)
	wet.cull_mask = LAYER
	wet.texture_albedo = _puddles(noise, pixels, [WET, WET, PUDDLE, PUDDLE])
	wet.texture_orm = _puddles(
		noise,
		pixels,
		[
			Color(1.0, WET_ROUGHNESS, 0.0),
			Color(1.0, WET_ROUGHNESS, 0.0),
			Color(1.0, PUDDLE_ROUGHNESS, 0.0),
			Color(1.0, PUDDLE_ROUGHNESS, 0.0),
		]
	)
	wet.upper_fade = 0.05
	wet.lower_fade = 0.05
	add_child(wet)


## Haze over the roof: volumetric fog over the whole deck, denser right at it.
## The lower edge is slightly under the deck: the floors under the roof stay out of the haze.
func _fog(rules: BuildingRules, deck: float) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var look := ShaderMaterial.new()
	look.shader = MIST_SHADER
	look.set_shader_parameter("density", MIST_DENSITY)
	look.set_shader_parameter("deck_boost", MIST_SPRAY)
	look.set_shader_parameter("deck_y", deck)
	look.set_shader_parameter("back_z", _box.position.z)
	_mist = FogVolume.new()
	_mist.name = "Mist"
	_mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_mist.size = Vector3(bounds.y - bounds.x + 1.0, MIST_HEIGHT, 5.0)
	_mist.position = Vector3((bounds.x + bounds.y) * 0.5, deck + MIST_HEIGHT * 0.5 - 0.1, -0.8)
	_mist.material = look
	add_child(_mist)


## The lamp's halo in the rain and its cone in the haze.
func _glow(lamp: OmniLight3D) -> void:
	lamp.light_volumetric_fog_energy = LAMP_IN_FOG
	_halo = RainLook.halo(lamp.position + Vector3(0.0, 0.0, -1.5), lamp.light_color)
	add_child(_halo)


## Puddles by noise: dry up to the noise's middle, puddle above it.
static func _puddles(noise: FastNoiseLite, pixels: Vector2i, colours: Array[Color]) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.56, 0.64, 1.0])
	gradient.colors = PackedColorArray(colours)
	var texture := NoiseTexture2D.new()
	texture.width = pixels.x
	texture.height = pixels.y
	texture.noise = noise
	texture.color_ramp = gradient
	return texture


func _local(box: AABB) -> AABB:
	return AABB(box.position - global_position, box.size)
