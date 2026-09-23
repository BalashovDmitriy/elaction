class_name BuildingShell
extends Node3D

## Оболочка здания: перекрытия, наружные стены, внутренние стены и комната
## за коридором.
##
## Своим узлом, как [BuildingShafts] и [BuildingRibs]: уровень собирает здание из
## нескольких строителей, и держать их в одном файле — значит держать в одном
## файле всё здание разом. Правил тут нет, только геометрия по готовой раскладке.
##
## Что чем режется, решает [BuildingPlan], и счёта у него два: плита — проёмами
## ([method BuildingPlan.gaps_on]), ходьба — проёмами и стенами (ADR-0024,
## решение 5). Оболочка строит по первому: стена стоит на плите, а не вместо неё.

## Толщина наружной стены уровня, м.
const WALL_WIDTH: float = 0.48

## Толщина стены, у которой нет тела: её только видно.
const PANEL_THICKNESS: float = 0.1

## Ширина выхода из здания, м. Здесь, а не в уровне: оболочка режет ею проём
## в задней стене, а уровень ставит в этот проём саму дверь выхода и вывеску —
## и мерить один проём двумя числами нельзя.
##
## С Otto в M18c не вырос, а сузился: шире его не пускает шаг места. Кабина
## соседней шахты начинается в 0.9 м от середины выхода, и прежние 1.92 м
## заходили за неё на 6 см; 2.56 м, которые дал бы рост в 4/3, вырезали бы ещё
## и стену над соседней дверью (ADR-0026, решение 7). Otto шириной 0.72 проходит
## в 1.68 свободно.
const EXIT_WIDTH: float = Proportions.EXIT_WIDTH

## Насколько тон палитры раунда входит в материалы: задняя стена берёт тон
## этажа, наружные стены — кладку (ADR-0029, решение 5). Немного: палитра —
## оттенок раунда, а не заливка, и читаемость держится на всех.
const PALETTE_SHARE: float = 0.18

## Во сколько раз задняя стена тёмного этажа темнее светлой (ADR-0029, решение 6).
## Кадры M18e: на сумрачной башне тёмный этаж без ламп отличался от светлого
## слабо — стена отражала общий тон так же, как на светлом.
const UNLIT_SHADE: float = 0.45

var _rules: BuildingRules = null
var _plan: BuildingPlan = null
var _ribs: BuildingRibs = null
## Стены без тел отдельным узлом: их много, и в дереве они не должны мешаться
## среди тел, по которым ходят.
var _panels: Node3D = null


## Куски перекрытия уровня прямоугольниками правил.
##
## Статический и публичный: по нему проверяют, что проём режет плиту именно там,
## где обещала раскладка, — без сцены и без узлов.
static func slab_segments(
	surface: float, gaps: Array[Vector2], bounds: Vector2, thickness: float
) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for span in BuildingPlan.spans_between(gaps, bounds):
		rects.append(Rect2(span.x, surface, span.y - span.x, thickness))
	return rects


## Строит оболочку целиком. [param ribs] получает торцы плит и простенки —
## рёбра ставятся по той же геометрии, что и стены, и вторым обходом разъехались бы.
func build(rules: BuildingRules, plan: BuildingPlan, ribs: BuildingRibs) -> void:
	_rules = rules
	_plan = plan
	_ribs = ribs
	_panels = Node3D.new()
	_panels.name = "Panels"
	add_child(_panels)

	_build_floors()
	_build_room()


func _build_floors() -> void:
	# Перекрытие — пол: полированный, в него ложатся отражения (ADR-0023, решение 5).
	var slab := GreyboxLook.polished(GreyboxLook.SLAB)
	var wall := GreyboxLook.surface(GreyboxLook.WALL.lerp(_rules.palette.masonry, PALETTE_SHARE))

	for index: int in _rules.levels():
		var surface := _rules.floor_surface(index)
		var bounds := _rules.floor_span(index)
		var gaps := _plan.gaps_on(_rules, index)
		# Перекрытие шире собственных стен там, где силуэт делает ступень: оно же
		# потолок нижнего этажа, а тот шире своего верхнего соседа.
		for rect in slab_segments(surface, gaps, _rules.slab_span(index), _rules.slab_height):
			_build_solid(rect, slab)
			_ribs.edge_of(rect)
		_build_side_walls(index, surface, bounds, wall)
		_build_inner_walls(index, surface, wall)


## Внутренние стены этажа: глухие, от пола до потолка (ADR-0024, решение 5).
##
## Сквозь них не проходят ни люди, ни пули, и агент за стеной Otto не достаёт.
## Где они стоят, решает раскладка: она же убрала те, что запирали документ или
## выход, и граф достижимости считает куски этажа уже с ними.
func _build_inner_walls(index: int, surface: float, material: StandardMaterial3D) -> void:
	# От низа перекрытия сверху до пола: стена стоит на плите, а не вместо неё.
	var top := _rules.story_top(index)
	var height := surface - top
	if height <= 0.0:
		return
	for inner_wall in _plan.walls:
		if inner_wall.floor_index != index:
			continue
		var band := inner_wall.band(_rules)
		_build_solid(Rect2(band.x, top, band.y - band.x, height), material)


