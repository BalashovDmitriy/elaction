extends GutTest

## Одежда здания: шахта, машинное отделение и трос вступления.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров даётся зданию, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Сколько кадров ждать спуска по тросу, прежде чем сдаться.
const PATIENCE: int = 240

## Насколько ассет считается стоящим на своём месте, px.
const TOLERANCE: float = 1.0


func before_all() -> void:
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	GameState.instance().reset()


## Здание настоящее: тридцать этажей, пять шахт, крыша сверху.
func _build(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## Куски одежды с нужным ассетом: они лежат прямо в уровне, детьми.
func _parts(level: GreyboxLevel, asset: String) -> Array[TextureRect]:
	var tile := SpriteTextures.tile(asset)
	var found: Array[TextureRect] = []
	for child: Node in level.get_children():
		var rect := child as TextureRect
		if rect != null and rect.texture == tile:
			found.append(rect)
	return found


## У каждой шахты есть обе направляющие во всю её высоту.
##
## Шахта была дырой в перекрытии со столбом света, и в кадре её почти не было
## (ADR-0017, решение 3). Проверяется не «есть хоть что-то», а что стойки идут
## по краям проёма и кончаются вместе с шахтой: короткая стойка обманет глаз
## сильнее, чем её отсутствие.
##
## Стойка ищется сразу по краю и по низу: шахты не сквозные, и в одном столбце
## их стоит несколько — одна под другой.
func test_every_shaft_wears_both_rails() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var rules := level.rules
		var rails := _parts(level, "shaft_rail")
		for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
			var half := rules.shaft_width * 0.5
			var bottom := rules.floor_surface(shaft.bottom)
			var span := bottom - rules.floor_surface(shaft.top)
			var sides: Array[float] = [
				shaft.x - half, shaft.x + half - GreyboxLevel.SHAFT_RAIL_WIDTH
			]
			for left: float in sides:
				var found := false
				for rail: TextureRect in rails:
					if absf(rail.position.x - left) > TOLERANCE:
						continue
					if absf(rail.position.y + rail.size.y - bottom) > TOLERANCE:
						continue
					# Стойка идёт от потолка верхнего этажа шахты, то есть выше
					# его пола: ниже пролёта она не бывает.
					assert_gt(
						rail.size.y, span, "сид %d: стойка короче своей шахты" % building_seed
					)
					found = true
				assert_true(
					found,
					(
						"сид %d: у шахты %d–%d на %.0f px нет стойки на %.0f px"
						% [building_seed, shaft.top, shaft.bottom, shaft.x, left]
					)
				)

		_drop(level)


## Створки стоят на каждом этаже, который шахта обслуживает, — и только там.
func test_shaft_doors_stand_on_every_floor_it_serves() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var doors := _parts(level, "shaft_door")
	var served := 0
	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		served += shaft.height()
		for index: int in range(shaft.top, shaft.bottom + 1):
			var surface := rules.floor_surface(index)
			var found := false
			for door: TextureRect in doors:
				var centre := door.position.x + door.size.x * 0.5
				if absf(centre - shaft.x) > TOLERANCE:
					continue
				if absf(door.position.y + door.size.y - surface) <= TOLERANCE:
					found = true
			assert_true(found, "на этаже %d нет створок шахты на %.0f px" % [index, shaft.x])

	assert_eq(doors.size(), served, "створок ровно столько, сколько этажей у шахт")
	_drop(level)


## Надстройка стоит над верхней шахтой и не занимает место, где появляется Otto.
##
## Тела у неё нет намеренно: под ней проём той самой шахты, с которой начинается
## спуск. А вот встать на неё Otto не должен — иначе он начинал бы здание внутри
## домика.
func test_machine_room_stands_over_the_top_shaft() -> void:
	for building_seed: int in [1, 2, 3]:
		var level := _build(building_seed)
		await wait_physics_frames(SETTLE_FRAMES)

		var rooms := _parts(level, "machine_room")
		assert_eq(rooms.size(), 1, "сид %d: машинное отделение одно" % building_seed)
		if rooms.is_empty():
			_drop(level)
			continue

		var room := rooms[0]
		var centre := room.position.x + room.size.x * 0.5
		var top_shaft := level.plan().roof_shaft()
		assert_not_null(top_shaft, "сид %d: в здании есть шахта до крыши" % building_seed)
		assert_eq(
			top_shaft.top,
			BuildingRules.ROOF,
			"сид %d: верхняя шахта доходит до крыши" % building_seed
		)
		assert_almost_eq(centre, top_shaft.x, TOLERANCE, "сид %d: домик над шахтой" % building_seed)

		var landing := level.plan().safe_x(level.rules, BuildingRules.ROOF)
		var gap := absf(landing - centre)
		assert_gt(
			gap,
			room.size.x * 0.5,
			"сид %d: Otto появляется внутри домика (%.0f px от его середины)" % [building_seed, gap]
		)
		_drop(level)


## Вступление кончается тем, что Otto стоит на крыше и снова слушается игрока.
func test_the_rope_lands_otto_on_the_roof() -> void:
	var level := _build(1)
	var rules := level.rules
	var surface := rules.floor_surface(BuildingRules.ROOF)
	assert_lt(level.otto.global_position.y, surface, "начинает он над крышей, на тросе")

	var left := PATIENCE
	while not level.otto.is_grounded() and left > 0:
		await wait_physics_frames(1)
		left -= 1

	assert_almost_eq(level.otto.global_position.y, surface, 1.0, "съехал ровно на крышу")
	assert_eq(_parts(level, "rope").size(), 0, "трос ушёл вместе с вступлением")

	# Управляем: до M12 ввод на спуске не действовал, и «приехал» не означало
	# «отпустили». Проверяется не состоянием, а тем, что Otto пошёл.
	var before := level.otto.global_position.x
	Input.action_press(&"move_right")
	await wait_physics_frames(6)
	Input.action_release(&"move_right")
	assert_gt(level.otto.global_position.x, before, "и снова слушается игрока")
	_drop(level)


## У каждой шахты есть упоры сверху и снизу: по ним видно, где полоса кончается.
func test_every_shaft_is_capped_at_both_ends() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var buffers := _parts(level, "shaft_buffer")
	var shafts := level.plan().shafts.size()
	assert_eq(buffers.size(), shafts * 2, "по упору на каждый конец каждой шахты")

	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		var mine := 0
		for buffer: TextureRect in buffers:
			var centre := buffer.position.x + buffer.size.x * 0.5
			if absf(centre - shaft.x) <= TOLERANCE:
				mine += 1
		assert_eq(mine, 2, "у шахты на %.0f px оба конца отмечены" % shaft.x)
	_drop(level)
