extends GutTest

## Здание по карте оригинала (ADR-0028): двери, красные двери и тёмные этажи
## по таблицам ROM — на любом сиде и любом навыке, а не на одном здании.
##
## Здание генерируется, поэтому проверяется не «этот уровень верен», а «любое
## здание, которое сгенерируется, верно» (`docs/testing.md`).

const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34]

## Навыки: первое здание, середина и тот, где квоты красных уже не растут.
const SKILLS: Array[int] = [0, 3, 8]


func _rules(skill: int) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = skill
	return rules


func _doors_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for door in plan.doors:
		if door.floor_index == floor_index:
			count += 1
	return count


## Дверей на этаже не больше числа карты на ширину и хоть одна там, где карта
## их даёт; на седьмом ROM и на крыше — ни одной.
func test_doors_follow_the_map_on_any_building() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for index: int in rules.levels():
				var placed := _doors_on(plan, index)
				var wanted := rules.doors_on(index)
				var where := "навык %d, сид %d, этаж %d" % [skill, building_seed, index]
				assert_lte(placed, wanted, where + ": дверей больше, чем по карте")
				if wanted > 0:
					assert_gte(placed, 1, where + ": ни одной двери")
				else:
					assert_eq(placed, 0, where + ": двери там, где карта их не ставит")


## Этаж по кадру не пустее оригинала: двери стоят по карте, пока есть место.
##
## На этаже без эскалаторов дверей ровно столько, сколько даёт карта, или
## столько, сколько мест осталось после шахт, ламп и выхода. Эскалатор
## занимает места и на своём этаже, и на нижнем, и его этажи проверяются только
## сверху: в полосе эскалаторов башни они съедают четыре места из семи, и
## дверь там одна (ADR-0028, решение 2).
func test_floors_hold_their_map_doors_while_there_is_room() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			for index: int in rules.floors:
				if _touched_by_an_escalator(plan, index):
					continue
				var span := rules.slot_range(index)
				var room := span.y - span.x + 1 - _shafts_on(plan, index) - _lamps_on(plan, index)
				if index == rules.floors - 1:
					room -= 1
				assert_eq(
					_doors_on(plan, index),
					mini(rules.doors_on(index), maxi(room, 0)),
					"навык %d, сид %d, этаж %d" % [skill, building_seed, index]
				)


## Широкий низ не пустее экрана оригинала: дверей хоть столько, сколько у
## оригинала на один экран.
func test_wide_floors_are_not_emptier_than_a_screen_of_the_original() -> void:
	var rules := _rules(0)
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for index: int in rules.floors:
			if not rules.is_wide(index):
				continue
			var rom := Arcade.rom_floor(index, rules.floors)
			assert_gte(
				_doors_on(plan, index),
				Arcade.doors_on_floor(rom),
				"сид %d: широкий этаж %d пустее экрана оригинала" % [building_seed, index]
			)


func _touched_by_an_escalator(plan: BuildingPlan, floor_index: int) -> bool:
	for escalator in plan.escalators:
		if escalator.floor_index == floor_index or escalator.floor_index + 1 == floor_index:
			return true
	return false


func _shafts_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for shaft in plan.shafts:
		if shaft.top <= floor_index and shaft.bottom >= floor_index:
			count += 1
	return count


func _lamps_on(plan: BuildingPlan, floor_index: int) -> int:
	var count := 0
	for lamp in plan.lamps:
		if lamp.floor_index == floor_index:
			count += 1
	return count


## Красных дверей столько, сколько по таблице ROM на навыке, по одной на этаж,
## и в каждой полосе — её квота.
func test_documents_follow_the_rom_bands() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			var floors := plan.document_floors()
			var where := "навык %d, сид %d" % [skill, building_seed]
			assert_eq(floors.size(), Arcade.red_doors(skill), where + ": документов")
			var per_band: Dictionary = {}
			var seen: Dictionary = {}
			for index: int in floors:
				assert_false(seen.has(index), where + ": две красные на этаже %d" % index)
				seen[index] = true
				var rom := Arcade.rom_floor(index, rules.floors)
				for band: int in Arcade.RED_DOOR_BANDS.size():
					var span := Arcade.RED_DOOR_BANDS[band]
					if rom >= span.x and rom <= span.y:
						per_band[band] = int(per_band.get(band, 0)) + 1
			for band: int in Arcade.RED_DOOR_BANDS.size():
				assert_eq(
					int(per_band.get(band, 0)),
					Arcade.red_doors_in_band(band, skill),
					where + ": полоса %d" % band
				)


## Десять документов на восьмом навыке достижимы так же, как пять на нулевом.
func test_every_building_can_be_finished_on_any_skill() -> void:
	for skill: int in SKILLS:
		var rules := _rules(skill)
		for building_seed: int in SEEDS:
			var plan := BuildingPlan.generate(rules, building_seed)
			assert_true(
				BuildingRoute.is_winnable(plan, rules),
				"навык %d, сид %d: здание не пройти" % [skill, building_seed]
			)


## Тёмные этажи карты — ROM 11–15 — без ламп, прочие этажи — хоть с одной.
func test_dark_floors_carry_no_lamps() -> void:
	var rules := _rules(0)
	var dark := 0
	for index: int in rules.floors:
		if rules.is_unlit(index):
			dark += 1
	assert_eq(dark, 5, "тёмных этажей пять, как в оригинале")
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		var lamps: Dictionary = {}
		for lamp in plan.lamps:
			lamps[lamp.floor_index] = true
		for index: int in rules.floors:
			assert_eq(
				lamps.has(index),
				not rules.is_unlit(index),
				"сид %d, этаж %d: лампа не по карте" % [building_seed, index]
			)


## Соль ноль — сид равен номеру здания, как до M18e; разная соль — разные
## здания (ADR-0028, решение 6).
func test_salt_changes_the_building_and_zero_keeps_it() -> void:
	var game: GameState = autofree(GameState.new())
	game.building = 3
	game.salt = 0
	assert_eq(game.building_seed(), 3, "без соли сид — номер здания")
	game.salt = 12345
	var salted := game.building_seed()
	assert_ne(salted, 3, "соль меняет сид")
	game.salt = 54321
	assert_ne(game.building_seed(), salted, "другая соль — другой сид")

	var rules := _rules(0)
	var plain := BuildingPlan.generate(rules, 3)
	var other := BuildingPlan.generate(rules, salted)
	assert_ne(plain.document_floors(), other.document_floors(), "другое здание")
