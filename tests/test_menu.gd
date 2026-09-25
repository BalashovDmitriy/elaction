extends GutTest

## Тесты меню M22b (ADR-0035): страницы, пункты, фон и один шрифт.
##
## Меню видит каждый игрок первым, а сломанная страница молчит: пустая
## колонка — это не ошибка в логе, а экран, с которого не уйти. Поэтому каждая
## страница собирается и отдаёт фокус первому пункту — без него с геймпада по
## меню не походить.

const MENU_SCENE := preload("res://src/ui/menu.tscn")
const MAIN_SCENE := preload("res://src/main.tscn")

## Сколько кадров дать отложенному фокусу и вспышке выбора.
const SETTLE_FRAMES: int = 4

## Где искать ссылки на шрифт, которого в проекте больше нет.
const SOURCE_DIRS: Array[String] = ["res://src", "res://tools"]


func _menu() -> Menu:
	var menu := MENU_SCENE.instantiate() as Menu
	menu.settings = GameSettings.new()
	menu.records = Records.new()
	add_child_autofree(menu)
	return menu


func test_every_page_builds_and_takes_focus() -> void:
	var menu := _menu()
	for page: int in Menu.Page.size():
		menu.show_page(page as Menu.Page)
		await wait_physics_frames(SETTLE_FRAMES)
		var rows := menu.rows()
		assert_gt(rows.size(), 0, "на странице %d есть пункты" % page)
		assert_true(rows[0].has_focus(), "страница %d отдаёт фокус первому пункту" % page)


func test_settings_have_every_choice() -> void:
	# Громкость трижды, язык, сложность, графика, экран, разрешение, масштаб,
	# кровь, кадры в секунду — и «назад».
	var menu := _menu()
	menu.show_page(Menu.Page.SETTINGS)
	var kinds: Array[int] = []
	for row: MenuRow in menu.rows():
		kinds.append(row.kind)
	assert_eq(kinds.count(MenuRow.Kind.LEVEL), 3, "три громкости")
	assert_eq(kinds.count(MenuRow.Kind.CHOICE), 6, "шесть переключателей")
	assert_eq(kinds.count(MenuRow.Kind.TOGGLE), 2, "флажки крови и кадров в секунду")
	assert_eq(kinds.count(MenuRow.Kind.ACTION), 1, "назад")


func test_the_game_behind_blurs_only_over_a_game() -> void:
	# Из главного меню за ним город, а размывать нечего; на паузе и в конце
	# партии за ним замершее здание — и оно размывается, вместе с подстраницами.
	var menu := _menu()
	var blur := menu.get_node("Root/Blur") as ColorRect
	menu.show_page(Menu.Page.MAIN)
	assert_false(blur.visible, "главное меню — без размытия")
	menu.show_page(Menu.Page.SETTINGS)
	assert_false(blur.visible, "настройки из главного — без размытия")
	menu.show_page(Menu.Page.PAUSE)
	assert_true(blur.visible, "пауза — размыта")
	menu.show_page(Menu.Page.SETTINGS)
	assert_true(blur.visible, "настройки с паузы — размыты")


func test_the_sign_hangs_only_over_the_main_page() -> void:
	var menu := _menu()
	menu.show_page(Menu.Page.MAIN)
	assert_true(menu.title().visible)
	menu.show_page(Menu.Page.SETTINGS)
	assert_false(menu.title().visible, "настройкам нужна вся высота экрана")


func test_a_choice_wraps_both_ways() -> void:
	var row := MenuRow.choice("x", ["a", "b", "c"] as Array[String], 0)
	autofree(row)
	row.step_value(-1)
	assert_eq(row.index, 2, "влево с первого — на последний")
	row.step_value(1)
	assert_eq(row.index, 0, "вправо с последнего — на первый")
	assert_string_contains(row.value_text(), "a")


func test_a_level_steps_by_five_and_stops_at_the_ends() -> void:
	var row := MenuRow.slider("x", 0.97)
	autofree(row)
	row.step_value(1)
	assert_almost_eq(row.level, 1.0, 0.001, "выше ста не бывает")
	row.step_value(-1)
	assert_almost_eq(row.level, 0.95, 0.001, "шаг — пять процентов")
	assert_eq(row.value_text(), "95%")
	row.level = 0.02
	row.step_value(-1)
	assert_almost_eq(row.level, 0.0, 0.001, "ниже нуля не бывает")


func test_a_toggle_flips_either_way() -> void:
	var row := MenuRow.toggle("x", true)
	autofree(row)
	watch_signals(row)
	row.step_value(-1)
	assert_false(row.on)
	row.step_value(1)
	assert_true(row.on)
	assert_signal_emit_count(row, "changed", 2)


func test_the_stage_is_a_city_without_a_building() -> void:
	var stage := MenuStage.new()
	add_child_autofree(stage)
	stage.build(7)
	await wait_physics_frames(2)
	assert_true(stage.camera().current, "город ведётся камерой сцены")
	assert_eq(
		stage.camera().projection,
		Camera3D.PROJECTION_ORTHOGONAL,
		"камера — как у игры, ортогональная"
	)
	assert_not_null(stage.get_node_or_null("City") as CityBackdrop, "город на месте")
	for child: Node in stage.get_children():
		assert_false(child is GreyboxLevel, "здания за меню нет")


