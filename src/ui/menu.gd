class_name Menu
extends CanvasLayer

## Экраны вне игры: меню, пауза, конец партии, настройки, рекорды, управление.
##
## Один узел на все страницы, а не сцена на каждую: страницы отличаются только
## содержимым одной колонки, и держать ради этого шесть файлов значило бы шесть
## раз повторить фон, вывеску и разбор ввода.
##
## Содержимое собирается кодом, потому что оно данные: список пунктов, список
## переключателей, строки таблицы. Разметка в сцене — только фон, вывеска и
## колонка (ADR-0035).

## Что игрок выбрал. Решает не меню, а [Main]: оно знает про здание и партию.
signal play_pressed
signal resume_pressed
signal restart_pressed
signal to_menu_pressed
signal quit_pressed

enum Page { MAIN, PAUSE, GAME_OVER, SETTINGS, RECORDS, CONTROLS }

## Что показывает экран управления: подпись и действия, которые за ней стоят.
## Клавиши берутся из [InputMap], а подписи оттуда не достать — они здесь.
## Движение — четыре действия в одной строке: игроку интересна связка, а не то,
## как она разложена внутри.
const ACTIONS: Array[Array] = [
	["UI_MOVE", ["move_left", "move_right", "move_up", "move_down"]],
	["UI_CROUCH", ["move_down"]],
	["UI_JUMP", ["jump"]],
	["UI_SHOOT", ["shoot"]],
	["UI_PAUSE", ["pause"]],
]

## Имена кнопок геймпада. В [InputMap] они лежат номерами, а номер игроку
## ничего не говорит — на коробке написаны буквы. Значения, начинающиеся с
## `UI_`, переводятся: у крестовины имени на коробке нет.
const PAD_NAMES: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_DPAD_UP: "UI_DPAD",
	JOY_BUTTON_DPAD_DOWN: "UI_DPAD",
	JOY_BUTTON_DPAD_LEFT: "UI_DPAD",
	JOY_BUTTON_DPAD_RIGHT: "UI_DPAD",
}

## Ширина колонки: пунктов и настроек, px.
const COLUMN_WIDTH: float = 560.0
const WIDE_COLUMN: float = 900.0
## Сколько длится смена страницы и насколько колонка въезжает слева.
const PAGE_TIME: float = 0.22
const PAGE_SLIDE: float = 36.0
## Где начинается колонка: под вывеской на главной и выше на остальных —
## настройкам нужна вся высота экрана.
const COLUMN_TOP: float = 340.0
const COLUMN_TOP_HIGH: float = 110.0
## Кегль заголовка страницы и строк таблиц.
const CAPTION_SIZE: int = 28
const TABLE_SIZE: int = 30

var settings: GameSettings = null
var records: Records = null

## Счёт последней партии и её место в таблице: показываются на экране конца.
var _last_score: int = 0
var _last_place: int = -1

var _page: Page = Page.MAIN

## Страница, на которую вернёт «назад». Запоминается, а не угадывается по паузе:
## после партии, попавшей в таблицу, дерево тоже стоит на паузе, и по одному
## этому признаку «назад» из рекордов уводило с экрана конца партии в паузу.
var _back_to: Page = Page.MAIN

## Пока страница собирается и забирает фокус, переход фокуса не звучит: иначе
## каждая страница открывалась бы щелчком, которого игрок не делал.
var _settling: bool = false
var _page_tween: Tween = null

@onready var _column: VBoxContainer = %Page
@onready var _version: Label = %Version
@onready var _title: NeonTitle = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _hint: Label = %Hint
@onready var _blur: ColorRect = %Blur
@onready var _slot: Control = %Slot


func _ready() -> void:
	# Меню живёт на паузе: под ней оно и открывается.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Версия в углу — чтобы игрок мог назвать её, не открывая свойства файла.
	_version.text = Release.tag()
	_style_static_labels()


