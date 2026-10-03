class_name KeyBindings
extends RefCounted

## The player's control scheme: one key and one gamepad button per action (ADR-0039, decision 7).
##
## Six game actions are remappable. Pause on Esc and Start is not remappable — without it there is
## no way out of the game if something wrong is assigned; the screenshot on F12 neither. The gamepad
## stick always drives directions, alongside the d-pad: the scheme does not touch its events in
## [InputMap].
##
## A taken key is swapped: the action it was taken from gets the new action's previous key. No
## action is left without a key.
##
## Keys are by physical location ([member InputEventKey.physical_keycode]): the scheme survives a
## keyboard layout change, like the default mapping since M1.
##
## A class without nodes: it stores, changes, writes to [ConfigFile] and lays out into [InputMap];
## it does not care who calls it — the menu or the game start.

const SECTION := "keys"

## Remappable actions, in the order of the controls screen.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"shoot"
]

## Default keys — the same as the first ones in `project.godot`.
const DEFAULT_KEYS: Dictionary = {
	&"move_left": KEY_LEFT,
	&"move_right": KEY_RIGHT,
	&"move_up": KEY_UP,
	&"move_down": KEY_DOWN,
	&"jump": KEY_SPACE,
	&"shoot": KEY_X,
}

## Default gamepad buttons — Xbox layout, as in `project.godot`.
const DEFAULT_PADS: Dictionary = {
	&"move_left": JOY_BUTTON_DPAD_LEFT,
	&"move_right": JOY_BUTTON_DPAD_RIGHT,
	&"move_up": JOY_BUTTON_DPAD_UP,
	&"move_down": JOY_BUTTON_DPAD_DOWN,
	&"jump": JOY_BUTTON_A,
	&"shoot": JOY_BUTTON_X,
}

## Reserved for pause and screenshot: they cannot be assigned to a game action.
const RESERVED_KEYS: Array[Key] = [KEY_ESCAPE, KEY_F12]
const RESERVED_PADS: Array[JoyButton] = [JOY_BUTTON_START, JOY_BUTTON_BACK]

## An action event listens to all devices, as in `project.godot`. Our own event is bound to one by
## default: the keyboard to 16, the gamepad to zero, and without this a second gamepad or a gamepad
## not numbered 0 would press nothing.
const ALL_DEVICES: int = -1

var _keys: Dictionary = DEFAULT_KEYS.duplicate()
var _pads: Dictionary = DEFAULT_PADS.duplicate()


## Scheme from the settings file. No section, a foreign value or two keys in one place — the default
## scheme: a half-broken scheme is worse than none.
static func read_from(file: ConfigFile) -> KeyBindings:
	var bindings := KeyBindings.new()
	if not file.has_section(SECTION):
		return bindings
	var keys := {}
	var pads := {}
	for action: StringName in ACTIONS:
		var key: Variant = file.get_value(SECTION, "key_" + action, DEFAULT_KEYS[action])
		var pad: Variant = file.get_value(SECTION, "pad_" + action, DEFAULT_PADS[action])
		# A hand-edited slot that is not a number: the scheme is broken, as with a duplicate —
		# not a failed conversion that would stop the game at startup (ADR-0060).
		if key is not int or pad is not int:
			return bindings
		keys[action] = key
		pads[action] = pad
	if (
		_usable(keys.values(), RESERVED_KEYS, KEY_NONE)
		and _usable(pads.values(), RESERVED_PADS, -1)
	):
		bindings._keys = keys
		bindings._pads = pads
	return bindings


## Writes the scheme to the settings file.
func write_to(file: ConfigFile) -> void:
	for action: StringName in ACTIONS:
		file.set_value(SECTION, "key_" + action, int(_keys[action]))
		file.set_value(SECTION, "pad_" + action, int(_pads[action]))


func key_of(action: StringName) -> Key:
	return _keys.get(action, KEY_NONE) as Key


func pad_of(action: StringName) -> JoyButton:
	return _pads.get(action, JOY_BUTTON_INVALID) as JoyButton


## Assigns a key. One taken by another action is swapped. One reserved for pause or screenshot is
## not taken, and false is returned.
func bind_key(action: StringName, key: Key) -> bool:
	if not _keys.has(action) or key == KEY_NONE or RESERVED_KEYS.has(key):
		return false
	_swap_into(_keys, action, key)
	return true


## Assigns a gamepad button — the same way as a key.
func bind_pad(action: StringName, button: JoyButton) -> bool:
	if not _pads.has(action) or button < 0 or RESERVED_PADS.has(button):
		return false
	_swap_into(_pads, action, button)
	return true


## The default scheme.
func reset() -> void:
	_keys = DEFAULT_KEYS.duplicate()
	_pads = DEFAULT_PADS.duplicate()


## Whether this is the same scheme as the default: then there is nothing to "reset".
func is_default() -> bool:
	return _keys == DEFAULT_KEYS and _pads == DEFAULT_PADS


## Lays out the scheme into [InputMap]: each action keeps one key, one button and the stick axes it
## had.
func apply() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventJoypadButton:
				InputMap.action_erase_event(action, event)
		var key := InputEventKey.new()
		key.device = ALL_DEVICES
		key.physical_keycode = key_of(action)
		InputMap.action_add_event(action, key)
		var button := InputEventJoypadButton.new()
		button.device = ALL_DEVICES
		button.button_index = pad_of(action)
		InputMap.action_add_event(action, button)


## Gives [param value] to action [param action]; whoever had it gets the previous value of [param
## action].
static func _swap_into(slots: Dictionary, action: StringName, value: int) -> void:
	var previous: int = slots[action]
	for other: StringName in slots:
		if other != action and int(slots[other]) == value:
			slots[other] = previous
	slots[action] = value


## Whether a set of values is valid: all different, none reserved or empty.
static func _usable(values: Array, reserved: Array, empty: int) -> bool:
	var seen := {}
	for value: Variant in values:
		var code := int(value)
		if code == empty or code < 0 or reserved.has(code) or seen.has(code):
			return false
		seen[code] = true
	return true
