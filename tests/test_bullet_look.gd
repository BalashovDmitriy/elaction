extends GutTest

## Bullet look: tracer, tail and muzzle flash ([BulletLook]). Looks only —
## hits are handled by the bullet shape, and it is not touched here.

const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")


func _look(direction: float) -> BulletLook:
	var look := BulletLook.make(direction)
	add_child_autofree(look)
	return look


func test_the_trail_grows_with_the_path_and_stops_at_its_length() -> void:
	var look := _look(1.0)
	var trail := look.get_node("Trail") as MeshInstance3D
	assert_false(trail.visible, "у ствола хвоста нет: он торчал бы из стрелка")
	look.follow(0.5)
	assert_almost_eq(trail.scale.x, 0.5, 0.001, "хвост — пройденный путь")
	look.follow(10.0)
	assert_almost_eq(trail.scale.x, BulletLook.TRAIL_LENGTH, 0.001, "и не длиннее своей длины")


func test_the_trail_is_behind_the_bullet() -> void:
	for direction: float in [1.0, -1.0]:
		var look := _look(direction)
		look.follow(0.6)
		var trail := look.get_node("Trail") as MeshInstance3D
		assert_lt(
			trail.position.x * direction, 0.0, "хвост позади пули, летящей в %+.0f" % direction
		)


## The muzzle flash is a light pulse for a few frames, not for the whole flight of
## the bullet: since M24a the bullet is three times faster, and a light riding with it would
## go out within a frame a metre from the shooter (ADR-0037, decision 5). The flash node
## removes itself.
func test_the_muzzle_flash_is_a_short_pulse_that_cleans_up() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var fx := ShotFx.muzzle(host, Vector3(1.0, 1.0, 0.0), 1.0)
	var lights := fx.find_children("*", "OmniLight3D", false, false)
	assert_eq(lights.size(), 1, "в миг выстрела — вспышка света")
	assert_false((lights[0] as OmniLight3D).shadow_enabled, "без тени: живёт три кадра")
	await wait_seconds(ShotFx.FLASH_TIME + 0.1)
	assert_eq(fx.find_children("*", "OmniLight3D", false, false).size(), 0, "и гаснет")
	await wait_seconds(ShotFx.SMOKE_LIFETIME + 0.4)
	assert_false(is_instance_valid(fx), "дымок рассеялся — узла нет")


## The core glows with emission, and Godot 4 unshaded does not take emission: the core would
## shine with albedo, no brighter than one, and the tracer would have no halo (code review M21).
func test_the_core_glows_brighter_than_the_frame() -> void:
	var core := _look(1.0).get_node("Core") as MeshInstance3D
	var material := core.material_override as StandardMaterial3D
	assert_true(material.emission_enabled, "ядро светится")
	assert_gt(material.emission_energy_multiplier, 1.0, "ярче кадра")
	assert_ne(
		material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "эмиссия у unshaded молчит"
	)


func test_the_bullet_wears_the_tracer_and_keeps_its_shape() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	add_child_autofree(bullet)
	assert_not_null(bullet.get_node_or_null("Look"), "у пули вид трассера")
	# The bullet shape is what one crouches and dodges from: the look does not change it.
	assert_almost_eq(bullet.half_length(), 0.09, 0.001)
