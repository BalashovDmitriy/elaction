class_name Skyline
extends RefCounted

## Силуэт города за окнами здания.
##
## Художника до M7 нет, поэтому город выкладывается кодом из сида — теми же
## правилами, что и само здание (ADR-0010, пункт 10). Значит, он повторяем:
## одно и то же здание всегда стоит в одном и том же городе, и это проверяется
## тестом, а не глазами.
##
## Класс ничего не рисует и не знает про узлы: отдаёт прямоугольники, а уровень
## делает из них панели. Поэтому проверяется без сцены.


## Башня города: её силуэт и горящие окна в ней.
class Tower:
	extends RefCounted

	var rect: Rect2
	var windows: Array[Rect2] = []


## Ширина башни и просвет между соседними, px.
const WIDTH := Vector2(48.0, 130.0)
const GAP := Vector2(6.0, 30.0)

## Высота башни в долях высоты отведённой полосы.
const HEIGHT := Vector2(0.25, 1.0)

## Окно башни и отступ от её краёв, px.
const WINDOW := Vector2(7.0, 10.0)
const WINDOW_GAP: float = 9.0
const WINDOW_MARGIN: float = 8.0

## Какая доля окон горит.
const WINDOWS_LIT: float = 0.40


## Выкладывает город по полосе [param area]: башни стоят на её нижнем краю.
static func generate(building_seed: int, area: Rect2) -> Array[Tower]:
	var rng := RandomNumberGenerator.new()
	# Свой поток, а не тот, что раскладывает здание: город не должен смещать
	# раскладку, иначе правка вида чинила бы или ломала проходимость.
	rng.seed = hash("skyline:%d" % building_seed)

	var towers: Array[Tower] = []
	var x := area.position.x
	while x < area.end.x:
		var width := minf(rng.randf_range(WIDTH.x, WIDTH.y), area.end.x - x)
		if width < WIDTH.x * 0.5:
			break

		var height := area.size.y * rng.randf_range(HEIGHT.x, HEIGHT.y)
		var tower := Tower.new()
		tower.rect = Rect2(x, area.end.y - height, width, height)
		tower.windows = _windows_in(rng, tower.rect)
		towers.append(tower)

		x += width + rng.randf_range(GAP.x, GAP.y)
	return towers


## Горящие окна башни: сетка по её лицевой стороне, горит не всякое.
static func _windows_in(rng: RandomNumberGenerator, tower: Rect2) -> Array[Rect2]:
	var windows: Array[Rect2] = []
	var step := Vector2(WINDOW.x + WINDOW_GAP, WINDOW.y + WINDOW_GAP)
	var y := tower.position.y + WINDOW_MARGIN

	while y + WINDOW.y <= tower.end.y - WINDOW_MARGIN:
		var x := tower.position.x + WINDOW_MARGIN
		while x + WINDOW.x <= tower.end.x - WINDOW_MARGIN:
			if rng.randf() < WINDOWS_LIT:
				windows.append(Rect2(x, y, WINDOW.x, WINDOW.y))
			x += step.x
		y += step.y
	return windows
