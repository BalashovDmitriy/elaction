class_name BuildingRoof
extends Node3D

## Скаты крыши ступенями по бокам шахты (ADR-0029, решение 4).
##
## В оригинале над тридцатым этажом крыша поднимается ступенями к шахте с обеих
## сторон, и кадр читается верхом дома. У нас это силуэт за плоскостью игры:
## ступени стоят позади коридора, без тел, а Otto ходит по плоскому настилу —
## путь, бот и проверки проходимости не меняются.

## Сколько ступеней в скате.
const STEPS: int = 4

## Высота ступени, м. Верхняя ступень ниже машинного отделения
## ([constant BuildingShafts.MACHINE_ROOM_SIZE]): шахта выходит над скатами,
## как в оригинале.
const STEP_RISE: float = 0.3

## Сколько скат не доходит до машинного отделения, м.
const MACHINE_ROOM_GAP: float = 0.15


## Ступени скатов прямоугольниками правил: x вдоль крыши, y — от верха ступени
## до настила. Левый скат поднимается слева направо, правый — справа налево.
##
## Статический: геометрию проверяют без сцены — ступени внутри крыши и не
## заходят на машинное отделение.
static func steps(rules: BuildingRules, plan: BuildingPlan) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var shaft := plan.roof_shaft()
	if shaft == null:
		return rects
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var inner := Vector2(bounds.x + BuildingShell.WALL_WIDTH, bounds.y - BuildingShell.WALL_WIDTH)
	var half_room := BuildingShafts.MACHINE_ROOM_SIZE.x * 0.5 + MACHINE_ROOM_GAP
	var surface := rules.floor_surface(BuildingRules.ROOF)
	var sides: Array[Vector2] = [
		Vector2(inner.x, shaft.x - half_room), Vector2(shaft.x + half_room, inner.y)
	]
	for side in sides.size():
		var span := sides[side]
		var length := span.y - span.x
		if length <= 0.0:
			continue
		var run := length / float(STEPS)
		for step in STEPS:
			# Ступень лежит от своего края до машинного отделения: нижние шире,
			# верхние уже, и вместе они складываются в скат.
			var rise := STEP_RISE * float(step + 1)
			var from := span.x + run * float(step) if side == 0 else span.x
			var to := span.y if side == 0 else span.y - run * float(step)
			rects.append(Rect2(from, surface - rise, to - from, rise))
	return rects


## Ставит скаты по правилам и плану. Цвет — кладка палитры раунда, приглушённая
## к серому: крыша — фон, а не вывеска (ADR-0029, решение 5).
func build(rules: BuildingRules, plan: BuildingPlan) -> void:
	var tone := GreyboxLook.SKY_WALL.lerp(rules.palette.masonry, 0.08)
	var material := GreyboxLook.surface(tone)
	var depth := WorldSpace.ROOM_DEPTH
	for rect in steps(rules, plan):
		var box := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
		box.position = WorldSpace.to_scene(rect.get_center())
		box.position.z = WorldSpace.BACK_WALL_Z - depth * 0.5
		add_child(box)
