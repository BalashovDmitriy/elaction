extends GutTest

## Переназначение клавиш (ADR-0039, решение 7).

var _saved: Dictionary = {}


func before_each() -> void:
	# [method KeyBindings.apply] меняет [InputMap] всего процесса: после теста
	# он обязан вернуться, иначе соседние тесты жали бы не те клавиши.
	_saved.clear()
	for action: StringName in KeyBindings.ACTIONS:
		_saved[action] = InputMap.action_get_events(action)


func after_each() -> void:
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)


func test_defaults_match_the_first_keys_of_the_project() -> void:
	# Схема по умолчанию — не своя придумка, а то, что уже стоит в project.godot:
	# иначе игрок без файла настроек и с ним играл бы разными клавишами.
	for action: StringName in KeyBindings.ACTIONS:
		var key := -1
		var pad := -1
		for event: InputEvent in _saved[action]:
			if event is InputEventKey and key < 0:
				key = (event as InputEventKey).physical_keycode
			if event is InputEventJoypadButton and pad < 0:
				pad = (event as InputEventJoypadButton).button_index
		assert_eq(key, int(KeyBindings.DEFAULT_KEYS[action]), "%s: клавиша проекта" % action)
		assert_eq(pad, int(KeyBindings.DEFAULT_PADS[action]), "%s: кнопка проекта" % action)


func test_a_free_key_is_simply_bound() -> void:
	var bindings := KeyBindings.new()
	assert_true(bindings.bind_key(&"jump", KEY_C), "свободная клавиша берётся")
	assert_eq(bindings.key_of(&"jump"), KEY_C, "прыжок на C")
	assert_false(bindings.is_default(), "схема уже не по умолчанию")


func test_a_taken_key_swaps_places() -> void:
	var bindings := KeyBindings.new()
	var old_jump := bindings.key_of(&"jump")
	assert_true(bindings.bind_key(&"jump", bindings.key_of(&"shoot")), "занятая берётся")
	assert_eq(
		bindings.key_of(&"jump"), KeyBindings.DEFAULT_KEYS[&"shoot"], "прыжок на клавише выстрела"
	)
	assert_eq(bindings.key_of(&"shoot"), old_jump, "выстрел — на прежней клавише прыжка")


func test_a_taken_pad_button_swaps_places() -> void:
	var bindings := KeyBindings.new()
	assert_true(bindings.bind_pad(&"shoot", JOY_BUTTON_A), "кнопка прыжка на выстрел")
	assert_eq(bindings.pad_of(&"shoot"), JOY_BUTTON_A, "выстрел на A")
	assert_eq(bindings.pad_of(&"jump"), JOY_BUTTON_X, "прыжок — на прежней кнопке выстрела")


func test_no_action_is_ever_left_without_a_key() -> void:
	# Цепочка обменов — всё равно перестановка: сколько бы игрок ни назначал,
	# у шести действий шесть разных клавиш.
	var bindings := KeyBindings.new()
	var keys: Array[Key] = [KEY_X, KEY_LEFT, KEY_A, KEY_SPACE, KEY_UP, KEY_A, KEY_DOWN]
	for step: int in keys.size():
		bindings.bind_key(KeyBindings.ACTIONS[step % KeyBindings.ACTIONS.size()], keys[step])
	var seen := {}
	for action: StringName in KeyBindings.ACTIONS:
		assert_ne(bindings.key_of(action), KEY_NONE, "%s с клавишей" % action)
		seen[bindings.key_of(action)] = true
	assert_eq(seen.size(), KeyBindings.ACTIONS.size(), "и все клавиши разные")


func test_pause_and_screenshot_keys_are_not_taken() -> void:
	var bindings := KeyBindings.new()
	assert_false(bindings.bind_key(&"jump", KEY_ESCAPE), "Esc — пауза, не отдаётся")
	assert_false(bindings.bind_key(&"jump", KEY_F12), "F12 — скриншот")
	assert_false(bindings.bind_pad(&"jump", JOY_BUTTON_START), "Start — пауза")
	assert_true(bindings.is_default(), "схема не тронута")


func test_pause_is_not_rebindable() -> void:
	var bindings := KeyBindings.new()
	assert_false(bindings.bind_key(&"pause", KEY_P), "паузу не переназначить")


func test_reset_restores_the_defaults() -> void:
	var bindings := KeyBindings.new()
	bindings.bind_key(&"jump", KEY_C)
	bindings.bind_pad(&"shoot", JOY_BUTTON_Y)
	bindings.reset()
	assert_true(bindings.is_default(), "после сброса — по умолчанию")


func test_the_scheme_survives_a_save_and_load() -> void:
	var bindings := KeyBindings.new()
	bindings.bind_key(&"move_left", KEY_A)
	bindings.bind_pad(&"jump", JOY_BUTTON_B)
	var file := ConfigFile.new()
	bindings.write_to(file)
	var loaded := KeyBindings.read_from(file)
	assert_eq(loaded.key_of(&"move_left"), KEY_A, "клавиша прочитана")
	assert_eq(loaded.pad_of(&"jump"), JOY_BUTTON_B, "кнопка прочитана")


func test_a_broken_file_falls_back_to_defaults() -> void:
	var file := ConfigFile.new()
	KeyBindings.new().write_to(file)
	# Две клавиши на одно место: так файл не пишет, но руками поправить можно.
	file.set_value(KeyBindings.SECTION, "key_jump", KEY_X)
	assert_true(KeyBindings.read_from(file).is_default(), "дубль — схема по умолчанию")
	file.set_value(KeyBindings.SECTION, "key_jump", KEY_ESCAPE)
	assert_true(KeyBindings.read_from(file).is_default(), "закреплённая — тоже")
	assert_true(KeyBindings.read_from(ConfigFile.new()).is_default(), "нет секции — тоже")


func test_apply_leaves_one_key_one_button_and_the_stick() -> void:
	var bindings := KeyBindings.new()
	bindings.bind_key(&"move_left", KEY_A)
	bindings.apply()
	var keys := 0
	var buttons := 0
	var axes := 0
	for event: InputEvent in InputMap.action_get_events(&"move_left"):
		if event is InputEventKey:
			keys += 1
			assert_eq((event as InputEventKey).physical_keycode, KEY_A, "клавиша — назначенная")
		elif event is InputEventJoypadButton:
			buttons += 1
		elif event is InputEventJoypadMotion:
			axes += 1
	assert_eq(keys, 1, "одна клавиша")
	assert_eq(buttons, 1, "одна кнопка")
	assert_eq(axes, 1, "и стик на месте")
