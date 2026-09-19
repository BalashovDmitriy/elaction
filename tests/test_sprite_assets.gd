extends GutTest

## Тесты ассетов окружения.
##
## Проверяется не «вот этот спрайт на месте», а правило: каждый ассет, который
## просит уровень, нарисован целиком — цвет, нормаль и блик, — карты одного
## размера, и здание действительно кладёт их на геометрию (ADR-0011, пункты 2 и 7).
##
## Так тест переживает добавление новых ассетов: список берётся из
## [constant SpriteTextures.NAMES], и забытая нормаль падает сама, без правки теста.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")
const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")

## Сколько кадров дать зданию собраться.
const SETTLE_FRAMES: int = 5

## Ассеты, которые кладутся в готовый узел сцены: ассет, сцена, имя узла.
##
## Размер места живёт в `.tscn`, размер картинки — в генераторе, и связаны они
## только словом в комментарии. Здесь это слово проверяется.
const FITTED: Array[Array] = [
	["door", DOOR_SCENE, "Panel"],
	["door_red", DOOR_SCENE, "Panel"],
	["door_ajar", DOOR_SCENE, "Panel"],
	["door_open", DOOR_SCENE, "Panel"],
	["door_mat", DOOR_SCENE, "MatVisual"],
	["lamp", LAMP_SCENE, "Visual"],
	["car_slab", CAR_SCENE, "FloorVisual"],
	["car_slab", CAR_SCENE, "RoofVisual"],
]


func before_each() -> void:
	# Кэш общий на весь прогон, а тесты грузят текстуры в своём порядке.
	SpriteTextures.forget()


func test_every_asset_has_all_three_maps() -> void:
	for asset: String in SpriteTextures.NAMES:
		for path: String in SpriteTextures.paths_of(asset):
			assert_true(ResourceLoader.exists(path), "нарисована карта %s" % path)


func test_maps_of_one_asset_are_the_same_size() -> void:
	for asset: String in SpriteTextures.NAMES:
		var expected := Vector2.ZERO
		for path: String in SpriteTextures.paths_of(asset):
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
	for asset: String in SpriteTextures.NAMES:
		var tile := SpriteTextures.tile(asset)
		assert_not_null(tile, "ассет %s собирается" % asset)
		if tile == null:
			continue
		assert_not_null(tile.normal_texture, "у %s есть нормаль" % asset)
		assert_not_null(tile.specular_texture, "у %s есть блик" % asset)


func test_the_slab_tile_is_as_thick_as_the_slab_it_covers() -> void:
	# Толщина перекрытия — правило здания, а не число в ассете. Разойдутся —
	# плита либо обрежется, либо повторится по вертикали половинкой.
	var rules := BuildingRules.new()
	var tile := SpriteTextures.tile("slab")
	assert_not_null(tile)
	if tile == null:
		return
	assert_eq(float(tile.diffuse_texture.get_height()), rules.slab_height)


func test_a_framed_asset_is_three_margins_wide() -> void:
	# Рамка нарезается девятикусочно, и ширина её полей записана дважды: в
	# генераторе и в SpriteTextures. Разойдутся — рама поедет углами внутрь.
	for asset: String in SpriteTextures.FRAMED:
		var tile := SpriteTextures.tile(asset)
		assert_not_null(tile, "ассет %s собирается" % asset)
		if tile == null:
			continue
		var side := SpriteTextures.FRAME_MARGIN * 3.0
		assert_eq(
			tile.diffuse_texture.get_size(), Vector2(side, side), "%s нарезается по полям" % asset
		)


func test_the_side_wall_tile_is_as_wide_as_the_wall() -> void:
	# Боковая стена не тайлится по горизонтали: тайл шире или уже стены — и она
	# собирается из обрезков либо вылезает за свой габарит.
	var tile := SpriteTextures.tile("wall_side")
	assert_not_null(tile)
	if tile == null:
		return
	assert_eq(float(tile.diffuse_texture.get_width()), GreyboxLevel.WALL_WIDTH)