## Показывает страницу и забирает фокус на пункт [param focus], обычно первый:
## иначе стрелками и геймпадом по меню не походить.
func show_page(page: Page, focus: int = 0) -> void:
	_page = page
	if page == Page.MAIN or page == Page.PAUSE or page == Page.GAME_OVER:
		# Корневые страницы — те, с которых уходят в подстраницы. Последняя из них
		# и есть то, куда вернёт «назад».
		_back_to = page
	visible = true
	_settling = true
	for child: Node in _column.get_children():
		# Сначала из колонки, потом в утиль: [method Node.queue_free] удаляет узел
		# лишь в конце кадра, а отложенный [method _focus_row] успевает раньше —
		# и фокус доставался пункту прошлой страницы, которую тут же и удаляли.
		_column.remove_child(child)
		child.queue_free()

	# Над игрой — пауза и конец партии со своими подстраницами — за меню стоит
	# замершее здание, и оно размывается. Из главного меню за ним город.
	var over_game := _back_to != Page.MAIN
	_blur.visible = over_game
	_title.visible = page == Page.MAIN
	_subtitle.visible = page == Page.MAIN
	# «Esc — назад» только там, где Esc и правда ведёт назад: с корневых страниц
	# уходят пунктами, а на паузе Esc её закрывает.
	_hint.text = tr("UI_HINT_ROOT" if _is_root(page) else "UI_HINT")
	var wide := page == Page.SETTINGS or page == Page.CONTROLS or page == Page.RECORDS
	_column.custom_minimum_size.x = WIDE_COLUMN if wide else COLUMN_WIDTH
	# Контейнер сам не сужается: после широких настроек узкая страница осталась
	# бы шириной настроек, и пункты тянулись бы через полэкрана.
	_column.reset_size()
	_slot.position.y = COLUMN_TOP if page == Page.MAIN else COLUMN_TOP_HIGH
	_column.add_theme_constant_override("separation", 8 if wide else 14)

	match page:
		Page.MAIN:
			_build_main()
		Page.PAUSE:
			_build_pause()
		Page.GAME_OVER:
			_build_game_over()
		Page.SETTINGS:
			_build_settings()
		Page.RECORDS:
			_build_records()
		Page.CONTROLS:
			_build_controls()

	_slide_in()
	_focus_row.call_deferred(focus)


## Прячет меню целиком — игра продолжается.
func close() -> void:
	visible = false


## Запоминает итог партии для экрана конца.
func remember(score: int, place: int) -> void:
	_last_score = score
	_last_place = place


func current_page() -> Page:
	return _page


## Пункты текущей страницы — тем, кто водит меню снаружи: тестам и снимкам.
func rows() -> Array[MenuRow]:
	var found: Array[MenuRow] = []
	_collect_rows(_column, found)
	return found


## Вывеска — нужна тестам и снимкам, чтобы остановить мигание.
func title() -> NeonTitle:
	return _title


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# «Назад» с подстраницы — Esc или B. С корневых страниц уходят только
	# пунктами: пауза закрывается своим действием, и это решает [Main].
	if event.is_action_pressed(&"ui_cancel") and not _is_root(_page):
		get_viewport().set_input_as_handled()
		_go_back()


# --- Страницы ----------------------------------------------------------------


