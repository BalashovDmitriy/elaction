extends GutTest

## Вид пули: трассер, хвост и вспышка у ствола ([BulletLook]). Только вид —
## попадания держит форма пули, и её здесь не трогают.

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


func test_the_muzzle_flash_stays_where_the_shot_was_and_fades() -> void:
	var look := _look(-1.0)
	var flash := look.get_node("Flash") as MeshInstance3D
	assert_true(flash.visible, "в миг выстрела вспышка горит")
	look.follow(0.3)
	assert_almost_eq(flash.position.x, 0.3, 0.001, "вспышка отстаёт от пули ровно на путь")
	assert_gt(flash.transparency, 0.0, "и гаснет")
	look.follow(BulletLook.FLASH_FADE + 0.01)
	assert_false(flash.visible, "а за первые полметра гаснет совсем")


func test_the_bullet_wears_the_tracer_and_keeps_its_shape() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	add_child_autofree(bullet)
	assert_not_null(bullet.get_node_or_null("Look"), "у пули вид трассера")
	# Форма пули — то, от чего приседают и уклоняются: вид её не меняет.
	assert_almost_eq(bullet.half_length(), 0.09, 0.001)
