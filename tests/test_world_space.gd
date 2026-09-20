extends GutTest

## Перевод между плоскостью правил и сценой.
##
## Тест без сцены и физики: [WorldSpace] — чистая арифметика, и именно поэтому
## он единственное место, где можно ошибиться знаком безнаказанно.


func test_the_plane_and_the_scene_disagree_about_where_down_is() -> void:
	# Ради этого класс и существует: у правил Y растёт вниз, у сцены вверх.
	var lower_floor := Vector2(0.0, 100.0)
	var upper_floor := Vector2(0.0, 10.0)
	assert_gt(lower_floor.y, upper_floor.y, "у правил нижний этаж дальше по Y")
	assert_lt(
		WorldSpace.to_scene(lower_floor).y,
		WorldSpace.to_scene(upper_floor).y,
		"в сцене нижний этаж обязан оказаться ниже"
	)


func test_a_point_survives_the_round_trip() -> void:
	var point := Vector2(12.5, -3.25)
	assert_eq(WorldSpace.to_plane(WorldSpace.to_scene(point)), point)


func test_a_height_survives_the_round_trip() -> void:
	assert_eq(WorldSpace.height_to_plane(WorldSpace.height_to_scene(7.5)), 7.5)


func test_a_direction_survives_the_round_trip() -> void:
	var delta := Vector2(-2.0, 9.0)
	assert_eq(WorldSpace.direction_to_plane(WorldSpace.direction_to_scene(delta)), delta)


func test_everything_game_side_lands_in_one_plane() -> void:
	# Плоскость игры одна — ADR-0021, решение 1. Если этот тест покраснел,
	# значит кто-то начал разносить игровые объекты по глубине.
	for point in [Vector2.ZERO, Vector2(38.4, 0.0), Vector2(-5.0, 112.0)]:
		assert_eq(WorldSpace.to_scene(point).z, WorldSpace.PLAY_Z)


func test_falling_down_the_plane_is_falling_down_the_scene() -> void:
	# Падение в шахту у правил — рост Y; в сцене оно обязано быть убыванием.
	var fall := WorldSpace.direction_to_scene(Vector2(0.0, 1.0))
	assert_lt(fall.y, 0.0, "падение по правилам должно опускать и в сцене")


func test_the_corridor_is_shallower_than_the_room_behind_it() -> void:
	# Глубина берётся комнатой за стеной, а не коридором: иначе передний план
	# начнёт загораживать Otto (ADR-0021, решение 1).
	assert_lt(WorldSpace.CORRIDOR_DEPTH, WorldSpace.ROOM_DEPTH)
