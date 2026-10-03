class_name Atmosphere
extends RefCounted

## The building's atmosphere: ambient tone, reflections, fog, glow and tonemapping.
##
## The numbers come from the `tools/look3d.gd` probe, tuned on our own geometry
## (ADR-0023, decision 7), and change only by a `tools/light_bench.gd` measurement.
## Built here, not in the level: the level is content with one line, while the bench and
## the probes need the same atmosphere without the whole building.

## The sky behind the building and the ambient tone. The tone is low and is needed only so
## that a darkened zone is dark rather than black: agents in the dark keep
## shooting, and the player must see what to shoot back at (ADR-0010, item 3).
const SKY := Color(0.03, 0.04, 0.07)
const AMBIENT_ENERGY: float = 0.55

## Floor reflections: screen-space, they need the camera tilt (decision 1).
const SSR_STEPS: int = 96
const SSR_FADE_IN: float = 0.2

## Contact shadows in the corners: under the actors, at the skirting, in openings.
const SSAO_INTENSITY: float = 2.0
const SSAO_RADIUS: float = 0.6

## Fog is a hint, not milk: at 0.015 the lamp cones ate the whole frame. The density
## multiplier and air glow are by building kind ([constant BuildingAir.FOG_GAIN]).
const FOG_DENSITY: float = 0.0035

## Glow only from what is brighter than the frame: otherwise bloom grows every lamp into
## a white pillar and eats the detail that everything was done for.
const GLOW_INTENSITY: float = 0.6
const GLOW_THRESHOLD: float = 1.0

const EXPOSURE: float = 1.15

## The frame tone is night noir after the reference (ADR-0030, decision 1): per-channel
## curves from cold shadows to warm light, slightly more contrast, slightly less colour.
## Game signs glow with emission on top of the tone and stay bright.
##
## Tuned in M22 by shots from three sets (`layout_shot --tone=N`): cold in the
## shadows and warmth in the light are spread further apart than in M20 — marble and
## wallpaper were no longer bleached by the lamp, and doors and lamps became warmer on the
## blue wall.
##
## Since M24n the contrast and night tone of the frame are set by the building kind
## ([BuildingAir]): noir here is the night tone of the day in [TimeOfDay], and at night
## the kind overrides it entirely.
const NOIR_SHADOW := Color(0.0, 0.03, 0.08)
const NOIR_MIDDLE := Color(0.27, 0.33, 0.4)
const NOIR_LIGHT := Color(1.0, 0.93, 0.8)
const NOIR_MIDDLE_AT: float = 0.35
const SATURATION: float = 0.9


## Building atmosphere with ambient tone [param ambient] — the round palette colour — at
## time of day [param time] (ADR-0051): by day the building is lighter and without lamps,
## the frame tone is its own for each time. Since M24n the tone, saturation and fog also
## depend on building kind [param kind] ([BuildingAir], ADR-0056).
static func environment(
	ambient: Color,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> Environment:
	var air := Environment.new()
	air.background_mode = Environment.BG_COLOR
	air.background_color = SKY
	air.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	air.ambient_light_color = TimeOfDay.ambient(time, ambient)
	air.ambient_light_energy = AMBIENT_ENERGY * TimeOfDay.ambient_gain(time)

	air.ssr_enabled = true
	air.ssr_max_steps = SSR_STEPS
	air.ssr_fade_in = SSR_FADE_IN
	air.ssao_enabled = true
	air.ssao_intensity = SSAO_INTENSITY
	air.ssao_radius = SSAO_RADIUS

	air.volumetric_fog_enabled = true
	air.volumetric_fog_density = FOG_DENSITY * BuildingAir.FOG_GAIN[kind]
	air.volumetric_fog_emission = BuildingAir.FOG_GLOW[kind].lerp(
		TimeOfDay.HORIZON[time] * 0.08, TimeOfDay.daylight(time)
	)

	air.glow_enabled = true
	air.glow_intensity = GLOW_INTENSITY
	air.glow_bloom = 0.0
	air.glow_hdr_threshold = GLOW_THRESHOLD
	air.tonemap_mode = Environment.TONE_MAPPER_ACES
	air.tonemap_exposure = EXPOSURE

	air.adjustment_enabled = true
	air.adjustment_contrast = BuildingAir.CONTRAST[kind]
	air.adjustment_saturation = BuildingAir.saturation(kind, time)
	air.adjustment_color_correction = grade_curve(time, kind)
	Graphics.apply_to(air)
	return air


## Tone curves: a gradient by which each channel is mapped from its own
## value to its own. At night — noir: black goes to cold blue, white to
## warm; at other times — its own tone ([constant TimeOfDay.GRADE_SHADOW] and
## neighbours), tinted by the tone of building kind [param kind] ([BuildingAir]).
static func grade_curve(
	time: TimeOfDay.Kind, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, NOIR_MIDDLE_AT, 1.0])
	gradient.colors = BuildingAir.grade(kind, time)
	var curve := GradientTexture1D.new()
	curve.gradient = gradient
	return curve
