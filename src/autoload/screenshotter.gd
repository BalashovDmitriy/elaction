extends Node

## Снимки экрана для последующего анализа и оптимизации.
##
## Ручной режим: F12 сохраняет текущий кадр в `screens/manual/`.
## Автоматический: запуск игры с аргументом `-- --capture=M2` прогоняет короткий
## сценарий вехи, сохраняет по кадру на каждый шаг и закрывает игру. Так снимки
## снимаются после каждой играбельной вехи — см. tools/capture.py.
##
## Снимки пишутся в JPEG рядом с проектом: `screens/<веха>/<время>_<шаг>.jpg`.

const OUTPUT_ROOT := "res://screens"
const JPEG_QUALITY: float = 0.9
const CAPTURE_ARG_PREFIX := "--capture="
const MANUAL_FOLDER := "manual"

## Шаги автоматического прогона по вехам: что удерживать и сколько секунд.
##
## План выбирается аргументом --capture=<веха>, регистр имени не важен; для
## незнакомой вехи берётся план M1 и в лог идёт предупреждение.
##
## Выдержки M1 завязаны на время полёта Otto (2 · jump_speed / gravity ≈ 0.85 с):
## «jump» снимается около вершины, а «crouch» — уже после приземления.
##
## Выдержки M2 намеренно не требуют точности: «ride_down» держит спуск дольше,
## чем нужно на три этажа, и кабина упирается в низ шахты. Так кадр не зависит
## от того, за сколько именно она едет.
##
## Выдержка «at_red_door» в M3 — это путь до коврика красной двери и ничего
## больше: 320 px от места появления Otto при walk_speed 90 px/с. «Вверх» в этом
## шаге не держится намеренно, иначе Otto успел бы зайти внутрь и кадр, обещающий
## его перед дверью, показал бы пустой проём.
##
## Гибели в сценарии нет намеренно. Упасть на дно шахты можно только со среднего
## этажа и только пока кабина выше: где она окажется к этому моменту, зависит от
## её расписания, а оно сдвигается от любой правки пауз. Такой шаг молча снимал бы
## не то, что обещает подпись. Падение и сдавливание проверяются отдельным
## прогоном вручную — как это делается, описано в docs/STATUS.md.
const AUTO_PLANS: Dictionary = {
	"M1":
	[
		{"label": "idle", "actions": [], "hold": 0.7},
		{"label": "walk", "actions": ["move_right"], "hold": 0.9},
		{"label": "jump", "actions": ["move_right", "jump"], "hold": 0.42},
		{"label": "crouch", "actions": ["move_down"], "hold": 0.9},
	],
	"M2":
	[
		{"label": "floor_top", "actions": [], "hold": 0.4},
		{"label": "in_car", "actions": ["move_right"], "hold": 0.55},
		{"label": "ride_down", "actions": ["move_down"], "hold": 4.5},
		{"label": "floor_bottom", "actions": [], "hold": 0.4},
		{"label": "left_car", "actions": ["move_right"], "hold": 0.7},
		{"label": "to_escalator", "actions": ["move_left", "move_up"], "hold": 3.4},
		{"label": "middle_floor", "actions": [], "hold": 1.0},
	],
	"M3":
	[
		{"label": "floor_top", "actions": [], "hold": 0.4},
		{"label": "at_red_door", "actions": ["move_left"], "hold": 3.55},
		{"label": "inside", "actions": ["move_up"], "hold": 0.7},
		{"label": "back_outside", "actions": ["move_right"], "hold": 0.6},
	],
	"M4A":
	[
		{"label": "agent_out", "actions": [], "hold": 0.8},
		{"label": "otto_fires", "actions": ["shoot"], "hold": 0.2},
		{"label": "after_the_shot", "actions": [], "hold": 1.5},
		{"label": "under_fire", "actions": [], "hold": 7.0},
	],
}
const DEFAULT_PLAN := "M1"

var _milestone: String = MANUAL_FOLDER