func _build_main() -> void:
	_action("UI_PLAY", func() -> void: play_pressed.emit())
	_action("UI_RECORDS", func() -> void: show_page(Page.RECORDS))
	_action("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	_action("UI_CONTROLS", func() -> void: show_page(Page.CONTROLS))
	_action("UI_QUIT", func() -> void: quit_pressed.emit())


func _build_pause() -> void:
	_caption("UI_PAUSED")
	_action("UI_RESUME", func() -> void: resume_pressed.emit())
	_action("UI_RESTART", func() -> void: restart_pressed.emit())
	_action("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	# Справка — и с паузы: из главного меню её не находили (ADR-0037, решение 9).
	_action("UI_CONTROLS", func() -> void: show_page(Page.CONTROLS))
	_action("UI_TO_MENU", func() -> void: to_menu_pressed.emit())


func _build_game_over() -> void:
	_caption("UI_GAME_OVER")
	var caption := NeonStyle.label(26, NeonStyle.INK_DIM, 600)
	caption.text = tr("UI_YOUR_SCORE").to_upper()
	_column.add_child(caption)
	var score := NeonStyle.label(88, NeonStyle.INK, 800)
	score.text = Hud.format_score(_last_score)
	_column.add_child(score)
	if _last_place >= 0:
		var record := NeonStyle.label(32, _neon(), 700)
		record.text = "%s  #%d" % [tr("UI_NEW_RECORD"), _last_place + 1]
		_column.add_child(record)
	_gap(18.0)
	_action("UI_RESTART", func() -> void: restart_pressed.emit())
	_action("UI_RECORDS", func() -> void: show_page(Page.RECORDS))
	_action("UI_TO_MENU", func() -> void: to_menu_pressed.emit())


func _build_settings() -> void:
	_caption("UI_SETTINGS")
	if settings != null:
		_level("UI_VOLUME_MASTER", Sounds.MASTER_BUS)
		_level("UI_VOLUME_MUSIC", Sounds.MUSIC_BUS)
		_level("UI_VOLUME_SFX", Sounds.SFX_BUS)
		_languages()
		_difficulty()
		_quality()
		_window_mode()
		_resolution()
		_render_scale()
		_blood()
		_fps()
	_gap(10.0)
	_back()


func _build_records() -> void:
	_caption("UI_RECORDS")
	var rows_shown := records.rows if records != null else [] as Array[Dictionary]
	if rows_shown.is_empty():
		_note(tr("UI_NO_RECORDS"))
	else:
		# Сеткой, а не строкой с пробелами: Exo 2 пропорциональный, и колонки
		# из пробелов у него разъезжаются.
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 48)
		grid.add_theme_constant_override("v_separation", 6)
		for index: int in rows_shown.size():
			var row := rows_shown[index]
			var tint := _neon() if index == 0 else NeonStyle.INK
			_cell(grid, "%d." % (index + 1), NeonStyle.INK_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
			_cell(grid, Hud.format_score(int(row[Records.SCORE])), tint, HORIZONTAL_ALIGNMENT_RIGHT)
			_cell(grid, String(row[Records.DATE]), NeonStyle.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		_column.add_child(grid)
	_gap(10.0)
	_back()


func _build_controls() -> void:
	_caption("UI_CONTROLS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 10)
	for row: Array in ACTIONS:
		var actions: Array[StringName] = []
		for action: Variant in row[1] as Array:
			actions.append(StringName(action))
		_cell(grid, tr(String(row[0])), NeonStyle.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		_cell(grid, _keys_of(actions), NeonStyle.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_column.add_child(grid)
	_gap(6.0)
	# Только клавиши, без объяснений игры: в неё разбираются по ходу, как в
	# любой другой (решение пользователя, ADR-0037, решение 9).
	_note(tr("UI_REBIND_LATER"))
	_gap(10.0)
	_back()


## Возвращает на страницу, с которой ушли, и записывает настройки на диск:
## громкость меняется по шагу, и сохранять её на каждый шаг значило бы писать
## файл двадцать раз за одно движение.
func _go_back() -> void:
	Sounds.play(Sounds.UI_BACK)
	if settings != null:
		settings.save_to()
	show_page(_back_to)


# --- Кирпичи -----------------------------------------------------------------


## Заголовок страницы неоновыми капителями — как подписи на плашках HUD.
func _caption(key: String) -> void:
	var label := NeonStyle.label(CAPTION_SIZE, _neon(), 700)
	label.text = tr(key).to_upper()
	_column.add_child(label)
	_gap(6.0)


func _note(text: String) -> void:
	var label := NeonStyle.label(22, NeonStyle.INK_DIM, 400)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(_column.custom_minimum_size.x, 0.0)
	_column.add_child(label)


func _cell(grid: GridContainer, text: String, colour: Color, align: HorizontalAlignment) -> void:
	var label := NeonStyle.label(TABLE_SIZE, colour, 600)
	label.text = text
	label.horizontal_alignment = align
	grid.add_child(label)


func _gap(height: float) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(gap)


func _action(key: String, action: Callable) -> MenuRow:
	var row := MenuRow.action(tr(key))
	row.pressed.connect(
		func() -> void:
			Sounds.play(Sounds.UI_SELECT)
			action.call()
	)
	return _add_row(row)


func _back() -> void:
	var row := MenuRow.action(tr("UI_BACK"), 34)
	row.pressed.connect(_go_back)
	_add_row(row)


func _add_row(row: MenuRow) -> MenuRow:
	row.neon = _neon()
	row.focus_entered.connect(_on_row_focused)
	row.changed.connect(func(_value: Variant) -> void: Sounds.play(Sounds.UI_MOVE))
	_column.add_child(row)
	return row


## Громкость: полоса и проценты, влево-вправо по пять.
func _level(key: String, bus: String) -> void:
	var row := _add_row(MenuRow.slider(tr(key), settings.level_of(bus)))
	# Громкость применяется сразу, а на диск уезжает при уходе со страницы.
	row.changed.connect(func(value: Variant) -> void: settings.set_level(bus, float(value)))


func _languages() -> void:
	var names: Array[String] = []
	var current := 0
	for index: int in GameSettings.LOCALES.size():
		var code := GameSettings.LOCALES[index]
		names.append(tr("UI_LANGUAGE_" + code.to_upper()))
		if code == settings.locale:
			current = index
	var row := _add_row(MenuRow.choice(tr("UI_LANGUAGE"), names, current))
	row.changed.connect(_on_language_selected)


## Уровень сложности: четыре положения DIP-переключателя автомата.
func _difficulty() -> void:
	var names: Array[String] = []
	for level: int in GameSettings.DIFFICULTIES:
		names.append(tr("UI_DIFFICULTY_%d" % level))
	var row := _add_row(MenuRow.choice(tr("UI_DIFFICULTY"), names, settings.difficulty))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.difficulty = int(value)
			settings.save_to()
	)


## Качество графики: четыре уровня (ADR-0030, решение 5; «Ультра» — ADR-0034).
func _quality() -> void:
	var names: Array[String] = []
	for level: int in Graphics.Quality.size():
		names.append(tr("UI_QUALITY_%d" % level))
	var row := _add_row(MenuRow.choice(tr("UI_QUALITY"), names, settings.quality))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.quality = int(value)
			# Выбрал игрок — замер первого запуска его уже не перебьёт.
			settings.quality_measured = true
			settings.apply()
			settings.save_to()
	)


## Режим окна: окно, без рамки, полный экран в родном разрешении.
func _window_mode() -> void:
	var names: Array[String] = []
	for mode: int in DisplayModes.Mode.size():
		names.append(tr("UI_WINDOW_MODE_%d" % mode))
	var row := _add_row(MenuRow.choice(tr("UI_WINDOW_MODE"), names, settings.window_mode))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.window_mode = int(value)
			settings.apply()
			settings.save_to()
	)


## Размер окна — из тех, что держит монитор игрока.
func _resolution() -> void:
	var area := DisplayModes.window_area().size
	var sizes := DisplayModes.available(area)
	var current := DisplayModes.nearest(settings.resolution, area)
	var names: Array[String] = []
	var selected := 0
	for index: int in sizes.size():
		names.append("%d × %d" % [sizes[index].x, sizes[index].y])
		if sizes[index] == current:
			selected = index
	var row := _add_row(MenuRow.choice(tr("UI_RESOLUTION"), names, selected))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.resolution = sizes[int(value)]
			settings.apply()
	)


## Масштаб 3D-рендера: на 4K слабая карта рисует сцену меньше, интерфейс — нет.
func _render_scale() -> void:
	var names: Array[String] = []
	# Отмечается ближайший масштаб, а не равный: в файле может стоять любой, и
	# без отметки список показывался пустым (авторевью M22).
	var closest := 0
	for index: int in DisplayModes.RENDER_SCALES.size():
		var share := DisplayModes.RENDER_SCALES[index]
		names.append("%d%%" % roundi(share * 100.0))
		var gap := absf(share - settings.render_scale)
		if gap < absf(DisplayModes.RENDER_SCALES[closest] - settings.render_scale):
			closest = index
	var row := _add_row(MenuRow.choice(tr("UI_RENDER_SCALE"), names, closest))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.render_scale = DisplayModes.RENDER_SCALES[int(value)]
			settings.apply()
	)


## Кровь при попадании пули — выключаемая, как принято в играх (ADR-0031).
func _blood() -> void:
	var row := _add_row(MenuRow.toggle(tr("UI_BLOOD"), settings.blood))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.blood = bool(value)
			settings.apply()
			settings.save_to()
	)


