extends GutTest

## Round palette: the set of colours the building is painted with.
##
## The main thing here is not beauty but readability: a darkened floor must differ from
## a lit one by hue, not brightness, because in the dark agents keep shooting (ADR-0010,
## point 3; ADR-0017, decision 2). A colour roaming freely will sooner or later produce a
## round where a darkened floor does not read — and it is the player who will find that.

## How much brighter a lit floor is than a darkened one. Less — and the difference reads
## as "slightly darker", not as "the light was turned off".
const LIGHT_GAP: float = 0.25

## Below this a darkened floor counts as black.
##
## The gap from the lit one does not guard this by itself: with a bright enough lit one,
## a black tone passes too. And a darkened floor must not be black — in the dark agents
## keep shooting, only their range drops (ADR-0007, point 4), and a floor where the enemy
## cannot be seen would be death for nothing.
const DARK_FLOOR: float = 0.25

## How far apart the tones are around the hue wheel, as a share of the full circle.
const HUE_GAP: float = 0.04

## How much the shaft and masonry tone differs from the floor's tone.
##
## The measure is not by hue but by distance in RGB: a blue shaft on a turquoise wall
## differs first of all in brightness, and by hue alone such a pair would count as
## indistinguishable, even though in the frame it is visible a mile away. Identical
## colours give zero, neighbouring hues of the same brightness about 0.05, the closest
## pair of the set 0.26.
const APART: float = 0.25


## Distance between hues around the wheel: 0.5 — opposite.
func _hue_gap(first: Color, second: Color) -> float:
	var raw := absf(first.h - second.h)
	return minf(raw, 1.0 - raw)


## How distinguishable two colours are to the eye: a weighted distance in RGB.
##
## Weights follow the eye's sensitivity: green weighs more than red, red more than blue.
## Divided by three so that black and white give one.
func _apart(first: Color, second: Color) -> float:
	var dr := first.r - second.r
	var dg := first.g - second.g
	var db := first.b - second.b
	return sqrt(2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db) / 3.0


## The set is finite and cycles: rounds in the original go around in a circle.
func test_the_set_repeats_itself() -> void:
	var size := BuildingPalette.count()
	assert_gt(size, 1, "раунды должны отличаться хоть чем-то")
	assert_eq(BuildingPalette.of_round(size + 1), BuildingPalette.of_round(1), "набор по кругу")
	assert_eq(BuildingPalette.of_round(size + 2), BuildingPalette.of_round(2))


## A zero or negative round must not crash the game: the number comes from the game
## state, and once it already arrived as zero.
func test_a_round_below_one_still_gets_a_palette() -> void:
	assert_eq(BuildingPalette.of_round(0), BuildingPalette.of_round(1))
	assert_eq(BuildingPalette.of_round(-3), BuildingPalette.of_round(1))


## The palette is as much a building rule as the agents' anger.
func test_rules_take_the_palette_of_their_round() -> void:
	for number: int in [1, 2, 3, 4, 5, 9]:
		var rules := BuildingRules.for_building(number)
		assert_eq(rules.palette, BuildingPalette.of_round(number), "раунд %d" % number)


## Consecutive buildings differ to the eye — that is the milestone's DoD.
##
## The last pair is not "fourth and fifth" but "fourth and first": the set goes around
## in a circle, and at its seam the rounds are neighbours too. Without this pair the set
## could close on itself with the same colour, and the player would be the one to notice.
## Since M24n there are three sets (ADR-0056, decision 2) — and in each the rounds differ.
func test_neighbouring_rounds_differ() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for number: int in range(1, BuildingPalette.count() + 1):
			var here := BuildingPalette.of_round(number, kind)
			var next := BuildingPalette.of_round(number + 1, kind)
			assert_gt(
				_hue_gap(here.story, next.story),
				HUE_GAP,
				"тип %d: раунды %d и %d красят этаж одинаково" % [kind, number, number + 1]
			)


## Each kind has its own set (ADR-0056, decision 2), and in each set darkness reads
## against that kind's lamp light the same way as in the port set: a gap in brightness
## and hue, and the darkened does not go black. A lit floor is lamp light: that is what
## sets it apart from a darkened one (ADR-0010). The shaft and masonry are not in the
## wall's tone.
func test_every_kind_keeps_the_dark_floor_readable_in_every_round() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var light: Color = BuildingAir.LAMP_LIGHT[kind]
		for number: int in range(1, BuildingPalette.count() + 1):
			var palette := BuildingPalette.of_round(number, kind)
			var where := "тип %d, раунд %d" % [kind, number]
			var dark := palette.dark.get_luminance()
			assert_gt(light.get_luminance() - dark, LIGHT_GAP, where + ": темнота не темнее")
			assert_gt(dark, DARK_FLOOR, where + ": темнота ушла в чёрное")
			assert_gt(_hue_gap(light, palette.dark), HUE_GAP, where + ": только яркостью")
			assert_gt(_apart(palette.shaft, palette.story), APART, where + ": шахта как стена")
			assert_gt(_apart(palette.masonry, palette.story), APART, where + ": кладка как стена")


## Darkness is equally dark (decision 3): the darkened zone's tone has the same
## brightness in all sets.
func test_the_dark_is_equally_dark_in_every_kind() -> void:
	var lightest := 0.0
	var darkest := 1.0
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		for number: int in range(1, BuildingPalette.count() + 1):
			var dark := BuildingPalette.of_round(number, kind).dark.get_luminance()
			lightest = maxf(lightest, dark)
			darkest = minf(darkest, dark)
	assert_lt(lightest - darkest, 0.06, "темнота у типов разной яркости")


## The level converts the round palette into its kind's set; the round number is the same.
func test_a_round_palette_moves_to_the_family_of_its_kind() -> void:
	for number: int in range(1, BuildingPalette.count() + 1):
		var hotel := BuildingPalette.of_round(number)
		for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
			var moved := BuildingPalette.of_kind(hotel, kind)
			assert_eq(
				moved, BuildingPalette.of_round(number, kind), "раунд %d, тип %d" % [number, kind]
			)
			assert_eq(
				BuildingPalette.of_kind(moved, BuildingIdentity.Kind.HOTEL), hotel, "и обратно"
			)
	var custom := BuildingPalette.new()
	assert_eq(
		BuildingPalette.of_kind(custom, BuildingIdentity.Kind.OFFICE), custom, "своя — как есть"
	)


## Kinds differ to the eye: in one round the hotel, office and residential walls are
## different colours.
func test_kinds_paint_the_same_round_apart() -> void:
	for number: int in range(1, BuildingPalette.count() + 1):
		var kinds := BuildingIdentity.Kind.values()
		for first: int in kinds.size():
			for second: int in range(first + 1, kinds.size()):
				var one := BuildingPalette.of_round(number, kinds[first])
				var two := BuildingPalette.of_round(number, kinds[second])
				assert_gt(
					_apart(one.story, two.story),
					APART * 0.5,
					"раунд %d: типы одного цвета" % number
				)
