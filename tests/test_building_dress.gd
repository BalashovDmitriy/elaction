extends GutTest

## Одежда здания: шахта и машинное отделение. Вступление с вертолётом —
## в `test_roof_arrival.gd`.
##
## Части одежды — коробки без тела, и тест узнаёт их по габариту: тому же, каким
## их собирают [BuildingShafts] и [GreyboxLevel]. Другого признака у серой коробки
## нет, а материал у створок шахты и у домика один и тот же.
##
## Мерит тест в плоскости правил: каждая коробка переводится в [Rect2] с началом
## в левом верхнем углу — так считала раскладка, и так считал этот же тест до
## переезда в 3D. Утверждения при переезде не менялись (ADR-0021).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько кадров даётся зданию, чтобы встать на места.
const SETTLE_FRAMES: int = 4

## Насколько часть считается стоящей на своём месте, м: сантиметр.
const TOLERANCE: float = 0.01


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


## Части одежды нужного вида, прямоугольниками в плоскости правил.
##
## Ищутся и в самом уровне, и в [BuildingShafts]: одежда шахт живёт своим узлом
## (частей за полсотни на здание, и под каждый обход детей они попадать не
## должны), а машинное отделение — прямой ребёнок уровня.
func _parts(level: GreyboxLevel, kind: String) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var hosts: Array[Node] = [level]
	hosts.append_array(level.find_children("*", "BuildingShafts", false, false))
	for host: Node in hosts:
		for child: Node in host.get_children():
			var part := child as MeshInstance3D
			if part == null:
				continue
			var box := part.mesh as BoxMesh
			if box == null or not _is_a(kind, box.size):
				continue
			var size := Vector2(box.size.x, box.size.y)
			var centre := WorldSpace.to_plane(part.global_position)
			found.append(Rect2(centre - size * 0.5, size))
	return found


## Узнаёт часть по габариту — тому же, которым её собирали.
static func _is_a(kind: String, size: Vector3) -> bool:
	match kind:
		"shaft_rail":
			return is_equal_approx(size.x, BuildingShafts.RAIL_WIDTH)
		"shaft_door":
			# Проём портала шахты: во всю её ширину и в высоту двери (ADR-0031).
			return (
				is_equal_approx(size.x, Proportions.SHAFT)
				and is_equal_approx(size.y, Proportions.DOOR.y)
			)
		"shaft_buffer":
			return is_equal_approx(size.y, BuildingShafts.BUFFER_HEIGHT)
		"machine_room":
			return (
				is_equal_approx(size.x, BuildingShafts.MACHINE_ROOM_SIZE.x)
				and is_equal_approx(size.y, BuildingShafts.MACHINE_ROOM_SIZE.y)
			)
	return false


## Где Otto стоит в плоскости правил.
func _otto_at(level: GreyboxLevel) -> Vector2:
	return WorldSpace.to_plane(level.otto.global_position)


## У каждой шахты есть обе направляющие во всю её высоту.
##
## Шахта была дырой в перекрытии, и в кадре её почти не было (ADR-0017,
## решение 3). Проверяется не «есть хоть что-то», а что стойки идут по краям
## проёма и кончаются вместе с шахтой: короткая стойка обманет глаз сильнее,
## чем её отсутствие.
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
			var sides: Array[float] = [shaft.x - half, shaft.x + half - BuildingShafts.RAIL_WIDTH]
			for left: float in sides:
				var found := false
				for rail: Rect2 in rails:
					if absf(rail.position.x - left) > TOLERANCE:
						continue
					if absf(rail.end.y - bottom) > TOLERANCE:
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
						"сид %d: у шахты %d–%d на %.2f м нет стойки на %.2f м"
						% [building_seed, shaft.top, shaft.bottom, shaft.x, left]
					)
				)

		_drop(level)


## Портал стоит на каждом этаже, который шахта обслуживает, — и только там. На
## крыше портала нет: там шахта уходит в машинное отделение.
func test_shaft_doors_stand_on_every_floor_it_serves() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var rules := level.rules
	var doors := _parts(level, "shaft_door")
	var served := 0
	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		for index: int in range(maxi(shaft.top, 0), shaft.bottom + 1):
			served += 1
			var surface := rules.floor_surface(index)
			var found := false
			for door: Rect2 in doors:
				if absf(door.get_center().x - shaft.x) > TOLERANCE:
					continue
				if absf(door.end.y - surface) <= TOLERANCE:
					found = true
			assert_true(found, "на этаже %d нет створок шахты на %.2f м" % [index, shaft.x])

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
		var centre := room.get_center().x
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
			"сид %d: Otto появляется внутри домика (%.2f м от его середины)" % [building_seed, gap]
		)
		_drop(level)


