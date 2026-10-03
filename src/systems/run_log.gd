class_name RunLog
extends RefCounted

## Run log: what happened in the game, one JSON line per event.
##
## Bot runs and playthrough tests are long, and analysing them by rerunning with new
## debug prints takes ten minutes per question (M24g, seed 3). The log records
## everything needed for analysis at once: Otto's deaths with the cause and who shot,
## hits, agent release and deaths, returns to play, bot decisions, rides. It is read by
## `tools/run_log.py`: a summary, filters by floor, kind and time.
##
## Enabled by a file path: [method open], the `--log=path` flag of the tools and the
## `ELACTION_LOG` environment variable. When disabled, [method write] costs nothing but
## a single check.
##
## Line: [code]{"frame": physics frame, "t": game time, s, "kind": kind, …}[/code].
## Coordinates are in the rules plane, x and y, m.

const ENV := "ELACTION_LOG"
const FLAG := "--log="
## Placeholder for the seed number in the log path of the run tools.
const SEED_MARK := "{seed}"

static var _file: FileAccess = null
static var _clock: float = 0.0


## Opens the log at [param path]; an empty path — by the flag or the environment
## variable, if set. The previous log is closed.
static func open(path: String = "") -> bool:
	close()
	var target := path
	if target.is_empty():
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with(FLAG):
				target = argument.trim_prefix(FLAG)
	if target.is_empty():
		target = OS.get_environment(ENV)
	# A path with {seed} is a `tools/playthrough.gd` template: it opens the log for each
	# seed itself. Opened here, at game start, the template would leave an extra file with
	# "{seed}" in its name.
	if target.is_empty() or target.contains(SEED_MARK):
		return false
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	_file = FileAccess.open(target, FileAccess.WRITE)
	_clock = 0.0
	return _file != null


static func close() -> void:
	if _file != null:
		_file.close()
	_file = null


## Whether the log is being written.
static func is_on() -> bool:
	return _file != null


## Advances the log's game clock: called by whoever drives the run, once per step.
static func tick(delta: float) -> void:
	_clock += delta


## Writes event [param kind] with details [param details]. Vectors become pairs of
## numbers, nodes become names.
static func write(kind: String, details: Dictionary = {}) -> void:
	if _file == null:
		return
	var line := {"frame": Engine.get_physics_frames(), "t": snappedf(_clock, 0.001), "kind": kind}
	for key: Variant in details:
		line[key] = _plain(details[key])
	_file.store_line(JSON.stringify(line))
	_file.flush()


## A scene point — in the rules plane, rounded to a centimetre.
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