func _ready() -> void:
	# Это инструмент разработки. В экспортированной сборке res:// недоступен на
	# запись, а глобальный перехват ввода и занятая F12 игре не нужны.
	if not OS.is_debug_build():
		set_process_input(false)
		return

	# Снимок должен сниматься и на паузе, иначе F12 перестанет работать в M8.
	process_mode = Node.PROCESS_MODE_ALWAYS

	var milestone := _milestone_from_cmdline()
	if milestone.is_empty():
		return
	_milestone = milestone
	_run_auto_plan.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		# Ручной кадр всегда в manual/, даже посреди автоматического прогона:
		# иначе он попал бы в папку вехи и сошёл бы за кадр сценария.
		capture(MANUAL_FOLDER, MANUAL_FOLDER)


## Сохраняет текущий кадр. Вызывать через await, иначе снимок уедет на кадр вперёд.
##
## [param folder] переопределяет папку вехи; пустая строка — папка текущего прогона.
func capture(label: String, folder: String = "") -> void:
	await RenderingServer.frame_post_draw

	var target := _milestone if folder.is_empty() else folder
	var absolute_root := ProjectSettings.globalize_path(OUTPUT_ROOT)
	var absolute_folder := absolute_root.path_join(target)
	var error := DirAccess.make_dir_recursive_absolute(absolute_folder)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Не удалось создать папку для снимков: %s (код %d)" % [absolute_folder, error])
		return
	_mark_ignored_by_engine(absolute_root)

	var absolute_path := _free_path(absolute_folder, label)
	var image := get_viewport().get_texture().get_image()
	error = image.save_jpg(absolute_path, JPEG_QUALITY)
	if error != OK:
		push_error("Не удалось сохранить снимок %s (код %d)" % [absolute_path, error])
		return

	print("[screenshot] %s" % absolute_path)


func _run_auto_plan() -> void:
	var tree := get_tree()
	# Даём сцене собраться и уровню построить геометрию.
	await tree.process_frame

	for step: Dictionary in _plan_for(_milestone):
		var actions: Array = step.get("actions", [])
		for action: String in actions:
			Input.action_press(action)

		await tree.create_timer(float(step.get("hold", 0.5))).timeout
		await capture(str(step.get("label", "frame")))

		for action: String in actions:
			Input.action_release(action)

	tree.quit()


## Сценарий вехи. Регистр не важен: в документах веха зовётся `M4a`, а ключ
## здесь один на оба написания.
##
## У незнакомой вехи плана нет, и молча снимать вместо неё M1 нельзя: кадры
## легли бы в папку с её именем и сошли бы за её сценарий. Поэтому — предупреждение.
func _plan_for(milestone: String) -> Array:
	var key := milestone.to_upper()
	if AUTO_PLANS.has(key):
		return AUTO_PLANS[key]
	push_warning("Нет плана съёмки для вехи «%s», снимается %s" % [milestone, DEFAULT_PLAN])
	return AUTO_PLANS[DEFAULT_PLAN]


func _milestone_from_cmdline() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(CAPTURE_ARG_PREFIX):
			return argument.trim_prefix(CAPTURE_ARG_PREFIX).strip_edges()
	return ""


## Свободный путь для кадра. Метка времени идёт до секунд, поэтому два снимка
## в одну секунду с одной меткой различаются суффиксом, а не затирают друг друга.
func _free_path(folder: String, label: String) -> String:
	var base := folder.path_join("%s_%s" % [_timestamp(), label])
	var candidate := "%s.jpg" % base
	var index := 2
	while FileAccess.file_exists(candidate):
		candidate = "%s-%d.jpg" % [base, index]
		index += 1
	return candidate


## Кладёт .gdignore рядом со снимками: без него Godot импортирует каждый JPEG
## как ресурс проекта и засевает папку .import-файлами.
func _mark_ignored_by_engine(root_folder: String) -> void:
	var marker := root_folder.path_join(".gdignore")
	if FileAccess.file_exists(marker):
		return
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file == null:
		push_error("Не удалось создать %s (код %d)" % [marker, FileAccess.get_open_error()])
		return
	file.close()


func _timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return (
		"%04d%02d%02d-%02d%02d%02d"
		% [now["year"], now["month"], now["day"], now["hour"], now["minute"], now["second"]]
	)
