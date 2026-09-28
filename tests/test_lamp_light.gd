extends GutTest

## Свет лампы на запасном этаже (ADR-0042, решение 2).
##
## Этажи за кромкой кадра горят заранее, чтобы въезжающий этаж не вспыхивал на
## глазах. Их тени никто не видит, а внизу здания они давали треть проходов
## теней: там лампа горит конусом без тени и не дальше своего пола.

const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")
const HANG: float = 2.6


func after_all() -> void:
	Graphics.broadcast(Graphics.Quality.HIGH)


func _lamp() -> Lamp:
	Graphics.broadcast(Graphics.Quality.ULTRA)
	var lamp := LAMP_SCENE.instantiate() as Lamp
	add_child_autofree(lamp)
	lamp.hang(HANG, HANG + 0.5)
	return lamp


func _lights(lamp: Lamp) -> Array[Light3D]:
	var found: Array[Light3D] = []
	for node: Node in lamp.find_children("*", "Light3D", true, false):
		found.append(node as Light3D)
	return found


func test_a_lamp_in_frame_casts_shadows() -> void:
	var lamp := _lamp()
	lamp.set_light_visible(true, true)
	for light: Light3D in _lights(lamp):
		assert_true(light.visible, "%s горит" % light.get_class())
		assert_true(light.shadow_enabled, "%s кладёт тень" % light.get_class())


func test_a_margin_lamp_lights_its_own_floor_only() -> void:
	var lamp := _lamp()
	lamp.set_light_visible(true, false)
	for light: Light3D in _lights(lamp):
		var spot := light as SpotLight3D
		if spot == null:
			assert_false(light.visible, "заливка без тени светила бы сквозь потолок — не горит")
			continue
		assert_true(spot.visible, "конус горит")
		assert_false(spot.shadow_enabled, "без тени")
		assert_lt(spot.spot_range, HANG + Proportions.SLAB, "и не глубже плиты под своим полом")


func test_back_in_frame_the_lamp_is_whole_again() -> void:
	var lamp := _lamp()
	lamp.set_light_visible(true, false)
	lamp.set_light_visible(true, true)
	for light: Light3D in _lights(lamp):
		assert_true(light.visible and light.shadow_enabled, "%s снова с тенью" % light.get_class())
