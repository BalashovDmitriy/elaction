class_name CityPlan
extends RefCounted

## Кварталы города за зданием: где стоят дома, какой высоты и какие окна горят
## (ADR-0029, решение 1).
##
## Только числа, без узлов: по ним строит [CityBackdrop], а тесты проверяют, что
## город повторяется по сиду и закрывает всю ширину кадра. Координаты — метры
## сцены города: x вдоль здания, y вверх от земли, z вглубь, от камеры прочь.

## Чем кончается дом сверху (M22, замечание пользователя — «больше детализации
## заднему фону»): плоская крыша, уступ, шпиль, бак, антенна. Силуэт горизонта
## и в размытии читается городом, а не рядом коробок.
enum Crown { FLAT, SETBACK, SPIRE, TANK, ANTENNA }

## Что за дом (M24a): контора, жилой, стеклянная башня, кирпичный. От этого
## тон фасада, переплёт окон и что за стеклом ([CityLook]).
enum Kind { OFFICE, HOMES, GLASS, BRICK }


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
	## Верх дома и мигает ли на нём красный огонь.
	var crown: Crown = Crown.FLAT
	var beacon: bool = false
	## Неоновая вывеска на фасаде: цвет (прозрачный — вывески нет), ширина и
	## высота, на какой высоте её середина.
	var sign_colour := Color(0.0, 0.0, 0.0, 0.0)
	var sign_size := Vector2.ZERO
	var sign_y: float = 0.0
	## Сдвиг вывески от середины фасада по x: вертикальная висит у угла.
	var sign_x: float = 0.0
	## Что за дом и какой у окон переплёт: 0 — нет, 1 — стойка, 2 — крест.
	var kind: Kind = Kind.OFFICE
	var mullions: int = 0


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

## С каким шансом у дома горит целый этаж.
const LIT_FLOOR_CHANCE: float = 0.35

## Доли верхов домов: плоских больше всего, шпилей меньше всего.
const CROWN_WEIGHTS: Array[float] = [0.4, 0.22, 0.1, 0.16, 0.12]

## С каким шансом у шпиля и антенны мигает огонь, и у высокого плоского дома.
const BEACON_CHANCE: float = 0.8

## С каким шансом на доме неоновая вывеска и какие у неё цвета: не цвета
## огоньков игры (ADR-0023, решение 6).
const SIGN_CHANCE: float = 0.4
const SIGN_COLOURS: Array[Color] = [
	Color(1.0, 0.25, 0.6),
	Color(0.3, 0.85, 1.0),
	Color(0.62, 0.35, 1.0),
	Color(0.75, 0.82, 1.0),
]

## Доли типов домов ([enum Kind]) и шанс, что вывеска вертикальная.
const KIND_WEIGHTS: Array[float] = [0.35, 0.3, 0.15, 0.2]
const VERTICAL_SIGN_CHANCE: float = 0.4

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
	_dress_crowns(blocks, building_seed)
	_dress_facades(blocks, building_seed)
	return blocks


## Тип дома, переплёт и вертикальные вывески — своим жребием, после верхов:
## раскладка, верхи и горящие окна по сиду те же, что до M24a.
static func _dress_facades(blocks: Array[Block], building_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "facades"])
	for block in blocks:
		block.kind = _weighted(rng, KIND_WEIGHTS) as Kind
		block.mullions = rng.randi_range(0, 2)
		if block.kind == Kind.GLASS:
			block.mullions = 1
		# Часть вывесок — вертикальные, у угла дома, как над входом в отель.
		if block.sign_colour.a > 0.0 and rng.randf() < VERTICAL_SIGN_CHANCE:
			var tall := minf(rng.randf_range(7.0, 14.0), block.height * 0.5)
			var wide := minf(rng.randf_range(1.8, 3.0), block.width * 0.3)
			block.sign_size = Vector2(wide, tall)
			block.sign_y = clampf(block.sign_y, tall * 0.5 + 3.0, block.height - tall * 0.5)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			block.sign_x = side * (block.width * 0.5 - wide * 0.5 - 0.6)


## Верхи и вывески — своим жребием, после раскладки: раскладка кварталов по
## сиду та же, что до M22, и её тесты не сдвигаются.
static func _dress_crowns(blocks: Array[Block], building_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "crowns"])
	for block in blocks:
		block.crown = _weighted(rng, CROWN_WEIGHTS) as Crown
		var tall := block.height > ROWS[block.row].z * 0.8
		var pointed := block.crown == Crown.SPIRE or block.crown == Crown.ANTENNA
		block.beacon = (pointed or tall) and rng.randf() < BEACON_CHANCE
		if rng.randf() < SIGN_CHANCE:
			block.sign_colour = SIGN_COLOURS[rng.randi_range(0, SIGN_COLOURS.size() - 1)]
			block.sign_size = Vector2(
				block.width * rng.randf_range(0.35, 0.7), rng.randf_range(2.0, 4.0)
			)
			# Где угодно по высоте, а не только под крышей: камера города видит
			# полосу домов на своей высоте, и вывеска под самой крышей близкого
			# дома с этажей не видна вовсе.
			block.sign_y = block.height * rng.randf_range(0.12, 0.9)
		# Горящие этажи — как у контор ночью: целая строка окон, на которой
		# видно, что дом живой. Своим списком, чтобы окна раскладки не менялись.
		if rng.randf() < LIT_FLOOR_CHANCE:
			var grid := window_grid(block)
			var level := rng.randi_range(0, grid.y - 1)
			for column in grid.x:
				var cell := Vector2i(column, level)
				if not block.lit.has(cell):
					block.lit.append(cell)


static func _weighted(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for index in weights.size():
		roll -= weights[index]
		if roll <= 0.0:
			return index
	return weights.size() - 1


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
