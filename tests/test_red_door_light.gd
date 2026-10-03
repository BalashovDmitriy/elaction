extends GutTest

## The red door's wall lamp (ADR-0042, decision 8): the red door got lost in the corridor shadow.
## Its own wall lamp is on while there is a document behind the door, and goes out with it.

const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")


func _door(red: bool) -> Door:
	var door := DOOR_SCENE.instantiate() as Door
	door.has_document = red
	add_child_autofree(door)
	return door


func test_a_red_door_has_its_own_light() -> void:
	var door := _door(true)
	await wait_physics_frames(2)
	assert_true(door.is_red_light_on(), "the red door has its sconce lit")
	var light := door.get_node("RedLight") as SpotLight3D
	assert_false(light.shadow_enabled, "no shadow — cheap")
	# Along the tilted beam down to the bottom of the slab under its own floor — beyond the range.
	var height := Proportions.DOOR.y + Door.SIGN_RISE
	var through := (height + Proportions.SLAB) / cos(Door.RED_LIGHT_TILT)
	assert_lt(light.spot_range, through, "does not shine through the slab under its own floor")
	assert_gt(light.spot_range, height / cos(Door.RED_LIGHT_TILT), "but reaches the floor")


func test_a_plain_door_has_none() -> void:
	var door := _door(false)
	await wait_physics_frames(2)
	assert_false(door.is_red_light_on(), "an ordinary door's sconce is not lit")


func test_the_light_goes_out_with_the_document() -> void:
	var door := _door(true)
	await wait_physics_frames(2)
	door.has_document = false
	await wait_physics_frames(2)
	assert_false(door.is_red_light_on(), "document taken — sconce went out")


## Off-screen the wall lamp is not lit, like the lamps: a building has up to a dozen red doors.
func test_the_light_is_out_off_frame() -> void:
	var door := _door(true)
	await wait_physics_frames(2)
	door.set_light_in_view(false)
	assert_false(door.is_red_light_on(), "floor left the frame — sconce went out")
	door.set_light_in_view(true)
	assert_true(door.is_red_light_on(), "came back — lit")
