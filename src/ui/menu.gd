class_name Menu
extends CanvasLayer

## Out-of-game screens: menu, pause, game over, settings, high scores, controls.
##
## One node for all pages, not a scene for each: the pages differ only in
## the contents of one column, and keeping six files for that would mean repeating the
## background, the sign and input handling six times.
##
## The contents are built in code because they are data: a list of items, a list of
## switches, table rows. The layout in the scene is only the background, the sign and
## the column (ADR-0035).

## What the player chose. It is decided not by the menu but by [Main]: it knows about the
## building and the game.
signal play_pressed
signal resume_pressed
signal restart_pressed
signal to_menu_pressed
signal quit_pressed

enum Page { MAIN, PAUSE, GAME_OVER, SETTINGS, RECORDS, CONTROLS, CREDITS }

## Labels of the controls screen actions. The actions themselves and their order belong
## to [KeyBindings]; labels cannot be obtained from [InputMap], so they are here. Crouch
## is the same "down", and the label says so instead of adding a duplicate row.
const ACTION_NAMES: Dictionary = {
	&"move_left": "UI_MOVE_LEFT",
	&"move_right": "UI_MOVE_RIGHT",
	&"move_up": "UI_MOVE_UP",
	&"move_down": "UI_MOVE_DOWN",
	&"jump": "UI_JUMP",
	&"shoot": "UI_SHOOT",
}

## Gamepad button names. In [InputMap] they are stored as numbers, and a number tells the
## player nothing: the box has letters printed on it. Values starting with
## `UI_` are translated: the D-pad has no name on the box. None of the game's fonts
## has arrows (M22b debt), so the direction is given as a word.
const PAD_NAMES: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_DPAD_UP: "UI_DPAD_UP",
	JOY_BUTTON_DPAD_DOWN: "UI_DPAD_DOWN",
	JOY_BUTTON_DPAD_LEFT: "UI_DPAD_LEFT",
	JOY_BUTTON_DPAD_RIGHT: "UI_DPAD_RIGHT",
}

## Column width: items and settings, px.
const COLUMN_WIDTH: float = 560.0
const WIDE_COLUMN: float = 900.0
## How long a page change lasts and how far the column slides in from the left.
const PAGE_TIME: float = 0.22
const PAGE_SLIDE: float = 36.0
## Where the column starts: below the sign on the main page and higher on the others:
## the settings need the full screen height.
const COLUMN_TOP: float = 340.0
const COLUMN_TOP_HIGH: float = 110.0
## Font size of the page title and table rows.
const CAPTION_SIZE: int = 28
const TABLE_SIZE: int = 30

var settings: GameSettings = null
var records: Records = null

## Score of the last game and its place in the table: shown on the game-over screen.
var _last_score: int = 0
var _last_place: int = -1

var _page: Page = Page.MAIN

## The page "back" returns to. It is remembered, not guessed from the pause:
## after a game that made it into the table, the tree is also paused, and by that sign
## alone "back" from the high scores led from the game-over screen to the pause.
var _back_to: Page = Page.MAIN

## While a page is being built and takes focus, the focus change makes no sound:
## otherwise every page would open with a click the player did not make.
var _settling: bool = false
var _page_tween: Tween = null
## The action the controls screen is waiting for a key for right now, and its item.
## Empty means nobody is waiting.
var _listening: StringName = &""
var _listen_row: MenuRow = null

@onready var _column: VBoxContainer = %Page
@onready var _version: Label = %Version
@onready var _title: NeonTitle = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _hint: Label = %Hint
@onready var _blur: ColorRect = %Blur
@onready var _slot: Control = %Slot


func _ready() -> void:
	# The menu lives on pause: it opens under the pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The version in the corner, so that the player can name it without opening the file
	# properties.
	_version.text = Release.tag()
	_style_static_labels()


## The subtitle is translated in code, and the saved language is applied after the menu is
## ready: without following the change, a restart showed it in the system language
## (ADR-0060).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _subtitle != null:
		_subtitle.text = tr("UI_SUBTITLE")


