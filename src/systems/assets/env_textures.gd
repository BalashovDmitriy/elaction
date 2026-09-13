class_name EnvTextures
extends RefCounted

## Текстуры окружения: три карты одного ассета, собранные в [CanvasTexture].
##
## Генератор `tools/render_env.py` пишет рядом три файла: `slab.png` — цвет,
## `slab_n.png` — нормаль, `slab_s.png` — блик (ADR-0011, пункт 7). Здесь они
## складываются в одну текстуру, потому что свет 2D читает нормаль и specular
## только из [CanvasTexture], а не из отдельных спрайтов.
##
## Результат кэшируется: в здании тридцать этажей, плит на каждом до десятка,
## а тайл перекрытия один и тот же.

const DIR := "res://assets/sprites/env/"
const NORMAL_SUFFIX := "_n"
const SPECULAR_SUFFIX := "_s"

## Ассеты, которые просит уровень. По этому списку тест проверяет, что все три
## карты каждого ассета на месте и одного размера, — а не «вот этот спрайт есть».
const NAMES: PackedStringArray = [
	"slab",
	"wall",
	"wall_side",
	"window_frame",
	"door",
	"door_red",
	"door_ajar",
	"door_open",
	"door_mat",
	"car_slab",
	"escalator_belt",
	"lamp",
	"exit_way",
	"city_wall",
]

## Ширина рамки девятикусочных ассетов: та же величина стоит в
## `tools/render_env.py`, и тест следит, чтобы они не разошлись.
const FRAME_MARGIN: float = 8.0

## Ассеты, которые кладутся девятикусочно, а не плиткой.
const FRAMED: PackedStringArray = ["window_frame"]

static var _cache := {}


## Текстура ассета или null, если генератор её ещё не нарисовал.
static func tile(name: String) -> CanvasTexture:
	if _cache.has(name):
		return _cache[name] as CanvasTexture

	var built := _build(name)
	_cache[name] = built
	return built


## Пути всех карт ассета: диффуз, нормаль, блик. Нужны тесту и отладке.
static func paths_of(name: String) -> PackedStringArray:
	return PackedStringArray(
		[
			DIR + name + ".png",
			DIR + name + NORMAL_SUFFIX + ".png",
			DIR + name + SPECULAR_SUFFIX + ".png",
		]
	)


## Сбрасывает кэш. Нужен тестам: они грузят текстуры в своём порядке.
static func forget() -> void:
	_cache.clear()


static func _build(name: String) -> CanvasTexture:
	var diffuse := _map(name)
	if diffuse == null:
		# Не тихий null: без диффуза уровень остался бы без геометрии вовсе,
		# а причина была бы не видна ни в кадре, ни в логе.
		push_error("Нет диффузной карты ассета %s — запустите tools/render_env.py" % name)
		return null

	var texture := CanvasTexture.new()
	texture.diffuse_texture = diffuse
	texture.normal_texture = _map(name + NORMAL_SUFFIX)
	texture.specular_texture = _map(name + SPECULAR_SUFFIX)
	# Резкость блика лежит в альфе карты, поэтому множитель остаётся нейтральным.
	texture.specular_shininess = 1.0
	return texture


static func _map(file: String) -> Texture2D:
	var path := DIR + file + ".png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
