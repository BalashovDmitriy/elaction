class_name CityPlan
extends RefCounted

## Кварталы города за зданием: где стоят дома, какой высоты и какие окна горят
## (ADR-0029, решение 1).
##
## Только числа, без узлов: по ним строит [CityBackdrop], а тесты проверяют, что
## город повторяется по сиду и закрывает всю ширину кадра. Координаты — метры
## сцены города: x вдоль здания, y вверх от земли, z вглубь, от камеры прочь.


## Дом: коробка на земле и сетка окон на фасаде, обращённом к камере.
class Block:
	extends RefCounted
	## Ряд по глубине: 0 — ближний.
	var row: int = 0
	var x: float = 0.0
	var width: float = 0.0
	var height: float = 0.0
	## Середина дома по глубине.
	var z: float = 0.0
	var depth: float = 0.0
	## Горящие окна: пары «колонка, этаж» от левого нижнего угла фасада.
	var lit: Array[Vector2i] = []


## Ряды по глубине: насколько ряд позади плоскости игры, м, и какой высоты там
## дома. Ближний ряд — в шестидесяти метрах: ближе окна выходили размером с
## дверь, и город читался декорацией вплотную за стеной (первые кадры M19).
## Ближние ниже нашей башни — над её крышей видно небо и дальние ряды, —
## дальние выше: горизонт большого города растёт к центру.
const ROWS: Array[Vector3] = [
	# глубина, высота от, высота до
	Vector3(60.0, 30.0, 85.0),
	Vector3(100.0, 45.0, 120.0),
	Vector3(150.0, 60.0, 160.0),
	Vector3(220.0, 80.0, 200.0),
]

## Ширина дома, м: от узкой башни до квартала.
const WIDTH := Vector2(10.0, 30.0)

## Промежуток между домами ряда, м.
const GAP := Vector2(1.0, 6.0)

## Глубина дома, м.
const DEPTH: float = 12.0

## Шаг окон по фасаду, м: колонка и этаж. Этаж как у нашего здания — город
## того же масштаба.
const WINDOW_STEP := Vector2(2.4, Proportions.FLOOR)

## Сколько окон горит ночью.
const LIT_SHARE: float = 0.35

## Смешивается с сидом, чтобы город не повторял жребий раскладки здания.
const SALT: int = 0x0C17_7A11


## Кварталы вдоль здания от [param from_x] до [param to_x] по сиду. Ряд
## уходит за края с запасом: дальний ряд в перспективе виден шире ближнего.
static func generate(building_seed: int, from_x: float, to_x: float) -> Array[Block]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var blocks: Array[Block] = []
	for row in ROWS.size():
		var spec := ROWS[row]
		var reach := spec.x * 1.2
		var x := from_x - reach + rng.randf_range(0.0, WIDTH.x)
		while x < to_x + reach:
			var block := Block.new()
			block.row = row
			block.width = rng.randf_range(WIDTH.x, WIDTH.y)
			block.x = x + block.width * 0.5
			block.height = rng.randf_range(spec.y, spec.z)
			block.depth = DEPTH
			block.z = -spec.x - DEPTH * 0.5
			block.lit = _lit_windows(rng, block)
			blocks.append(block)
			x += block.width + rng.randf_range(GAP.x, GAP.y)
	return blocks


## Сколько колонок и этажей окон у фасада дома.
static func window_grid(block: Block) -> Vector2i:
	return Vector2i(
		maxi(int(block.width / WINDOW_STEP.x) - 1, 1),
		maxi(int(block.height / WINDOW_STEP.y) - 1, 1)
	)


static func _lit_windows(rng: RandomNumberGenerator, block: Block) -> Array[Vector2i]:
	var grid := window_grid(block)
	var lit: Array[Vector2i] = []
	for column in grid.x:
		for level in grid.y:
			if rng.randf() < LIT_SHARE:
				lit.append(Vector2i(column, level))
	return lit