## Shows a page and takes focus to item [param focus], usually the first one:
## otherwise you cannot move around the menu with the arrows and a gamepad.
func show_page(page: Page, focus: int = 0) -> void:
	_page = page
	_listening = &""
	_listen_row = null
	if page == Page.MAIN or page == Page.PAUSE or page == Page.GAME_OVER:
		# Root pages are the ones subpages are entered from. The last of them
		# is where "back" returns to.
		_back_to = page
	visible = true
	_settling = true
	for child: Node in _column.get_children():
		# First out of the column, then to the trash: [method Node.queue_free] deletes the node
		# only at the end of the frame, and the deferred [method _focus_row] gets there earlier,
		# so focus went to an item of the previous page, which was being deleted right then.
		_column.remove_child(child)
		child.queue_free()

	# Over the game (the pause and game over with their subpages) a frozen building stands
	# behind the menu, and it is blurred. From the main menu the city is behind it.
	var over_game := _back_to != Page.MAIN
	_blur.visible = over_game
	_title.visible = page == Page.MAIN
	_subtitle.visible = page == Page.MAIN
	# "Esc: back" only where Esc really leads back: root pages are left
	# through items, and on the pause Esc closes it.
	_hint.text = tr("UI_HINT_ROOT" if _is_root(page) else "UI_HINT")
	var wide := (
		page == Page.SETTINGS
		or page == Page.CONTROLS
		or page == Page.RECORDS
		or page == Page.CREDITS
	)
	_column.custom_minimum_size.x = WIDE_COLUMN if wide else COLUMN_WIDTH
	# The container does not shrink by itself: after the wide settings a narrow page would
	# stay the width of the settings, and the items would stretch across half the screen.
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
		Page.CREDITS:
			_build_credits()

	_slide_in()
	_focus_row.call_deferred(focus)


## Keeps the page items disabled for [param seconds] seconds: a press
## started while still in the game must not select an item (ADR-0042, decision 5). Focus
## stays in place: a disabled item holds it instead of giving it away.
func hold_rows(seconds: float) -> void:
	var held := rows()
	for row: MenuRow in held:
		row.disabled = true
	var page := _page
	await get_tree().create_timer(seconds, true, false, true).timeout
	for row: MenuRow in held:
		if is_instance_valid(row) and _page == page:
			row.disabled = false


## Hides the menu entirely: the game continues.
func close() -> void:
	visible = false


## Remembers the game result for the game-over screen.
func remember(score: int, place: int) -> void:
	_last_score = score
	_last_place = place


func current_page() -> Page:
	return _page


## Items of the current page, for those who drive the menu from outside: tests and shots.
func rows() -> Array[MenuRow]:
	var found: Array[MenuRow] = []
	_collect_rows(_column, found)
	return found


## The sign: tests and shots need it to stop the flicker.
func title() -> NeonTitle:
	return _title


## A pending assignment takes the next press before the menu focus sees it:
## otherwise the arrow being assigned would move to the neighboring item.
func _input(event: InputEvent) -> void:
	if not visible or _listening == &"":
		return
	var key := event as InputEventKey
	var button := event as InputEventJoypadButton
	if key != null and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		if key.physical_keycode == KEY_ESCAPE:
			_stop_listening()
		else:
			_bound(settings.bindings.bind_key(_listening, key.physical_keycode))
	elif button != null and button.pressed:
		get_viewport().set_input_as_handled()
		if button.button_index == JOY_BUTTON_START:
			_stop_listening()
		else:
			_bound(settings.bindings.bind_pad(_listening, button.button_index))


## Whether the controls screen is waiting for a key right now. For tests.
func is_listening() -> bool:
	return _listening != &""


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# "Back" from a subpage is Esc or B. Root pages are left only through
	# items: the pause is closed by its own action, and [Main] decides that.
	if event.is_action_pressed(&"ui_cancel") and not _is_root(_page):
		get_viewport().set_input_as_handled()
		_go_back()


# --- Pages -------------------------------------------------------------------