## Счётчик кадров в углу HUD.
func _fps() -> void:
	var row := _add_row(MenuRow.toggle(tr("UI_SHOW_FPS"), settings.show_fps))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.show_fps = bool(value)
			settings.apply()
			settings.save_to()
	)


## Клавиши и кнопки действий, как их видит [InputMap].
##
## Читается, но не меняется: переназначение отложено до после релиза (ADR-0012,
## пункт 10), а показать раскладку надо уже сейчас — иначе её негде узнать.
func _keys_of(actions: Array[StringName]) -> String:
	var keys: Array[String] = []
	var pads: Array[String] = []
	for action: StringName in actions:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				var label := OS.get_keycode_string(key.physical_keycode)
				if not keys.has(label):
					keys.append(label)
				continue
			var button := event as InputEventJoypadButton
			if button != null:
				var pad := String(PAD_NAMES.get(button.button_index, str(button.button_index)))
				if pad.begins_with("UI_"):
					pad = tr(pad)
				if not pads.has(pad):
					pads.append(pad)

	var parts: Array[String] = []
	if not keys.is_empty():
		parts.append(", ".join(keys))
	if not pads.is_empty():
		parts.append("%s: %s" % [tr("UI_GAMEPAD"), ", ".join(pads)])
	return "   ·   ".join(parts)


