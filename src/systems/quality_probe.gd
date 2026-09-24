class_name QualityProbe
extends Node

## Выбор уровня качества при первом запуске — по замеру кадра (ADR-0034,
## решение 3).
##
## Меряется на вступлении первого здания: Otto едет по тросу на крышу, игры в
## эти секунды почти нет, а кадр — крыша с техникой, неон и город — один из
## самых насыщенных. Замер начинается с «Ультра» и спускается на уровень, пока
## медиана времени GPU не уложится в [constant TARGET_MS]. Первые кадры каждого
## уровня пропускаются: в них компилируются шейдеры, и замер вышел бы вдвое
## хуже правды.
##
## Выбранный уровень пишется в настройки один раз; дальше его меняет только
## игрок. Правил игры замер не трогает — только картинку.

signal finished(level: Graphics.Quality)

## Медиана кадра GPU, в которую уровень обязан уложиться, мс: бюджет 16.6 с
## запасом на тяжёлые этажи и чужие программы.
const TARGET_MS: float = 12.0

## Сколько кадров пропустить после смены уровня и сколько мерить.
const WARMUP_FRAMES: int = 45
const SAMPLE_FRAMES: int = 60

## Дольше этого замер не идёт, с: где остановился — то и берётся.
const TIMEOUT: float = 8.0

var _settings: GameSettings = null
var _level: Graphics.Quality = Graphics.Quality.ULTRA
var _frames: int = 0
var _samples := PackedFloat64Array()
var _elapsed: float = 0.0


## Нужен ли замер: игрок ещё не выбирал и игра ещё не мерила.
static func needed(settings: GameSettings) -> bool:
	return not settings.quality_measured


## Начинает замер для настроек [param settings]: с «Ультра», по кадрам окна.
func start(settings: GameSettings) -> void:
	name = "QualityProbe"
	_settings = settings
	# Замер — картинка, а не игра: пауза его не останавливает, иначе меню
	# посреди вступления растянуло бы его навсегда.
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_switch(Graphics.Quality.ULTRA)


func _process(delta: float) -> void:
	if _settings == null:
		return
	_elapsed += delta
	_frames += 1
	if _frames > WARMUP_FRAMES:
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(
			get_viewport().get_viewport_rid()
		)
		if gpu > 0.0:
			_samples.append(gpu)
	if _elapsed >= TIMEOUT:
		_finish()
		return
	if _samples.size() < SAMPLE_FRAMES:
		return
	var fits := median(_samples) <= TARGET_MS
	if fits or _level == Graphics.Quality.LOW:
		_finish()
	else:
		_switch((_level - 1) as Graphics.Quality)


## Какой уровень взять по медиане кадра [param gpu_ms] на уровне [param level]:
## тот же, если укладывается, иначе ступенью ниже. Для тестов — без окна.
static func step(level: Graphics.Quality, gpu_ms: float) -> Graphics.Quality:
	if gpu_ms <= TARGET_MS or level == Graphics.Quality.LOW:
		return level
	return (level - 1) as Graphics.Quality


## Медиана: один долгий кадр — загрузка, сборщик — не опускает уровень.
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


func _finish() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), false)
	_settings.quality = _level
	_settings.quality_measured = true
	_settings.save_to()
	finished.emit(_level)
	_settings = null
	queue_free()
