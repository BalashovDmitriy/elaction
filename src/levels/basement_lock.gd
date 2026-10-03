class_name BasementLock
extends Node3D

## The basement is locked until all documents are collected (M24b, the user's decision).
##
## In the ROM without the documents Otto rides down to the basement and is sent back up
## (@09B5–0A69). Ours used to: the shaft into the basement is closed, and there is no way
## to get there at all. The cab stops a floor above and goes no lower — neither with a
## passenger nor by itself ([member ElevatorMotion.bottom_locked]); the shaft opening in
## the slab above the basement is closed by leaves flush with the floor — a body for
## everyone: Otto, agents, the falling. Otherwise people would jump down there from the
## floor above: a one-floor fall does not kill.
##
## The last document opens the basement by itself: the leaves slide apart into the slab
## with a sound, and the bottom stop is available again. No text says so.
##
## There are no doors in the basement ([method BuildingRules.doors_on]), so a locked
## basement cuts off nothing: everything Otto goes for before the exit is above.

## Group of hatches: a support that will one day disappear.
const HATCH_GROUP := &"basement_hatches"
## How far the leaves' look is below their body, m. The body is flush with the floor,
## otherwise a small sill would grow at the cab's edge; and a look flush with the cab
## floor would flicker with it when the cab stands over the leaves.
const LID_SINK: float = 0.005
## How long the leaves take to slide apart, s.
const OPEN_TIME: float = 0.6
## Leaves sound — the elevator buzzer, at the shaft; how far it is heard, m.
const OPEN_SOUND := Sounds.BASEMENT_OPEN
const SOUND_REACH: float = 24.0

## The leaves' look: heavy steel, not floor. Grey leaves in the trim colour read as
## floor tiles flush with it (frame `basement_01_locked`), and the locked shaft could not
## be seen. Now — dark steel plates with ribs, a yellow-and-black "zebra" along the edge,
## a seam in the middle and red indicator lights while locked.
const STEEL := Color(0.15, 0.16, 0.18)
const RIB := Color(0.1, 0.105, 0.12)
const HAZARD_YELLOW := Color(0.95, 0.7, 0.08)
const HAZARD_BLACK := Color(0.04, 0.04, 0.045)
const LAMP_RED := Color(1.0, 0.12, 0.08)
## Zebra: stripe step in the world, m, a stripe on the front edge at top and bottom, m,
## and a stripe along the edge of the leaves' top, m. The top as seen from the camera is
## a narrow strip: the edge at the play plane is always visible.
const HAZARD_PITCH: float = 0.34
const HAZARD_TOP: float = 0.17
const HAZARD_BOTTOM: float = 0.09
const HAZARD_EDGE: float = 0.3
## Seam gap between the leaves and ribs on the face: how many per leaf, cross-section, m.
const SEAM: float = 0.03
const RIBS: int = 2
const RIB_SIZE := Vector2(0.06, 0.025)
## Lock indicator light on the face at each edge of the opening: size, m. Emission, not
## a source.
const LAMP_SIZE := Vector3(0.1, 0.07, 0.03)
## How much the zebra glows by itself: it reads on a darkened floor too.
const HAZARD_GLOW: float = 0.35
## Side of the zebra image, texels: a stripe is half a period along the diagonal.
const HAZARD_TEXELS: int = 32

## One zebra material for all buildings: the stripe image is built by code once.
static var _hazard: StandardMaterial3D = null

var _cars: Array[ElevatorCar] = []
var _hatches: Array[StaticBody3D] = []
var _lamps: Array[MeshInstance3D] = []
var _locked: bool = false


## Openings above the basement as rules rectangles: one for each shaft reaching the
## basement — in the slab of the floor above it, where the shaft cut through it.
static func hatches(rules: BuildingRules, plan: BuildingPlan) -> Array[Rect2]:
	var found: Array[Rect2] = []
	var bottom := rules.floors - 1
	var above := bottom - 1
	if above <= BuildingRules.ROOF:
		return found
	var half := rules.shaft_width * 0.5
	for shaft in plan.shafts:
		if shaft.bottom == bottom and shaft.top <= above:
			found.append(
				Rect2(
					shaft.x - half, rules.floor_surface(above), rules.shaft_width, rules.slab_height
				)
			)
	return found


