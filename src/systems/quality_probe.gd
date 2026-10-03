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

## Time each level gets, s. Each level has its own: with one budget for the whole measurement
## a slow card ran out of time on "Ultra" or "High", and the levels below were never tried
## (ADR-0060). The level at which time ran out is not proven: what was measured so far
## decides ([method settle]).
const LEVEL_TIMEOUT: float = 4.0
## The whole measurement does not go longer than this, s, whatever the levels have spent:
## the measurement always ends.
const TIMEOUT: float = 12.0
## A frame longer than this, s, is a stall — a shader compiles, a building loads — not the
## card's speed: it is charged to the level's budget only up to this length.
const STALL: float = 0.1
## How much cheaper each level down makes the frame, roughly: a level that ran out of time far
## over [constant TARGET_MS] drops as many levels as the excess calls for, not one.
const STEP_GAIN: float = 1.5
## Fewer frames than this say nothing about the card: right after a level change they are
## shader compiles. A level the overall time cut off this early steps down one, as unproven.
const JUDGE_FRAMES: int = 10

var _settings: GameSettings = null
var _trial := Trial.new()
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
	if Graphics.quality != _trial.level:
		_switch(_trial.level)
		return
	var gpu := 0.0
	for view: RID in _views:
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(view)
	var was := _trial.level
	_trial.feed(delta, gpu)
	if _trial.done:
		_finish(_trial.level)
	elif _trial.level != was:
		Graphics.broadcast(_trial.level)


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
## [param samples] measured. If anything was measured, the median decides: a level that fits
## stays, one far over [constant TARGET_MS] drops by the excess — about [constant STEP_GAIN]
## per level — not by one step (ADR-0060). If nothing — the level does not fit, one step
## lower. Otherwise the weakest card, on which the measurement does not finish, would get
## "Ultra" (code review M22).
static func settle(level: Graphics.Quality, samples: PackedFloat64Array) -> Graphics.Quality:
	if samples.is_empty():
		return step(level, INF)
	var excess := median(samples) / TARGET_MS
	if excess <= 1.0:
		return level
	var drop := maxi(ceili(log(excess) / log(STEP_GAIN)), 1)
	return maxi(level - drop, Graphics.Quality.LOW) as Graphics.Quality


## Median: one long frame — loading, the garbage collector — does not lower the level.
static func median(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _switch(level: Graphics.Quality) -> void:
	_trial.begin(level)
	Graphics.broadcast(level)


func _finish(level: Graphics.Quality) -> void:
	if level != Graphics.quality:
		Graphics.broadcast(level)
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


## The measurement rules without a window: frames go in, a level comes out. The node feeds it
## the real frames, the tests — made-up ones.
class Trial:
	extends RefCounted

	## The level being measured; once [member done] — the chosen one.
	var level: Graphics.Quality = Graphics.Quality.ULTRA
	var done: bool = false
	var _frames: int = 0
	## GPU time of the measured frames, ms, and the length of every frame of the level, ms:
	## the frames stand in when the warm-up does not pass in the level's time.
	var _samples := PackedFloat64Array()
	var _times := PackedFloat64Array()
	## Time charged to this level and to the whole measurement, s.
	var _spent: float = 0.0
	var _total: float = 0.0

	## Starts measuring [param at] anew: warm-up, samples and its own time budget.
	func begin(at: Graphics.Quality) -> void:
		level = at
		_frames = 0
		_samples.clear()
		_times.clear()
		_spent = 0.0

	## One frame of [param delta] s with [param gpu_ms] of GPU time, zero if not measured.
	func feed(delta: float, gpu_ms: float) -> void:
		if done:
			return
		_total += delta
		# A shader compile stall is charged as one slow frame, not as seconds of the budget.
		_spent += minf(delta, QualityProbe.STALL)
		_frames += 1
		_times.append(delta * 1000.0)
		if _frames > QualityProbe.WARMUP_FRAMES and gpu_ms > 0.0:
			_samples.append(gpu_ms)
		var out_of_time := _total >= QualityProbe.TIMEOUT
		if out_of_time or _spent >= QualityProbe.LEVEL_TIMEOUT:
			var next := _judge()
			# Warm-up passed and still no GPU time: the card does not report it, and the levels
			# below would not report either — one step down, as decided, and no further.
			var mute := _samples.is_empty() and _frames > QualityProbe.WARMUP_FRAMES
			if out_of_time or mute:
				level = next
				done = true
			else:
				_move(next)
		elif _samples.size() >= QualityProbe.SAMPLE_FRAMES:
			_move(QualityProbe.step(level, QualityProbe.median(_samples)))

	## The level when its time ran out. Measured — by the GPU median. The warm-up did not even
	## pass — by the frame length: frames many times over the budget drop the level as far as
	## they call for, rather than one step at a time (ADR-0060). A handful of frames is
	## compile stalls, not the card's speed ([constant JUDGE_FRAMES]): one step down.
	func _judge() -> Graphics.Quality:
		if _samples.is_empty() and _frames <= QualityProbe.WARMUP_FRAMES:
			if _times.size() < QualityProbe.JUDGE_FRAMES:
				return QualityProbe.step(level, INF)
			return QualityProbe.settle(level, _times)
		return QualityProbe.settle(level, _samples)

	## The level stays — it is chosen; lower — measured next. Below low there is nothing to
	## try, and low is taken without measuring.
	func _move(next: Graphics.Quality) -> void:
		if next == level or next == Graphics.Quality.LOW:
			level = next
			done = true
		else:
			begin(next)
