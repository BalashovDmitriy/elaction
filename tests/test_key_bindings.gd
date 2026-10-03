extends GutTest

## Key rebinding (ADR-0039, decision 7).

var _saved: Dictionary = {}


func before_each() -> void:
	# [method KeyBindings.apply] changes the [InputMap] of the whole process: after the test
	# it must be restored, otherwise neighbouring tests would press the wrong keys.
	_saved.clear()
	for action: StringName in KeyBindings.ACTIONS:
		_saved[action] = InputMap.action_get_events(action)


func after_each() -> void:
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)


func test_defaults_match_the_first_keys_of_the_project() -> void:
	# The default scheme is not our own invention but what is already in project.godot:
	# otherwise a player without a settings file and with one would play with different keys.
	for action: StringName in KeyBindings.ACTIONS:
		var key := -1
		var pad := -1
		for event: InputEvent in _saved[action]:
			if event is InputEventKey and key < 0:
				key = (event as InputEventKey).physical_keycode
			if event is InputEventJoypadButton and pad < 0:
				pad = (event as InputEventJoypadButton).button_index
		assert_eq(key, int(KeyBindings.DEFAULT_KEYS[action]), "%s: project key" % action)
		assert_eq(pad, int(KeyBindings.DEFAULT_PADS[action]), "%s: project button" % action)


func test_a_free_key_is_simply_bound() -> void:
	var bindings := KeyBindings.new()
	assert_true(bindings.bind_key(&"jump", KEY_C), "a free key is taken")
	assert_eq(bindings.key_of(&"jump"), KEY_C, "jump on C")
	assert_false(bindings.is_default(), "the scheme is no longer the default")


func test_a_taken_key_swaps_places() -> void:
	var bindings := KeyBindings.new()
	var old_jump := bindings.key_of(&"jump")
	assert_true(bindings.bind_key(&"jump", bindings.key_of(&"shoot")), "a taken one is taken too")
	assert_eq(bindings.key_of(&"jump"), KeyBindings.DEFAULT_KEYS[&"shoot"], "jump on the shoot key")
	assert_eq(bindings.key_of(&"shoot"), old_jump, "shoot - on the old jump key")


func test_a_taken_pad_button_swaps_places() -> void:
	var bindings := KeyBindings.new()
	assert_true(bindings.bind_pad(&"shoot", JOY_BUTTON_A), "jump button given to shoot")
	assert_eq(bindings.pad_of(&"shoot"), JOY_BUTTON_A, "shoot on A")
	assert_eq(bindings.pad_of(&"jump"), JOY_BUTTON_X, "jump - on the old shoot button")


func test_no_action_is_ever_left_without_a_key() -> void:
	# A chain of swaps is still a permutation: however much the player reassigns,
	# six actions have six different keys.
	var bindings := KeyBindings.new()
	var keys: Array[Key] = [KEY_X, KEY_LEFT, KEY_A, KEY_SPACE, KEY_UP, KEY_A, KEY_DOWN]
	for step: int in keys.size():
		bindings.bind_key(KeyBindings.ACTIONS[step % KeyBindings.ACTIONS.size()], keys[step])
	var seen := {}
	for action: StringName in KeyBindings.ACTIONS:
		assert_ne(bindings.key_of(action), KEY_NONE, "%s has a key" % action)
		seen[bindings.key_of(action)] = true
	assert_eq(seen.size(), KeyBindings.ACTIONS.size(), "and all keys are different")


func test_pause_and_screenshot_keys_are_not_taken() -> void:
	var bindings := KeyBindings.new()
	assert_false(bindings.bind_key(&"jump", KEY_ESCAPE), "Esc is pause, not given away")
	assert_false(bindings.bind_key(&"jump", KEY_F12), "F12 is the screenshot")
	assert_false(bindings.bind_pad(&"jump", JOY_BUTTON_START), "Start is pause")
	assert_true(bindings.is_default(), "the scheme is untouched")


func test_pause_is_not_rebindable() -> void:
	var bindings := KeyBindings.new()
	assert_false(bindings.bind_key(&"pause", KEY_P), "pause cannot be rebound")


func test_reset_restores_the_defaults() -> void:
	var bindings := KeyBindings.new()
	bindings.bind_key(&"jump", KEY_C)
	bindings.bind_pad(&"shoot", JOY_BUTTON_Y)
	bindings.reset()
	assert_true(bindings.is_default(), "after a reset - the default")


func test_the_scheme_survives_a_save_and_load() -> void:
	var bindings := KeyBindings.new()
	bindings.bind_key(&"move_left", KEY_A)
	bindings.bind_pad(&"jump", JOY_BUTTON_B)
	var file := ConfigFile.new()
	bindings.write_to(file)
	var loaded := KeyBindings.read_from(file)
	assert_eq(loaded.key_of(&"move_left"), KEY_A, "key was read")
	assert_eq(loaded.pad_of(&"jump"), JOY_BUTTON_B, "button was read")


func test_a_broken_file_falls_back_to_defaults() -> void:
	var file := ConfigFile.new()
	KeyBindings.new().write_to(file)
	# Two keys in one slot: the file does not write it that way, but it can be edited by hand.
	file.set_value(KeyBindings.SECTION, "key_jump", KEY_X)
	assert_true(KeyBindings.read_from(file).is_default(), "a duplicate - the default scheme")
	file.set_value(KeyBindings.SECTION, "key_jump", KEY_ESCAPE)
	assert_true(KeyBindings.read_from(file).is_default(), "a reserved one - also")
	assert_true(KeyBindings.read_from(ConfigFile.new()).is_default(), "no section - also")
	file.set_value(KeyBindings.SECTION, "key_jump", "space")
	assert_true(KeyBindings.read_from(file).is_default(), "a word, not a key - also")
	file.set_value(KeyBindings.SECTION, "key_jump", KEY_A)
	file.set_value(KeyBindings.SECTION, "pad_jump", [JOY_BUTTON_B])
	assert_true(KeyBindings.read_from(file).is_default(), "a list, not a button - also")


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
			assert_eq((event as InputEventKey).physical_keycode, KEY_A, "key is the assigned one")
			assert_eq(event.device, KeyBindings.ALL_DEVICES, "key from any keyboard")
		elif event is InputEventJoypadButton:
			buttons += 1
			assert_eq(event.device, KeyBindings.ALL_DEVICES, "button from any gamepad")
		elif event is InputEventJoypadMotion:
			axes += 1
	assert_eq(keys, 1, "one key")
	assert_eq(buttons, 1, "one button")
	assert_eq(axes, 1, "and the stick is in place")
