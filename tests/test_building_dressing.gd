extends GutTest

## Раскладка обстановки моделями паков ([BuildingDressing], ADR-0033, решение 3)
## — на любом здании, отеле и офисе: широкая мебель не задевает двери, шахты и
## стены, на стене не висит лишнего, и этажи не пустые.

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]
const SKILLS: Array[int] = [0, 5]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func _identities() -> Array[BuildingIdentity]:
	var hotel := BuildingIdentity.new()
	var office := BuildingIdentity.new()
	office.kind = BuildingIdentity.Kind.OFFICE
	office.name = BuildingIdentity.OFFICE_NAMES[0]
	return [hotel, office]


## Что на этаже мебель задевать не вправе: проёмы дверей, шахты с наличниками,
## глухие стены, пролёт эскалатора с этажа выше и выход.
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


## Мебель не встаёт друг на друга: широкая занимает соседние места.
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


## На стене не висит у шахты (там панель кнопок) и над высокой мебелью.
func test_wall_decor_keeps_off_shafts_and_tall_furniture() -> void:
	var hung := 0
	for building_seed: int in SEEDS:
		var rules := _rules(5)
		var step := rules.slot_x(1) - rules.slot_x(0)
		var plan := BuildingPlan.generate(rules, building_seed)
		var dressing := BuildingDressing.lay(rules, plan, building_seed, _identities()[1])
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
				if PropCatalog.entry(prop.name).height > BuildingDressing.TALL:
					assert_gte(
						absf(prop.x - item.x) + 0.001,
						(prop.width + BuildingDressing.WALL_WIDTH) * 0.5,
						"%s над %s" % [item.name, prop.name]
					)
	assert_gt(hung, 0, "стены пустые")


## Предметы — из своего здания: в отеле нет кулеров и картотек, в офисе —
## напольных часов и комодов. Труб на виду в отеле нет.
func test_each_building_gets_its_own_things() -> void:
	var rules := _rules(5)
	for identity in _identities():
		var other := PropCatalog.Fit.OFFICE if identity.is_hotel() else PropCatalog.Fit.HOTEL
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			for item in dressing.props + dressing.decor:
				assert_ne(
					PropCatalog.entry(item.name).fit, other, "%s не из этого здания" % item.name
				)
			if identity.is_hotel():
				assert_eq(dressing.pipes.size(), 0, "в отеле трубы на виду")


## «Богато, но читаемо»: на стенах в среднем больше предмета на этаж, мебели —
## не меньше двух на три этажа. Узкий этаж башни с четырьмя дверями, двумя
## лампами и шахтой держит всего три-четыре свободных места, и больше мебели
## на него не встанет.
func test_floors_are_not_bare() -> void:
	var rules := _rules(5)
	for identity in _identities():
		var floors := 0
		var furniture := 0
		var decor := 0
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var dressing := BuildingDressing.lay(rules, plan, building_seed, identity)
			floors += rules.floors - 1
			furniture += dressing.props.size()
			decor += dressing.decor.size()
		assert_gt(float(furniture) / floors, 0.66, "мебели меньше двух предметов на три этажа")
		assert_gt(float(decor) / floors, 1.0, "на стенах меньше предмета на этаж")


## Мебель не встаёт на гараж — этаж выхода пустой, с одной машиной.
func test_the_garage_stays_empty() -> void:
	var rules := _rules(5)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var dressing := BuildingDressing.lay(rules, plan, building_seed, _identities()[0])
		for item in dressing.props + dressing.decor:
			assert_lt(item.floor_index, rules.floors - 1, "в гараже %s" % item.name)
