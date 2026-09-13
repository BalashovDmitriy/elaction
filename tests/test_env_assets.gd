extends GutTest

## Тесты ассетов окружения.
##
## Проверяется не «вот этот спрайт на месте», а правило: каждый ассет, который
## просит уровень, нарисован целиком — цвет, нормаль и блик, — карты одного
## размера, и здание действительно кладёт их на геометрию (ADR-0011, пункты 2 и 7).
##
## Так тест переживает добавление новых ассетов: список берётся из
## [constant EnvTextures.NAMES], и забытая нормаль падает сама, без правки теста.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров дать зданию собраться.
const SETTLE_FRAMES: int = 5


func before_each() -> void:
	# Кэш общий на весь прогон, а тесты грузят текстуры в своём порядке.
	EnvTextures.forget()


func test_every_asset_has_all_three_maps() -> void:
	for asset: String in EnvTextures.NAMES:
		for path: String in EnvTextures.paths_of(asset):
			assert_true(ResourceLoader.exists(path), "нарисована карта %s" % path)


func test_maps_of_one_asset_are_the_same_size() -> void:
	for asset: String in EnvTextures.NAMES:
		var expected := Vector2.ZERO
		for path: String in EnvTextures.paths_of(asset):
			var texture := load(path) as Texture2D
			assert_not_null(texture, "карта %s читается" % path)
			if texture == null:
				continue
			if expected == Vector2.ZERO:
				expected = texture.get_size()
			# Разъехавшиеся карты свет читает как рельеф не в том месте, и в кадре
			# это выглядит грязью, а не ошибкой, — то есть само не найдётся.
			assert_eq(texture.get_size(), expected, "%s того же размера" % path)


func test_every_tile_carries_normal_and_specular() -> void:
	for asset: String in EnvTextures.NAMES:
		var tile := EnvTextures.tile(asset)
		assert_not_null(tile, "ассет %s собирается" % asset)
		if tile == null:
			continue
		assert_not_null(tile.normal_texture, "у %s есть нормаль" % asset)
		assert_not_null(tile.specular_texture, "у %s есть блик" % asset)


func test_the_slab_tile_is_as_thick_as_the_slab_it_covers() -> void:
	# Толщина перекрытия — правило здания, а не число в ассете. Разойдутся —
	# плита либо обрежется, либо повторится по вертикали половинкой.
	var rules := BuildingRules.new()
	var tile := EnvTextures.tile("slab")
	assert_not_null(tile)
	if tile == null:
		return
	assert_eq(float(tile.diffuse_texture.get_height()), rules.slab_height)


func test_the_building_lays_the_tile_on_its_slabs() -> void:
	var rules := BuildingRules.new()
	rules.floors = 6
	rules.documents = 1

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame

	var textured := 0
	for body: Node in level.get_children():
		for child: Node in body.get_children():
			var panel := child as TextureRect
			if panel != null and panel.texture is CanvasTexture:
				textured += 1

	assert_gt(textured, 0, "перекрытия собраны из ассета, а не из заливки")
