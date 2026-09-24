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

## Рёбра кровельных листов на ступенях: шаг и сечение, м.
const RIB_STEP: float = 0.45
const RIB := Vector2(0.05, 0.05)

## Сколько скат не доходит до машинного отделения, м.
const MACHINE_ROOM_GAP: float = 0.15

## Доля кладки палитры раунда в тоне скатов. Меньше, чем у стен
## ([constant BuildingShell.PALETTE_SHARE]), и от тона дальней стены, а не от
## стены коридора: скаты стоят позади игры и должны уходить в фон, а не
## спорить с парапетами (кадры M19).
const PALETTE_SHARE: float = 0.08


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
	var tone := GreyboxLook.SKY_WALL.lerp(rules.palette.masonry, PALETTE_SHARE)
	# Кровля — гравий (ADR-0033, решение 8), тон раунда множителем.
	var material := BuildingFinish.roof_gravel(tone)
	var depth := WorldSpace.ROOM_DEPTH
	var rib := GreyboxLook.metal(GreyboxLook.SKY_WALL.lerp(GreyboxLook.TRIM, 0.35))
	for rect in steps(rules, plan):
		var box := GreyboxLook.box(Vector3(rect.size.x, rect.size.y, depth), material)
		box.position = WorldSpace.to_scene(rect.get_center())
		box.position.z = WorldSpace.BACK_WALL_Z - depth * 0.5
		add_child(box)
		# Рёбра кровельных листов по верху ступени (ADR-0031, решение 2): глухая
		# коробка читалась стеной, а не кровлей.
		var count := int(rect.size.x / RIB_STEP)
		for index in count:
			var x := rect.position.x + RIB_STEP * (float(index) + 0.5)
			var strip := GreyboxLook.box(Vector3(RIB.x, RIB.y, depth), rib)
			strip.position = WorldSpace.to_scene(Vector2(x, rect.position.y - RIB.y * 0.5))
			strip.position.z = box.position.z
			add_child(strip)