## У каждой шахты есть упоры сверху и снизу: по ним видно, где полоса кончается.
##
## Проверяется и место по вертикали, а не только счёт: нижний упор однажды уехал
## в толщу перекрытия — считался он там же, где и раньше, но в кадре его не было
## вовсе. Счёт этого не заметил.
func test_every_shaft_is_capped_at_both_ends() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)

	var buffers := _parts(level, "shaft_buffer")
	var shafts := level.plan().shafts.size()
	assert_eq(buffers.size(), shafts * 2, "по упору на каждый конец каждой шахты")

	for shaft: BuildingPlan.ShaftSpot in level.plan().shafts:
		var mine := 0
		# Низ шахты — пол её нижнего этажа: упор стоит на нём, а не под ним.
		var floor_surface := level.rules.floor_surface(shaft.bottom)
		# Своя шахта опознаётся столбцом и высотой разом. Одного столбца мало
		# с M18: шахты перехлёстываются, место сетки достаётся нескольким из них
		# на разной высоте, и по одному x в кучу попадали чужие упоры (ADR-0024).
		var top_edge := level.rules.story_top(shaft.top)
		var capped_below := false
		for buffer: Rect2 in buffers:
			if absf(buffer.get_center().x - shaft.x) > TOLERANCE:
				continue
			var middle := buffer.get_center().y
			if middle < top_edge - TOLERANCE or middle > floor_surface + TOLERANCE:
				continue
			mine += 1
			assert_lte(
				buffer.end.y,
				floor_surface + TOLERANCE,
				"упор шахты на %.2f м не утоплен в перекрытие" % shaft.x
			)
			if absf(buffer.end.y - floor_surface) <= TOLERANCE:
				capped_below = true
		assert_eq(mine, 2, "у шахты на %.2f м оба конца отмечены" % shaft.x)
		assert_true(capped_below, "у шахты на %.2f м упор лежит на её дне" % shaft.x)
	_drop(level)


## Номер на каждом этаже, как в оригинале: у правой стены, под потолком, и
## верхний этаж — самый большой номер (ADR-0026, решение 9).
##
## Табличка не должна висеть над проёмом шахты: там её закрыла бы кабина, а
## на любом сиде в крайнем правом месте шахта может стоять.
func test_every_floor_wears_its_number() -> void:
	var level := _build(1)
	await wait_physics_frames(SETTLE_FRAMES)
	var rules := level.rules
	var signs := level.get_node("FloorSigns")
	assert_eq(signs.get_child_count(), rules.floors, "по табличке на этаж, у крыши нет")
	var half := Proportions.FLOOR_SIGN * 0.5
	for index in rules.floors:
		var number := FloorSigns.label_of(rules, index)
		var plate := signs.get_node("Floor%s" % number) as Node3D
		assert_not_null(plate, "этаж %s без таблички" % number)
		if plate == null:
			continue
		var label := plate.get_child(1) as Label3D
		assert_eq(label.text, number, "на табличке свой номер")
		var at := WorldSpace.to_plane(plate.position)
		var span := rules.floor_span(index)
		assert_lt(at.x + half.x, span.y - BuildingShell.WALL_WIDTH, "внутри стен")
		# Ниже полосы, которую прячет кромка перекрытия, — иначе цифр не видно.
		assert_gt(
			at.y - half.y, rules.story_top(index) + FloorSigns.hidden_band(), "не под кромкой"
		)
		# Правее крайнего места: там ни двери, ни табло над ней, ни лампы.
		var last := rules.slot_x(rules.slot_range(index).y)
		assert_gt(at.x - half.x, last + Proportions.SLOT * 0.5, "за крайним местом")
		for shaft in level.plan().shafts:
			if shaft.top <= index and index <= shaft.bottom:
				assert_gt(
					at.x - half.x,
					shaft.x + rules.shaft_width * 0.5,
					"этаж %s: табличка над шахтой" % number
				)
	assert_eq(FloorSigns.number_of(rules, 0), rules.floors, "верхний этаж — старший номер")
	assert_eq(FloorSigns.number_of(rules, rules.floors - 2), 2, "над паркингом — второй")
	assert_eq(FloorSigns.label_of(rules, rules.floors - 1), "P", "нижний — паркинг, «P»")
	assert_eq(FloorSigns.label_of(rules, rules.floors - 2), "2", "остальные не сдвинулись")
	_drop(level)
