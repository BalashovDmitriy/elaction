extends GutTest

## Экран управления: переназначение клавиш из меню (ADR-0039, решение 7).

const MENU_SCENE := preload("res://src/ui/menu.tscn")
## Куда экран управления сохраняет схему в тестах: настройки игрока не трогаются.
const TEMP := "user://test_menu_bindings.cfg"

## События игровых действий в [InputMap]: экран управления меняет их для всего
## процесса, и тест обязан вернуть как было — даже если упал посередине.
var _saved: Dictionary = {}


func before_each() -> void:
	_saved.clear()
	for action: StringName in KeyBindings.ACTIONS:
		_saved[action] = InputMap.action_get_events(action)


func after_each() -> void:
	for action: StringName in _saved:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved[action]:
			InputMap.action_add_event(action, event)
	if FileAccess.file_exists(TEMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func _menu() -> Menu:
	var menu := MENU_SCENE.instantiate() as Menu
	menu.settings = GameSettings.new()
	menu.settings.file_path = TEMP
	menu.records = Records.new()
	add_child_autofree(menu)
	return menu


func _row_labelled(menu: Menu, text: String) -> MenuRow:
	for row: MenuRow in menu.rows():
		for label: Node in row.find_children("*", "Label", true, false):
			if (label as Label).text == text:
				return row
	return null


## Экран управления переназначает клавиши (ADR-0039, решение 7): нажал строку —
## она ждёт, первая нажатая клавиша встаёт на место, занятая меняется местами.
func test_the_controls_rebind_a_key_and_swap_a_taken_one() -> void:
	var menu := _menu()
	menu.show_page(Menu.Page.CONTROLS)
	var bindings := _binding_rows(menu)
	assert_eq(bindings.size(), KeyBindings.ACTIONS.size(), "строка на каждое действие")
	bindings[0].pressed.emit()
	assert_true(menu.is_listening(), "нажатая строка ждёт клавишу")
	assert_eq(bindings[0].value_text(), tr("UI_PRESS_KEY"), "и просит её нажать")
	menu._input(_key(KEY_RIGHT))
	assert_false(menu.is_listening(), "клавиша пришла — ждать нечего")
	assert_eq(menu.settings.bindings.key_of(&"move_left"), KEY_RIGHT, "влево — на стрелке вправо")
	assert_eq(menu.settings.bindings.key_of(&"move_right"), KEY_LEFT, "а вправо — на прежней влево")
	assert_true(
		bindings[1].value_text().begins_with(OS.get_keycode_string(KEY_LEFT)),
		"строка соседа переписана вместе с обменом"
	)
	assert_true(FileAccess.file_exists(TEMP), "схема сохранена")


func test_escape_cancels_listening_and_reset_restores_defaults() -> void:
	var menu := _menu()
	menu.show_page(Menu.Page.CONTROLS)
	var bindings := _binding_rows(menu)
	bindings[4].pressed.emit()
	menu._input(_key(KEY_ESCAPE))
	assert_false(menu.is_listening(), "Esc отменяет ожидание")
	assert_true(menu.settings.bindings.is_default(), "и ничего не назначает")
	menu.settings.bindings.bind_key(&"jump", KEY_C)
	var reset := _row_labelled(menu, tr("UI_RESET_KEYS"))
	assert_not_null(reset, "есть сброс")
	if reset != null:
		reset.pressed.emit()
	assert_true(menu.settings.bindings.is_default(), "сброс вернул схему по умолчанию")


func _binding_rows(menu: Menu) -> Array[MenuRow]:
	var found: Array[MenuRow] = []
	for row: MenuRow in menu.rows():
		if row.kind == MenuRow.Kind.BINDING:
			found.append(row)
	return found


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event
