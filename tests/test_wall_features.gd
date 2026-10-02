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


## Элемент не прячется за мебелью: за высокой — никакой, как картина, а перед
## дверью на лестницу, что стоит до пола, — никакая.
func test_features_keep_off_openings_pictures_and_furniture() -> void:
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
					var half: float = WallFeatures.HALF[feature.kind]
					for prop: BuildingDressing.PropSpot in dressing.props:
						if prop.floor_index != feature.floor_index:
							continue
						if absf(prop.x - feature.x) >= prop.width * 0.5 + half:
							continue
						assert_ne(feature.kind, "stairs", where + " за " + prop.name)
						assert_lte(
							PropCatalog.footprint(prop.name).y,
							BuildingDressing.TALL,
							where + " за высоким " + prop.name
						)


## Дверь на лестницу стоит до пола — перед панелью низа стены с поручнем, а не
## за ней; низ люка мусоропровода, ниши и рамы зеркала — над поручнем.
func test_features_clear_the_wainscot() -> void:
	var rules := _rules(5)
	var own := {
		BuildingIdentity.Kind.HOTEL: WallFeatures.HOTEL,
		BuildingIdentity.Kind.RESIDENTIAL: WallFeatures.RESIDENTIAL,
	}
	var ground := WorldSpace.height_to_scene(rules.floor_surface(2))
	var front := WorldSpace.BACK_WALL_Z + BuildingRibs.RAIL_DEPTH
	var low_parts := 0
	for kind: BuildingIdentity.Kind in own:
		var style := BuildingStyle.of(BuildingIdentity.typed(kind))
		var rail_top := style.wainscot_height + BuildingRibs.RAIL_HEIGHT
		for what: String in own[kind]:
			var feature := WallFeatures.Feature.new()
			feature.kind = what
			feature.floor_index = 2
			feature.x = 10.0
			var features := WallFeatures.new()
			add_child_autofree(features)
			features.build(rules, [feature] as Array[WallFeatures.Feature])
			# Коробки — до мультимеша: без экрана движок их места не хранит.
			for part: String in features._parts:
				for box: Transform3D in features._parts[part]:
					var size := box.basis.get_scale()
					var low := box.origin.y - size.y * 0.5 - ground
					var face := box.origin.z + size.z * 0.5
					# Что ниже верха поручня, то — перед ним: стояки труб уходят за
					# панель, как в жизни за плинтус, — их это не касается.
					if low < rail_top - 0.001 and what != "risers":
						low_parts += 1
						assert_gte(face, front, "тип %d: %s за панелью низа" % [kind, what])
	assert_gt(low_parts, 0, "дверь на лестницу до пола проверена")


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