func _build_main() -> void:
	_action("UI_PLAY", func() -> void: play_pressed.emit())
	_action("UI_RECORDS", func() -> void: show_page(Page.RECORDS))
	_action("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	_action("UI_CONTROLS", func() -> void: show_page(Page.CONTROLS))
	_action("UI_CREDITS", func() -> void: show_page(Page.CREDITS))
	_action("UI_QUIT", func() -> void: quit_pressed.emit())


func _build_pause() -> void:
	_caption("UI_PAUSED")
	_action("UI_RESUME", func() -> void: resume_pressed.emit())
	_action("UI_RESTART", func() -> void: restart_pressed.emit())
	_action("UI_SETTINGS", func() -> void: show_page(Page.SETTINGS))
	# Help is available from the pause too: from the main menu it could not be found
	# (ADR-0037, decision 9).
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
		_frame_limit()
		_vsync()
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
		# A grid, not a line with spaces: Exo 2 is proportional, and columns
		# made of spaces drift apart in it.
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


## Authors of third-party models, textures, sounds and fonts, from `CREDITS.md` via
## [Credits] (ADR-0042, decision 6). Per section, a line of names with licenses.
## The credits page is in English only, in any game language (the user's request,
## 2026-10-01): both translation columns of its keys are English.
func _build_credits() -> void:
	_caption("UI_CREDITS_TITLE")
	# First the author of the idea and development, then the original the remake is based on,
	# then the authors of the assets from `CREDITS.md`.
	_credit_line(tr("UI_CREDITS_CREATOR"), tr("UI_CREDITS_CREATOR_NAME"))
	_credit_line(tr("UI_CREDITS_ORIGINAL"), tr("UI_CREDITS_ORIGINAL_NAME"))
	_gap(10.0)
	_note(tr("UI_CREDITS_ABOUT"))
	for section: Credits.Section in Credits.load_sections():
		_credit_line(tr(section.key), section.line())
	_gap(10.0)
	_back()


## A section heading of the "Credits" page and the line of names under it.
func _credit_line(title: String, line: String) -> void:
	var heading := NeonStyle.label(20, _neon(), 700)
	heading.text = title.to_upper()
	_column.add_child(heading)
	var names := NeonStyle.label(19, NeonStyle.INK, 500)
	names.text = line
	names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.custom_minimum_size = Vector2(_column.custom_minimum_size.x, 0.0)
	_column.add_child(names)


func _build_controls() -> void:
	_caption("UI_CONTROLS")
	if settings == null:
		_back()
		return
	# One row per action: press it, the row waits for a key or a button, and the first
	# one pressed takes its place (ADR-0039, decision 7). Keys only, no
	# explanations of the game (the user's decision, ADR-0037, decision 9).
	for action: StringName in KeyBindings.ACTIONS:
		var row := _add_row(
			MenuRow.binding(tr(String(ACTION_NAMES[action])), _binding_text(action))
		)
		row.pressed.connect(_listen.bind(action, row))
	# Pause is fixed: without it you cannot leave the game if you assign the wrong thing.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	_cell(grid, tr("UI_PAUSE"), NeonStyle.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_cell(grid, "Esc   ·   %s: Start" % tr("UI_GAMEPAD"), NeonStyle.INK, HORIZONTAL_ALIGNMENT_LEFT)
	_column.add_child(grid)
	_gap(6.0)
	_action("UI_RESET_KEYS", _reset_keys)
	_gap(10.0)
	_back()


## The action's key and button, as the scheme sees them.
func _binding_text(action: StringName) -> String:
	var bindings := settings.bindings
	var pad := String(PAD_NAMES.get(bindings.pad_of(action), str(bindings.pad_of(action))))
	if pad.begins_with("UI_"):
		pad = tr(pad)
	return "%s   ·   %s" % [OS.get_keycode_string(bindings.key_of(action)), pad]


func _listen(action: StringName, row: MenuRow) -> void:
	Sounds.play(Sounds.UI_SELECT)
	if _listen_row != null:
		_listen_row.show_text(_binding_text(_listening))
	_listening = action
	_listen_row = row
	row.show_text(tr("UI_PRESS_KEY"))


## Whether the assignment went through or not: the scheme goes to disk and into
## [InputMap], the rows are rebuilt. A swap also changes another row, so all are rewritten.
func _bound(taken: bool) -> void:
	Sounds.play(Sounds.UI_MOVE if taken else Sounds.UI_BACK)
	if taken:
		settings.bindings.apply()
		settings.save_to()
	_stop_listening()


func _stop_listening() -> void:
	_listening = &""
	_listen_row = null
	var index := 0
	for row: MenuRow in rows():
		if row.kind == MenuRow.Kind.BINDING:
			row.show_text(_binding_text(KeyBindings.ACTIONS[index]))
			index += 1


func _reset_keys() -> void:
	settings.bindings.reset()
	settings.bindings.apply()
	settings.save_to()
	_stop_listening()


## Returns to the page we came from and writes the settings to disk:
## volume changes in steps, and saving it on every step would mean writing
## the file twenty times for a single movement.
func _go_back() -> void:
	Sounds.play(Sounds.UI_BACK)
	if settings != null:
		settings.save_to()
	show_page(_back_to)


# --- Building blocks ---------------------------------------------------------


## The page title in neon small caps, like the labels on the HUD plates.
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


## Volume: a bar and percent, left and right in steps of five.
func _level(key: String, bus: String) -> void:
	var row := _add_row(MenuRow.slider(tr(key), settings.level_of(bus)))
	# Volume applies at once and goes to disk when leaving the page.
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


## Difficulty level: the four positions of the cabinet's DIP switch.
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


## Graphics quality: four levels (ADR-0030, decision 5; "Ultra" is ADR-0034).
func _quality() -> void:
	var names: Array[String] = []
	for level: int in Graphics.Quality.size():
		names.append(tr("UI_QUALITY_%d" % level))
	var row := _add_row(MenuRow.choice(tr("UI_QUALITY"), names, settings.quality))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.quality = int(value)
			# The player chose: the first-launch measurement will no longer override it.
			settings.quality_measured = true
			settings.apply()
			settings.save_to()
	)


