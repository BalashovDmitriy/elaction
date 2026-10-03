class_name VerticalSign
extends Node3D

## The building's neon sign on the facade corner, letters in a column (ADR-0033,
## decision 2).
##
## Before M21b the HOTEL neon stood on the roof, behind the equipment, and on the way
## down it went out over the top of the frame and under the HUD. The corner sign hangs
## along the upper floors outside the building facing the camera: the equipment does not
## cover it, and it is visible all the way down the tower. The hotel has its name and
## HOTEL, the office has the corporation's name.
##
## Light is the letters' emission and one glow source, the same one the neon on the roof
## had: the budget of environment light sources does not grow. One letter occasionally
## flickers, like real neon whose tube is about to die.

## Letter step in height and their size, m; the board is wider than a letter by margins.
const LETTER_STEP: float = 0.82
const LETTER_SIZE: float = 0.7
const MARGIN: float = 0.3
## How far the neon hum can be heard, m.
const BUZZ_REACH: float = 9.0
const PANEL_WIDTH: float = 1.1
const PANEL_DEPTH: float = 0.18
## Gap between lines (the name and HOTEL), in letter steps.
const LINE_GAP: float = 0.6

## How far the sign stands off the building's side wall and where in depth, m.
const STANDOFF: float = 0.75
const Z: float = -0.25
## Top of the sign above the roof deck, m.
const RISE: float = 0.4

## Neon: hotel is pink, office is cold blue, residential building is purple
## (ADR-0055, decision 3). Not the colors of the game's indicator lights (ADR-0023,
## decision 6).
const NEON_HOTEL := Color(1.0, 0.25, 0.55)
const NEON_OFFICE := Color(0.3, 0.85, 1.0)
const NEON_RESIDENTIAL := Color(0.45, 0.42, 1.0)
const PANEL := Color(0.07, 0.07, 0.09)

## Glow: brightness and radius, m.
const GLOW_ENERGY: float = 1.6
const GLOW_RANGE: float = 9.0

## Neon halo in the rain: how much wider and taller than the board, m, brightness, and
## how far behind the board, beyond the building's back wall, so that the halo does not
## fall into the corridors.
const HALO_MARGIN := Vector2(2.4, 2.0)
const HALO_STRENGTH: float = 0.25
const HALO_BEHIND: float = 1.6

## Unlit neon by day (ADR-0052, decision 4): glass tubes of the neon color, but dark and
## in sunlight: the sign is visible, but it does not glow.
const UNLIT_DARKEN: float = 0.55
const UNLIT_GREY: float = 0.35

## Flicker: how often in seconds a letter goes out and for how long.
const FLICKER_EVERY: float = 3.7
const FLICKER_FOR: float = 0.18

var _letters: Array[Label3D] = []
var _glow: OmniLight3D = null
var _halo: MeshInstance3D = null
## Board height, m: the rain halo follows it.
var _height: float = 0.0
## Top of the board in the rules plane.
var _top: float = 0.0
var _flicker: Label3D = null
var _clock: float = 0.0
var _lit: bool = true


## Neon color of building [param identity]: the sign and the HUD edge.
static func neon_of(identity: BuildingIdentity) -> Color:
	match identity.kind:
		BuildingIdentity.Kind.OFFICE:
			return NEON_OFFICE
		BuildingIdentity.Kind.RESIDENTIAL:
			return NEON_RESIDENTIAL
	return NEON_HOTEL


