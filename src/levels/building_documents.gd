class_name BuildingDocuments
extends RefCounted

## The building's red doors: how many and on which floors.
##
## As its own class, not in [BuildingPlan]: the rule came from the ROM as a whole table of bands and
## quotas (ADR-0028, decision 3), and it got cramped in the layout. The plan calls [method lay] and
## gets the floors where documents were placed; the doors themselves are placed by [method
## BuildingPlan.place_door] — with the same draw as the blue ones.

## The smallest and largest number of documents in a building — as many as the ROM table gives at
## zero and at the top skill.
const FEWEST: int = 5
const MOST: int = 10


## How many red doors in the building: by hand ([member BuildingRules.documents_cap]) or drawn from
## 5 to 10 by the building seed (ADR-0037, decision 8). Its own draw, from the seed with a salt: the
## shared layout generator would shift everything drawn after the documents — and the tests'
## buildings by seed.
static func count(rules: BuildingRules, building_seed: int) -> int:
	if rules.documents_cap >= 0:
		return rules.documents_cap
	return _draw(building_seed).randi_range(FEWEST, MOST)


## The ROM table column by which the building's documents are placed: the skill that has exactly as
## many red doors as came up. Ten are given by four skills in a row — then there is a draw between
## them, and the band pattern can differ.
static func column(rules: BuildingRules, building_seed: int) -> int:
	var wanted := count(rules, building_seed)
	var fitting: Array[int] = []
	for skill_level: int in Arcade.RED_DOOR_SKILL_TOP + 1:
		if Arcade.red_doors(skill_level) == wanted:
			fitting.append(skill_level)
	if fitting.is_empty():
		return clampi(rules.skill, 0, Arcade.RED_DOOR_SKILL_TOP)
	var rng := _draw(building_seed)
	rng.randi()
	return fitting[rng.randi_range(0, fitting.size() - 1)]


static func _draw(building_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, "documents"])
	return rng


## Lays out the red doors: the building is split into bands, and each has as many as the rule says.
## No more than one per floor.
##
## Per the ROM the bands and quotas are the original's, by the table column with the drawn number
## ([method column], [method _rom_bands]): with five documents the top is empty, with ten both the
## bottom and the top are filled (ADR-0028, decision 3; ADR-0037, decision 8). A hand-set number
## ([member BuildingRules.documents_cap]) is split evenly by height, as before M18e.
##
## Inside a band the floors are tried until the door fits: there may be no room left on the
## reachable part of a floor. A document that found no room in its band is put on any floor of the
## building without a document rather than lost: you cannot collect four out of five.
static func lay(
	plan: BuildingPlan,
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	building_seed: int
) -> Dictionary:
	var chosen: Dictionary = {}
	var wanted := mini(count(rules, building_seed), rules.floors)
	if wanted <= 0:
		# Before the checks: the route is a pass over the whole layout, and in a building without
		# documents nobody needs it. Besides, on a zero-floor building it crashes.
		return chosen

	# Floor pieces are computed once: by themselves they are a pass over the whole layout, and the
	# route needs exactly the same ones.
	var spans := BuildingRoute.segments(plan, rules)
	var routed := BuildingRoute.reachable_in(plan, rules, spans)

	var bands := (
		_rom_bands(rules, column(rules, building_seed))
		if rules.documents_cap < 0
		else _even_bands(rules.floors, wanted)
	)
	var left := 0
	for band: Vector3i in bands:
		var placed := _lay_in(
			plan, rules, rng, taken, band.x, band.y, band.z, chosen, routed, spans
		)
		left += band.z - placed
	# No more than one per floor can be placed: in a building lower than the ROM number the remainder
	# is cut by floors, like the hand-set number, rather than failing with an error.
	left = mini(left, wanted - chosen.size())
	if left > 0:
		left -= _lay_in(plan, rules, rng, taken, 0, rules.floors - 1, left, chosen, routed, spans)
	if left > 0:
		push_error("no place in the building for %d document(s)" % left)
	return chosen


## Places up to [param wanted] red doors on floors [param from]..[param to], one per floor, in
## random order. Returns how many were placed.
static func _lay_in(
	plan: BuildingPlan,
	rules: BuildingRules,
	rng: RandomNumberGenerator,
	taken: Dictionary,
	from: int,
	to: int,
	wanted: int,
	chosen: Dictionary,
	routed: Dictionary,
	spans: Dictionary
) -> int:
	var placed := 0
	if wanted <= 0 or to < from:
		return placed
	for index: int in _shuffled_range(rng, from, to):
		if placed >= wanted:
			break
		if chosen.has(index) or rules.doors_on(index) <= 0:
			continue
		if not plan.place_door(rules, rng, taken, index, true, routed, spans):
			continue
		chosen[index] = true
		placed += 1
	return placed


## The original's red door bands in our floors: "first, last, how many".
##
## A ROM band is translated into the floors whose ROM number falls into it ([method
## Arcade.rom_floor]). In a building lower than thirty floors a band may get none — its documents go
## to the common remainder.
static func _rom_bands(rules: BuildingRules, skill_level: int) -> Array[Vector3i]:
	var bands: Array[Vector3i] = []
	for band in Arcade.RED_DOOR_BANDS.size():
		var quota := Arcade.red_doors_in_band(band, skill_level)
		if quota <= 0:
			continue
		var rom := Arcade.RED_DOOR_BANDS[band]
		var from := rules.floors
		var to := -1
		for index in rules.floors:
			var number := Arcade.rom_floor(index, rules.floors)
			if number >= rom.x and number <= rom.y:
				from = mini(from, index)
				to = maxi(to, index)
		bands.append(Vector3i(from, to, quota))
	return bands


## The building evenly split into [param wanted] bands, one document in each.
static func _even_bands(floors: int, wanted: int) -> Array[Vector3i]:
	var bands: Array[Vector3i] = []
	var band := float(floors) / float(wanted)
	for number in wanted:
		var from := int(floor(band * float(number)))
		var to := maxi(int(floor(band * float(number + 1))) - 1, from)
		bands.append(Vector3i(from, to, 1))
	return bands


## The band's floors in random order. Our own shuffle, not [method Array.shuffle]: that one takes
## the global generator, and the building would stop repeating by seed.
static func _shuffled_range(rng: RandomNumberGenerator, from: int, to: int) -> Array[int]:
	var order: Array[int] = []
	for index in range(from, to + 1):
		order.append(index)
	for index in range(order.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var kept := order[index]
		order[index] = order[other]
		order[other] = kept
	return order
