class_name BuildingBackdrop
extends Node2D

## Дальний план здания: задние стены с окнами и город за ними.
##
## Всё, что рисуется позади действия и ни с чем не сталкивается. Вынесено из
## [GreyboxLevel] отдельным узлом, когда тот перерос тысячу строк: у дальнего
## плана своя глубина, свой параллакс и своё правило света — город не
## освещается зданием вовсе.
##
## Тон этажей задаёт палитра раунда: стены нарисованы серыми, и цвет им даётся
## умножением ([ADR-0017](../../docs/adr/0017-spectrum-palette-and-shafts.md),
## решение 2).

## Окна в задней стене: сколько на этаже и какого размера.
const WINDOWS_PER_FLOOR: int = 6
const WINDOW_SIZE := Vector2(150.0, 100.0)
## На сколько ниже потолка начинается окно, px.
const WINDOW_TOP: float = 42.0

## Город за окнами: силуэт и горящие окна. Само небо — цвет узла Background
## в сцене, там же, где сам узел.
const CITY := Color(0.12, 0.14, 0.24)
const CITY_WINDOW := Color(0.92, 0.83, 0.50)

## Насколько город отстаёт от камеры: 1 — бесконечно далёк и стоит на месте.
## По вертикали больше, чем по горизонтали: здание высокое, и город, бегущий
## вниз наравне со спуском, читался бы как соседняя стена, а не как даль.
const CITY_PARALLAX := Vector2(0.86, 0.94)

## Полоса, в которой стоит город, в координатах его собственного слоя.
const CITY_AREA := Rect2(0.0, 120.0, 3840.0, 1500.0)

## Город: он один на здание и ездит за камерой медленнее неё.
var _city: Node2D = null
## Задние стены этажей. Их под три сотни, и держать их прямо в уровне значит
## заставить каждый обход детей уровня перебирать ещё и их.
var _walls: Node2D = null


## Окна этажа: равные проёмы в задней стене, через которые виден город.
##
## Статический, чтобы проверяться без сцены, — как и [method GreyboxLevel.slab_segments].
## [param bounds] — внутренние края стены, между которыми раскладываются окна.
static func window_gaps(bounds: Vector2, count: int, window_width: float) -> Array[Vector2]:
	var gaps: Array[Vector2] = []
	var width := bounds.y - bounds.x
	if count <= 0 or window_width <= 0.0 or width <= 0.0:
		return gaps

	var pitch := width / float(count)
	for number: int in count:
		# Окно стоит посередине своей доли стены: так они разнесены поровну
		# и у стен здания остаётся полполосы, а не обрезанное окно.
		var centre := bounds.x + pitch * (float(number) + 0.5)
		var half := minf(window_width, pitch) * 0.5
		gaps.append(Vector2(centre - half, centre + half))
	return gaps


## Собирает дальний план здания. [param wall_width] — толщина боковой стены:
## окна режутся по внутренним краям этажа, а не по его габариту.
##
## Раскладка сюда не приходит нарочно: за окнами нет ни шахт, ни дверей — только
## стена, рамы и город, а их место выводится из одних правил.
func build(rules: BuildingRules, building_seed: int, wall_width: float) -> void:
	_build_city(building_seed)
	_build_walls(rules, wall_width)


## Двигает город вслед за камерой. Оттого он и кажется далёким.
func follow(view: Rect2) -> void:
	if _city != null:
		_city.position = view.position * CITY_PARALLAX


## Город за окнами. Свет здания на него не падает: он снаружи и далеко.
func _build_city(building_seed: int) -> void:
	_city = Node2D.new()
	_city.z_index = -9
	add_child(_city)

	var stone := SpriteTextures.tile("city_wall")
	for tower: Skyline.Tower in Skyline.generate(building_seed, CITY_AREA):
		_add_city_panel(tower.rect, CITY, stone)
		for window: Rect2 in tower.windows:
			# Окно города — источник, а не поверхность: рельеф ему ни к чему.
			_add_city_panel(window, CITY_WINDOW, null)


