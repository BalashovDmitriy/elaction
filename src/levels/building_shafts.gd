class_name BuildingShafts
extends Node2D

## Одежда шахт здания: направляющие, створки этажей, упоры и машинное отделение.
##
## Своим узлом, а не прямыми детьми уровня. Частей выходит за полсотни на здание,
## а по детям уровня ходят и агенты, и кабины, и половина тестов — каждый такой
## обход перебирал бы ещё и стойки со створками. Ровно по этой причине из уровня
## в своё время вынесли [BuildingBackdrop].
##
## Тел здесь нет ни у чего: по направляющим не ходят, они только видны. Ездит
## кабина, а проём в перекрытии режет само перекрытие.

## Ширина направляющей шахты, px. Стойка идёт по краю проёма во всю его высоту.
const RAIL_WIDTH: float = 18.0

## Высота створок шахты, px. Совпадает с ассетом `shaft_door`.
const DOOR_HEIGHT: float = 102.0

## Высота упора в конце полосы шахты, px. Совпадает с ассетом `shaft_buffer`.
const BUFFER_HEIGHT: float = 24.0

## Надстройка машинного отделения на крыше, px. Совпадает с ассетом `machine_room`.
const MACHINE_ROOM_SIZE := Vector2(216.0, 132.0)

var _rules: BuildingRules
var _plan: BuildingPlan


## Одевает все шахты здания разом.
func dress(rules: BuildingRules, plan: BuildingPlan) -> void:
	_rules = rules
	_plan = plan
	# Тайлы берутся один раз на здание: шахт в нём пять, а этажей у них тридцать.
	var rail_tile := SpriteTextures.tile("shaft_rail")
	var door_tile := SpriteTextures.tile("shaft_door")
	var buffer_tile := SpriteTextures.tile("shaft_buffer")
	for shaft in plan.shafts:
		_dress_shaft(shaft, rail_tile, door_tile, buffer_tile)
	_spawn_machine_room()


## Верх шахты: докуда идут её стойки, упор и столб света.
##
## У шахты, доходящей до крыши, потолка нет — над ней небо, и [method
## BuildingRules.story_top] отдаёт верх мира. Стойка, упор и свет ушли бы в
## открытое небо над крышей; кончается такая шахта внутри машинного отделения,
## оно и есть её верх. Считается в одном месте, потому что разъехавшись эти трое
## дают шахту, которая светит выше, чем видна.
func top_of(shaft: BuildingPlan.ShaftSpot) -> float:
	if shaft.top > BuildingRules.ROOF:
		return _rules.story_top(shaft.top)
	return _rules.floor_surface(BuildingRules.ROOF) - MACHINE_ROOM_SIZE.y * 0.5


## Одевает шахту: направляющие во всю её высоту и створки на каждом её этаже.
##
## До M12 шахта была дырой в перекрытии со столбом света — в кадре её почти не
## было, хотя спуск по зданию и есть игра (ADR-0017, решение 3). Направляющие
## дают ей края, створки — отметку этажа: по ним видно, где кабина встаёт.
##
## Рисуется позади перекрытий (`z_index` −2): стойка идёт сквозь всю шахту, и
## на каждом этаже её перекрывает плита — ровно так, как она и шла бы внутри
## шахты. Кабина идёт впереди и закрывает их собой, когда проходит мимо.
func _dress_shaft(
	shaft: BuildingPlan.ShaftSpot,
	rail_tile: CanvasTexture,
	door_tile: CanvasTexture,
	buffer_tile: CanvasTexture
) -> void:
	_mark_shaft_ends(shaft, buffer_tile)
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom)
	var half := _rules.shaft_width * 0.5
	var tint := _rules.palette.shaft

	for side: float in [-1.0, 1.0]:
		var x := shaft.x + half * side
		var left := x if side < 0.0 else x - RAIL_WIDTH
		_add_part(Rect2(left, top, RAIL_WIDTH, bottom - top), rail_tile, tint)

	for index: int in range(shaft.top, shaft.bottom + 1):
		var surface := _rules.floor_surface(index)
		var door := Rect2(shaft.x - half, surface - DOOR_HEIGHT, _rules.shaft_width, DOOR_HEIGHT)
		_add_part(door, door_tile, tint, true)


## Упоры в концах полосы: дальше кабина не идёт, и это видно.
##
## Отзыв после игры: «лифт не слушается команд и стоит, а сошёл — уехал». Это
## и был конец полосы — кабина слышала команду, но идти дальше ей некуда, а
## пустая она тут же уезжала по своему расписанию. Упор объясняет предел без
## единого слова; второй указатель — стрелки в самой кабине.
##
## Нижний упор лежит на дне шахты, то есть над полом нижнего её этажа, а не под
## ним: перекрытие рисуется ближе к зрителю (`z_index` −1 против −2), и упор,
## опущенный в толщу плиты, не виден вовсе — ровно там, где предел и надо
## объяснить.
func _mark_shaft_ends(shaft: BuildingPlan.ShaftSpot, tile: CanvasTexture) -> void:
	var half := _rules.shaft_width * 0.5
	var top := top_of(shaft)
	var bottom := _rules.floor_surface(shaft.bottom) - BUFFER_HEIGHT

	_add_part(
		Rect2(shaft.x - half, top, _rules.shaft_width, BUFFER_HEIGHT), tile, Color.WHITE, true
	)
	_add_part(
		Rect2(shaft.x - half, bottom, _rules.shaft_width, BUFFER_HEIGHT), tile, Color.WHITE, true
	)


## Кусок одежды шахты. Без тела: по направляющим не ходят, они только видны.
##
## [param whole] — ассет кладётся целиком, а не плиткой. Стойка тайлится: она
## идёт на сотни пикселей, а тайл у неё в шестнадцать. Створки — одна картинка
## шириной в шахту, и замостить её значило бы порезать их пополам, стоит
## [member BuildingRules.shaft_width] разойтись с ассетом.
func _add_part(rect: Rect2, tile: CanvasTexture, tint: Color, whole: bool = false) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var part := (
		TiledRect.stretched(rect.size, rect.position, tile, tint)
		if whole
		else TiledRect.make(rect.size, rect.position, tile, tint)
	)
	part.z_index = -2
	add_child(part)


## Надстройка машинного отделения над верхней шахтой.
##
## Тела у неё нет намеренно: под ней проём той самой шахты, с которой начинается
## спуск, и сплошная надстройка заперла бы Otto на крыше. Стоит она позади него
## (`z_index` −2), и он проходит перед ней.
func _spawn_machine_room() -> void:
	var shaft := _plan.roof_shaft()
	if shaft == null:
		return

	var surface := _rules.floor_surface(BuildingRules.ROOF)
	var rect := Rect2(
		Vector2(shaft.x - MACHINE_ROOM_SIZE.x * 0.5, surface - MACHINE_ROOM_SIZE.y),
		MACHINE_ROOM_SIZE
	)
	# Не плиткой, а целиком: у домика рисунок цельный, и замостить его значило
	# бы порезать крышу на четверти.
	var room := TiledRect.stretched(
		rect.size, rect.position, SpriteTextures.tile("machine_room"), _rules.palette.masonry
	)
	room.z_index = -2
	add_child(room)
