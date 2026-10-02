class_name RoofCatch
extends RefCounted

## Чем крыша ловит то, что падает с неба: дождь ([RoofRain]) и снег
## ([RoofSnow]). Частицы гаснут не по таймеру, а о саму крышу — по карте
## высот, снятой сверху с настила, ступеней, парапетов, машинного отделения и
## техники (ADR-0037, решение 3). Одно место на обе погоды: разведи их — и
## снег падал бы в шахту там, где дождь уже гаснет о крышку.
##
## Карта снимается один раз и только со слоя [constant LAYER]: на него
## [method mark] переводит неподвижное на крыше. Otto и агенты в ней не
## числятся — снятые на месте, где стояли при сборке, они оставили бы в
## осадках дыру в форме человека.

## Слой, с которого снимается карта высот и на который ложатся мокрый настил и
## снежный покров. Двадцатый: остальные слои в проекте не заняты, и камеры и
## свет видят все двадцать.
const LAYER: int = 1 << 19

## Толщина крышки над проёмом крыши, м: частица за шаг проходит до 15 см.
const LID_DEPTH: float = 0.4


## Коробка над крышей, где идут осадки: по ширине крыши с отливами, по глубине
## от [param back_z] до [param front_z], высотой [param height] над настилом.
static func box(rules: BuildingRules, back_z: float, front_z: float, height: float) -> AABB:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	var edge := BuildingShell.COPING_OVERHANG + 0.1
	return AABB(
		Vector3(bounds.x - edge, deck - 0.6, back_z - 0.3),
		Vector3(bounds.y - bounds.x + edge * 2.0, height + 1.0, front_z - back_z + 0.6)
	)


## Карта высот, снимаемая с коробки [param over].
static func catcher(over: AABB, name: String) -> GPUParticlesCollisionHeightField3D:
	var caught := GPUParticlesCollisionHeightField3D.new()
	caught.name = name
	caught.size = over.size
	caught.position = over.get_center()
	caught.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	caught.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	caught.heightfield_mask = LAYER
	return caught


## Невидимые крышки над проёмами в плите крыши — над верхней шахтой.
##
## Машинное отделение накрывает шахту только у задней стены, а проём идёт
## сквозь плиту на всю глубину. Капли и снежинки перед домиком падали бы в
## шахту и дальше вниз — перед порталом тридцатого этажа, то есть осадками в
## здании. Крышка — на уровне настила: верх чуть выше него, на шаг частиц
## [param step], и частица гаснет вровень с настилом, а не под ним.
static func lids(
	rules: BuildingRules, plan: BuildingPlan, over: AABB, step: float
) -> Array[GPUParticlesCollisionBox3D]:
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	var made: Array[GPUParticlesCollisionBox3D] = []
	for gap in plan.gaps_on(rules, BuildingRules.ROOF):
		var lid := GPUParticlesCollisionBox3D.new()
		lid.name = "Lid"
		lid.size = Vector3(gap.y - gap.x + 0.1, LID_DEPTH, over.size.z)
		var top := deck + step
		lid.position = Vector3((gap.x + gap.y) * 0.5, top - LID_DEPTH * 0.5, over.get_center().z)
		made.append(lid)
	return made


## Переводит на слой [constant LAYER] неподвижное на крыше под [param roots],
## что задевает коробку [param over].
static func mark(roots: Array[Node], over: AABB) -> void:
	for root in roots:
		for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
			var shape := node as GeometryInstance3D
			if shape is GPUParticles3D:
				continue
			if shape.get_aabb().size == Vector3.ZERO:
				continue
			var reach := shape.global_transform * shape.get_aabb()
			if reach.intersects(over):
				shape.layers |= LAYER
