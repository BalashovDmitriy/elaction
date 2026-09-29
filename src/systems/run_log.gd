class_name RunLog
extends RefCounted

## Журнал прогона: что происходило в игре, строкой JSON на событие.
##
## Прогоны ботом и тесты прохождения длинные, и разбирать их перезапусками с
## новыми отладочными печатями — по десять минут на вопрос (M24g, сид 3).
## Журнал пишет всё нужное для разбора сразу: смерти Otto с причиной и тем, кто
## стрелял, попадания, выпуск и гибель агентов, возвращения в игру, решения бота,
## поездки. Читает его `tools/run_log.py`: сводка, фильтры по этажу, виду и
## времени.
##
## Включается путём файла: [method open], флаг `--log=путь` у инструментов и
## переменная окружения `ELACTION_LOG`. Выключен — [method write] не стоит
## ничего, кроме одной проверки.
##
## Строка: [code]{"frame": кадр физики, "t": игровое время, с, "kind": вид, …}[/code].
## Координаты — в плоскости правил, x и y, м.

const ENV := "ELACTION_LOG"
const FLAG := "--log="

static var _file: FileAccess = null
static var _clock: float = 0.0


## Открывает журнал в [param path]; пустой путь — по флагу или переменной
## окружения, если заданы. Прежний журнал закрывается.
static func open(path: String = "") -> bool:
	close()
	var target := path
	if target.is_empty():
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with(FLAG):
				target = argument.trim_prefix(FLAG)
	if target.is_empty():
		target = OS.get_environment(ENV)
	if target.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	_file = FileAccess.open(target, FileAccess.WRITE)
	_clock = 0.0
	return _file != null


static func close() -> void:
	if _file != null:
		_file.close()
	_file = null


## Пишется ли журнал.
static func is_on() -> bool:
	return _file != null


## Двигает игровые часы журнала: зовёт тот, кто ведёт прогон, раз в шаг.
static func tick(delta: float) -> void:
	_clock += delta


## Пишет событие [param kind] с подробностями [param details]. Векторы
## превращаются в пары чисел, узлы — в имена.
static func write(kind: String, details: Dictionary = {}) -> void:
	if _file == null:
		return
	var line := {"frame": Engine.get_physics_frames(), "t": snappedf(_clock, 0.001), "kind": kind}
	for key: Variant in details:
		line[key] = _plain(details[key])
	_file.store_line(JSON.stringify(line))
	_file.flush()


## Точка сцены — в плоскости правил, с округлением до сантиметра.
static func at(node: Node3D) -> Array:
	if node == null or not is_instance_valid(node):
		return []
	var point := WorldSpace.to_plane(node.global_position)
	return [snappedf(point.x, 0.01), snappedf(point.y, 0.01)]


static func _plain(value: Variant) -> Variant:
	if value is Vector2:
		var v := value as Vector2
		return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]
	if value is Vector3:
		var w := value as Vector3
		return [snappedf(w.x, 0.01), snappedf(w.y, 0.01), snappedf(w.z, 0.01)]
	if value is float:
		return snappedf(value as float, 0.001)
	if value is Node:
		return String((value as Node).name)
	if value is Array:
		var out: Array = []
		for item: Variant in value:
			out.append(_plain(item))
		return out
	return value