func test_the_exit_asset_covers_the_whole_doorway() -> void:
	# Выход — одна картинка, а не тайл: разойдётся с проёмом — вывеска повторится
	# половинкой или обрежется.
	var tile := SpriteTextures.tile("exit_way")
	assert_not_null(tile)
	if tile == null:
		return
	assert_eq(
		tile.diffuse_texture.get_size(), Vector2(GreyboxLevel.EXIT_WIDTH, GreyboxLevel.EXIT_HEIGHT)
	)


func test_the_shaft_wears_assets_of_its_own_size() -> void:
	# Одежда шахты подогнана под правила здания, а не наоборот, и связаны они
	# только словом в комментарии генератора. Разойдутся — стойка соберётся из
	# обрезков, а створки повторятся половинкой или обрежутся по шахте.
	var rules := BuildingRules.new()
	var rail := SpriteTextures.tile("shaft_rail")
	assert_not_null(rail)
	if rail != null:
		assert_eq(
			float(rail.diffuse_texture.get_width()),
			GreyboxLevel.SHAFT_RAIL_WIDTH,
			"стойка нарисована во всю свою ширину"
		)

	var door := SpriteTextures.tile("shaft_door")
	assert_not_null(door)
	if door != null:
		assert_eq(
			door.diffuse_texture.get_size(),
			Vector2(rules.shaft_width, GreyboxLevel.SHAFT_DOOR_HEIGHT),
			"створки нарисованы по проёму шахты"
		)


func test_the_roof_assets_match_their_places() -> void:
	# Надстройка и трос кладутся целиком, а не плиткой: их размер задан
	# константами уровня, и ассет не того размера молча растянется.
	var room := SpriteTextures.tile("machine_room")
	assert_not_null(room)
	if room != null:
		assert_eq(
			room.diffuse_texture.get_size(),
			GreyboxLevel.MACHINE_ROOM_SIZE,
			"машинное отделение нарисовано под своё место"
		)

	var rope := SpriteTextures.tile("rope")
	assert_not_null(rope)
	if rope != null:
		assert_eq(
			float(rope.diffuse_texture.get_width()),
			GreyboxLevel.ROPE_WIDTH,
			"трос нарисован во всю свою ширину"
		)


func test_an_asset_is_exactly_as_big_as_the_node_it_fills() -> void:
	# У этих узлов растяжение по месту, и ассет не того размера молча растянется,
	# а не упадёт. Размер места берётся из офсетов сцены, а не у живого узла: в
	# дереве узел сам подтягивается под текстуру и о расхождении уже не скажет.
	for row: Array in FITTED:
		var asset := row[0] as String
		var scene := row[1] as PackedScene
		var node_name := row[2] as String

		var blueprint := scene.instantiate()
		var visual := blueprint.get_node(node_name) as TextureRect
		var slot := Vector2(
			visual.offset_right - visual.offset_left, visual.offset_bottom - visual.offset_top
		)
		blueprint.free()

		var tile := SpriteTextures.tile(asset)
		assert_not_null(tile, "ассет %s собирается" % asset)
		if tile == null:
			continue
		assert_eq(tile.diffuse_texture.get_size(), slot, "%s нарисован под %s" % [asset, node_name])


func test_the_building_lays_the_tile_on_every_slab() -> void:
	# Считать любой TextureRect в здании нельзя: их носят и кабина, и дверь, и
	# лампа, и выход, — проверка проходила бы, даже если бы все перекрытия
	# остались заливкой. Смотрим только на тела геометрии, и на все.
	var level := await _building()
	var solids := 0
	var textured := 0
	for body: Node in level.get_children():
		# Ровно [StaticBody2D], а не «is»: кабина и лампа — [AnimatableBody2D],
		# то есть тоже StaticBody2D, а их настил и абажур кладёт не уровень.
		if body.get_class() != "StaticBody2D":
			continue
		solids += 1
		for child: Node in body.get_children():
			var panel := child as TextureRect
			if panel != null and panel.texture is CanvasTexture:
				textured += 1

	assert_gt(solids, 0, "геометрия здания собрана")
	assert_eq(textured, solids, "каждое тело геометрии закрыто ассетом, а не заливкой")