## Боковые стены уровня. Идут ступенями вслед за силуэтом, а не сплошными
## столбцами во всю высоту: здание расширяется книзу (ADR-0014, пункт 3).
##
## У крыши стена доходит до верха мира: это парапет, и он же не даёт шагнуть
## с крыши мимо здания. Прыжок берёт 2.4 м, и низкий бортик Otto перемахнул бы.
func _build_side_walls(
	index: int, surface: float, bounds: Vector2, material: StandardMaterial3D
) -> void:
	var top := _rules.story_top(index)
	var height := surface + _rules.slab_height - top
	if height <= 0.0:
		return

	_build_solid(Rect2(bounds.x, top, WALL_WIDTH, height), material)
	_build_solid(Rect2(bounds.y - WALL_WIDTH, top, WALL_WIDTH, height), material)


## Комната за коридором: задняя стена с проёмами дверей и дальняя стена.
##
## Это и есть глубина кадра по ADR-0021, решение 1: игра идёт в плоскости, а
## объём — за задней стеной, и виден он в проёмы. Проёмы режутся тем же
## [method BuildingPlan.spans_between], что и перекрытия: дверь занимает в стене
## ровно свою ширину, над ней — перемычка до потолка.
##
## Крыша стены не получает: над ней небо, а за ней — город ([CityBackdrop]).
func _build_room() -> void:
	var tone := GreyboxLook.BACK_WALL.lerp(_rules.palette.story, PALETTE_SHARE)
	var lit_back := GreyboxLook.surface(tone)
	var unlit_back := GreyboxLook.surface(
		Color(tone.r * UNLIT_SHADE, tone.g * UNLIT_SHADE, tone.b * UNLIT_SHADE)
	)
	var far := GreyboxLook.surface(GreyboxLook.SKY_WALL)
	var back_z := WorldSpace.BACK_WALL_Z - PANEL_THICKNESS * 0.5
	var far_z := WorldSpace.BACK_WALL_Z - WorldSpace.ROOM_DEPTH

	for index: int in _rules.levels():
		if index == BuildingRules.ROOF:
			continue
		var surface := _rules.floor_surface(index)
		var top := _rules.story_top(index)
		var bounds := _rules.floor_span(index)
		var inner := Vector2(bounds.x + WALL_WIDTH, bounds.y - WALL_WIDTH)
		var back := unlit_back if _rules.is_unlit(index) else lit_back

		var openings := _openings_on(index)
		var lintel_top := surface - Door.LEAF_SIZE.y
		for span in BuildingPlan.spans_between(openings, inner):
			_build_panel(Rect2(span.x, top, span.y - span.x, surface - top), back, back_z)
		for opening in openings:
			_build_panel(
				Rect2(opening.x, top, opening.y - opening.x, lintel_top - top), back, back_z
			)
		_ribs.line_the_wall(index, inner, openings)

		_build_panel(Rect2(inner.x, top, inner.y - inner.x, surface - top), far, far_z)


## Проёмы в задней стене этажа: двери и, на нижнем, выход.
func _openings_on(index: int) -> Array[Vector2]:
	var openings: Array[Vector2] = []
	var half := Door.LEAF_SIZE.x * 0.5
	for spot in _plan.doors:
		if spot.floor_index == index:
			openings.append(Vector2(spot.x - half, spot.x + half))
	if index == _rules.floors - 1:
		var exit_half := EXIT_WIDTH * 0.5
		openings.append(Vector2(_plan.exit_x - exit_half, _plan.exit_x + exit_half))
	return openings


## Коробка с телом на месте прямоугольника правил: по ней ходят и об неё
## останавливаются пули.
##
## Глубиной на коридор и комнату вместе: перекрытие — пол не только коридора,
## но и комнаты за стеной, иначе в проём двери было бы видно пустоту под ногами.
## Передняя грань приходится на переднюю грань коридора, а не на плоскость игры.
func _build_solid(rect: Rect2, material: StandardMaterial3D) -> void:
	var depth := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var size := Vector3(rect.size.x, rect.size.y, depth)
	var centre := WorldSpace.to_scene(rect.get_center())
	centre.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5

	var body := StaticBody3D.new()
	body.position = centre

	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.add_child(GreyboxLook.box(size, material))

	add_child(body)


## Стена, которая только видна: без тела, толщиной [constant PANEL_THICKNESS],
## серединой на [param z].
func _build_panel(rect: Rect2, material: StandardMaterial3D, z: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var panel := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, PANEL_THICKNESS), material)
	panel.position = WorldSpace.to_scene(rect.get_center())
	panel.position.z = z
	_panels.add_child(panel)
