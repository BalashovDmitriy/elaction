extends GutTest

## Подвал на плане: одна шахта вниз, без эскалаторов, машина у ворот слева
## (ADR-0038, решение 3).
##
## Шахта в подвал — жребий здания, и путь к машине зависит от того, какая
## выпала. Поэтому проверяется не одно здание, а любое, которое сгенерируется
## (`docs/testing.md`): на сотне сидов, на разных навыках и на маленьких
## зданиях из тестов сборки и бота.


## Здание на проверку: правила, сид и собранный план.
class Case:
	extends RefCounted
	var rules: BuildingRules
	var building_seed: int = 0
	var plan: BuildingPlan

	func label() -> String:
		return "этажей %d, навык %d, сид %d" % [rules.floors, rules.skill, building_seed]


## Сидов больше, чем в соседних проверках плана: шахта в подвал выбирается из
## пяти, а запертый спуск, который лечит перекладка шахт, выпадал на сидах 65
## и 79 — в первых десятках его не видно.
const SEEDS: int = 100

## Навыки: первое здание, середина и тот, где квоты красных уже не растут.
const SKILLS: Array[int] = [0, 3, 8]

## Планы собираются один раз на файл: пятьсот зданий на каждый тест заново
## стоили бы полминуты прогона, а план между тестами не меняется.
var _cases: Array[Case] = []


func before_all() -> void:
	for rules: BuildingRules in _buildings():
		for building_seed: int in SEEDS:
			var case := Case.new()
			case.rules = rules
			case.building_seed = building_seed
			case.plan = BuildingPlan.generate(rules, building_seed)
			_cases.append(case)


## Здания, на которых проверяется подвал: настоящие на трёх навыках и
## маленькие — такие собирают тесты машины, сборки и бота.
func _buildings() -> Array[BuildingRules]:
	var all: Array[BuildingRules] = []
	for skill: int in SKILLS:
		var rules := BuildingRules.new()
		rules.skill = skill
		all.append(rules)
	for floors: int in [4, 8]:
		var small := BuildingRules.new()
		small.floors = floors
		small.documents_cap = 1
		small.shaft_span = 2
		all.append(small)
	return all


## В подвал спускается ровно одна шахта, и та, что доходит до этажа над ним;
## остальные кончаются выше, как в ROM ($802D).
func test_exactly_one_shaft_goes_down_to_the_basement() -> void:
	for case in _cases:
		var basement := case.rules.floors - 1
		var down: Array[BuildingPlan.ShaftSpot] = []
		for shaft in case.plan.shafts:
			if shaft.bottom >= basement:
				down.append(shaft)
		assert_eq(down.size(), 1, "%s: в подвал шахт %d" % [case.label(), down.size()])
		if down.size() != 1:
			continue
		var shaft := down[0]
		assert_eq(
			BuildingBasement.shaft_of(case.plan), shaft, "%s: план знает свою шахту" % case.label()
		)
		assert_lte(shaft.top, basement - 1, "%s: шахта идёт с этажа над подвалом" % case.label())
		assert_true(
			shaft.rides_between(basement - 1, basement),
			"%s: кабина возит в подвал — пара ярусов его не отрезает" % case.label()
		)


## Эскалаторы в подвал не спускаются: туда ведёт только шахта.
func test_no_escalator_lands_in_the_basement() -> void:
	for case in _cases:
		for escalator in case.plan.escalators:
			assert_lt(
				escalator.floor_index + 1,
				case.rules.floors - 1,
				"%s: эскалатор с этажа %d" % [case.label(), escalator.floor_index]
			)


## Выход — крайнее левое место подвала, на машине у ворот; шахта в подвал
## машину не задевает, и машина встаёт именно у ворот.
func test_the_exit_is_at_the_left_gate_clear_of_the_shaft() -> void:
	for case in _cases:
		var rules := case.rules
		var plan := case.plan
		var basement := rules.floors - 1
		var car := ExitCar.parked_span(rules)
		var bounds := rules.floor_span(basement)
		var label := case.label()
		assert_almost_eq(
			car.x, bounds.x + BuildingShell.WALL_WIDTH + ExitCar.GAP, 0.001, "машина у торца"
		)
		assert_almost_eq(
			plan.exit_x,
			rules.slot_x(rules.slot_range(basement).x),
			0.001,
			"%s: выход на крайнем левом месте" % label
		)
		assert_between(plan.exit_x, car.x, car.y, "%s: выход приходится на машину" % label)
		var shaft := BuildingBasement.shaft_of(plan)
		if shaft == null:
			fail_test("%s: нет шахты в подвал" % label)
			continue
		assert_true(
			ExitCar.clears_shaft(rules, shaft.x),
			"%s: шахта x=%.1f задевает машину" % [label, shaft.x]
		)
		assert_almost_eq(
			ExitCar.spot(plan.exit_x, rules, plan),
			(car.x + car.y) * 0.5,
			0.001,
			"%s: машина встала у ворот" % label
		)


## Здание проходится до машины: с крыши — шахтой в подвал, а из неё пешком —
## до выхода, без стены и проёма между ними.
func test_the_car_is_reachable_through_the_basement_shaft() -> void:
	for case in _cases:
		var rules := case.rules
		var plan := case.plan
		var basement := rules.floors - 1
		var label := case.label()
		var shaft := BuildingBasement.shaft_of(plan)
		if shaft == null:
			fail_test("%s: нет шахты в подвал" % label)
			continue
		var floors := BuildingRoute.segments(plan, rules)
		var seen := BuildingRoute.reachable_in(plan, rules, floors)
		# В подвале под шахтой проёма нет — там дно, и кусок у кабины один.
		var landing := BuildingRoute.node_in(floors, basement, shaft.x)
		assert_true(seen.has(landing), "%s: шахтой в подвал не спуститься" % label)
		var exit := BuildingRoute.node_in(floors, basement, plan.exit_x)
		assert_eq(landing, exit, "%s: от шахты до машины не дойти пешком" % label)
		assert_eq(
			BuildingRoute.unreachable_spots(plan, rules),
			[] as Array[String],
			"%s: здание не проходится" % label
		)
		# Тот же путь — графом, по которому ходит бот: он обязан найти шаг
		# к машине прямо с крыши.
		var graph := BuildingRoute.walkable(plan, rules)
		var roof_x := plan.safe_x(rules, BuildingRules.ROOF)
		var step := BuildingRoute.step_toward(
			graph, BuildingRules.ROOF, roof_x, basement, plan.exit_x
		)
		assert_false(step.is_empty(), "%s: бот не видит пути к машине" % label)