func test_a_strip_thinner_than_its_tile_keeps_its_height() -> void:
	# Полоса стены над окном тоньше своего тайла: 14 px против 32 px. По умолчанию
	# [TextureRect] объявляет минимальным размером размер текстуры, и [Control]
	# поднимал полосу до размера тайла — стена закрывала верхнюю треть проёма, и
	# город в окне пропадал. Правило общее: место задаёт размер, а не картинка.
	var level := await _building()
	var found := false
	# Ширина полосы — не ширина здания: этаж уже него, и стена идёт между
	# его собственными стенами (ADR-0014, пункт 3). Отбор по ширине всё равно
	# нужен: без него тест поймал бы любой узел подходящей высоты и молчал бы
	# о том, что задней стены не осталось вовсе.
	var widths := _back_wall_widths(level.rules)
	for panel: TextureRect in _rects_of(level):
		if not widths.has(roundi(panel.size.x)):
			continue
		if is_equal_approx(panel.size.y, BuildingBackdrop.WINDOW_TOP):
			found = true

	assert_true(found, "полоса стены над окном осталась во всю свою толщину")


func test_every_light_stands_above_the_canvas() -> void:
	# Свет 2D читает нормаль поверхности, и при нулевой высоте луч идёт вдоль
	# стены: плоскость не получает ничего, а здание уходит в темноту целиком.
	# До ассетов это ничем не грозило, поэтому проверка появилась только сейчас.
	var level := await _building()
	var lights := _lights_of(level)
	assert_gt(lights.size(), 0, "в здании есть свет")
	for light: Light2D in lights:
		var spot := light as PointLight2D
		if spot == null:
			continue
		# Проверяется не поле, а то, что дойдёт до шейдера: движок множит высоту
		# на средний масштаб узла, а масштаб у наших источников любой.
		var scaled := spot.height * (absf(spot.scale.x) + absf(spot.scale.y)) * 0.5
		# В здании два вида источников: заливка этажа со столбом шахты и пятно
		# лампы. Высота у них разная, поэтому ожидание выбирается по близости.
		var wanted := (
			LightTextures.SPOT_HEIGHT
			if absf(scaled - LightTextures.SPOT_HEIGHT) < absf(scaled - LightTextures.FILL_HEIGHT)
			else LightTextures.FILL_HEIGHT
		)
		assert_almost_eq(scaled, wanted, 1.0, "источник %s поднят на свою высоту" % spot.name)


func _building() -> GreyboxLevel:
	var rules := BuildingRules.new()
	rules.floors = 6
	rules.documents = 1

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules
	level.building_seed = 1
	# Проверяется, что здание собрано из ассетов, а не что бой выигрывается:
	# агенты и их пули здесь только добавляли бы кадров и случайности.
	level.spawn_agents = false
	add_child_autofree(level)
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	return level


## Ширины задних стен здания: у каждого этажа своя, по силуэту его уровня.
## Стена идёт между внутренними краями боковых стен, отсюда двойной [constant
## GreyboxLevel.WALL_WIDTH].
func _back_wall_widths(rules: BuildingRules) -> Dictionary:
	var widths: Dictionary = {}
	for index: int in rules.floors:
		var span := rules.floor_span(index)
		widths[roundi(span.y - span.x - GreyboxLevel.WALL_WIDTH * 2.0)] = true
	return widths


func _rects_of(node: Node) -> Array[TextureRect]:
	var found: Array[TextureRect] = []
	var rect := node as TextureRect
	if rect != null:
		found.append(rect)
	for child: Node in node.get_children():
		found.append_array(_rects_of(child))
	return found