## Locks the basement if the documents are not yet collected, and opens it with the last
## one.
##
## [param cars] — all of the building's cabs: those going down to the basement are locked
## ([method ElevatorCar.bottom_reach]). Pair decks are skipped — the leading one locks
## them.
func setup(rules: BuildingRules, plan: BuildingPlan, cars: Array[ElevatorCar]) -> void:
	name = "BasementLock"
	var game := GameState.instance()
	if game.all_documents_collected():
		return
	var basement := rules.floor_surface(rules.floors - 1)
	for car in cars:
		if car.is_deck() or not is_equal_approx(car.bottom_reach(), basement):
			continue
		car.lock_bottom_stop(true)
		_cars.append(car)
	for rect in hatches(rules, plan):
		_hatches.append(_build_hatch(rect))
	_locked = true
	game.documents_changed.connect(_on_documents_changed)


## Whether the basement is locked right now.
func is_locked() -> bool:
	return _locked


## How many leaves still close the shafts: bodies that are walked on.
func closed_hatches() -> int:
	var closed := 0
	for hatch in _hatches:
		if is_instance_valid(hatch) and hatch.collision_layer != 0:
			closed += 1
	return closed


## Opens the basement: the cabs go down to the bottom, the leaves slide apart.
##
## The body goes at once, the look — over [constant OPEN_TIME]: whoever stood on the
## leaves falls through with them rather than hanging over the open opening.
func unlock() -> void:
	if not _locked:
		return
	_locked = false
	for car in _cars:
		if is_instance_valid(car):
			car.lock_bottom_stop(false)
	for lamp in _lamps:
		if is_instance_valid(lamp):
			lamp.visible = false
	if _hatches.is_empty():
		return
	# The sound source is on the lock node, not the leaves: the leaves are removed before
	# the buzzer finishes playing.
	var buzzer := Sounds.source(self, OPEN_SOUND, SOUND_REACH)
	buzzer.position = _hatches[0].position
	buzzer.finished.connect(buzzer.queue_free)
	buzzer.play()
	var tween := create_tween().set_parallel()
	for hatch in _hatches:
		hatch.collision_layer = 0
		hatch.collision_mask = 0
	# A corpse settled on the leaves sleeps, and the vanished support does not wake it: it
	# would hang over the open opening (ADR-0043, decision 12).
	for node: Node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := Corpse.of(node)
		if corpse != null and not corpse.gone:
			corpse.ragdoll.wake()
	for hatch in _hatches:
		for leaf in hatch.get_children():
			var part := leaf as MeshInstance3D
			# The indicator lights hang on the body next to the leaves and stay in place.
			if part == null or _lamps.has(part):
				continue
			# Each leaf goes its own way, into the thickness of the slab.
			var aside := part.position.x * 3.0
			tween.tween_property(part, "position:x", aside, OPEN_TIME)
	tween.chain().tween_callback(_drop_hatches)


## Leaves in place of a rules rectangle: a body through the full depth of the slab, like
## the shell's slabs, and two steel leaves on top — those slide apart. On the leaves'
## face — zebra along the edges and ribs, red indicator lights at the opening's edges.
func _build_hatch(rect: Rect2) -> StaticBody3D:
	var depth := WorldSpace.CORRIDOR_DEPTH + WorldSpace.ROOM_DEPTH
	var body := StaticBody3D.new()
	body.name = "Hatch"
	# The hatch goes when the documents are collected: a corpse asleep on it is woken by
	# [method unlock], and it falls along with it rather than hanging in the air.
	body.add_to_group(HATCH_GROUP)
	body.position = WorldSpace.to_scene(rect.get_center())
	body.position.z = WorldSpace.CORRIDOR_DEPTH * 0.5 - depth * 0.5

	var shape := BoxShape3D.new()
	shape.size = Vector3(rect.size.x, rect.size.y, depth)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	var half := rect.size.x * 0.5
	var width := half - SEAM * 0.5
	var height := rect.size.y - LID_SINK
	for side: float in [-1.0, 1.0]:
		var leaf := GreyboxLook.box(Vector3(width, height, depth), GreyboxLook.metal(STEEL))
		leaf.name = "Leaf"
		leaf.position = Vector3(side * (half + SEAM * 0.5) * 0.5, -LID_SINK * 0.5, 0.0)
		body.add_child(leaf)
		_dress_leaf(leaf, width, height, depth)
	# Indicator lights are on the body, not the leaves: the leaves go, the lights go out
	# in place.
	for side: float in [-1.0, 1.0]:
		var lamp := GreyboxLook.box(LAMP_SIZE, GreyboxLook.light(LAMP_RED))
		lamp.name = "LockLamp"
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(
			side * (half - LAMP_SIZE.x * 0.5 - 0.06), 0.0, depth * 0.5 + LAMP_SIZE.z * 0.5 + 0.004
		)
		body.add_child(lamp)
		_lamps.append(lamp)
	add_child(body)
	return body


