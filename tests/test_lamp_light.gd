extends GutTest

## Lamp light on a spare floor (ADR-0042, decision 2).
##
## Floors beyond the frame edge are lit in advance so a floor coming in does not flare up
## before the eyes. Nobody sees their shadows, and at the bottom of the building they gave a
## third of the shadow passes: there the lamp is lit as a cone without shadow and no further
## than its floor.

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
		assert_true(light.visible, "%s is lit" % light.get_class())
		assert_true(light.shadow_enabled, "%s casts a shadow" % light.get_class())


func test_a_margin_lamp_lights_its_own_floor_only() -> void:
	var lamp := _lamp()
	lamp.set_light_visible(true, false)
	for light: Light3D in _lights(lamp):
		var spot := light as SpotLight3D
		if spot == null:
			assert_false(
				light.visible, "fill without a shadow would shine through the ceiling — it is off"
			)
			continue
		assert_true(spot.visible, "cone is lit")
		assert_false(spot.shadow_enabled, "no shadow")
		assert_lt(
			spot.spot_range,
			HANG + Proportions.SLAB,
			"and no deeper than the slab under its own floor"
		)


## Dressing does not get into the fill shadow: the shadow mask takes an item by any
## shared layer, and an item that also stayed on the first one would not be released by the
## fill (code review M24f).
func test_props_cast_no_fill_shadow() -> void:
	var lamp := _lamp()
	var fill: OmniLight3D = null
	for light: Light3D in _lights(lamp):
		if light is OmniLight3D:
			fill = light as OmniLight3D
	assert_not_null(fill, "the lamp has a fill")
	if fill == null:
		return
	var checked := 0
	# A few items, not the whole catalogue: the layer is set by one build function.
	for entry: PropCatalog.Entry in PropCatalog.entries().slice(0, 4):
		var prop := PropCatalog.make(entry.name)
		if prop == null:
			continue
		for node: Node in prop.find_children("*", "VisualInstance3D", true, false):
			var visual := node as VisualInstance3D
			assert_eq(
				visual.layers & fill.shadow_caster_mask,
				0,
				"%s: not in the fill's shadow" % entry.name
			)
			checked += 1
		prop.free()
	assert_gt(checked, 0, "items checked")


func test_back_in_frame_the_lamp_is_whole_again() -> void:
	var lamp := _lamp()
	lamp.set_light_visible(true, false)
	lamp.set_light_visible(true, true)
	for light: Light3D in _lights(lamp):
		assert_true(
			light.visible and light.shadow_enabled, "%s has a shadow again" % light.get_class()
		)


## A blinking residential lamp shot down by a bullet does not light the darkened
## diffuser again: the blinking releases the light at full strength, while the look of a
## shot-down lamp stays with [method Lamp.shoot_down] (code review M24m: it glowed in flight).
func test_a_shot_flickering_lamp_stays_dark() -> void:
	var lamp := LAMP_SCENE.instantiate() as Lamp
	lamp.flicker = true
	add_child_autofree(lamp)
	lamp.hang(HANG, HANG + 0.5)
	var diffuser := lamp.find_children("*", "MeshInstance3D", true, false).filter(
		func(node: Node) -> bool: return (node as MeshInstance3D).mesh is SphereMesh
	)
	assert_eq(diffuser.size(), 1, "the shade has one diffuser")
	if diffuser.is_empty():
		return
	var glass := diffuser[0] as MeshInstance3D
	assert_eq(glass.material_override, GreyboxLook.marker(GreyboxLook.LAMP), "an intact one glows")
	lamp.shoot_down()
	var dark := glass.material_override
	assert_ne(dark, GreyboxLook.marker(GreyboxLook.LAMP), "a broken one went dark")
	lamp._process(1.0 / 60.0)
	assert_eq(glass.material_override, dark, "flickering did not light it again")
	assert_false(lamp.is_processing(), "a broken one no longer flickers")