## Window mode: windowed, borderless, fullscreen at the native resolution.
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
			# The list of resolutions depends on the mode ([method DisplayModes.choices]):
			# the page is rebuilt, focus stays on the mode: otherwise in fullscreen
			# the native non-standard one could not be chosen, and in a window it would remain.
			show_page(_page, rows().find(row))
	)


## Window size, from those the player's monitor supports; in fullscreen and borderless,
## the 3D resolution ([method DisplayModes.share]).
func _resolution() -> void:
	var area := DisplayModes.screen_rect().size
	var mode := settings.window_mode as DisplayModes.Mode
	var sizes := DisplayModes.choices(mode, area)
	var current := (
		settings.resolution
		if sizes.has(settings.resolution)
		else DisplayModes.nearest(settings.resolution, area)
	)
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
			settings.save_to()
	)


## Frame limit: by monitor, a number or unlimited. Monitor refresh rates are not in
## the list: Godot neither enumerates nor changes them
## ([constant DisplayModes.FRAME_LIMITS]).
func _frame_limit() -> void:
	var names: Array[String] = []
	for limit: int in DisplayModes.FRAME_LIMITS:
		names.append(frame_limit_name(limit))
	var current := maxi(DisplayModes.FRAME_LIMITS.find(settings.frame_limit), 0)
	var row := _add_row(MenuRow.choice(tr("UI_FRAME_LIMIT"), names, current))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.frame_limit = DisplayModes.FRAME_LIMITS[int(value)]
			settings.apply()
			settings.save_to()
	)


## Frame limit label: numbers like the counter in the HUD corner, "144 FPS".
func frame_limit_name(limit: int) -> String:
	match limit:
		DisplayModes.FRAME_MONITOR:
			return tr("UI_FRAME_LIMIT_MONITOR")
		DisplayModes.FRAME_UNLIMITED:
			return tr("UI_FRAME_LIMIT_NONE")
		_:
			return "%d FPS" % limit


## Vertical sync: without it there are more frames, but tearing happens.
func _vsync() -> void:
	var row := _add_row(MenuRow.toggle(tr("UI_VSYNC"), settings.vsync))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.vsync = bool(value)
			settings.apply()
			settings.save_to()
	)


## Blood on a bullet hit: can be turned off, as is customary in games (ADR-0031).
func _blood() -> void:
	var row := _add_row(MenuRow.toggle(tr("UI_BLOOD"), settings.blood))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.blood = bool(value)
			settings.apply()
			settings.save_to()
	)


## The frame counter in the HUD corner.
func _fps() -> void:
	var row := _add_row(MenuRow.toggle(tr("UI_SHOW_FPS"), settings.show_fps))
	row.changed.connect(
		func(value: Variant) -> void:
			settings.show_fps = bool(value)
			settings.apply()
			settings.save_to()
	)


## Neon color: the hotel one, as for the first building and the HUD edge by default.
func _neon() -> Color:
	return Hud.DEFAULT_NEON


func _is_root(page: Page) -> bool:
	return page == Page.MAIN or page == Page.PAUSE or page == Page.GAME_OVER


## The column slides in from the left and fades in: the page changed rather than blinked.
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


## Focus to item [param at] of the page: otherwise you cannot move around the menu with
## the arrows and a gamepad. After this, focus changes make sound again.
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
	# The page is redrawn entirely: the labels are built in code, and they
	# will not respond to a language change by themselves. Focus stays on the language: from
	# the first item the next "right" would already turn the volume (M22b code review).
	var keep := rows().find(get_viewport().gui_get_focus_owner() as MenuRow)
	show_page(_page, maxi(keep, 0))