## Hangs the sign of building [param identity] at the right wall of the top floor.
func hang(rules: BuildingRules, identity: BuildingIdentity) -> void:
	name = "VerticalSign"
	var lines := identity.sign_lines()
	var neon := neon_of(identity)
	_lit = TimeOfDay.sign_lit(rules.time_of_day)
	var count := 0
	for line in lines:
		count += line.length()
	var height := (count + LINE_GAP * (lines.size() - 1)) * LETTER_STEP + MARGIN * 2.0
	_height = height
	var top := rules.floor_surface(BuildingRules.ROOF) - RISE
	_top = top
	var x := rules.floor_span(0).y + STANDOFF

	var panel := GreyboxLook.box(
		Vector3(PANEL_WIDTH, height, PANEL_DEPTH), GreyboxLook.metal(PANEL)
	)
	panel.position = WorldSpace.to_scene(Vector2(x, top + height * 0.5))
	panel.position.z = Z
	add_child(panel)
	# The neon hums where it hangs (ADR-0036): audible on the roof and the upper floors.
	# Unlit neon is silent.
	if _lit:
		Sounds.source(panel, Sounds.NEON_BUZZ, BUZZ_REACH, true)
	# Brackets to the wall: top and bottom.
	for share: float in [0.12, 0.88]:
		var arm := GreyboxLook.box(
			Vector3(STANDOFF, 0.08, 0.08), GreyboxLook.metal(PANEL.lightened(0.2))
		)
		arm.position = WorldSpace.to_scene(Vector2(x - STANDOFF * 0.5, top + height * share))
		arm.position.z = Z
		add_child(arm)

	var y := top + MARGIN + LETTER_STEP * 0.5
	for line in lines:
		for letter in line:
			var label := Label3D.new()
			label.text = letter
			label.font = NeonStyle.scene_font(700)
			label.font_size = 96
			label.pixel_size = LETTER_SIZE / 96.0
			if _lit:
				label.modulate = neon
				label.outline_modulate = neon.darkened(0.4)
			else:
				var tube := unlit_tube(neon)
				label.modulate = tube
				label.outline_modulate = tube.darkened(0.3)
			label.outline_size = 8
			# Lit neon glows by itself; unlit neon is in daylight, like glass.
			label.shaded = not _lit
			label.position = WorldSpace.to_scene(Vector2(x, y))
			label.position.z = Z + PANEL_DEPTH * 0.5 + 0.01
			add_child(label)
			_letters.append(label)
			y += LETTER_STEP
		y += LETTER_STEP * LINE_GAP
	add_to_group(Graphics.GROUP)
	if not _lit:
		# An unlit sign has nothing to flicker and nothing to light with.
		return
	# One letter flickers, chosen by building name: always the same one for this building.
	_flicker = (
		_letters[posmod(hash(identity.name), _letters.size())] if not _letters.is_empty() else null
	)

	var glow := OmniLight3D.new()
	_glow = glow
	glow.name = "NeonGlow"
	glow.light_color = neon
	glow.light_energy = GLOW_ENERGY
	glow.omni_range = GLOW_RANGE
	glow.shadow_enabled = false
	glow.position = WorldSpace.to_scene(Vector2(x, top + height * 0.5))
	glow.position.z = Z + 1.2
	add_child(glow)
	apply_graphics()


## Where the board hangs in height: top and bottom in the rules plane. In front of it, on
## the right end wall of the tower, no flags or louvers ([BuildingFlanks]) are placed: they
## would cover the letters.
func span() -> Vector2:
	return Vector2(_top, _top + _height)


## Neon halo in the rain (ADR-0037, decision 3, addendum): the rain near the sign glows
## in its color. Only in the rain: on a clear night the air is transparent.
func glow_in_rain() -> void:
	if _glow == null or _halo != null:
		return
	_halo = RainLook.halo(
		Vector3(_glow.position.x, _glow.position.y, Z - HALO_BEHIND),
		_glow.light_color,
		HALO_STRENGTH,
		Vector2(PANEL_WIDTH, _height) + HALO_MARGIN
	)
	add_child(_halo)


## The neon halo in the rain, for a test; outside the rain it does not exist.
func halo() -> MeshInstance3D:
	return _halo


## Neon glow in volumetric fog, by quality level (ADR-0034, decision 1):
## on "Ultra" the air around the sign glows.
func apply_graphics() -> void:
	if _glow != null:
		_glow.light_volumetric_fog_energy = Graphics.light_in_fog()


## Flickers a letter. A picture, not a rule: by the wall clock.
func _process(delta: float) -> void:
	if _flicker == null:
		return
	_clock = fmod(_clock + delta, FLICKER_EVERY)
	var shown := _clock > FLICKER_FOR
	# A dying tube crackles where it hangs (ADR-0052, decision 7).
	if _flicker.visible and not shown:
		Sounds.play_at(self, Sounds.NEON_FLICKER, _flicker.global_position, BUZZ_REACH)
	_flicker.visible = shown


## Whether the neon is lit: in the evening and at night yes, in the morning and by day no.
func is_lit() -> bool:
	return _lit


## An unlit neon tube by day: the neon color, but dark and in the light. One for the
## building sign and the shop signs by the exit ([ExitStreet]).
static func unlit_tube(neon: Color) -> Color:
	return neon.lerp(Color(0.5, 0.5, 0.5), UNLIT_GREY).darkened(UNLIT_DARKEN)


## The sign text from top to bottom, letters without spaces: for tests.
func text() -> String:
	var joined := ""
	for label in _letters:
		joined += label.text
	return joined
