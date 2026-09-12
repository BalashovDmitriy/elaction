extends GutTest

## Тесты города за окнами.
##
## Город выкладывается из сида, как и само здание, поэтому проверяется тем же
## приёмом: то же число — тот же город, и ни одна башня не вылезает за отведённую
## полосу (ADR-0010, пункт 10).

const AREA := Rect2(0.0, 40.0, 1280.0, 500.0)


func _towers(building_seed: int) -> Array[Skyline.Tower]:
	return Skyline.generate(building_seed, AREA)


func _describe(towers: Array[Skyline.Tower]) -> String:
	var parts: Array[String] = []
	for tower: Skyline.Tower in towers:
		parts.append("%s:%d" % [tower.rect, tower.windows.size()])
	return "|".join(parts)


func test_the_same_seed_builds_the_same_city() -> void:
	assert_eq(_describe(_towers(7)), _describe(_towers(7)), "город повторяется по сиду")


func test_another_seed_builds_another_city() -> void:
	assert_ne(_describe(_towers(7)), _describe(_towers(8)))


func test_the_city_is_not_empty() -> void:
	var towers := _towers(1)
	assert_gt(towers.size(), 3, "в городе не одна башня")

	var windows := 0
	for tower: Skyline.Tower in towers:
		windows += tower.windows.size()
	assert_gt(windows, 0, "и в нём горит свет")


func test_towers_stand_inside_the_area() -> void:
	for building_seed: int in range(1, 12):
		for tower: Skyline.Tower in _towers(building_seed):
			assert_almost_eq(
				tower.rect.end.y, AREA.end.y, 0.01, "сид %d: башня стоит на земле" % building_seed
			)
			assert_gte(tower.rect.position.x, AREA.position.x, "сид %d" % building_seed)
			assert_lte(tower.rect.end.x, AREA.end.x, "сид %d: башня вылезла вбок" % building_seed)
			assert_gte(tower.rect.position.y, AREA.position.y, "сид %d: выше неба" % building_seed)


func test_windows_stay_inside_their_tower() -> void:
	for building_seed: int in range(1, 12):
		for tower: Skyline.Tower in _towers(building_seed):
			for window: Rect2 in tower.windows:
				assert_true(
					tower.rect.encloses(window),
					"сид %d: окно %s вне башни %s" % [building_seed, window, tower.rect]
				)


## Город считается своим потоком случайных чисел. Иначе правка вида двигала бы
## раскладку здания, и от смены цвета окон ломалась бы проходимость.
func test_the_city_does_not_move_the_building() -> void:
	var rules := BuildingRules.new()
	var before := BuildingPlan.generate(rules, 5).document_floors()
	_towers(5)
	var after := BuildingPlan.generate(rules, 5).document_floors()
	assert_eq(before, after)
