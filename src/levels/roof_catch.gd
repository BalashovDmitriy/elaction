class_name RoofCatch
extends RefCounted

## How the roof catches what falls from the sky: rain ([RoofRain]) and snow ([RoofSnow]). Particles
## die not by a timer but on the roof itself — by a height map taken from above from the deck,
## steps, parapets, machine room and equipment (ADR-0037, decision 3). One place for both weathers:
## separate them — and snow would fall into the shaft where rain already dies on the lid.
##
## The map is taken once and only from layer [constant LAYER]: [method mark] moves stationary things
## on the roof onto it. Otto and agents are not in it — captured where they stood at assembly, they
## would leave a human-shaped hole in the precipitation.

## The layer from which the height map is taken and on which the wet deck and the snow cover lie.
## The twentieth: other layers in the project are not taken, and cameras and lights see all twenty.
const LAYER: int = 1 << 19

## Thickness of the lid over the roof opening, m: a particle travels up to 15 cm per step.
const LID_DEPTH: float = 0.4


## The box over the roof where precipitation falls: across the roof width with the drips, in depth
## from [param back_z] to [param front_z], [param height] high above the deck.
static func box(rules: BuildingRules, back_z: float, front_z: float, height: float) -> AABB:
	var bounds := rules.floor_span(BuildingRules.ROOF)
	var deck := WorldSpace.height_to_scene(rules.floor_surface(BuildingRules.ROOF))
	var edge := BuildingShell.COPING_OVERHANG + 0.1
	return AABB(
		Vector3(bounds.x - edge, deck - 0.6, back_z - 0.3),
		Vector3(bounds.y - bounds.x + edge * 2.0, height + 1.0, front_z - back_z + 0.6)
	)


## Height map taken from box [param over] from layer [param mask].
static func catcher(
	over: AABB, name: String, mask: int = LAYER
) -> GPUParticlesCollisionHeightField3D:
	var caught := GPUParticlesCollisionHeightField3D.new()
	caught.name = name
	caught.size = over.size
	caught.position = over.get_center()
	caught.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_1024
	caught.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	caught.heightfield_mask = mask
	return caught


## Invisible lids over the openings in the roof slab — over the top shaft.
##
## The machine room covers the shaft only at the back wall, while the opening goes through the slab
## over its whole depth. Drops and snowflakes in front of the little house would fall into the shaft
## and further down — in front of the thirtieth floor's portal, that is precipitation inside the
## building. The lid is at deck level: its top is slightly above the deck, by the particle step
## [param step], and a particle dies level with the deck, not under it.
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


## Moves stationary things on the roof under [param roots] that touch box [param over] onto layer
## [constant LAYER].
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
