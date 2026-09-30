extends GutTest

## Свет внизу здания дешевле (ADR-0044, решение 11): лампы гаснут и за краем
## кадра по X, а тень заливки кладут только ближайшие к середине кадра.
##
## Замер M24h: стилобат в полтора кадра шириной, и на нижних этажах горели и
## клали тени лампы, которых в кадре нет, — кадр вдвое дороже верхних этажей.

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
