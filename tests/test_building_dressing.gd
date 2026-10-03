extends GutTest

## Dressing layout with pack models ([BuildingDressing], ADR-0033, decision 3)
## — on any building, hotel and office: wide furniture does not touch doors, shafts and
## walls, nothing extra hangs on the wall, and floors are not empty.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func _identities() -> Array[BuildingIdentity]:
	var all: Array[BuildingIdentity] = []
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		all.append(BuildingIdentity.typed(kind))
	return all


## What furniture on a floor has no right to touch: door openings, shafts with trims and the call
## button panel, solid walls, the escalator run from the floor above, and the exit. The panel side
## is decided by [BuildingShafts] — it cannot be recomputed here without repeating it.
func _blockers(rules: BuildingRules, plan: BuildingPlan, index: int) -> Array[Vector2]:
	var zones: Array[Vector2] = []
	var door_half := Door.LEAF_SIZE.x * 0.5
	for door in plan.doors:
		if door.floor_index == index:
			zones.append(Vector2(door.x - door_half, door.x + door_half))
	var shaft_half := rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in plan.shafts:
		if shaft.top <= index and index <= shaft.bottom:
			zones.append(Vector2(shaft.x - shaft_half, shaft.x + shaft_half))
			var panel := BuildingShafts.call_panel_span(rules, plan, shaft.x, index)
			if panel.y > panel.x:
				zones.append(panel)
	for wall in plan.walls:
		if wall.floor_index == index:
			zones.append(wall.band(rules))
	for escalator in plan.escalators:
		if escalator.floor_index + 1 == index:
			zones.append(escalator.gap(rules))
	return zones


func test_furniture_keeps_off_doors_shafts_walls_and_escalators() -> void:
	var checked := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for identity in _identities():
				var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
				for prop in dressing.props:
					checked += 1
					var span := Vector2(prop.x - prop.width * 0.5, prop.x + prop.width * 0.5)
					for zone in _blockers(rules, plan, prop.floor_index):
						assert_true(
							span.y <= zone.x + 0.001 or span.x >= zone.y - 0.001,
							(
								"сид %d, этаж %d: %s (%.2f..%.2f) задевает %s"
								% [building_seed, prop.floor_index, prop.name, span.x, span.y, zone]
							)
						)
	assert_gt(checked, 0, "мебели нет — проверять нечего")


## Furniture does not stand on top of each other: a wide item takes the neighbouring slots.
func test_furniture_does_not_overlap() -> void:
	for building_seed: int in SEEDS:
		var rules := _rules(5)
		var plan := BuildingPlan.generate(rules, building_seed)
		var dressing := BuildingDressing.lay(rules, plan, building_seed, _identities()[0])
		for a in dressing.props:
			for b in dressing.props:
				if a == b or a.floor_index != b.floor_index:
					continue
				assert_gte(
					absf(a.x - b.x) + 0.001,
					(a.width + b.width) * 0.5,
					(
						"сид %d, этаж %d: %s налезает на %s"
						% [building_seed, a.floor_index, a.name, b.name]
					)
				)


## Nothing hangs on the wall at a shaft (the button panel is there) or above tall furniture — in
## the hotel and the office: a chest of drawers with a lamp exists only in the hotel.
func test_wall_decor_keeps_off_shafts_and_tall_furniture() -> void:
	var hung := 0
	for identity in _identities():
		for building_seed: int in SEEDS:
			var rules := _rules(5)
			var step := rules.slot_x(1) - rules.slot_x(0)
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			for item in dressing.decor:
				hung += 1
				assert_lte(
					item.width, BuildingDressing.WALL_WIDTH + 0.001, "%s шире простенка" % item.name
				)
				for shaft in plan.shafts:
					if shaft.top <= item.floor_index and item.floor_index <= shaft.bottom:
						assert_gte(absf(shaft.x - item.x), step * 1.5, "%s у шахты" % item.name)
				for prop in dressing.props:
					if prop.floor_index != item.floor_index:
						continue
					# Height includes the lamp on top: it overlapped the bottom of a picture.
					if PropCatalog.footprint(prop.name).y > BuildingDressing.TALL:
						assert_gte(
							absf(prop.x - item.x) + 0.001,
							(prop.width + BuildingDressing.WALL_WIDTH) * 0.5,
							"%s над %s" % [item.name, prop.name]
						)
	assert_gt(hung, 0, "стены пустые")


## Items come from their own building: the hotel has no water coolers or filing cabinets, the office
## — no grandfather clocks or chests of drawers, the residential building — neither, but it has a
## pram and mailboxes. The hotel has no pipes in plain sight.
func test_each_building_gets_its_own_things() -> void:
	var rules := _rules(5)
	for identity in _identities():
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			for item in dressing.props + dressing.decor:
				var fit := PropCatalog.entry(item.name).fit
				assert_true(
					fit == identity.fit() or fit == PropCatalog.Fit.ANY,
					"%s не из этого здания" % item.name
				)
			if identity.is_hotel():
				assert_eq(dressing.pipes.size(), 0, "в отеле трубы на виду")


## "Rich but readable": on the walls on average more than one item per floor, furniture —
## more than one item per three corridor floors (special floors since M24o are furnished as a hall,
## ADR-0057). A narrow tower floor with four doors, two
## lamps and a shaft holds only three or four free slots, and no more furniture
## will fit on it.
##
## Forty buildings, not eight: since M24b five shafts meet one floor up, above
## the basement (ADR-0038, decision 3), furniture on average became 0.69 instead of 0.71 per
## floor, and on eight seeds the draw spread pushed the hotel under the threshold.
func test_floors_are_not_bare() -> void:
	var rules := _rules(5)
	for identity in _identities():
		var floors := 0
		var furniture := 0
		var decor := 0
		rules.kind = identity.kind
		for building_seed: int in range(1, 41):
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			# Special floors are furnished as a hall, not a corridor (ADR-0057).
			for index: int in rules.floors - 1:
				floors += 0 if FloorRole.hall_at(rules, index) else 1
			furniture += dressing.props.size()
			decor += dressing.decor.size()
			# Since M24n part of the wall is niches, mirrors, windows, panels (ADR-0056): the wall
			# is not empty even without a picture.
			decor += WallFeatures.lay(rules, plan, building_seed, identity, dressing).size()
		# The podium's wide floors since M24o are halls (ADR-0057): corridors remained
		# in the narrow tower, and an item per three floors is no longer little.
		assert_gt(float(furniture) / floors, 0.3, "мебели меньше предмета на три этажа")
		if identity.kind == BuildingIdentity.Kind.OFFICE:
			# The office wall is glass (ADR-0056): nothing hangs on it.
			assert_eq(decor, 0, "на стекле офиса что-то висит")
			continue
		assert_gt(float(decor) / floors, 1.0, "на стенах меньше предмета на этаж")


## Furniture does not stand in the garage — the exit floor is empty, with one car.
func test_the_garage_stays_empty() -> void:
	var rules := _rules(5)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var dressing := BuildingDressing.lay(rules, plan, building_seed, _identities()[0])
		for item in dressing.props + dressing.decor:
			assert_lt(item.floor_index, rules.floors - 1, "в гараже %s" % item.name)
