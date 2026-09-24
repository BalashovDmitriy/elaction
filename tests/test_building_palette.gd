extends GutTest

## Палитра раунда: набор цветов, которым красится здание.
##
## Главное здесь — не красота, а читаемость: погашенный этаж должен отличаться
## от горящего оттенком, а не яркостью, потому что в темноте агенты продолжают
## стрелять (ADR-0010, пункт 3; ADR-0017, решение 2). Свободно гуляющий цвет
## рано или поздно даст раунд, где погашенный этаж не читается, — и найдётся
## это уже игроком.

## Насколько горящий этаж ярче погашенного. Меньше — и разница читается как
## «чуть темнее», а не как «свет выключили».
const LIGHT_GAP: float = 0.25

## Ниже этого погашенный этаж считается чёрным.
##
## Разрыв с горящим сам по себе этого не стережёт: при достаточно ярком горящем
## его проходит и чёрный тон. А чёрным погашенный этаж быть не должен — в темноте
## агенты продолжают стрелять, у них лишь падает дальность (ADR-0007, пункт 4),
## и этаж, на котором врага не видно, был бы смертью ни за что.
const DARK_FLOOR: float = 0.25

## Насколько далеко тона расходятся по кругу оттенков, доля от полного круга.
const HUE_GAP: float = 0.04

## Насколько тон шахты и кладки отличается от тона этажа.
##
## Мерка не по оттенку, а по расстоянию в RGB: синяя шахта на бирюзовой стене
## разнится в первую очередь яркостью, и по одному оттенку такая пара считалась
## бы неразличимой, хотя в кадре её видно за версту. Одинаковые цвета дают ноль,
## соседние оттенки одной яркости — около 0.05, самая близкая пара набора — 0.26.
const APART: float = 0.25


## Расстояние между оттенками по кругу: 0.5 — противоположные.
func _hue_gap(first: Color, second: Color) -> float:
	var raw := absf(first.h - second.h)
	return minf(raw, 1.0 - raw)


## Насколько два цвета различимы на глаз: взвешенное расстояние в RGB.
##
## Веса — по чувствительности глаза: зелёный весит больше красного, красный
## больше синего. Делится на три, чтобы чёрное с белым давали единицу.
func _apart(first: Color, second: Color) -> float:
	var dr := first.r - second.r
	var dg := first.g - second.g
	var db := first.b - second.b
	return sqrt(2.0 * dr * dr + 4.0 * dg * dg + 3.0 * db * db) / 3.0


func test_every_round_keeps_the_dark_floor_readable() -> void:
	for number: int in range(1, BuildingPalette.count() + 1):
		var palette := BuildingPalette.of_round(number)
		# Горящий этаж — свет лампы: он и отличает его от погашенного (ADR-0010).
		var lit := Lamp.LIGHT_COLOR.get_luminance()
		var dark := palette.dark.get_luminance()
		assert_gt(lit - dark, LIGHT_GAP, "раунд %d: погашенный этаж не темнее горящего" % number)
		assert_gt(dark, DARK_FLOOR, "раунд %d: погашенный этаж ушёл в чёрное" % number)
		assert_gt(
			_hue_gap(Lamp.LIGHT_COLOR, palette.dark),
			HUE_GAP,
			"раунд %d: погашенный отличается только яркостью" % number
		)


func test_every_round_keeps_the_shaft_apart_from_the_wall() -> void:
	for number: int in range(1, BuildingPalette.count() + 1):
		var palette := BuildingPalette.of_round(number)
		assert_gt(
			_apart(palette.shaft, palette.story),
			APART,
			"раунд %d: шахта не отличается от стены" % number
		)
		assert_gt(
			_apart(palette.masonry, palette.story),
			APART,
			"раунд %d: кладка не отличается от стены" % number
		)


## Набор конечный и зацикливается: раунды в оригинале идут по кругу.
func test_the_set_repeats_itself() -> void:
	var size := BuildingPalette.count()
	assert_gt(size, 1, "раунды должны отличаться хоть чем-то")
	assert_eq(BuildingPalette.of_round(size + 1), BuildingPalette.of_round(1), "набор по кругу")
	assert_eq(BuildingPalette.of_round(size + 2), BuildingPalette.of_round(2))


## Нулевой и отрицательный раунд не должны валить игру: номер приходит из
## состояния партии, и однажды он уже приходил нулём.
func test_a_round_below_one_still_gets_a_palette() -> void:
	assert_eq(BuildingPalette.of_round(0), BuildingPalette.of_round(1))
	assert_eq(BuildingPalette.of_round(-3), BuildingPalette.of_round(1))


## Палитра — такое же правило здания, как злость агентов.
func test_rules_take_the_palette_of_their_round() -> void:
	for number: int in [1, 2, 3, 4, 5, 9]:
		var rules := BuildingRules.for_building(number)
		assert_eq(rules.palette, BuildingPalette.of_round(number), "раунд %d" % number)


## Здания подряд отличаются на глаз — это и есть DoD вехи.
##
## Последняя пара — не «четвёртый и пятый», а «четвёртый и первый»: набор идёт
## по кругу, и на его стыке раунды тоже соседние. Без этой пары набор мог бы
## замкнуться сам на себя одним и тем же цветом, и заметил бы это игрок.
func test_neighbouring_rounds_differ() -> void:
	for number: int in range(1, BuildingPalette.count() + 1):
		var here := BuildingPalette.of_round(number)
		var next := BuildingPalette.of_round(number + 1)
		assert_gt(
			_hue_gap(here.story, next.story),
			HUE_GAP,
			"раунды %d и %d красят этаж одинаково" % [number, number + 1]
		)