## Кусок дальнего плана: башня с текстурой или окно, которое рисуется заливкой.
##
## Маска гасится на каждой панели, а не на общем узле: [member CanvasItem.light_mask]
## детям не передаётся, и город в окне разгорался вместе с этажом — окно читалось
## как освещённая ниша, а не как улица.
func _add_city_panel(rect: Rect2, color: Color, tile: CanvasTexture = null) -> void:
	var panel: Control = (
		TiledRect.fill(rect.size, rect.position, color)
		if tile == null
		else TiledRect.make(rect.size, rect.position, tile)
	)
	panel.light_mask = 0
	_city.add_child(panel)


## Задняя стена: сплошная, кроме окон. Через окна виден город.
##
## Стена кладётся тремя полосами: над окнами, по окнам и под ними. Резать её
## по горизонтали умеет [method BuildingPlan.spans_between] — та же функция,
## что режет перекрытия проёмами.
func _build_walls(rules: BuildingRules, wall_width: float) -> void:
	_walls = Node2D.new()
	_walls.z_index = -8
	# Тон раунда — на весь узел разом: стен и рам под три сотни, и красить их
	# по одной значило бы держать цвет в трёхстах местах (ADR-0017, решение 2).
	_walls.modulate = rules.palette.story
	add_child(_walls)

	# Тайлы берутся один раз на здание: полос и рам под три сотни, а текстур две.
	var wall_tile := SpriteTextures.tile("wall")
	var frame_tile := SpriteTextures.tile("window_frame")
	# Этажи, крыши среди них нет: она снаружи, комнаты за ней не бывает, и стена
	# вышла бы полосой в небе над тем местом, где Otto начинает.
	for index: int in rules.floors:
		var top := rules.story_top(index)
		var surface := rules.floor_surface(index)
		if surface - top <= 0.0:
			continue

		# Окна режутся по ширине своего этажа: на узких этажах стена короче,
		# и окна, разложенные по ширине здания, уехали бы за неё на улицу.
		var bounds := rules.floor_span(index)
		var inner := Vector2(bounds.x + wall_width, bounds.y - wall_width)
		var gaps := window_gaps(inner, WINDOWS_PER_FLOOR, WINDOW_SIZE.x)

		var window_top := minf(top + WINDOW_TOP, surface)
		var window_bottom := minf(window_top + WINDOW_SIZE.y, surface)
		var width := inner.y - inner.x
		_add_wall(Rect2(inner.x, top, width, window_top - top), wall_tile)
		_add_wall(Rect2(inner.x, window_bottom, width, surface - window_bottom), wall_tile)

		for span: Vector2 in BuildingPlan.spans_between(gaps, inner):
			var strip := Rect2(span.x, window_top, span.y - span.x, window_bottom - window_top)
			_add_wall(strip, wall_tile)

		for gap: Vector2 in gaps:
			var opening := Rect2(gap.x, window_top, gap.y - gap.x, window_bottom - window_top)
			_add_window_frame(opening, frame_tile)


func _add_wall(rect: Rect2, tile: CanvasTexture) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	_walls.add_child(TiledRect.make(rect.size, rect.position, tile))


## Рама вокруг проёма, в котором виден город.
##
## Кладётся девятикусочно и наполовину заходит на стену: так проём получает
## откос, на котором играет свет этажа, а город в нём остаётся городом —
## середина рамы пустая, а не застеклённая.
func _add_window_frame(opening: Rect2, tile: CanvasTexture) -> void:
	if opening.size.x <= 0.0 or opening.size.y <= 0.0:
		return

	var overlap := SpriteTextures.FRAME_MARGIN * 0.5
	var frame := NinePatchRect.new()
	frame.texture = tile
	frame.draw_center = false
	frame.patch_margin_left = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_top = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_right = int(SpriteTextures.FRAME_MARGIN)
	frame.patch_margin_bottom = int(SpriteTextures.FRAME_MARGIN)
	frame.position = opening.position - Vector2(overlap, overlap)
	frame.size = opening.size + Vector2(overlap, overlap) * 2.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walls.add_child(frame)
