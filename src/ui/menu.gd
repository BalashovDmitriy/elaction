class_name Menu
extends CanvasLayer

## Экраны вне игры: меню, пауза, конец партии, настройки, рекорды, управление.
##
## Один узел на все страницы, а не сцена на каждую: страницы отличаются только
## содержимым одной колонки, и держать ради этого шесть файлов значило бы шесть
## раз повторить рамку, затемнение и разбор ввода.
##
## Содержимое собирается кодом, потому что оно данные: список кнопок, список
## ползунков, список строк таблицы. Разметка в сцене — только рамка вокруг.

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
## ничего не говорит — на коробке написаны буквы.
##
## Значения, начинающиеся с `UI_`, переводятся: у крестовины имени на коробке
## нет, а рисовать стрелки нечем — в пиксельном шрифте их просто не оказалось.
## Все четыре её направления сводятся в одно слово, и в строке оно одно.
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

@onready var _column: VBoxContainer = %Page
@onready var _version: Label = %Version


func _ready() -> void:
	# Меню живёт на паузе: под ней оно и открывается.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Версия в углу — чтобы игрок мог назвать её, не открывая свойства файла.
	_version.text = Release.tag()


## Показывает страницу и забирает фокус на первую кнопку: иначе стрелками
## и геймпадом по меню не походить.
func show_page(page: Page) -> void:
	_page = page
	if page == Page.MAIN or page == Page.PAUSE or page == Page.GAME_OVER:
		# Корневые страницы — те, с которых уходят в подстраницы. Последняя из них
		# и есть то, куда вернёт «назад».
		_back_to = page
	visible = true
	for child: Node in _column.get_children():
		# Сначала из колонки, потом в утиль: [method Node.queue_free] удаляет узел
		# лишь в конце кадра, а отложенный [method _focus_first] успевает раньше —
		# и фокус доставался кнопке прошлой страницы, которую тут же и удаляли.
		_column.remove_child(child)
		child.queue_free()

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

	_focus_first.call_deferred()


## Прячет меню целиком — игра продолжается.
func close() -> void:
	visible = false


## Запоминает итог партии для экрана конца.
func remember(score: int, place: int) -> void:
	_last_score = score
	_last_place = place


func current_page() -> Page:
	return _page


# --- Страницы ----------------------------------------------------------------


