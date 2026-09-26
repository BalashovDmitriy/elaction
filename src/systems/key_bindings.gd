class_name KeyBindings
extends RefCounted

## Схема управления игрока: одна клавиша и одна кнопка геймпада на действие
## (ADR-0039, решение 7).
##
## Переназначаются шесть игровых действий. Пауза на Esc и Start не
## переназначается — без неё из игры не выйти, если назначить не то; скриншот на
## F12 тоже. Стик геймпада ведёт направления всегда, рядом с крестовиной: его
## события в [InputMap] схема не трогает.
##
## Занятая клавиша меняется местами: действие, у которого её забрали, получает
## прежнюю клавишу нового. Ни одно действие не остаётся без клавиши.
##
## Клавиши — по физическому месту ([member InputEventKey.physical_keycode]):
## схема переживает смену раскладки, как и раскладка по умолчанию с M1.
##
## Класс без узлов: хранит, меняет, пишет в [ConfigFile] и раскладывает в
## [InputMap]; кто его позовёт — меню или запуск игры, — ему всё равно.

const SECTION := "keys"

## Действия, которые можно переназначить, в порядке экрана управления.
const ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"shoot"
]

## Клавиши по умолчанию — те же, что первыми стоят в `project.godot`.
const DEFAULT_KEYS: Dictionary = {
	&"move_left": KEY_LEFT,
	&"move_right": KEY_RIGHT,
	&"move_up": KEY_UP,
	&"move_down": KEY_DOWN,
	&"jump": KEY_SPACE,
	&"shoot": KEY_X,
}

## Кнопки геймпада по умолчанию — раскладка Xbox, как в `project.godot`.
const DEFAULT_PADS: Dictionary = {
	&"move_left": JOY_BUTTON_DPAD_LEFT,
	&"move_right": JOY_BUTTON_DPAD_RIGHT,
	&"move_up": JOY_BUTTON_DPAD_UP,
	&"move_down": JOY_BUTTON_DPAD_DOWN,
	&"jump": JOY_BUTTON_A,
	&"shoot": JOY_BUTTON_X,
}

## Закреплены за паузой и скриншотом: назначить их игровому действию нельзя.
const RESERVED_KEYS: Array[Key] = [KEY_ESCAPE, KEY_F12]
const RESERVED_PADS: Array[JoyButton] = [JOY_BUTTON_START, JOY_BUTTON_BACK]

var _keys: Dictionary = DEFAULT_KEYS.duplicate()
var _pads: Dictionary = DEFAULT_PADS.duplicate()


## Схема из файла настроек. Нет секции, чужое значение или две клавиши на одно
## место — схема по умолчанию: полусломанная схема хуже никакой.
static func read_from(file: ConfigFile) -> KeyBindings:
	var bindings := KeyBindings.new()
	if not file.has_section(SECTION):
		return bindings
	var keys := {}
	var pads := {}
	for action: StringName in ACTIONS:
		keys[action] = int(file.get_value(SECTION, "key_" + action, DEFAULT_KEYS[action]))
		pads[action] = int(file.get_value(SECTION, "pad_" + action, DEFAULT_PADS[action]))
	if (
		_usable(keys.values(), RESERVED_KEYS, KEY_NONE)
		and _usable(pads.values(), RESERVED_PADS, -1)
	):
		bindings._keys = keys
		bindings._pads = pads
	return bindings


## Записывает схему в файл настроек.
func write_to(file: ConfigFile) -> void:
	for action: StringName in ACTIONS:
		file.set_value(SECTION, "key_" + action, int(_keys[action]))
		file.set_value(SECTION, "pad_" + action, int(_pads[action]))


func key_of(action: StringName) -> Key:
	return _keys.get(action, KEY_NONE) as Key


func pad_of(action: StringName) -> JoyButton:
	return _pads.get(action, JOY_BUTTON_INVALID) as JoyButton


## Назначает клавишу. Занятую другим действием меняет местами. Закреплённую за
## паузой или скриншотом не берёт и возвращает false.
func bind_key(action: StringName, key: Key) -> bool:
	if not _keys.has(action) or key == KEY_NONE or RESERVED_KEYS.has(key):
		return false
	_swap_into(_keys, action, key)
	return true


## Назначает кнопку геймпада — так же, как клавишу.
func bind_pad(action: StringName, button: JoyButton) -> bool:
	if not _pads.has(action) or button < 0 or RESERVED_PADS.has(button):
		return false
	_swap_into(_pads, action, button)
	return true


## Схема по умолчанию.
func reset() -> void:
	_keys = DEFAULT_KEYS.duplicate()
	_pads = DEFAULT_PADS.duplicate()


## Та же ли это схема, что по умолчанию: тогда «сбросить» нечего.
func is_default() -> bool:
	return _keys == DEFAULT_KEYS and _pads == DEFAULT_PADS


## Раскладывает схему в [InputMap]: у каждого действия остаются одна клавиша,
## одна кнопка и оси стика, какие были.
func apply() -> void:
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventJoypadButton:
				InputMap.action_erase_event(action, event)
		var key := InputEventKey.new()
		key.physical_keycode = key_of(action)
		InputMap.action_add_event(action, key)
		var button := InputEventJoypadButton.new()
		button.button_index = pad_of(action)
		InputMap.action_add_event(action, button)


## Ставит [param value] действию [param action]; у кого оно было — тому
## достаётся прежнее значение [param action].
static func _swap_into(slots: Dictionary, action: StringName, value: int) -> void:
	var previous: int = slots[action]
	for other: StringName in slots:
		if other != action and int(slots[other]) == value:
			slots[other] = previous
	slots[action] = value


## Годится ли набор значений: все разные, ни одного закреплённого и пустого.
static func _usable(values: Array, reserved: Array, empty: int) -> bool:
	var seen := {}
	for value: Variant in values:
		var code := int(value)
		if code == empty or code < 0 or reserved.has(code) or seen.has(code):
			return false
		seen[code] = true
	return true
