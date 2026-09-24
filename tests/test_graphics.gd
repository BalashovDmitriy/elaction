extends GutTest

## Уровни качества (ADR-0030, решение 5; ADR-0034): каждый включает то, что
## обещает таблица, уровни идут по возрастанию, правил игры уровень не трогает,
## а первый запуск выбирает уровень по замеру.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_each() -> void:
	Graphics.broadcast(Graphics.Quality.HIGH)


func after_all() -> void:
	GameState.instance().reset()


## Таблица ADR-0034: на каждом уровне — ровно то, что обещано.
func test_each_level_turns_on_what_it_promises() -> void:
	var expected := {
		Graphics.Quality.LOW: [false, false, false, false, false, false],
		Graphics.Quality.MEDIUM: [false, true, true, false, true, false],
		Graphics.Quality.HIGH: [true, true, true, false, true, true],
		Graphics.Quality.ULTRA: [true, true, true, true, true, true],
	}
	for level: Graphics.Quality in expected:
		Graphics.broadcast(level)
		var got := [
			Graphics.reflections(),
			Graphics.contact_shadows(),
			Graphics.volumetric_fog(),
			Graphics.indirect_light(),
			Graphics.spot_shadows(),
			Graphics.fill_shadows(),
		]
		assert_eq(got, expected[level], "уровень %d" % level)


## Сглаживание и тени — на окне: ни один уровень не хуже нижнего.
func test_the_window_gets_sharper_with_each_level() -> void:
	var root := get_tree().root
	var last_atlas := 0
	for level: int in Graphics.Quality.size():
		Graphics.broadcast(level as Graphics.Quality)
		assert_gte(root.positional_shadow_atlas_size, last_atlas, "атлас теней не уменьшается")
		last_atlas = root.positional_shadow_atlas_size
		assert_false(root.use_taa, "TAA размывает обводку актёров")
		if level == Graphics.Quality.LOW:
			assert_eq(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "низкому — FXAA")
		else:
			assert_ne(root.msaa_3d, Viewport.MSAA_DISABLED, "уровень %d без MSAA" % level)
	assert_eq(root.msaa_3d, Viewport.MSAA_4X, "«Ультра» — MSAA ×4")


## Каждая таблица по уровню — на все уровни: новый уровень без столбца упал бы
## индексом посреди партии.
func test_every_per_level_table_covers_every_level() -> void:
	var size := Graphics.Quality.size()
	assert_eq(Graphics.CITY_SHARE.size(), size)
	assert_eq(Graphics.RAIN_SHARE.size(), size)
	assert_eq(Graphics.MSAA.size(), size)
	assert_eq(Graphics.SHADOW_ATLAS.size(), size)
	assert_eq(Graphics.LIGHT_IN_FOG.size(), size)
	assert_eq(Graphics.FOG_GRID.size(), size)


## «Ультра» доходит до воздуха и ламп стоящего здания: отражённый свет и свет в
## тумане.
func test_ultra_reaches_the_air_and_the_lamps() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var air := (level.get_node("Scenery/Air") as WorldEnvironment).environment
	Graphics.broadcast(Graphics.Quality.ULTRA)
	assert_true(air.ssil_enabled, "отражённый свет не включился")
	var lamps := level.find_children("*", "Lamp", true, false)
	assert_gt(lamps.size(), 0, "ламп нет")
	var spot := lamps[0].find_children("*", "SpotLight3D", true, false)[0] as SpotLight3D
	assert_almost_eq(
		spot.light_volumetric_fog_energy, Graphics.LIGHT_IN_FOG[Graphics.Quality.ULTRA], 0.001
	)
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_false(air.ssil_enabled, "на высоком отражённого света нет")
	remove_child(level)


## Замер спускается по ступени, пока кадр не уложится, и не ниже низкого.
func test_the_probe_steps_down_until_the_frame_fits() -> void:
	var slow := QualityProbe.TARGET_MS + 3.0
	assert_eq(QualityProbe.step(Graphics.Quality.ULTRA, slow), Graphics.Quality.HIGH)
	assert_eq(
		QualityProbe.step(Graphics.Quality.HIGH, 4.0), Graphics.Quality.HIGH, "уложился — остаётся"
	)
	assert_eq(
		QualityProbe.step(Graphics.Quality.LOW, 40.0), Graphics.Quality.LOW, "ниже низкого некуда"
	)


## Время вышло, а уровень не доказан: на слабой карте разогрев «Ультра» не
## успевает пройти за отведённые секунды, и «Ультра» ей не достаётся.
func test_a_timed_out_probe_does_not_keep_an_unproven_level() -> void:
	assert_eq(
		QualityProbe.settle(Graphics.Quality.ULTRA, PackedFloat64Array()),
		Graphics.Quality.HIGH,
		"ничего не намерено — ступенью ниже"
	)
	assert_eq(
		QualityProbe.settle(Graphics.Quality.HIGH, PackedFloat64Array([40.0, 42.0, 41.0])),
		Graphics.Quality.MEDIUM,
		"намерено мало, но медленно — ступенью ниже"
	)
	assert_eq(
		QualityProbe.settle(Graphics.Quality.ULTRA, PackedFloat64Array([5.0, 6.0])),
		Graphics.Quality.ULTRA,
		"намерено мало, но быстро — остаётся"
	)


## Игрок выбрал уровень, пока шёл замер: замер уходит и выбор не перебивает.
func test_the_probe_gives_way_to_the_players_choice() -> void:
	var settings := GameSettings.new()
	var probe := QualityProbe.new()
	add_child_autofree(probe)
	probe.start(settings)
	assert_eq(Graphics.quality, Graphics.Quality.ULTRA, "замер начинается с «Ультра»")
	settings.quality = Graphics.Quality.LOW
	settings.quality_measured = true
	Graphics.broadcast(Graphics.Quality.LOW)
	await wait_physics_frames(3)
	assert_false(is_instance_valid(probe), "замер не ушёл")
	assert_eq(settings.quality, Graphics.Quality.LOW, "замер перебил выбор игрока")
	assert_eq(Graphics.quality, Graphics.Quality.LOW, "замер вернул свой уровень")


## Медиана, а не среднее: один долгий кадр загрузки уровень не опускает.
func test_one_slow_frame_does_not_drop_the_level() -> void:
	var frames := PackedFloat64Array([4.0, 4.2, 3.9, 60.0, 4.1])
	assert_lt(QualityProbe.median(frames), QualityProbe.TARGET_MS)


## Замер — один раз: выбранный уровень помечается, и уровень до M22 считается
## выбранным игроком.
func test_the_measured_level_is_remembered() -> void:
	var path := "user://test_settings_quality.cfg"
	var fresh := GameSettings.new()
	assert_true(QualityProbe.needed(fresh), "первый запуск — мерить")
	fresh.quality = Graphics.Quality.MEDIUM
	fresh.quality_measured = true
	fresh.save_to(path)
	var back := GameSettings.load_from(path)
	assert_eq(back.quality, Graphics.Quality.MEDIUM)
	assert_false(QualityProbe.needed(back), "замерили — больше не мерить")

	var old := ConfigFile.new()
	old.set_value(GameSettings.SECTION, "quality", Graphics.Quality.LOW)
	old.save(path)
	assert_false(QualityProbe.needed(GameSettings.load_from(path)), "уровень до M22 — выбор игрока")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
