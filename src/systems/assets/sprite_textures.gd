class_name SpriteTextures
extends RefCounted

## Спрайты игры: три карты одного ассета, собранные в [CanvasTexture].
##
## Генераторы пишут рядом три файла: `slab.png` — цвет, `slab_n.png` — нормаль,
## `slab_s.png` — блик (ADR-0011, пункт 7). Здесь они складываются в одну
## текстуру, потому что свет 2D читает нормаль и specular только из
## [CanvasTexture], а не из отдельных спрайтов.
##
## Ассеты лежат двумя наборами: окружение рисует `tools/render_env.py`, актёров
## снимает с модели `tools/render_actors.py`. Загрузка у них общая, различаются
## только папка и список.
##
## Результат кэшируется: в здании тридцать этажей, плит на каждом до десятка,
## а тайл перекрытия один и тот же.

const DIR := "res://assets/sprites/env/"
const ACTOR_DIR := "res://assets/sprites/actors/"
const NORMAL_SUFFIX := "_n"
const SPECULAR_SUFFIX := "_s"

## Ассеты окружения, которые просит уровень. По этому списку тест проверяет,
## что все три карты каждого на месте и одного размера, — а не «вот спрайт есть».
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
	"bullet",
]

## Позы актёров. Имя ассета — «<актёр>_<поза>», и по этому же списку [Otto]
## и [Enemy] выбирают, что показать: набор поз и набор состояний обязаны
## совпадать, и это проверяется тестом.
const OTTO_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"crouch",
	"jump",
	"kick",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
]
## Машина у выхода: одна поза, но ассет тот же по устройству (ADR-0011, п. 14).
const CAR_POSES: PackedStringArray = ["parked"]
const AGENT_POSES: PackedStringArray = [
	"idle",
	"walk_0",
	"walk_1",
	"walk_2",
	"shoot",
	"dead_0",
	"dead_1",
	"crushed",
]

## Кадров ходьбы в секунду. На двенадцати шаг читается как бег, а Otto ходит
## (ADR-0011, пункт 5).
const WALK_FPS: float = 10.0

## Ширина рамки девятикусочных ассетов: та же величина стоит в
## `tools/render_env.py`, и тест следит, чтобы они не разошлись.
const FRAME_MARGIN: float = 8.0

## Ассеты, которые кладутся девятикусочно, а не плиткой.
const FRAMED: PackedStringArray = ["window_frame"]

## Заглушка на месте ненарисованного ассета.
const MISSING_COLOR := Color(1.0, 0.0, 0.9)
const MISSING_SIDE: int = 8

static var _cache: Dictionary = {}


## Текстура ассета окружения. Ассета нет — вернётся заглушка, но не null.
##
## Половина узлов молча оставалась бы невидимой, а другая половина подставляла
## серую заливку, и ни то ни другое не показывает причину. Заглушка показывает.
static func tile(name: String) -> CanvasTexture:
	return _cached(DIR, name)


## Текстура позы актёра: [code]actor("otto", "walk_0")[/code].
static func actor(name: String, pose: String) -> CanvasTexture:
	return _cached(ACTOR_DIR, "%s_%s" % [name, pose])


## Пути всех карт ассета окружения: диффуз, нормаль, блик. Нужны тесту и отладке.
static func paths_of(name: String) -> PackedStringArray:
	return paths_in(DIR, name)


## Пути всех карт ассета актёра.
static func actor_paths(name: String, pose: String) -> PackedStringArray:
	return paths_in(ACTOR_DIR, "%s_%s" % [name, pose])


## Три карты ассета в заданной папке.
static func paths_in(dir: String, name: String) -> PackedStringArray:
	return PackedStringArray(
		[
			dir + name + ".png",
			dir + name + NORMAL_SUFFIX + ".png",
			dir + name + SPECULAR_SUFFIX + ".png",
		]
	)


static func _cached(dir: String, name: String) -> CanvasTexture:
	var key := dir + name
	if _cache.has(key):
		return _cache[key] as CanvasTexture

	var built := _build(dir, name)
	_cache[key] = built
	return built


## Сбрасывает кэш. Нужен тестам: они грузят текстуры в своём порядке.
static func forget() -> void:
	_cache.clear()


static func _build(dir: String, name: String) -> CanvasTexture:
	# Пути берутся из [method paths_in], а не собираются заново: по ним же
	# проверяет тест, и второй такой же счёт разъехался бы с этим.
	var maps := paths_in(dir, name)
	var diffuse := _map(maps[0])
	if diffuse == null:
		push_error("Нет диффузной карты ассета %s — запустите генератор ассетов" % name)
		return _missing()

	var texture := CanvasTexture.new()
	texture.diffuse_texture = diffuse
	texture.normal_texture = _map(maps[1])
	texture.specular_texture = _map(maps[2])
	# Резкость блика лежит в альфе карты, поэтому множитель остаётся нейтральным.
	texture.specular_shininess = 1.0
	return texture


## Ядовитый квадрат вместо ассета: в кадре его видно сразу, и он не
## притворяется картинкой, как притворялась бы серая заливка.
static func _missing() -> CanvasTexture:
	var image := Image.create_empty(MISSING_SIDE, MISSING_SIDE, false, Image.FORMAT_RGBA8)
	image.fill(MISSING_COLOR)
	var texture := CanvasTexture.new()
	texture.diffuse_texture = ImageTexture.create_from_image(image)
	return texture


static func _map(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
