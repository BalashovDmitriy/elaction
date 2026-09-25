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


## Вспышка у ствола — импульс света на несколько кадров, а не весь полёт
## пули: с M24a пуля втрое быстрее, и свет, едущий с ней, гас бы за кадр в
## метре от стрелка (ADR-0037, решение 5). Узел вспышки убирает себя сам.
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


## Ядро светится эмиссией, а unshaded Godot 4 эмиссию не берёт: ядро горело бы
## альбедо, не ярче единицы, и ореола у трассера не было бы (авторевью M21).
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
	# Форма пули — то, от чего приседают и уклоняются: вид её не меняет.
	assert_almost_eq(bullet.half_length(), 0.09, 0.001)
