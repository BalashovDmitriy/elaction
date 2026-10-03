class_name FloorSigns
extends Node3D

## Floor numbers: an indicator with red digits at the right wall of each floor.
##
## In the original it hangs on every floor, right under the ceiling, against the right
## wall. It is not dressing but a game summary: how much further to descend and where
## a document lies (ADR-0026, decision 9). So the digits glow by themselves — the same
## technique as the door indicators (ADR-0023, decision 6) — and read on a darkened
## floor.
##
## Since M21b only the digit glows, not the whole sign (user's remark:
## a red glowing shield "stands out a lot" among the wallpaper and furniture). The indicator is like
## a real one: a steel frame, dark glass, red digits with a halo. The red
## comes from the original's sign.
##
## Numbering as in the original: the top floor has the highest number, the bottom one is first.
## There is no sign on the roof: there is neither a wall nor a ceiling, and the original has none
## there.
##
## The bottom floor is an underground garage (ADR-0038, decision 3), and everywhere the player
## sees the floor, it is "P", not "1": on the sign, on the shaft indicators, on the garage columns
## and in the HUD. The other floors' numbers do not shift — [method number_of] is unchanged.

## How the bottom floor — the garage — is labelled where others have a number.
const PARKING_MARK := "P"

## Font size: the larger it is, the sharper the digit. The digit height in the world is set by
## [constant Proportions.FLOOR_DIGIT], not by it.
const FONT_SIZE: int = 64

## The fraction of the font size a digit takes in height in Exo 2: by it the size
## is converted to metres. Measured by glyphs: from 0.69 ("1", "4", "7") to 0.72
## ("0", "3"); Pixellari, which the sign used before M22b, had 0.69.
const DIGIT_SHARE: float = 0.71

## How far the sign stands in front of the back wall: in front of the pilasters, so as
## not to sink into them at the edge of a wall section.
const STANDOFF: float = 0.25

## Indicator frame: how much wider than the glass on each side, and its colour — dark steel.
const BEZEL: float = 0.04
const BEZEL_COLOR := Color(0.34, 0.35, 0.38)
## Glass: almost black with a red sheen — something for the digit to glow on.
const GLASS := Color(0.06, 0.02, 0.02)
## The digit is a red LED with a halo of the same tone.
const DIGIT := Color(1.0, 0.28, 0.2)

var _rules: BuildingRules = null


## Hangs signs on all floors of the building.
func hang(rules: BuildingRules) -> void:
	_rules = rules
	for index in rules.floors:
		_hang_on(index)


## Floor number as the player sees it: the top is [member BuildingRules.floors],
## the bottom is first.
static func number_of(rules: BuildingRules, index: int) -> int:
	return rules.floors - index


## Whether floor [param index] is the garage: the building's bottom floor.
static func is_parking(rules: BuildingRules, index: int) -> bool:
	return index == rules.floors - 1


## Label of floor [param index] as the player sees it: the number, and for the garage —
## [constant PARKING_MARK].
static func label_of(rules: BuildingRules, index: int) -> String:
	return PARKING_MARK if is_parking(rules, index) else str(number_of(rules, index))


## Where the middle of a floor's sign hangs, in rule coordinates.
##
## Not against the ceiling, as in the original, but lower by the band covered by
## the slab edge. The camera looks [constant SideCamera.TILT_DEGREES]
## from above, and the front edge of the slab hides a band under the ceiling at the back
## wall — in the milestone's first shot the sign went half under it, and only the bottom
## of the digits remained.
static func centre_on(rules: BuildingRules, index: int) -> Vector2:
	var inner_right := rules.floor_span(index).y - BuildingShell.WALL_WIDTH
	var plate := Proportions.FLOOR_SIGN
	return Vector2(
		inner_right - Proportions.FLOOR_SIGN_GAP - plate.x * 0.5,
		rules.story_top(index) + hidden_band() + Proportions.FLOOR_SIGN_GAP + plate.y * 0.5
	)


## The band under the ceiling that the slab edge hides from the camera at
## depth [param z] (by default — the sign's), m.
##
## Needed by everything hanging under the ceiling at the back wall: the dressing pipes in
## the first M19 shots went entirely under the edge (M19 code review).
static func hidden_band(z: float = WorldSpace.BACK_WALL_Z + STANDOFF) -> float:
	var depth := WorldSpace.CORRIDOR_DEPTH * 0.5 - z
	return depth * tan(deg_to_rad(SideCamera.TILT_DEGREES))


func _hang_on(index: int) -> void:
	var plate := Proportions.FLOOR_SIGN
	var sign_node := Node3D.new()
	sign_node.name = "Floor%s" % label_of(_rules, index)
	sign_node.position = WorldSpace.to_scene(centre_on(_rules, index))
	sign_node.position.z = WorldSpace.BACK_WALL_Z + STANDOFF
	add_child(sign_node)

	# First the glass, second the digit: the test looks for it as the second child.
	var glass := GreyboxLook.box(Vector3(plate.x, plate.y, 0.03), GreyboxLook.polished(GLASS))
	sign_node.add_child(glass)

	var label := Label3D.new()
	label.text = label_of(_rules, index)
	label.font = NeonStyle.scene_font(700)
	label.font_size = FONT_SIZE
	label.pixel_size = Proportions.FLOOR_DIGIT / (float(FONT_SIZE) * DIGIT_SHARE)
	label.modulate = DIGIT
	label.outline_modulate = Color(DIGIT, 0.35)
	label.outline_size = 10
	# The digit is light, not paint: the scene lighting does not touch it.
	label.shaded = false
	label.position.z = 0.02
	sign_node.add_child(label)

	var bezel := GreyboxLook.box(
		Vector3(plate.x + BEZEL * 2.0, plate.y + BEZEL * 2.0, 0.02), GreyboxLook.metal(BEZEL_COLOR)
	)
	bezel.position.z = -0.015
	sign_node.add_child(bezel)
