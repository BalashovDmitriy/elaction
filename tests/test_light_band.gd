extends GutTest

## Light at the bottom of the building is cheaper (ADR-0044, decision 11): lamps also go out beyond
## the frame edge along X, and only the ones nearest to the middle of the frame cast the fill
## shadow.
##
## M24h measurement: the podium is a frame and a half wide, and on the lower floors lamps that are
## not in the frame were lit and cast shadows — the frame was twice as expensive as on the upper
## floors.

const VIEW := Rect2(10.0, 0.0, 23.5, 13.2)
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")


func test_the_band_covers_the_frame_and_its_reach() -> void:
	var strip := VisibleFloors.band(VIEW)
	assert_lte(strip.x, VIEW.position.x - VisibleFloors.BAND_REACH, "слева — кадр и запас")
	assert_gte(strip.y, VIEW.end.x + VisibleFloors.BAND_REACH, "справа тоже")
	assert_true(VisibleFloors.in_band(strip, VIEW.get_center().x), "середина кадра в полосе")
	assert_false(VisibleFloors.in_band(strip, strip.y + 0.5), "за полосой — нет")


func test_the_shadow_band_is_tighter() -> void:
	var light := VisibleFloors.band(VIEW)
	var shadow := VisibleFloors.band(VIEW, VisibleFloors.SHADOW_REACH)
	assert_gt(shadow.x, light.x, "тени нужно меньше запаса, чем свету")
	assert_lt(shadow.y, light.y)


func test_a_small_shift_keeps_the_band() -> void:
	var moved := Rect2(VIEW.position + Vector2(0.05, 0.0), VIEW.size)
	assert_eq(VisibleFloors.band(moved), VisibleFloors.band(VIEW), "сдвиг на 5 см свет не трогает")


func test_fill_shadows_go_to_the_lamps_nearest_the_middle() -> void:
	var lamps: Array[Lamp] = []
	for x: float in [0.0, 12.0, 20.0, 22.0, 24.0, 40.0]:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		lamp.position = WorldSpace.to_scene(Vector2(x, 3.0))
		add_child_autofree(lamp)
		lamps.append(lamp)
	var picked := FloorLighting.nearest(lamps, Vector2(21.0, 3.0), 3)
	assert_eq(picked.size(), 3, "не больше, чем просили")
	for lamp: Lamp in picked:
		var x := WorldSpace.to_plane(lamp.global_position).x
		assert_between(x, 19.0, 25.0, "ближние к середине: %.1f" % x)


## The fill shadow goes only to lamps that cast shadows: a margin floor and a lamp beyond the edge
## of the shadow band do not take a slot (M24h code review).
func test_fill_shadows_skip_lamps_that_cast_no_shadow() -> void:
	var lamps: Array[Lamp] = []
	# x, floor: at the middle — a lamp of the margin floor; beyond the band — one more.
	for spot: Vector2 in [
		Vector2(21.0, 6.0), Vector2(18.0, 5.0), Vector2(25.0, 5.0), Vector2(40.0, 5.0)
	]:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		lamp.position = WorldSpace.to_scene(Vector2(spot.x, 3.0))
		lamp.floor_index = int(spot.y)
		add_child_autofree(lamp)
		lamps.append(lamp)
	var picked := FloorLighting.nearest(
		lamps, Vector2(21.0, 3.0), 3, Vector2(10.0, 30.0), Vector2i(5, 5)
	)
	assert_eq(picked.size(), 2, "из четырёх тень кладут две")
	for lamp: Lamp in picked:
		assert_eq(lamp.floor_index, 5, "с этажа в кадре")
		assert_lt(WorldSpace.to_plane(lamp.global_position).x, 30.0, "из полосы теней")