func _lights_of(node: Node) -> Array[Light2D]:
	var found: Array[Light2D] = []
	var light := node as Light2D
	if light != null:
		found.append(light)
	for child: Node in node.get_children():
		found.append_array(_lights_of(child))
	return found


## Актёры: кто и какими позами нарисован. Список берётся у [SpriteTextures],
## поэтому забытая поза падает сама, без правки теста.
func _actor_rows() -> Array[Array]:
	return [
		["otto", SpriteTextures.OTTO_POSES],
		["agent", SpriteTextures.AGENT_POSES],
		["car", SpriteTextures.CAR_POSES],
	]


func test_every_pose_has_all_three_maps() -> void:
	for row: Array in _actor_rows():
		var actor := row[0] as String
		for pose: String in row[1] as PackedStringArray:
			for path: String in SpriteTextures.actor_paths(actor, pose):
				assert_true(ResourceLoader.exists(path), "нарисована карта %s" % path)


func test_maps_of_one_pose_are_the_same_size() -> void:
	for row: Array in _actor_rows():
		var actor := row[0] as String
		for pose: String in row[1] as PackedStringArray:
			var expected := Vector2.ZERO
			for path: String in SpriteTextures.actor_paths(actor, pose):
				var texture := load(path) as Texture2D
				assert_not_null(texture, "карта %s читается" % path)
				if texture == null:
					continue
				if expected == Vector2.ZERO:
					expected = texture.get_size()
				assert_eq(texture.get_size(), expected, "%s того же размера" % path)


func test_all_poses_of_an_actor_share_one_frame() -> void:
	# Кадры разного размера съехали бы друг относительно друга при смене позы:
	# привязка у спрайта одна на все, и она задана офсетом в сцене.
	for row: Array in _actor_rows():
		var actor := row[0] as String
		var frame := Vector2.ZERO
		for pose: String in row[1] as PackedStringArray:
			var texture := SpriteTextures.actor(actor, pose)
			assert_not_null(texture)
			if texture == null:
				continue
			if frame == Vector2.ZERO:
				frame = texture.diffuse_texture.get_size()
			assert_eq(
				texture.diffuse_texture.get_size(), frame, "%s_%s в общем кадре" % [actor, pose]
			)


func test_the_actor_folder_holds_nothing_but_the_listed_poses() -> void:
	# Обратная сторона [method test_every_pose_has_all_three_maps]: там список
	# ищет файлы, здесь файлы ищут список. Без этой проверки поза, выпавшая из
	# набора, остаётся в репозитории картинкой, которую никто не грузит, — а
	# веха считает её сделанной работой.
	var expected: Dictionary = {}
	for row: Array in _actor_rows():
		var actor := row[0] as String
		for pose: String in row[1] as PackedStringArray:
			for path: String in SpriteTextures.actor_paths(actor, pose):
				expected[path.get_file()] = true

	var files := DirAccess.get_files_at(SpriteTextures.ACTOR_DIR)
	assert_gt(files.size(), 0, "папка актёров читается")
	for file: String in files:
		if not file.ends_with(".png"):
			continue
		assert_true(expected.has(file), "%s кому-то нужен" % file)


func test_the_sprite_hangs_by_the_feet() -> void:
	# Спрайт крупнее коллизии нарочно (ADR-0011, пункт 4), поэтому привязан не
	# краем, а низом и серединой: иначе шляпа сдвинула бы фигуру над полом.
	for row: Array in [["otto", OTTO_SCENE], ["agent", ENEMY_SCENE]]:
		var actor := row[0] as String
		var blueprint := (row[1] as PackedScene).instantiate()
		var sprite := blueprint.get_node("Body") as Sprite2D
		var offset := sprite.offset
		var centered := sprite.centered
		blueprint.free()

		var frame := SpriteTextures.actor(actor, "idle").diffuse_texture.get_size()
		assert_false(centered, "%s: кадр кладётся от угла" % actor)
		assert_eq(offset, Vector2(-frame.x * 0.5, -frame.y), "%s: ноги на полу" % actor)
