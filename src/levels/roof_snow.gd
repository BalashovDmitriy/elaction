class_name RoofSnow
extends Node3D

## Snow over the roof (ADR-0054, decisions 2 and 5): flakes fall with wind drift and die
## on the roof — by the same heightmap as rain ([RoofCatch]) — and the snow cover
## already lies on everything facing up: the deck, steps, parapet flashing, machine
## room and equipment. The cover does not grow: the snow fell before Otto came down, and
## no more is added during the building.
##
## There is no snow in front of the floors, just like rain ([RoofRain]): the building is
## in cutaway, and flakes in front of a floor would read as snow in a room.
##
## The cover is a decal from above on the roof layer [constant RoofCatch.LAYER]: it lies
## only on faces that look up, and only on static things — Otto, agents and the
## helicopter are not on the layer and stay without snow.

## Flakes on "High" ([method Graphics.rain_share]) — for a lifetime at a single fall
## speed [code]FALL.x[/code] — sky height above the deck, fall speed, m/s, sideways wind,
## m/s, flake size.
const FLAKES: int = 1400
const HEIGHT: float = 8.0
const FALL := Vector2(1.1, 1.9)
const WIND: float = 0.7
const FLAKE: float = 0.11

## Where in depth the snow falls — the same place as the rain.
const BACK_Z: float = RoofRain.BACK_Z
const FRONT_Z: float = RoofRain.FRONT_Z

## Particle step: a flake is slow, sixty per second is enough.
const TICKS: int = 60

## Cover: how far it rises above the deck, m — higher than the machine room and
## equipment; colour of the snow and of dense spots, bald patches; from what slope a face
## is already without snow (share of [member Decal.normal_fade]).
const COVER_HEIGHT: float = 7.5
const COVER := Color(0.88, 0.9, 0.95, 1.0)
const COVER_THIN := Color(0.8, 0.83, 0.88, 0.55)
const COVER_NORMAL_FADE: float = 0.55

var _flakes: GPUParticles3D = null
var _catcher: GPUParticlesCollisionHeightField3D = null
var _cover: Decal = null
var _tracks: SnowTracks = null
var _box := AABB()


## Builds the snow over the building's roof by the rules and plan at time of day
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
	# Over shaft openings the cab is underfoot — metal, not snow.
	_tracks.watch(deck, bounds.x, bounds.y, plan.gaps_on(rules, BuildingRules.ROOF))
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Moves the static things on the roof under [param roots] to the roof layer: the
## heightmap is captured from it, the cover lies on it.
func catch_on(roots: Array[Node]) -> void:
	RoofCatch.mark(roots, _box)


## How many flakes by quality level — the same share as for drops.
func apply_graphics() -> void:
	RainLook.scale_amount(_flakes, Graphics.rain_share())


## Flakes that die on the roof — for the test.
func flakes() -> GPUParticles3D:
	return _flakes


## The snow heightmap — for the test.
func catcher() -> GPUParticlesCollisionHeightField3D:
	return _catcher


## The cover — for the test.
func cover() -> Decal:
	return _cover


## Footprints on the deck — for the test.
func tracks() -> SnowTracks:
	return _tracks


## Flakes fall over the deck shifted against the wind: drifted, they land on the roof
## rather than going past the parapet down the facade. The shift is by a smaller drift
## from the left edge and a larger one from the right ([method SnowLook.slant]):
## otherwise at the left parapet not a single flake reached the deck, and at the right
## one some went past the flashing (code review M24l).
func _snow(rules: BuildingRules, deck: float, time: TimeOfDay.Kind) -> void:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var fall := HEIGHT + 0.3
	var slant := SnowLook.slant(FALL, WIND)
	# Cornice overhang of its own building (ADR-0058), as for rain ([RoofRain]).
	var overhang := BuildingShell.coping_overhang(rules.kind)
	var from := bounds.x - overhang - fall * slant.x
	var to := bounds.y + overhang - fall * slant.y
	# Lifetime — down to the deck even for the most slanted flake; the flake count is for
	# the same flow as with a lifetime at one fall speed: one living longer lies dead longer.
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


## Cover: a decal from above over the whole roof with flashing and equipment. Denser in
## the middle, with bald patches by noise — an even white sheet would read as paint.
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
