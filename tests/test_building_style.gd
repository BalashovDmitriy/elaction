extends GutTest

## Отель и офис — разные коридоры (ADR-0048): по кадрам M24i они читались
## одинаковыми, и различие держится теперь стилем здания [BuildingStyle].
##
## Здание собирается целиком, и проверяется то, что видно: светильники, двери,
## бра, дорожка. Тип здания — жребий номера и сида: здание нужного типа тест
## ищет сам, а не берёт номер наугад.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SETTLE_FRAMES: int = 5


func after_each() -> void:
	GameState.instance().start_game()


## Номер здания нужного типа на сиде [param building_seed].
func _building_of(kind: BuildingIdentity.Kind, building_seed: int) -> int:
	for building: int in range(1, 60):
		if BuildingIdentity.of(building, building_seed).kind == kind:
			return building
	return -1


func _level(kind: BuildingIdentity.Kind, building_seed: int = 1) -> GreyboxLevel:
	GameState.instance().start_game()
	GameState.instance().building = _building_of(kind, building_seed)
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	var rules := BuildingRules.new()
	rules.floors = 8
	rules.documents_cap = 0
	level.rules = rules
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


func test_hotel_and_office_styles_differ_in_every_look() -> void:
	var hotel := BuildingStyle.of(BuildingIdentity.new())
	var identity := BuildingIdentity.new()
	identity.kind = BuildingIdentity.Kind.OFFICE
	var office := BuildingStyle.of(identity)
	assert_ne(hotel.runner, office.runner, "дорожка — только в отеле")
	assert_ne(hotel.fixture, office.fixture, "светильники разные")
	assert_ne(hotel.sconces, office.sconces, "бра — только в отеле")
	assert_ne(hotel.panels, office.panels, "филёнки — у отеля, стекло — у офиса")
	assert_ne(hotel.vision_glass, office.vision_glass)
	assert_ne(hotel.departments, office.departments, "отделы на табличках — у офиса")
	assert_false(hotel.crown.is_equal_approx(office.crown), "карниз разный")


func test_an_office_hangs_panels_and_glazed_doors() -> void:
	var level := await _level(BuildingIdentity.Kind.OFFICE)
	assert_false(level.identity.is_hotel(), "здание — офис")
	for lamp: Lamp in level.find_children("*", "Lamp", true, false):
		assert_eq(lamp.fixture, BuildingStyle.Fixture.PANEL, "в офисе — короб дневного света")
	var glazed := 0
	for door: Door in level.doors():
		if door.find_child("VisionGlass", true, false) != null:
			glazed += 1
	assert_gt(glazed, 0, "у офисных дверей стекло")
	assert_eq(level.find_children("Sconce", "", true, false).size(), 0, "бра в офисе нет")


func test_a_hotel_lights_its_pilasters_but_not_on_dark_floors() -> void:
	var level := await _level(BuildingIdentity.Kind.HOTEL)
	assert_true(level.identity.is_hotel(), "здание — отель")
	var sconces := level.find_children("Sconce", "", true, false)
	assert_gt(sconces.size(), 0, "бра на пилястрах отеля")
	for sconce: Node in sconces:
		var at := WorldSpace.to_plane((sconce as Node3D).global_position)
		var index := level.rules.floor_index_near(at.y + WallSconce.HEIGHT)
		assert_false(level.rules.is_unlit(index), "на тёмном этаже бра не горит")
	for door: Door in level.doors():
		assert_null(door.find_child("VisionGlass", true, false), "у отеля двери без стекла")