## A leaf's face: zebra along the top and bottom edges and along the edge of the top,
## ribs between them. All of it the leaf's children: it goes into the slab with it.
func _dress_leaf(leaf: MeshInstance3D, width: float, height: float, depth: float) -> void:
	var front := depth * 0.5 + 0.004
	var top := height * 0.5
	var bands: Array[Vector2] = [
		Vector2(top - HAZARD_TOP * 0.5, HAZARD_TOP),
		Vector2(-top + HAZARD_BOTTOM * 0.5, HAZARD_BOTTOM)
	]
	for band in bands:
		var strip := GreyboxLook.box(Vector3(width, band.y, 0.008), hazard_material())
		strip.name = "Hazard"
		strip.position = Vector3(0.0, band.x, front)
		leaf.add_child(strip)
	# The edge of the top at the play plane is the strip of the top the camera sees.
	var edge := GreyboxLook.box(Vector3(width, 0.008, HAZARD_EDGE), hazard_material())
	edge.name = "HazardEdge"
	edge.position = Vector3(0.0, top + 0.002, depth * 0.5 - HAZARD_EDGE * 0.5)
	leaf.add_child(edge)
	var middle := (HAZARD_BOTTOM - HAZARD_TOP) * 0.5
	var rib_height := height - HAZARD_TOP - HAZARD_BOTTOM
	for index in RIBS:
		var rib := GreyboxLook.box(
			Vector3(RIB_SIZE.x, rib_height, RIB_SIZE.y), GreyboxLook.metal(RIB)
		)
		rib.name = "Rib"
		rib.position = Vector3(
			width * (float(index + 1) / float(RIBS + 1) - 0.5), middle, front + RIB_SIZE.y * 0.5
		)
		leaf.add_child(rib)


## Yellow-and-black zebra: diagonal stripes in world coordinates, so they run evenly
## across all leaves and faces, and glow slightly by themselves.
static func hazard_material() -> StandardMaterial3D:
	if _hazard != null:
		return _hazard
	var image := Image.create(HAZARD_TEXELS, HAZARD_TEXELS, false, Image.FORMAT_RGBA8)
	for y in HAZARD_TEXELS:
		for x in HAZARD_TEXELS:
			var yellow := (x + y) % HAZARD_TEXELS * 2 < HAZARD_TEXELS
			image.set_pixel(x, y, HAZARD_YELLOW if yellow else HAZARD_BLACK)
	var texture := ImageTexture.create_from_image(image)
	_hazard = StandardMaterial3D.new()
	_hazard.albedo_texture = texture
	_hazard.roughness = 0.7
	_hazard.uv1_triplanar = true
	_hazard.uv1_world_triplanar = true
	_hazard.uv1_scale = Vector3.ONE / HAZARD_PITCH
	_hazard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hazard.emission_enabled = true
	_hazard.emission_texture = texture
	_hazard.emission_energy_multiplier = HAZARD_GLOW
	return _hazard


func _drop_hatches() -> void:
	for hatch in _hatches:
		if is_instance_valid(hatch):
			hatch.queue_free()
	_hatches.clear()


func _on_documents_changed(collected: int, total: int) -> void:
	# A building taken out of the tree still hears the count: the next building resets it
	# to zero from zero, and the previous one's lock would open with a buzzer into nowhere.
	if not is_inside_tree():
		return
	# "Zero from zero" is not the last document but a game reset: a locked building always
	# has documents ([method setup]). A new game from pause resets the count while the old
	# building is still in the tree — and the lock would open right before demolition.
	if total > 0 and collected >= total:
		unlock()