## Цвет неона: отеля, как у первого здания и у кромки HUD по умолчанию.
func _neon() -> Color:
	return Hud.DEFAULT_NEON


func _is_root(page: Page) -> bool:
	return page == Page.MAIN or page == Page.PAUSE or page == Page.GAME_OVER


## Колонка въезжает слева и проявляется — страница сменилась, а не мигнула.
func _slide_in() -> void:
	if _page_tween != null:
		_page_tween.kill()
	_column.modulate.a = 0.0
	_column.position.x = -PAGE_SLIDE
	_page_tween = create_tween()
	_page_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_page_tween.set_parallel(true)
	_page_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_tween.tween_property(_column, "modulate:a", 1.0, PAGE_TIME)
	_page_tween.tween_property(_column, "position:x", 0.0, PAGE_TIME)


func _style_static_labels() -> void:
	for label: Label in [_subtitle, _hint, _version]:
		label.add_theme_font_override("font", NeonStyle.font(600))
	_subtitle.text = tr("UI_SUBTITLE")


## Фокус на пункт [param at] страницы: иначе стрелками и геймпадом по меню не
## походить. Переход фокуса после этого снова звучит.
func _focus_row(at: int) -> void:
	var found := rows()
	if not found.is_empty():
		found[clampi(at, 0, found.size() - 1)].grab_focus()
	_settling = false


func _collect_rows(parent: Node, found: Array[MenuRow]) -> void:
	for child: Node in parent.get_children():
		var row := child as MenuRow
		if row != null:
			found.append(row)
		_collect_rows(child, found)


func _on_row_focused() -> void:
	if not _settling:
		Sounds.play(Sounds.UI_MOVE)


func _on_language_selected(index: Variant) -> void:
	settings.locale = GameSettings.LOCALES[int(index)]
	settings.apply()
	settings.save_to()
	# Страница перерисовывается целиком: подписи собраны кодом, и сами
	# они на смену языка не отзовутся. Фокус остаётся на языке: с первого пункта
	# следующее «вправо» крутило бы уже громкость (авторевью M22b).
	var keep := rows().find(get_viewport().gui_get_focus_owner() as MenuRow)
	_subtitle.text = tr("UI_SUBTITLE")
	show_page(_page, maxi(keep, 0))
