extends GutTest

## Residential building wear (ADR-0055, decision 4): marks on the walls and flickering
## lamps. The building is a draw, so any one is checked: marks exist only in
## a residential building, do not land on doors, shafts and solid walls and do not go past
## the outer walls; a share of lamps flickers, and only visually — the darkness rule
## knows nothing about the flicker.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5, 12]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func test_only_a_residential_building_is_worn() -> void:
	var rules := _rules(5)
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var identity := BuildingIdentity.typed(kind)
		var total := 0
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			total += WallWear.lay(rules, plan, building_seed, identity, dressing).size()
		if kind == BuildingIdentity.Kind.RESIDENTIAL:
			assert_gt(total, SEEDS.size() * 10, "a residential building has marked walls")
		else:
			assert_eq(total, 0, "kind %d: no marks" % kind)


func test_marks_keep_off_doors_shafts_and_walls() -> void:
	var identity := BuildingIdentity.typed(BuildingIdentity.Kind.RESIDENTIAL)
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			for mark: WallWear.Mark in WallWear.lay(rules, plan, building_seed, identity, dressing):
				var where := (
					"skill %d, seed %d, floor %d" % [skill, building_seed, mark.floor_index]
				)
				var zones := BuildingDressing.blocked_zones(rules, plan, mark.floor_index)
				assert_false(WallWear.clashes(zones, mark), where + ": mark on an occupied spot")
				var span := rules.floor_span(mark.floor_index)
				assert_gte(mark.x - mark.width * 0.5, span.x, where + ": past the left wall")
				assert_lte(mark.x + mark.width * 0.5, span.y, where + ": past the right wall")
				assert_lt(mark.floor_index, rules.floors - 1, where + ": garage without marks")
				assert_lt(
					mark.rise + mark.width * 0.5,
					rules.floor_height - rules.slab_height,
					where + ": under the ceiling"
				)
				# The picture lies on the plaster, behind the wall panel: a tag below its
				# top would be cut off by the panel (M24m code review).
				if WallWear.TAGS.has(mark.image):
					assert_gte(
						mark.rise - mark.width * WallWear.TAG_INK,
						BuildingRibs.SKIRTING_HEIGHT + BuildingRibs.RAIL_HEIGHT,
						where + ": tag above the panel"
					)


## A mark does not land under a wall feature ([WallFeatures]): they share slots, and
## a tag would stick out from under a fire escape window, brick from under a door.
func test_marks_keep_off_wall_features() -> void:
	var identity := BuildingIdentity.typed(BuildingIdentity.Kind.RESIDENTIAL)
	var marks := 0
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			var features := WallFeatures.lay(rules, plan, building_seed, identity, dressing)
			for mark: WallWear.Mark in WallWear.lay(
				rules, plan, building_seed, identity, dressing, features
			):
				marks += 1
				for feature: WallFeatures.Feature in features:
					if feature.floor_index != mark.floor_index:
						continue
					var half: float = WallFeatures.HALF[feature.kind]
					assert_gte(
						absf(feature.x - mark.x),
						half + mark.width * 0.5,
						(
							"skill %d, seed %d, floor %d: mark on %s"
							% [skill, building_seed, mark.floor_index, feature.kind]
						)
					)
	assert_gt(marks, SEEDS.size() * SKILLS.size() * 5, "almost no marks left")


## A share of the residential building's lamps flickers, in the hotel and office none; the draw by
## slot repeats.
func test_a_share_of_residential_lamps_flicker() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var style := BuildingStyle.of(BuildingIdentity.typed(kind))
		var flickering := 0
		var count := 0
		for index: int in 30:
			for slot: int in 10:
				var lamp := Lamp.new()
				lamp.floor_index = index
				lamp.position.x = slot * 1.8
				lamp.dress_as(style)
				var again := Lamp.new()
				again.floor_index = index
				again.position.x = slot * 1.8
				again.dress_as(style)
				assert_eq(lamp.flicker, again.flicker, "the roll repeats")
				flickering += 1 if lamp.flicker else 0
				count += 1
				lamp.free()
				again.free()
		if kind == BuildingIdentity.Kind.RESIDENTIAL:
			var share := float(flickering) / count
			assert_almost_eq(share, style.flicker_share, 0.06, "a share of lamps flickers")
		else:
			assert_eq(flickering, 0, "kind %d: none flicker" % kind)
