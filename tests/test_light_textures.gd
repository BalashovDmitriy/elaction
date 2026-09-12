extends GutTest

## Тесты профиля света.
##
## Профиль решает две вещи: ровно ли освещён этаж по всей ширине и не течёт ли
## свет за отведённую полосу на соседний. Обе проверяются числом, а не глазами.

const PLATEAU: float = 0.8


func test_the_middle_is_fully_lit() -> void:
	assert_eq(LightTextures.profile(0.0, PLATEAU), 1.0, "в середине свет полный")


func test_the_edge_is_dark() -> void:
	assert_eq(LightTextures.profile(1.0, PLATEAU), 0.0, "на краю света нет")


## Ноль ровно на краю — это то, из-за чего заливка не течёт на соседний этаж:
## её кладут точно по высоте пролёта, и за его пределами она уже не светит.
func test_light_stops_at_the_edges_of_its_area() -> void:
	var size := 120.0
	assert_eq(LightTextures.falloff(0.0, size, PLATEAU), 0.0, "у верхнего края")
	assert_eq(LightTextures.falloff(size, size, PLATEAU), 0.0, "у нижнего")
	assert_eq(LightTextures.falloff(size * 0.5, size, PLATEAU), 1.0, "в середине")


func test_plateau_keeps_the_middle_even() -> void:
	# При плато 0.8 ровная часть — это 80 % пути от середины к краю.
	assert_eq(LightTextures.profile(0.5, PLATEAU), 1.0, "половина пути — ещё плато")
	assert_lt(LightTextures.profile(0.9, PLATEAU), 1.0, "а девять десятых — уже спад")


func test_light_only_fades_outwards() -> void:
	var previous := 1.1
	for step: int in 21:
		var here := LightTextures.profile(float(step) / 20.0, PLATEAU)
		assert_lte(here, previous, "к краю свет только убывает, шаг %d" % step)
		previous = here


## Без плато профиль — обычное круглое пятно: спад начинается сразу от середины.
func test_a_spot_starts_fading_at_once() -> void:
	assert_lt(LightTextures.profile(0.25, 0.0), 1.0)
	assert_eq(LightTextures.profile(0.0, 0.0), 1.0, "но середина всё равно полная")


func test_beyond_the_edge_there_is_no_light() -> void:
	assert_eq(LightTextures.profile(2.0, PLATEAU), 0.0, "дальше края света не прибавляется")
	assert_eq(LightTextures.falloff(0.0, 0.0, PLATEAU), 0.0, "полоса нулевой ширины не светит")
