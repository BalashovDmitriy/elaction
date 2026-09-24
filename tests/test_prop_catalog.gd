extends GutTest

## Каталог моделей обстановки ([PropCatalog], ADR-0033, решения 3 и 4): у каждой
## модели есть автор, у предмета нет тел, и он влезает туда, где стоит.

const CREDITS_JSON := "res://assets/models/props/credits.json"
const CREDITS_MD := "res://CREDITS.md"


func _credits() -> Dictionary:
	var text := FileAccess.get_file_as_string(CREDITS_JSON)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


## Лицензия CC-BY требует автора, и модели без строки в CREDITS быть не может.
func test_every_model_has_an_author_and_a_licence() -> void:
	var credits := _credits()
	var page := FileAccess.get_file_as_string(CREDITS_MD)
	for entry in PropCatalog.entries():
		assert_true(credits.has(entry.name), "%s: нет в credits.json" % entry.name)
		if not credits.has(entry.name):
			continue
		var line: Dictionary = credits[entry.name]
		var licence := String(line.get("licence", ""))
		assert_true(
			licence.begins_with("CC0") or licence.begins_with("CC-BY"),
			"%s: лицензия %s не из разрешённых" % [entry.name, licence]
		)
		assert_false(String(line.get("author", "")).is_empty(), "%s: без автора" % entry.name)
		assert_string_contains(page, "`%s`" % entry.name, false)


## Модель в папке без записи в каталоге — мёртвый груз в репозитории.
func test_every_model_file_is_in_the_catalog() -> void:
	for file in DirAccess.get_files_at(PropCatalog.DIR):
		if file.ends_with(".glb"):
			var name := file.get_basename()
			assert_not_null(PropCatalog.entry(name), "%s лежит в папке, но не в каталоге" % name)


func test_props_have_no_bodies() -> void:
	for entry in PropCatalog.entries():
		var prop := PropCatalog.make(entry.name)
		assert_not_null(prop, "%s не собирается" % entry.name)
		if prop == null:
			continue
		var bodies := prop.find_children("*", "CollisionObject3D", true, false)
		assert_eq(bodies.size(), 0, "%s: у декора есть тело" % entry.name)
		prop.free()


## Рост — как в каталоге; мебель влезает между стеной и телом актёра; предмет
## на стене — между пилястрами.
func test_props_take_their_size_from_the_catalog() -> void:
	for entry in PropCatalog.entries():
		var size := PropCatalog.footprint(entry.name)
		match entry.place:
			PropCatalog.Place.FLOOR:
				assert_lte(size.z, PropCatalog.MAX_DEPTH + 0.001, "%s глубже места" % entry.name)
				if entry.top.is_empty():
					assert_almost_eq(size.y, entry.height, 0.01, "%s: рост" % entry.name)
			PropCatalog.Place.WALL:
				assert_lte(
					size.x, PropCatalog.WALL_MAX_WIDTH + 0.001, "%s шире простенка" % entry.name
				)
				assert_lte(size.y, entry.height + 0.01, "%s: не выше каталога" % entry.name)
			_:
				assert_almost_eq(size.y, entry.height, 0.01, "%s: рост" % entry.name)


## Мебель стоит на полу и прижата к стене задней гранью: нуль модели — низ по
## высоте, зад по глубине, середина по ширине.
func test_a_prop_stands_on_its_origin() -> void:
	for entry in PropCatalog.pick(PropCatalog.Place.FLOOR, PropCatalog.Fit.ANY):
		var prop := PropCatalog.make(entry.name)
		var box := PropCatalog.bounds_of(prop)
		assert_almost_eq(box.position.y, 0.0, 0.01, "%s: низ на полу" % entry.name)
		assert_almost_eq(box.position.z, 0.0, 0.01, "%s: зад у стены" % entry.name)
		assert_almost_eq(box.get_center().x, 0.0, 0.05, "%s: середина по ширине" % entry.name)
		prop.free()


## У отеля и офиса свои предметы и общие — и каждого хватает на этаж.
func test_hotels_and_offices_have_their_own_furniture() -> void:
	for fit: PropCatalog.Fit in [PropCatalog.Fit.HOTEL, PropCatalog.Fit.OFFICE]:
		var floor_items := PropCatalog.pick(PropCatalog.Place.FLOOR, fit)
		var wall_items := PropCatalog.pick(PropCatalog.Place.WALL, fit)
		assert_gt(floor_items.size(), 8, "мебели мало")
		assert_gt(wall_items.size(), 4, "на стены мало")
		var other := (
			PropCatalog.Fit.OFFICE if fit == PropCatalog.Fit.HOTEL else PropCatalog.Fit.HOTEL
		)
		for item in floor_items + wall_items:
			assert_ne(item.fit, other, "%s не из этого здания" % item.name)


func test_the_lamp_on_top_is_never_drawn_on_its_own() -> void:
	for fit: PropCatalog.Fit in [PropCatalog.Fit.HOTEL, PropCatalog.Fit.OFFICE]:
		for item in PropCatalog.pick(PropCatalog.Place.FLOOR, fit):
			assert_ne(item.name, "table_lamp", "лампа стоит только на мебели")


func test_the_first_building_is_the_empire_hotel() -> void:
	var identity := BuildingIdentity.of(1, 12345)
	assert_true(identity.is_hotel())
	assert_eq(identity.name, "EMPIRE")
	assert_eq(identity.sign_lines(), PackedStringArray(["EMPIRE", "HOTEL"]))


func test_buildings_draw_hotels_and_offices_and_keep_their_draw() -> void:
	var kinds := {}
	for building in range(2, 40):
		var one := BuildingIdentity.of(building, building * 17)
		var again := BuildingIdentity.of(building, building * 17)
		assert_eq(one.kind, again.kind, "жребий повторяется для того же здания")
		assert_eq(one.name, again.name)
		var names := (
			BuildingIdentity.HOTEL_NAMES if one.is_hotel() else BuildingIdentity.OFFICE_NAMES
		)
		assert_has(names, one.name, "имя из своего списка")
		kinds[one.kind] = true
		if not one.is_hotel():
			assert_eq(one.sign_lines(), PackedStringArray([one.name]), "у офиса — одно имя")
	assert_eq(kinds.size(), 2, "выпадают и отели, и офисы")
