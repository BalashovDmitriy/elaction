extends GutTest

## Задняя стена по устройству (ADR-0056, решение 4): у отеля и жилого дома свои
## элементы, у офиса — стекло, и на нём ничего. Здание — жребий, поэтому
## проверяется любое: элемент не ложится на дверь, шахту, глухую стену и пролёт
## эскалатора и не налезает на картину.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5, 12]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func test_each_kind_lines_its_own_wall() -> void:
	var rules := _rules(5)
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var identity := BuildingIdentity.typed(kind)
		var kinds := {}
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			for feature: WallFeatures.Feature in WallFeatures.lay(
				rules, plan, building_seed, identity, dressing
			):
				kinds[feature.kind] = true
		match kind:
			BuildingIdentity.Kind.HOTEL:
				assert_eq(kinds.keys().size(), WallFeatures.HOTEL.size(), "у отеля ниши и зеркала")
				for name: String in kinds:
					assert_has(WallFeatures.HOTEL, name, "у отеля только своё")
			BuildingIdentity.Kind.RESIDENTIAL:
				assert_eq(
					kinds.keys().size(), WallFeatures.RESIDENTIAL.size(), "у жилого дома всё своё"
				)
				for name: String in kinds:
					assert_has(WallFeatures.RESIDENTIAL, name, "у жилого дома только своё")
			_:
				assert_eq(kinds.size(), 0, "у офиса на стекле ничего")


func test_features_keep_off_openings_and_pictures() -> void:
	for kind: BuildingIdentity.Kind in [
		BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.RESIDENTIAL
	]:
		var identity := BuildingIdentity.typed(kind)
		for skill: int in SKILLS:
			var rules := _rules(skill)
			for building_seed: int in SEEDS:
				var plan := BuildingPlan.generate(rules, building_seed)
				var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
				for feature: WallFeatures.Feature in WallFeatures.lay(
					rules, plan, building_seed, identity, dressing
				):
					var where := (
						"тип %d, навык %d, сид %d, этаж %d: %s"
						% [kind, skill, building_seed, feature.floor_index, feature.kind]
					)
					var zones := BuildingDressing.blocked_zones(rules, plan, feature.floor_index)
					assert_false(WallFeatures.clashes(zones, feature), where + " на занятом")
					assert_lt(feature.floor_index, rules.floors - 1, where + " в гараже")
					for hung: BuildingDressing.PropSpot in dressing.decor:
						if hung.floor_index == feature.floor_index:
							assert_gte(
								absf(hung.x - feature.x),
								WallFeatures.DECOR_CLEAR,
								where + " на картине"
							)


## На тёмном этаже ниша не светится: свет погашен по правилам ROM.
func test_a_niche_on_a_dark_floor_stays_dark() -> void:
	var rules := _rules(5)
	var lit := WallFeatures.Feature.new()
	lit.kind = "niche"
	lit.floor_index = _floor(rules, false)
	var dark := WallFeatures.Feature.new()
	dark.kind = "niche"
	dark.floor_index = _floor(rules, true)
	assert_gte(dark.floor_index, 0, "тёмный этаж по карте есть")
	var features := WallFeatures.new()
	add_child_autofree(features)
	features.build(rules, [lit, dark] as Array[WallFeatures.Feature])
	var glow := features.find_child("Glow", false, false) as MultiMeshInstance3D
	var off := features.find_child("Glow Off", false, false) as MultiMeshInstance3D
	assert_not_null(glow, "на светлом — подсветка")
	assert_not_null(off, "на тёмном — погашенная")


## Первый этаж, тёмный по карте или светлый.
func _floor(rules: BuildingRules, unlit: bool) -> int:
	for index: int in rules.floors - 1:
		if rules.is_unlit(index) == unlit:
			return index
	return -1
