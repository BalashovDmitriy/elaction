extends Node2D

## Точка входа проекта.
##
## На этапе M0 сцена не делает ничего, кроме подтверждения того, что проект
## корректно импортируется, запускается и проходит проверки.

const MILESTONE: String = "M0 — фундамент"

@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	var version := _project_version()
	_status_label.text = "elaction v%s\n%s" % [version, MILESTONE]
	print("[elaction] v%s на Godot %s" % [version, Engine.get_version_info().get("string", "?")])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().quit()


func _project_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
