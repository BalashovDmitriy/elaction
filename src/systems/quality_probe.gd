class_name QualityProbe
extends Node

## Выбор уровня качества при первом запуске — по замеру кадра (ADR-0034,
## решение 3).
##
## Меряется на вступлении первого здания: Otto едет по тросу на крышу, игры в
## эти секунды почти нет, а кадр — крыша с техникой, неон и город — один из
## самых насыщенных. Замер начинается с «Ультра» и спускается на уровень, пока
## медиана времени GPU — окна и вида города вместе — не уложится в
## [constant TARGET_MS]. Первые кадры каждого
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

## Дольше этого замер не идёт, с. Уровень, на котором время вышло, не доказан:
## решает то, что успели намерить ([method settle]).
const TIMEOUT: float = 8.0

var _settings: GameSettings = null
var _level: Graphics.Quality = Graphics.Quality.ULTRA
var _frames: int = 0
var _samples := PackedFloat64Array()
var _elapsed: float = 0.0
## Виды, чьё время GPU складывается в кадр: окно и город — у города свой кадр
## со своим размытием, на «Ультра» в две трети разрешения окна.
var _views: Array[RID] = []


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
	_views = [get_viewport().get_viewport_rid()]
	# Город рисуется своим видом внутри здания; без него замер видел бы только
	# половину кадра (авторевью M22).
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
	# Уровень выбрал игрок, пока шёл замер: выбор его, замер его не перебивает
	# и в настройки не пишет (авторевью M22).
	if _settings.quality_measured:
		_stop()
		return
	# Настройки применили поверх замера — меню сменило язык или кровь и разослало
	# уровень из настроек: уровень замера ставится снова и меряется заново.
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


## Какой уровень взять по медиане кадра [param gpu_ms] на уровне [param level]:
## тот же, если укладывается, иначе ступенью ниже. Для тестов — без окна.
static func step(level: Graphics.Quality, gpu_ms: float) -> Graphics.Quality:
	if gpu_ms <= TARGET_MS or level == Graphics.Quality.LOW:
		return level
	return (level - 1) as Graphics.Quality


## Какой уровень взять, когда время замера вышло на уровне [param level] с
## намеренными [param samples]. Хоть что-то намерено — решает медиана. Ничего —
## кадры так долги, что за отведённое время не прошёл даже разогрев: уровень не
## укладывается, ступенью ниже. Иначе самая слабая карта, на которой замер не
## успевает, получала бы «Ультра» (авторевью M22).
static func settle(level: Graphics.Quality, samples: PackedFloat64Array) -> Graphics.Quality:
	return step(level, median(samples) if not samples.is_empty() else INF)


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


func _finish(level: Graphics.Quality) -> void:
	if level != _level:
		Graphics.broadcast(level)
	_level = level
	_settings.quality = level
	_settings.quality_measured = true
	_settings.save_to()
	finished.emit(level)
	_stop()


## Замер окончен или больше не нужен. Счёт времени кадра выключает выход из
## дерева — и тогда, когда здание выбросили посреди замера.
func _stop() -> void:
	_settings = null
	queue_free()
