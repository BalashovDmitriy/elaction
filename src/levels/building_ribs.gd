class_name BuildingRibs
extends Node3D

## Рёбра здания: торцы плит, плинтус и пилястры (ADR-0023, решение 4).
##
## Проба показала: под мягким светом гладкая коробка читается пятном, и полкадра
## вытянули не источники, а рёбра — то, за что свету цепляться. В веху входят
## три, и только они; силуэт, шахты и обстановка остаются M18 и M19.
##
## Коробки без тел, своим узлом — как одежда шахт: частей выходит по полтора
## десятка на этаж, и под обход детей уровня они попадать не должны.

## Торец плиты: светлая полоса по переднему краю перекрытия — доля толщины
## плиты, на какой доле от верха лежит её середина и вынос вперёд, м.
const EDGE_SHARE: float = 0.35
const EDGE_DROP: float = 0.2
const EDGE_DEPTH: float = 0.12

## Плинтус по низу задней стены: тёмная панель и светлая рейка поверху, м.
const SKIRTING_HEIGHT: float = 0.9
const SKIRTING_DEPTH: float = 0.16
const RAIL_HEIGHT: float = 0.08
const RAIL_DEPTH: float = 0.2

## Пилястры: по краям каждого простенка и между местами этажа, м. Не доходят
## до пола и потолка на зазор.
const PILASTER_WIDTH: float = 0.45
const PILASTER_DEPTH: float = 0.22
const PILASTER_GAP: float = 0.1
## Ближе этого к краю простенка промежуточная пилястра не ставится: две рядом
## читаются столбом, а не ритмом.
const PILASTER_CLEARANCE: float = 1.0

## Мест этажа в одном конструктивном пролёте — через столько границ сетки стоит
## промежуточная пилястра.
##
## Ритм стены не обязан следовать сетке раскладки. В M18 сетка стала вдвое мельче
## (ADR-0024, решение 1), и пилястра на каждой границе встала бы через 1.8 м:
## вдвое чаще прежнего, вдвое больше коробок в кадре и частокол вместо ритма.
## Два места на пролёт возвращают прежний шаг.
##
## **Ритм несимметричен, и это принято как есть** (решение пользователя,
## 2026-09-22). Шаг в два места проходит границы 0–1, 2–3 … 14–15 и не доходит
## до 15–16, отчего на узкой башне пролёты ложатся со сдвигом от середины.
## Симметричного варианта при 17 местах и шаге в два места не существует вовсе:
## шестнадцать границ на два не делятся так, чтобы середина попала в стык.
## Выбор был между смещённым ритмом и неровным центральным пролётом — оставлен
## первый. Менять только вместе с числом мест.
const SLOTS_PER_BAY: int = 2

var _rules: BuildingRules
var _plan: BuildingPlan
var _identity: BuildingIdentity = BuildingIdentity.new()


func setup(
	rules: BuildingRules, plan: BuildingPlan, identity: BuildingIdentity = BuildingIdentity.new()
) -> void:
	_rules = rules
	_plan = plan
	_identity = identity


## Что за здание: по нему отделка стены и пилястр.
func identity() -> BuildingIdentity:
	return _identity


## Торец плиты по её переднему краю. [param slab] — кусок перекрытия в
## плоскости правил, тот же, из которого уровень строит тело.
func edge_of(slab: Rect2) -> void:
	var height := slab.size.y * EDGE_SHARE
	var strip := Rect2(
		slab.position.x,
		slab.position.y + slab.size.y * EDGE_DROP - height * 0.5,
		slab.size.x,
		height
	)
	_add_part(
		strip, GreyboxLook.metal(GreyboxLook.TRIM), WorldSpace.CORRIDOR_DEPTH * 0.5, EDGE_DEPTH
	)


## Плинтус и пилястры этажа — по простенкам задней стены между проёмами.
##
## [param inner] — стена от стены, [param openings] — проёмы дверей и выхода;
## проёмы шахт добавляются здесь: створки шахты стоят на той же стене.
func line_the_wall(index: int, inner: Vector2, openings: Array[Vector2]) -> void:
	var surface := _rules.floor_surface(index)
	var top := _rules.story_top(index)
	var gaps := openings.duplicate()
	# Проём шахты — с наличником портала: пилястра у края простенка иначе
	# вставала поверх хромированной рамки и прятала её (авторевью M21b).
	var half := _rules.shaft_width * 0.5 + BuildingShafts.PORTAL_JAMB
	for shaft in _plan.shafts:
		if index >= shaft.top and index <= shaft.bottom:
			gaps.append(Vector2(shaft.x - half, shaft.x + half))

	for span in BuildingPlan.spans_between(gaps, inner):
		_skirting(span, surface)
		_pilasters(span, top, surface)


func _skirting(span: Vector2, surface: float) -> void:
	var width := span.y - span.x
	_add_part(
		Rect2(span.x, surface - SKIRTING_HEIGHT, width, SKIRTING_HEIGHT),
		BuildingFinish.wainscot(_identity, _rules.palette.story),
		WorldSpace.BACK_WALL_Z,
		SKIRTING_DEPTH
	)
	_add_part(
		Rect2(span.x, surface - SKIRTING_HEIGHT - RAIL_HEIGHT, width, RAIL_HEIGHT),
		GreyboxLook.metal(GreyboxLook.TRIM),
		WorldSpace.BACK_WALL_Z,
		RAIL_DEPTH
	)


## Пилястры простенка: по одной у каждого его края и по одной между соседними
## местами этажа, если до краёв далеко. Ритм идёт по местам, а не по метрам:
## двери и шахты стоят по местам, и пилястры между ними ложатся ровно.
func _pilasters(span: Vector2, top: float, surface: float) -> void:
	var width := span.y - span.x
	if width < PILASTER_WIDTH:
		return
	var centres := PackedFloat64Array()
	if width < PILASTER_WIDTH * 2.0 + PILASTER_GAP:
		centres.append((span.x + span.y) * 0.5)
	else:
		centres.append(span.x + PILASTER_WIDTH * 0.5)
		centres.append(span.y - PILASTER_WIDTH * 0.5)
		for slot in range(0, _rules.slots - 1, SLOTS_PER_BAY):
			var middle := (_rules.slot_x(slot) + _rules.slot_x(slot + 1)) * 0.5
			if middle > span.x + PILASTER_CLEARANCE and middle < span.y - PILASTER_CLEARANCE:
				centres.append(middle)

	var height := surface - top - PILASTER_GAP * 2.0
	for centre in centres:
		_add_part(
			Rect2(centre - PILASTER_WIDTH * 0.5, top + PILASTER_GAP, PILASTER_WIDTH, height),
			BuildingFinish.pilaster(
				_identity, GreyboxLook.PILASTER.lerp(_rules.palette.masonry, 0.1)
			),
			WorldSpace.BACK_WALL_Z,
			PILASTER_DEPTH
		)


## Часть глубиной [param depth], задней гранью на [param face]: рёбра стоят
## на стене или на торце и выступают из них вперёд, к камере.
func _add_part(rect: Rect2, material: StandardMaterial3D, face: float, depth: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var part := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
	part.position = WorldSpace.to_scene(rect.get_center())
	part.position.z = face + depth * 0.5
	add_child(part)
