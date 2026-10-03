class_name BuildingPalette
extends Resource

## Round palette: what the building is painted with and what light it glows with.
##
## In the original the layout barely changes, while colours change with every round
## ("colors change with new levels"). So colour is not a level constant but a
## building rule: [method BuildingRules.for_building] takes the palette by the round
## number, and the set loops, just as the rounds themselves loop
## ([ADR-0017](../../docs/adr/0017-spectrum-palette-and-shafts.md), decision 2).
##
## The round tone falls on the building materials: since M21b — as a multiplier on the wall
## texture ([BuildingFinish]), so the wallpaper and plaster pattern stays, while
## the round gives the colour.
##
## The first round is the port's frame: turquoise floors, red masonry, a blue shaft.

## Palette sets by building kind ([enum BuildingIdentity.Kind]), built on
## first request. Empty means not built yet.
static var _families: Array = []

## Tone of the floor interior: back wall, window reveals.
@export var story := Color(0.0, 0.78, 0.78)

## Tone of the side masonry and the roof superstructure.
@export var masonry := Color(0.85, 0.16, 0.16)

## Tone of the shaft rails and doors.
@export var shaft := Color(0.22, 0.32, 0.95)

## The building's overall tone — and also the tone of a darkened floor (ADR-0010, point 3).
##
## It differs from the lamp light of its building kind ([constant BuildingAir.LAMP_LIGHT])
## not only in brightness but in hue: in the dark agents keep shooting, and
## "just darker" would mean dying for nothing.
## The gap between the pair is checked by a test on every palette of every set.
@export var dark := Color(0.34, 0.42, 0.72)


## How many palettes are in a set. The set is finite and loops; all kinds have
## the same number of palettes.
static func count() -> int:
	return _all(BuildingIdentity.Kind.HOTEL).size()


## Round palette of a building of kind [param kind]. Numbered from one, then
## around the loop.
static func of_round(
	number: int, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> BuildingPalette:
	var all := _all(kind)
	return all[posmod(maxi(number, 1) - 1, all.size())]


## The same round palette — from the set of kind [param kind] (ADR-0056, decision 2):
## the rules know the round number, and the level learns the building kind. A foreign palette —
## not from the sets — stays as is: it was set by hand.
static func of_kind(palette: BuildingPalette, kind: BuildingIdentity.Kind) -> BuildingPalette:
	for family: int in BuildingIdentity.Kind.size():
		var index := _all(family as BuildingIdentity.Kind).find(palette)
		if index >= 0:
			return _all(kind)[index]
	return palette


## The set of kind [param kind]. Built once: a palette is a resource, and handing
## the same copy to all buildings is cheaper than building it anew for each.
##
## The hotel keeps the Spectrum port set — the game's first frame as in the original —
## the other kinds have their own ranges (ADR-0056, decision 2): the office is cold, the residential
## building faded and earthy. The darkened zone tone has the same brightness for all —
## darkness is equally dark (decision 3).
static func _all(kind: BuildingIdentity.Kind) -> Array:
	if _families.is_empty():
		_families = [_hotel(), _office(), _residential()]
	return _families[kind]


## Hotel: the Spectrum port set. Colours are taken from the attribute palette, but not
## literally: in the port they are at full strength and without light, while ours will get
## the floor fill and a highlight on top.
static func _hotel() -> Array[BuildingPalette]:
	return [
		# The port's frame: turquoise floors, red masonry, a blue shaft.
		_make(
			Color(0.0, 0.78, 0.78),
			Color(0.85, 0.16, 0.16),
			Color(0.22, 0.32, 0.95),
			Color(0.34, 0.42, 0.72)
		),
		# Green round: the masonry goes purple, the shaft stays cold.
		_make(
			Color(0.22, 0.80, 0.30),
			Color(0.78, 0.20, 0.72),
			Color(0.20, 0.36, 0.92),
			Color(0.30, 0.40, 0.70)
		),
		# Purple round: the shaft is turquoise, otherwise it would merge with the wall.
		_make(
			Color(0.80, 0.26, 0.80),
			Color(0.26, 0.34, 0.86),
			Color(0.16, 0.78, 0.78),
			Color(0.32, 0.38, 0.74)
		),
		# Yellow round: the warmest floor in the set, and the darkened one stands out
		# from it the most.
		_make(
			Color(0.82, 0.76, 0.18),
			Color(0.80, 0.22, 0.20),
			Color(0.22, 0.34, 0.90),
			Color(0.28, 0.40, 0.76)
		),
	]


## Office: a cold range — steel, ice, sea green, graphite with lilac.
static func _office() -> Array[BuildingPalette]:
	return [
		_make(
			Color(0.42, 0.62, 0.84),
			Color(0.30, 0.33, 0.40),
			Color(0.86, 0.56, 0.16),
			Color(0.30, 0.38, 0.72)
		),
		_make(
			Color(0.28, 0.70, 0.66),
			Color(0.24, 0.26, 0.34),
			Color(0.26, 0.30, 0.86),
			Color(0.30, 0.40, 0.70)
		),
		_make(
			Color(0.72, 0.78, 0.88),
			Color(0.20, 0.34, 0.62),
			Color(0.82, 0.30, 0.26),
			Color(0.32, 0.38, 0.74)
		),
		_make(
			Color(0.54, 0.50, 0.80),
			Color(0.22, 0.22, 0.30),
			Color(0.10, 0.80, 0.50),
			Color(0.30, 0.38, 0.72)
		),
	]


## Residential building: faded stairwell paint — mint, mustard, institutional
## turquoise, terracotta.
static func _residential() -> Array[BuildingPalette]:
	return [
		_make(
			Color(0.44, 0.68, 0.48),
			Color(0.64, 0.28, 0.18),
			Color(0.30, 0.36, 0.70),
			Color(0.30, 0.38, 0.68)
		),
		_make(
			Color(0.76, 0.62, 0.28),
			Color(0.40, 0.30, 0.24),
			Color(0.22, 0.46, 0.72),
			Color(0.30, 0.38, 0.72)
		),
		_make(
			Color(0.26, 0.60, 0.62),
			Color(0.72, 0.36, 0.22),
			Color(0.66, 0.62, 0.20),
			Color(0.30, 0.38, 0.70)
		),
		_make(
			Color(0.70, 0.46, 0.36),
			Color(0.18, 0.30, 0.20),
			Color(0.24, 0.40, 0.82),
			Color(0.30, 0.38, 0.72)
		),
	]


static func _make(
	story_tone: Color, masonry_tone: Color, shaft_tone: Color, dark_tone: Color
) -> BuildingPalette:
	var palette := BuildingPalette.new()
	palette.story = story_tone
	palette.masonry = masonry_tone
	palette.shaft = shaft_tone
	palette.dark = dark_tone
	return palette
