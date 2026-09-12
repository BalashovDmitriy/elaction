extends Node2D

## Точка входа проекта.
##
## На этапе M3 грузит greybox-уровень, показывает счёт с документами и
## отладочный оверлей с состоянием Otto. Игровой цикл и меню — в M5 и M8.

var _cleared: bool = false

@onready var _level: GreyboxLevel = $GreyboxLevel
@onready var _debug_label: Label = %DebugLabel
@onready var _hud_label: Label = %HudLabel


func _ready() -> void:
	var game := GameState.instance()
	game.score_changed.connect(_on_score_changed)
	game.documents_changed.connect(_on_documents_changed)
	_level.building_cleared.connect(_on_building_cleared)
	# Уровень готов раньше main, поэтому счётчики уже заполнены: рисуем как есть.
	_render_hud()


func _process(_delta: float) -> void:
	_debug_label.text = _debug_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().quit()


func _on_score_changed(_value: int) -> void:
	_render_hud()


func _on_documents_changed(_collected: int, _total: int) -> void:
	_render_hud()


func _on_building_cleared() -> void:
	_cleared = true
	_render_hud()


func _render_hud() -> void:
	var game := GameState.instance()
	var text := (
		"очки: %d\nдокументы: %d / %d"
		% [game.score, game.documents_collected, game.documents_total]
	)
	if _cleared:
		text += "\nздание пройдено"
	_hud_label.text = text


func _debug_text() -> String:
	var otto := _level.otto
	var motion := otto.motion()
	return (
		"состояние: %s\nскорость: %.0f / %.0f\nна полу: %s\nв кабине: %s\nFPS: %d"
		% [
			OttoStateMachine.state_name(otto.current_state()),
			motion.x,
			motion.y,
			"да" if otto.is_grounded() else "нет",
			"да" if otto.is_riding() else "нет",
			Engine.get_frames_per_second(),
		]
	)