func test_the_stage_drifts_along_the_street() -> void:
	var stage := MenuStage.new()
	add_child_autofree(stage)
	stage.build(7)
	var start := stage.camera().global_position.x
	await wait_seconds(0.5)
	assert_ne(stage.camera().global_position.x, start, "камера плывёт вдоль улицы")


func test_the_sign_measures_its_glow() -> void:
	var title := NeonTitle.new()
	autofree(title)
	var bare := NeonStyle.font(NeonTitle.WEIGHT).get_string_size(
		title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.font_size
	)
	assert_gt(title.get_combined_minimum_size().x, bare.x, "ореолу оставлено место по краям")


func test_the_sign_blinks_and_stops_on_demand() -> void:
	# Снимки гасят мигание посреди моргания — и буква не должна остаться тёмной.
	var title := NeonTitle.new()
	add_child_autofree(title)
	assert_true(title.is_letter_lit(), "вывеска зажигается горящей")
	title._process(NeonTitle.STEADY.y + 0.1)
	assert_false(title.is_letter_lit(), "дольше самой длинной паузы — буква моргнула")
	title.flicker_letter = -1
	assert_true(title.is_letter_lit(), "мигание снято — трубка горит")
	title._process(NeonTitle.STEADY.y + 0.1)
	assert_true(title.is_letter_lit(), "и больше не гаснет")


func test_a_level_at_its_end_stays_quiet() -> void:
	# Упёрлась в край — ни щелчка, ни записи в шину на каждое нажатие.
	var row := MenuRow.slider("x", 1.0)
	autofree(row)
	watch_signals(row)
	row.step_value(1)
	assert_signal_not_emitted(row, "changed", "выше ста не листается")
	row.step_value(-1)
	assert_signal_emit_count(row, "changed", 1, "а вниз — да")


func test_a_row_takes_its_neon_after_it_is_built() -> void:
	# Меню красит пункт уже собранным: кромка обязана перекраситься сразу, а не
	# с первой вспышкой фокуса.
	var row := MenuRow.action("x")
	add_child_autofree(row)
	row.neon = VerticalSign.NEON_OFFICE
	var box := row.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(Color(box.border_color, 1.0), Color(VerticalSign.NEON_OFFICE, 1.0))


func test_escape_from_settings_over_the_pause_stops_at_the_pause() -> void:
	# Esc — и «назад» меню, и «пауза» игры. С настроек над паузой меню уходит на
	# паузу ещё до кадра main, и по одной текущей странице то же нажатие тут же
	# снимало паузу (авторевью M22b). Кадр разыгран руками: сначала ввод, потом
	# _process — в этом порядке движок их и зовёт.
	var locale := TranslationServer.get_locale()
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	var menu := main.get_node("Menu") as Menu
	menu.show_page(Menu.Page.PAUSE)
	menu.show_page(Menu.Page.SETTINGS)
	main._process(0.0)

	var back := InputEventAction.new()
	back.action = &"ui_cancel"
	back.pressed = true
	menu._unhandled_input(back)
	Input.action_press(&"pause")
	main._process(0.0)
	assert_eq(menu.current_page(), Menu.Page.PAUSE, "назад — на паузу")
	assert_true(menu.visible, "и пауза не снялась тем же нажатием")

	Input.action_release(&"pause")
	main._process(0.0)
	Input.action_press(&"pause")
	main._process(0.0)
	assert_false(menu.visible, "второе нажатие на паузе снимает её")

	Input.action_release(&"pause")
	Sounds.stop_music()
	TranslationServer.set_locale(locale)


func test_leaving_the_pause_brings_the_music_back() -> void:
	# «Заново» с паузы снимало паузу дерева, но не глухую музыку паузы: вся
	# новая партия звучала из-за стены (авторевью M23). Из паузы теперь выходят
	# только через _unpause — «продолжить», «заново» и «в меню» разом.
	var director := AudioDirector.instance()
	if director == null:
		return
	director.reset()
	var main := MAIN_SCENE.instantiate()
	add_child_autofree(main)
	main.call("_pause")
	assert_true(director.music_muffled(), "на паузе музыка из-за стены")
	main.call("_unpause")
	assert_false(get_tree().paused, "пауза снята")
	assert_false(director.music_muffled(), "и музыка вернулась")
	Sounds.stop_music()


func test_no_code_points_at_pixellari() -> void:
	# ADR-0035, решение 3: один шрифт. Забытая ссылка на удалённый файл — это
	# ошибка загрузки в той сцене, куда реже всего заглядывают.
	for dir: String in SOURCE_DIRS:
		for path: String in _sources(dir):
			var text := FileAccess.get_file_as_string(path)
			assert_false(text.contains("Pixellari.ttf"), "%s не грузит Pixellari" % path)


func _sources(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "tscn", "tres", "py"]:
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_sources(dir.path_join(sub)))
	return found


## Справку по управлению не находили: из главного меню она была, с паузы — нет
## (ADR-0037, решение 9).
func test_the_controls_open_from_the_pause_and_lead_back() -> void:
	var menu := _menu()
	menu.show_page(Menu.Page.PAUSE)
	var wanted := tr("UI_CONTROLS")
	var found: MenuRow = null
	for row: MenuRow in menu.rows():
		for label: Node in row.find_children("*", "Label", true, false):
			if (label as Label).text == wanted:
				found = row
	assert_not_null(found, "на паузе есть «Управление»")
