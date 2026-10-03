class_name QualityProbe
extends Node

## Choosing the quality level on first launch — by frame measurement (ADR-0034,
## decision 3).
##
## Measured during the intro of the first building: Otto rides the rope to the roof, there
## is almost no gameplay in those seconds, and the frame — the roof with equipment, neon and
## the city — is one of the busiest. The measurement starts at "Ultra" and steps down a level
## until the median GPU time — of the window and the city view together — fits into
## [constant TARGET_MS]. The first frames of each
## level are skipped: shaders compile in them, and the measurement would come out twice
## as bad as the truth.
##
## The chosen level is written to the settings once; after that only the player
## changes it. The measurement does not touch the game rules — only the picture.

signal finished(level: Graphics.Quality)

## Median GPU frame the level must fit into, ms: a budget of 16.6 with
## a margin for heavy floors and other programs.
const TARGET_MS: float = 12.0

## How many frames to skip after a level change and how many to measure.
const WARMUP_FRAMES: int = 45
const SAMPLE_FRAMES: int = 60

## The measurement does not go longer than this, s. The level at which time ran out is not
## proven: what was measured so far decides ([method settle]).
const TIMEOUT: float = 8.0

var _settings: GameSettings = null
var _level: Graphics.Quality = Graphics.Quality.ULTRA
var _frames: int = 0
var _samples := PackedFloat64Array()
var _elapsed: float = 0.0
## Views whose GPU time adds up to the frame: the window and the city — the city has its own
## frame with its own blur, on "Ultra" at two thirds of the window resolution.
var _views: Array[RID] = []


## Whether a measurement is needed: the player has not chosen yet and the game has not
## measured yet.
static func needed(settings: GameSettings) -> bool:
	return not settings.quality_measured


## Starts measuring for settings [param settings]: from "Ultra", by window frames.
func start(settings: GameSettings) -> void:
	name = "QualityProbe"
	_settings = settings
	# The measurement is about the picture, not the game: pause does not stop it, otherwise a
	# menu in the middle of the intro would stretch it forever.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_views = [get_viewport().get_viewport_rid()]
	# The city is drawn by its own view inside the building; without it the measurement would
	# see only half the frame (code review M22).
	var host := get_parent()
	if host != null:
		for node in host.find_children("*", "SubViewport", true, false):
			_views.append((node as SubViewport).get_viewport_rid())
	for view in _views:
		RenderingServer.viewport_set_measure_render_time(view, true)
	_switch(Graphics.Quality.ULTRA)


func _process(delta: float) -> void:
	if _settings == null:
		return
	# The player chose a level while the measurement was running: the choice is his, the
	# measurement does not override it and does not write to the settings (code review M22).
	if _settings.quality_measured:
		_stop()
		return
	# Settings were applied on top of the measurement — the menu changed the language or blood
	# and broadcast the level from the settings: the measurement level is set again and
	# measured anew.
	if Graphics.quality != _level:
		_switch(_level)
		return
	_elapsed += delta
	_frames += 1
	if _frames > WARMUP_FRAMES:
		var gpu := 0.0
		for view in _views:
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(view)
		if gpu > 0.0:
			_samples.append(gpu)
	if _elapsed >= TIMEOUT:
		_finish(settle(_level, _samples))
		return
	if _samples.size() < SAMPLE_FRAMES:
		return
	var next := step(_level, median(_samples))
	if next == _level:
		_finish(_level)
	else:
		_switch(next)


func _exit_tree() -> void:
	for view in _views:
		RenderingServer.viewport_set_measure_render_time(view, false)


## Which level to take by frame median [param gpu_ms] at level [param level]:
## the same one if it fits, otherwise a step lower. For tests — without a window.
static func step(level: Graphics.Quality, gpu_ms: float) -> Graphics.Quality:
	if gpu_ms <= TARGET_MS or level == Graphics.Quality.LOW:
		return level
	return (level - 1) as Graphics.Quality


## Which level to take when the measurement time ran out at level [param level] with
## [param samples] measured. If anything was measured, the median decides. If nothing —
## frames are so long that not even the warm-up passed in the allotted time: the level does
## not fit, one step lower. Otherwise the weakest card, on which the measurement does not
## finish, would get "Ultra" (code review M22).
static func settle(level: Graphics.Quality, samples: PackedFloat64Array) -> Graphics.Quality:
	return step(level, median(samples) if not samples.is_empty() else INF)


## Median: one long frame — loading, the garbage collector — does not lower the level.
static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _switch(level: Graphics.Quality) -> void:
	_level = level
	_frames = 0
	_samples.clear()
	Graphics.broadcast(level)


func _finish(level: Graphics.Quality) -> void:
	if level != _level:
		Graphics.broadcast(level)
	_level = level
	_settings.quality = level
	_settings.quality_measured = true
	_settings.save_to()
	finished.emit(level)
	_stop()


## The measurement is over or no longer needed. Leaving the tree turns off frame time
## counting — also when the building was thrown away in the middle of the measurement.
func _stop() -> void:
	_settings = null
	queue_free()
