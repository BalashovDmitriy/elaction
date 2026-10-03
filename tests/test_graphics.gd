extends GutTest

## Quality levels (ADR-0030, decision 5; ADR-0034): each enables what the
## table promises, levels go in ascending order, the level does not touch the game rules,
## and the first launch chooses the level by measurement.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")


func after_each() -> void:
	Graphics.broadcast(Graphics.Quality.HIGH)


func after_all() -> void:
	GameState.instance().reset()


## The ADR-0034 table: each level has exactly what is promised.
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
		assert_eq(got, expected[level], "level %d" % level)


## Anti-aliasing and shadows are on the window: no level is worse than the lowest.
func test_the_window_gets_sharper_with_each_level() -> void:
	var root := get_tree().root
	var last_atlas := 0
	for level: int in Graphics.Quality.size():
		Graphics.broadcast(level as Graphics.Quality)
		assert_gte(root.positional_shadow_atlas_size, last_atlas, "shadow atlas does not shrink")
		last_atlas = root.positional_shadow_atlas_size
		assert_false(root.use_taa, "TAA blurs the actors' outline")
		if level == Graphics.Quality.LOW:
			assert_eq(root.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA, "low gets FXAA")
		else:
			assert_ne(root.msaa_3d, Viewport.MSAA_DISABLED, "level %d without MSAA" % level)
	assert_eq(root.msaa_3d, Viewport.MSAA_4X, "'Ultra' is MSAA x4")


## Every per-level table covers all levels: a new level without a column would fail
## with an index error in the middle of a game.
func test_every_per_level_table_covers_every_level() -> void:
	var size := Graphics.Quality.size()
	assert_eq(Graphics.CITY_SHARE.size(), size)
	assert_eq(Graphics.RAIN_SHARE.size(), size)
	assert_eq(Graphics.MSAA.size(), size)
	assert_eq(Graphics.SHADOW_ATLAS.size(), size)
	assert_eq(Graphics.LIGHT_IN_FOG.size(), size)
	assert_eq(Graphics.FOG_GRID.size(), size)


## "Ultra" reaches the atmosphere and lamps of a standing building: bounced light and light
## in the fog.
func test_ultra_reaches_the_air_and_the_lamps() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 1
	add_child_autofree(level)
	var air := (level.get_node("Scenery/Air") as WorldEnvironment).environment
	Graphics.broadcast(Graphics.Quality.ULTRA)
	assert_true(air.ssil_enabled, "bounced light did not turn on")
	var lamps := level.find_children("*", "Lamp", true, false)
	assert_gt(lamps.size(), 0, "no lamps")
	var spot := lamps[0].find_children("*", "SpotLight3D", true, false)[0] as SpotLight3D
	assert_almost_eq(
		spot.light_volumetric_fog_energy, Graphics.LIGHT_IN_FOG[Graphics.Quality.ULTRA], 0.001
	)
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_false(air.ssil_enabled, "no bounced light on high")
	remove_child(level)


## The measurement steps down until the frame fits, and not below low.
func test_the_probe_steps_down_until_the_frame_fits() -> void:
	var slow := QualityProbe.TARGET_MS + 3.0
	assert_eq(QualityProbe.step(Graphics.Quality.ULTRA, slow), Graphics.Quality.HIGH)
	assert_eq(
		QualityProbe.step(Graphics.Quality.HIGH, 4.0),
		Graphics.Quality.HIGH,
		"fit the budget — stays"
	)
	assert_eq(
		QualityProbe.step(Graphics.Quality.LOW, 40.0), Graphics.Quality.LOW, "nowhere below low"
	)


## Time ran out and the level is not proven: on a weak card the "Ultra" warm-up does not
## manage to pass in the allotted seconds, and it does not get "Ultra".
func test_a_timed_out_probe_does_not_keep_an_unproven_level() -> void:
	assert_eq(
		QualityProbe.settle(Graphics.Quality.ULTRA, PackedFloat64Array()),
		Graphics.Quality.HIGH,
		"nothing measured — one step down"
	)
	assert_eq(
		QualityProbe.settle(Graphics.Quality.HIGH, PackedFloat64Array([40.0, 42.0, 41.0])),
		Graphics.Quality.MEDIUM,
		"few measured but slow — one step down"
	)
	assert_eq(
		QualityProbe.settle(Graphics.Quality.ULTRA, PackedFloat64Array([5.0, 6.0])),
		Graphics.Quality.ULTRA,
		"few measured but fast — stays"
	)


## The player chose a level while the measurement was running: the measurement leaves and
## does not override the choice.
func test_the_probe_gives_way_to_the_players_choice() -> void:
	var settings := GameSettings.new()
	var probe := QualityProbe.new()
	add_child_autofree(probe)
	probe.start(settings)
	assert_eq(Graphics.quality, Graphics.Quality.ULTRA, "the probe starts from 'Ultra'")
	settings.quality = Graphics.Quality.LOW
	settings.quality_measured = true
	Graphics.broadcast(Graphics.Quality.LOW)
	await wait_physics_frames(3)
	assert_false(is_instance_valid(probe), "the probe did not go away")
	assert_eq(settings.quality, Graphics.Quality.LOW, "the probe overrode the player's choice")
	assert_eq(Graphics.quality, Graphics.Quality.LOW, "the probe restored its level")


## Median, not mean: one long loading frame does not lower the level.
func test_one_slow_frame_does_not_drop_the_level() -> void:
	var frames := PackedFloat64Array([4.0, 4.2, 3.9, 60.0, 4.1])
	assert_lt(QualityProbe.median(frames), QualityProbe.TARGET_MS)


## Measuring happens once: the chosen level is marked, and a level from before M22 counts as
## chosen by the player.
func test_the_measured_level_is_remembered() -> void:
	var path := "user://test_settings_quality.cfg"
	var fresh := GameSettings.new()
	assert_true(QualityProbe.needed(fresh), "first launch — measure")
	fresh.quality = Graphics.Quality.MEDIUM
	fresh.quality_measured = true
	fresh.save_to(path)
	var back := GameSettings.load_from(path)
	assert_eq(back.quality, Graphics.Quality.MEDIUM)
	assert_false(QualityProbe.needed(back), "measured — do not measure again")

	var old := ConfigFile.new()
	old.set_value(GameSettings.SECTION, "quality", Graphics.Quality.LOW)
	old.save(path)
	assert_false(
		QualityProbe.needed(GameSettings.load_from(path)),
		"level from before M22 — the player's choice"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