func _build_main() -> void:
	_title("UI_TITLE")
	_note("UI_SUBTITLE")
	_button("UI_PLAY", func() -> void: play_pressed.emit())
	_button("UI_RECORDS", func() -> void: show_page(Page.RECORDS))
	_button("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	_button("UI_CONTROLS", func() -> void: show_page(Page.CONTROLS))
	_button("UI_QUIT", func() -> void: quit_pressed.emit())


func _build_pause() -> void:
	_title("UI_PAUSED")
	_button("UI_RESUME", func() -> void: resume_pressed.emit())
	_button("UI_RESTART", func() -> void: restart_pressed.emit())
	_button("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	_button("UI_TO_MENU", func() -> void: to_menu_pressed.emit())


func _build_game_over() -> void:
	_title("UI_GAME_OVER")
	_note_text("%s %s" % [tr("UI_YOUR_SCORE"), Hud.format_score(_last_score)])
	if _last_place >= 0:
		var record := Label.new()
		record.text = "%s  #%d" % [tr("UI_NEW_RECORD"), _last_place + 1]
		record.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		record.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
		_column.add_child(record)

	_button("UI_RESTART", func() -> void: restart_pressed.emit())
	_button("UI_RECORDS", func() -> void: show_page(Page.RECORDS))
	_button("UI_TO_MENU", func() -> void: to_menu_pressed.emit())


func _build_settings() -> void:
	_title("UI_SETTINGS")
	if settings != null:
		_slider("UI_VOLUME_MASTER", Sounds.MASTER_BUS)
		_slider("UI_VOLUME_MUSIC", Sounds.MUSIC_BUS)
		_slider("UI_VOLUME_SFX", Sounds.SFX_BUS)
		_languages()
		_difficulty()
		_quality()
		_fullscreen()
		_blood()
	_button("UI_BACK", _go_back)


func _build_records() -> void:
	_title("UI_RECORDS")
	var rows := records.rows if records != null else [] as Array[Dictionary]
	if rows.is_empty():
		_note("UI_NO_RECORDS")
	for index: int in rows.size():
		var row := rows[index]
		var line := Label.new()
		line.text = (
			"%2d.  %10s   %s"
			% [index + 1, Hud.format_score(int(row[Records.SCORE])), String(row[Records.DATE])]
		)
		line.add_theme_font_size_override("font_size", 12)
		_column.add_child(line)
	_button("UI_BACK", _go_back)


func _build_controls() -> void:
	_title("UI_CONTROLS")
	for row: Array in ACTIONS:
		var actions: Array[StringName] = []
		for action: Variant in row[1] as Array:
			actions.append(StringName(action))
		_two_columns(tr(String(row[0])), _keys_of(actions))

	_note("UI_ACTION_HINT")
	_note("UI_REBIND_LATER")
	_button("UI_BACK", _go_back)


## Возвращает на страницу, с которой ушли, и записывает настройки на диск:
## громкость меняется ползунком по шагу, и сохранять её на каждый шаг значило бы
## писать файл двадцать раз за одно движение мышью.
func _go_back() -> void:
	if settings != null:
		settings.save_to()
	show_page(_back_to)


# --- Кирпичи -----------------------------------------------------------------


func _title(key: String) -> void:
	var label := Label.new()
	label.text = tr(key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	_column.add_child(label)


## Пояснение под заголовком по ключу перевода.
func _note(key: String) -> void:
	_note_text(tr(key))


## То же, но готовой строкой: на экране конца партии подпись собрана из перевода
## и счёта, и переводить её второй раз нечего.
func _note_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(300.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	_column.add_child(label)


func _button(key: String, action: Callable) -> void:
	var button := Button.new()
	button.text = tr(key)
	button.flat = true
	button.pressed.connect(action)
	_column.add_child(button)


## Строка настройки с подписью слева: ползунок, язык, сложность. Сам элемент
## кладёт в неё зовущий, а в колонку она уже вставлена.
func _setting_row(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = tr(key)
	label.custom_minimum_size = Vector2(150.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	_column.add_child(row)
	return row


## Ползунок громкости: подпись и ручка в строку.
func _slider(key: String, bus: String) -> void:
	var row := _setting_row(key)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = settings.level_of(bus)
	slider.custom_minimum_size = Vector2(160.0, 0.0)
	slider.value_changed.connect(func(value: float) -> void: _on_level_changed(bus, value))
	row.add_child(slider)


func _languages() -> void:
	var row := _setting_row("UI_LANGUAGE")
	var choice := OptionButton.new()
	for index: int in GameSettings.LOCALES.size():
		var code := GameSettings.LOCALES[index]
		choice.add_item(tr("UI_LANGUAGE_" + code.to_upper()), index)
		if code == settings.locale:
			choice.select(index)
	choice.item_selected.connect(_on_language_selected)
	row.add_child(choice)


## Уровень сложности: четыре положения DIP-переключателя автомата.
func _difficulty() -> void:
	var row := _setting_row("UI_DIFFICULTY")
	var choice := OptionButton.new()
	for level: int in GameSettings.DIFFICULTIES:
		choice.add_item(tr("UI_DIFFICULTY_%d" % level), level)
	choice.select(settings.difficulty)
	choice.item_selected.connect(_on_difficulty_selected)
	row.add_child(choice)


## Качество графики: три уровня (ADR-0030, решение 5).
func _quality() -> void:
	var row := _setting_row("UI_QUALITY")
	var choice := OptionButton.new()
	for level: int in Graphics.Quality.size():
		choice.add_item(tr("UI_QUALITY_%d" % level), level)
	choice.select(settings.quality)
	choice.item_selected.connect(_on_quality_selected)
	row.add_child(choice)


func _fullscreen() -> void:
	var toggle := CheckButton.new()
	toggle.text = tr("UI_FULLSCREEN")
	toggle.button_pressed = settings.fullscreen
	toggle.toggled.connect(_on_fullscreen_toggled)
	_column.add_child(toggle)


## Строка в две колонки: подпись слева, клавиши справа. Колонка шире подписи
## самого длинного действия, иначе строки едут друг относительно друга.
func _two_columns(left: String, right: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label := Label.new()
	label.text = left
	label.custom_minimum_size = Vector2(110.0, 0.0)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var keys := Label.new()
	keys.text = right
	keys.add_theme_font_size_override("font_size", 12)
	keys.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	row.add_child(keys)

	_column.add_child(row)


## Клавиши и кнопки действий, как их видит [InputMap].
##
## Читается, но не меняется: переназначение отложено до M9 (ADR-0012, пункт 10),
## а показать раскладку надо уже сейчас — иначе её негде узнать.
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
		parts.append("%s: %s" % [tr("UI_KEYBOARD"), ", ".join(keys)])
	if not pads.is_empty():
		parts.append("%s: %s" % [tr("UI_GAMEPAD"), ", ".join(pads)])
	return "   ".join(parts)


## Фокус на первый управляемый элемент страницы: иначе стрелками и геймпадом
## по меню не походить.
##
## Обход вглубь и по любому фокусируемому [Control], а не по кнопкам верхнего
## уровня: на настройках первым стоит ползунок, и лежит он внутри строки —
## поиск одних кнопок перепрыгивал через полстраницы к «полному экрану».
func _focus_first() -> void:
	_focus_within(_column)


func _focus_within(parent: Node) -> bool:
	for child: Node in parent.get_children():
		var control := child as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return true
		if _focus_within(child):
			return true
	return false


## Громкость применяется сразу, а на диск уезжает при уходе со страницы:
## ползунок шлёт значение на каждый шаг, и файл писался бы двадцать раз за
## одно движение мышью.
func _on_level_changed(bus: String, value: float) -> void:
	settings.set_level(bus, value)


func _on_language_selected(index: int) -> void:
	settings.locale = GameSettings.LOCALES[index]
	settings.apply()
	settings.save_to()
	# Страница перерисовывается целиком: подписи собраны кодом, и сами
	# они на смену языка не отзовутся.
	show_page(_page)


func _on_difficulty_selected(index: int) -> void:
	settings.difficulty = index
	settings.save_to()


## Кровь при попадании пули — выключаемая, как принято в играх (ADR-0031).
func _blood() -> void:
	var toggle := CheckButton.new()
	toggle.text = tr("UI_BLOOD")
	toggle.button_pressed = settings.blood
	toggle.toggled.connect(_on_blood_toggled)
	_column.add_child(toggle)


func _on_blood_toggled(pressed: bool) -> void:
	settings.blood = pressed
	settings.apply()
	settings.save_to()


func _on_quality_selected(index: int) -> void:
	settings.quality = index
	# Выбрал игрок — замер первого запуска его уже не перебьёт.
	settings.quality_measured = true
	settings.apply()
	settings.save_to()


func _on_fullscreen_toggled(pressed: bool) -> void:
	settings.fullscreen = pressed
	settings.apply()
	settings.save_to()
