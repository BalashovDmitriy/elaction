extends GutTest

## Прогрев шейдеров редких эффектов (ADR-0039, решение 8).


func test_every_rare_effect_is_shown_once() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	var shown := ShaderWarmup.spawn(host, Vector3.ZERO)
	var kinds := {}
	for node: Node in shown:
		var script := node.get_script() as Script
		kinds[node.get_class() if script == null else String(script.get_global_name())] = true
	for kind: String in ["ShotFx", "Sparks", "Blood", "BulletLook", "AimLaser"]:
		assert_true(kinds.has(kind), "%s прогревается" % kind)


func test_the_bolt_warms_where_the_lightning_lives() -> void:
	# Разряд рисуется в окне города, и греть его надо там же, под молнией.
	var host := Node3D.new()
	add_child_autofree(host)
	var lightning := Lightning.new()
	lightning.setup(1, Vector2(0.0, 40.0), 0.0)
	host.add_child(lightning)
	var shown := ShaderWarmup.spawn(host, Vector3.ZERO)
	var bolts := shown.filter(func(node: Node) -> bool: return node.get_parent() == lightning)
	assert_eq(bolts.size(), 1, "разряд встал под молнию")
	var bolt := bolts[0] as MeshInstance3D
	assert_true(bolt.mesh is ImmediateMesh, "той же сеткой, что настоящий")


func test_the_blood_setting_survives_the_warmup() -> void:
	# Кровь греется и выключенная, но настройку игрока прогрев не трогает.
	var host := Node3D.new()
	add_child_autofree(host)
	var was := Blood.enabled
	Blood.enabled = false
	ShaderWarmup.spawn(host, Vector3.ZERO)
	assert_false(Blood.enabled, "выключенная кровь осталась выключенной")
	Blood.enabled = was


func test_headless_runs_skip_the_warmup() -> void:
	# Рисовать нечем — и греть нечего: тесты не должны держать кадр чёрным.
	var host := Node3D.new()
	add_child_autofree(host)
	assert_false(ShaderWarmup.run(host), "без окна прогрева нет")


func test_the_export_presets_bake_shaders() -> void:
	var presets := ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK, "пресеты читаются")
	for section: String in presets.get_sections():
		if section.ends_with(".options"):
			assert_true(
				bool(presets.get_value(section, "shader_baker/enabled", false)),
				"%s: Shader Baker включён" % section
			)
