extends Node2D

## Точка входа проекта.
##
## На этапе M1 грузит greybox-уровень и показывает отладочный оверлей
## с состоянием Otto. Настоящий игровой цикл и меню появятся в M5 и M8.

@onready var _level: GreyboxLevel = $GreyboxLevel
@onready var _debug_label: Label = %DebugLabel


func _process(_delta: float) -> void:
	_debug_label.text = _debug_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().quit()


func _debug_text() -> String:
	var otto := _level.otto
	var motion := otto.motion()
	return (
		"состояние: %s\nскорость: %.0f / %.0f\nна полу: %s\nFPS: %d"
		% [
			OttoStateMachine.state_name(otto.current_state()),
			motion.x,
			motion.y,
			"да" if otto.is_grounded() else "нет",
			Engine.get_frames_per_second(),
		]
	)
