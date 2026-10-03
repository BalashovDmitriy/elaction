class_name Graphics
extends RefCounted

## Graphics quality level and what it enables (ADR-0030, decision 5;
## "Ultra", anti-aliasing and choosing by measurement — ADR-0034).
##
## One table for the whole project: the atmosphere, lamps, window and city ask here
## what they may do, rather than each keeping its own threshold. The level does not touch
## the game rules — darkness lives in [FloorLighting], not in the picture, and an agent in
## the dark sees Otto the same way on any level.
##
## The level changes via settings right in the middle of a game: nodes it matters to
## are in group [constant GROUP] and rebuild on [method broadcast].

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

## Group of nodes that rebuild when the level changes. Each of them
## must be able to [code]apply_graphics()[/code].
const GROUP := &"graphics"

## Fraction of the window resolution the city is drawn at, by level. It is hazy and
## blurred by design, and on low levels a second frame at full resolution
## would cost double. Since M24a the near row has frames, mullions and life behind the glass
## (ADR-0037, decision 4): on high the city is drawn at three quarters of the window, on
## "Ultra" at full. The city itself is cheap — boxes and quads without lights — and
## the frame measurement barely sees the difference.
const CITY_SHARE: Array[float] = [0.34, 0.5, 0.75, 1.0]

## Share of raindrops by level.
const RAIN_SHARE: Array[float] = [0.25, 0.5, 1.0, 1.0]

## Anti-aliasing by level (ADR-0034, decision 2): MSAA on the window, FXAA only for
## low. No level has TAA: it blurred the indicator lights and the actors' outline — which
## kept readability on a dark floor until M24f.
const MSAA: Array[Viewport.MSAA] = [
	Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_2X, Viewport.MSAA_4X
]

## Lamp shadow atlas, pixels per side: on "Ultra" twice as large, and the shadows of
## furniture and people are sharper.
const SHADOW_ATLAS: Array[int] = [2048, 4096, 4096, 8192]

## How much lamp light goes into the volumetric fog: on "Ultra" lamps have a halo in
## the corridor air (ADR-0034, decision 1), below — the fog only brightens slightly at
## the lamps, as it did since M17. More — and the haze lies over the actors.
const LIGHT_IN_FOG: Array[float] = [0.0, 1.0, 1.0, 3.0]

## Volumetric fog grid by level: width and depth. A coarser grid — and the lamp cone
## in the air is stepped.
const FOG_GRID: Array[Vector2i] = [
	Vector2i(64, 64), Vector2i(64, 64), Vector2i(64, 64), Vector2i(128, 128)
]

## Current level. Static: it is read by nodes that are created and
## recreated with each building, while the settings outlive any of them.
static var quality: Quality = Quality.HIGH


## Floor reflections — screen-space, the most expensive of high.
static func reflections() -> bool:
	return quality >= Quality.HIGH


## Contact shadows in the corners.
static func contact_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Volumetric fog.
static func volumetric_fog() -> bool:
	return quality >= Quality.MEDIUM


## Bounced light: a lamp bounces off the floor and walls.
static func indirect_light() -> bool:
	return quality == Quality.ULTRA


## Shadow from the lamp cone.
static func spot_shadows() -> bool:
	return quality >= Quality.MEDIUM


## Shadow from the lamp fill — a second shadow per lamp.
static func fill_shadows() -> bool:
	return quality >= Quality.HIGH


## Sun shadow on the roof and the street (ADR-0051).
static func sun_shadows() -> bool:
	return quality >= Quality.MEDIUM


## How much of a source's light goes into the volumetric fog.
static func light_in_fog() -> float:
	return LIGHT_IN_FOG[quality]


static func city_share() -> float:
	return CITY_SHARE[quality]


static func rain_share() -> float:
	return RAIN_SHARE[quality]


## Turns on and off what depends on the level in the atmosphere.
static func apply_to(environment: Environment) -> void:
	environment.ssr_enabled = reflections()
	environment.ssao_enabled = contact_shadows()
	environment.volumetric_fog_enabled = volumetric_fog()
	environment.ssil_enabled = indirect_light()


## Anti-aliasing and shadows are window properties, not atmosphere ones: set on the root
## window.
static func apply_to_viewport(viewport: Viewport) -> void:
	smooth(viewport)
	viewport.positional_shadow_atlas_size = SHADOW_ATLAS[quality]
	RenderingServer.positional_soft_shadow_filter_set_quality(
		(
			RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
			if quality == Quality.ULTRA
			else RenderingServer.SHADOW_QUALITY_SOFT_LOW
		)
	)
	var grid := FOG_GRID[quality]
	RenderingServer.environment_set_volumetric_fog_volume_size(grid.x, grid.y)


## Window anti-aliasing by level: both the root one and the city view (ADR-0037,
## decision 4). Without it the city view was drawn in steps, and stretched to the screen
## twofold — in steps twice as large.
static func smooth(viewport: Viewport) -> void:
	viewport.msaa_3d = MSAA[quality]
	viewport.screen_space_aa = (
		Viewport.SCREEN_SPACE_AA_FXAA
		if quality == Quality.LOW
		else Viewport.SCREEN_SPACE_AA_DISABLED
	)
	viewport.use_taa = false


## Sets the level and rebuilds everyone it matters to.
static func broadcast(level: Quality) -> void:
	quality = level
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		apply_to_viewport(tree.root)
		tree.call_group(GROUP, &"apply_graphics")
