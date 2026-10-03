class_name Corpse
extends RefCounted

## A jointed body for an agent, Otto and a torn-off piece (ADR-0043, decisions 7–12).
##
## The ragdoll ([Ragdoll]) is built when the actor is born and waits switched off: the
## living one walks with its own shape by the arcade rules, and the body parts only
## repeat the pose and collide with nothing. At the moment of death the body falls
## ([method fall]): the parts switch on and fly from the bullet's push, then physics
## decides everything: the body slumps, lands on other corpses, rides on the cab floor,
## falls into the shaft. The parts fall asleep by themselves once they have settled:
## corpses lying until the end of the building cost the frame nothing.
##
## Corpses lie on their own layer [constant LAYER] and see each other (decision 10).
## The living and Otto do not look at this layer and pass through.
##
## The cab cuts a body in two ways. With its bottom from above, [method cut_under]:
## whatever is under the bottom disappears. With a wall, [method tear]: a body across the
## threshold of a moving cab is torn, and the parts inside ride away as a separate
## [CorpsePiece]. Without blood the body is not torn: under the bottom it disappears
## whole.

## How long after the fall starts the body hits the floor, s, and how far that can be
## heard, m.
const THUD_AFTER: float = 0.4
const THUD_REACH: float = 16.0

## Group of fallen bodies: the cab searches it for whom to tear with its wall.
const GROUP := &"corpses"
## The corpse layer in `project.godot`.
const LAYER: int = 5
## The geometry layer: floor, walls, cabs.
const GEOMETRY_MASK: int = 1
## The bullet's push into the torso, N·s, and how much it lifts upward. Without a bullet
## the body is pushed backward, away from its gaze, at half strength: a limp body would
## otherwise sink straight down into a sitting position.
const HIT_IMPULSE: float = 60.0
const HIT_LIFT: float = 0.15
const SLUMP: float = 1.0
## Length of the puddle at the threshold, m.
const TEAR_PUDDLE: float = 0.3
## Metadata with which a bullet marks a hit: which way (−1 left, +1 right) and where.
const HIT_META := &"hit_from"
const HIT_POINT := &"hit_at"

## The body has fallen and lives by physics.
var fallen: bool = false
## The body is gone: cut off entirely or crushed.
var gone: bool = false
## The cut by the cab bottom, if it has started.
var cut: CarCut = null
var ragdoll: Ragdoll = null
## The body has already been torn by a wall: the cab does not tear it a second time.
var torn: bool = false

var _holder: Node3D
var _figure: FigureRig


## Builds the body with figure [param figure] of actor [param holder]. [param only]
## means only these parts (a piece); empty means all.
func _init(
	holder: Node3D, figure: FigureRig, only: PackedStringArray = PackedStringArray()
) -> void:
	_holder = holder
	_figure = figure
	ragdoll = Ragdoll.new(figure, only)
	ragdoll.corpse = self


## The body at node [param node] (an actor, a piece or a body part), or null.
static func of(node: Object) -> Corpse:
	if node == null:
		return null
	var part := node as PhysicalBone3D
	if part != null:
		if part.has_meta(&"ragdoll"):
			return (part.get_meta(&"ragdoll") as Ragdoll).corpse
		return null
	var found: Variant = node.get(&"corpse")
	if found is Corpse:
		return found as Corpse
	return null


## The body falls: the pose releases the skeleton, the parts fly at speed
## [param velocity] and from the bullet's push, if it marked the actor ([constant
## HIT_META]). The push comes into the part the bullet hit and at that very point: in the
## head, the head snaps back; in the legs, they are knocked out; in the torso, the whole
## body is thrown back.
func fall(velocity: Vector3) -> void:
	if fallen:
		return
	fallen = true
	_figure.set_process(false)
	var facing := signf(sin(_figure.rotation.y))
	var hit := float(_holder.get_meta(HIT_META, -facing * SLUMP))
	var impulse := Vector3(hit, HIT_LIFT * absf(hit), 0.0) * HIT_IMPULSE
	var at: Variant = _holder.get_meta(HIT_POINT) if _holder.has_meta(HIT_POINT) else null
	ragdoll.start(velocity, impulse, at)
	_holder.add_to_group(GROUP)
	# The body hits the ground a bit after the fall starts, when it has reached the floor.
	if _holder.is_inside_tree():
		var timer := _holder.get_tree().create_timer(THUD_AFTER, false)
		timer.timeout.connect(_thud)


## The body's impact on the floor at the body's place (ADR-0052, decision 7).
func _thud() -> void:
	if is_instance_valid(_holder) and _holder.is_inside_tree():
		var parent := _holder.get_parent()
		Sounds.play_at(parent, Sounds.BODY_FALL, _holder.global_position, THUD_REACH)


## The body gets up: Otto has revived. The skeleton is rebuilt (whatever the cab cut off
## comes back), and the pose drives the figure again.
func rise() -> void:
	ragdoll.dispose()
	ragdoll = Ragdoll.new(_figure)
	ragdoll.corpse = self
	_figure.heal()
	_figure.set_process(true)
	_holder.visible = true
	_holder.remove_from_group(GROUP)
	_holder.remove_meta(HIT_META)
	_holder.remove_meta(HIT_POINT)
	fallen = false
	gone = false
	torn = false
	cut = null


## The body is gone: not visible and does not collide.
func vanish() -> void:
	if gone:
		return
	gone = true
	_holder.visible = false
	ragdoll.remove(ragdoll.names())
	_holder.remove_from_group(GROUP)


## Whether the body can lie no farther than [param reach] from [param x] along the floor.
## An estimate by the pelvis: a whole body, neither cut nor torn, is held by its joints,
## and no part of it goes farther than its height from the pelvis.
func near(x: float, reach: float) -> bool:
	if ragdoll.parts.is_empty():
		return false
	var pelvis := ragdoll.parts.get("Body", ragdoll.parts.values()[0]) as PhysicalBone3D
	return absf(Ragdoll.center_of(pelvis).x - x) < reach + Proportions.BODY


## Where the body lies along X in the world: from and to.
func span() -> Vector2:
	var box := ragdoll.bounds()
	return Vector2(box.position.x, box.end.x)


## The bottom of cab [param car] passes over the body from above (decisions 7–9). Parts
## it has passed over to their middle disappear; the cab does not push through the body,
## otherwise it would press it into the floor.
func cut_under(car: ElevatorCar) -> void:
	if not fallen or (gone and (cut == null or cut.done)):
		return
	if not Blood.enabled:
		vanish()
		return
	var left := car.global_position.x - car.width() * 0.5
	var right := car.global_position.x + car.width() * 0.5
	var bottom := car.bottom()
	if cut == null:
		cut = CarCut.new()
		# A cutting cab does not push the body at all: otherwise it would push what lies
		# outside under its own bottom, where it is no longer visible.
		for part: PhysicalBone3D in ragdoll.parts.values():
			part.add_collision_exception_with(car)
	# The cut goes down to the floor even when no parts are left under the bottom: the stain
	# is laid when the bottom has reached the floor.
	var reach := ragdoll.bounds() if not ragdoll.parts.is_empty() else AABB()
	cut.advance(_figure, _holder.get_parent(), left, right, bottom, reach)
	# On reaching the floor, the bottom takes everything in its footprint, including what
	# the cab pushed under itself at the last moment.
	var under := PackedStringArray()
	for bone_name: String in ragdoll.parts:
		var center := Ragdoll.center_of(ragdoll.parts[bone_name] as PhysicalBone3D)
		if center.x > left and center.x < right and (cut.done or bottom < center.y):
			under.append(bone_name)
	ragdoll.remove(under)
	if ragdoll.parts.is_empty() and not gone:
		gone = true
		_holder.remove_from_group(GROUP)


## Body parts inside cab [param car], if the body lies across the threshold:
## the part outside, between heights [param low] and [param high], lies on something
## stationary, the landing. An arm hanging over the void is not a threshold, and
## then the body is not torn. Inside is everything in the cab over its whole height up to
## [param roof]: a raised arm, if left with the body, would drag it after the cab.
## Empty if there is nothing to tear.
func across(car: ElevatorCar, low: float, high: float, roof: float) -> PackedStringArray:
	var left := car.global_position.x - car.width() * 0.5
	var right := car.global_position.x + car.width() * 0.5
	var inside := PackedStringArray()
	var landed := false
	for bone_name: String in ragdoll.parts:
		var part := ragdoll.parts[bone_name] as PhysicalBone3D
		var center := Ragdoll.center_of(part)
		if center.x > left and center.x < right:
			if center.y >= low and center.y <= roof:
				inside.append(bone_name)
		elif not landed and center.y >= low and center.y <= high:
			landed = _rests_on_ground(part, car)
	if not landed:
		return PackedStringArray()
	# The foot goes where its shin goes: alone it would stay on the threshold as a stump.
	for foot: String in Ragdoll.ANKLES:
		var leg := String(Ragdoll.ANKLES[foot])
		if inside.has(leg) != inside.has(foot) and ragdoll.parts.has(foot):
			if inside.has(leg):
				inside.append(foot)
			else:
				inside.remove_at(inside.find(foot))
	return inside


## Whether part [param part] lies on something stationary, not on cab [param car].
func _rests_on_ground(part: PhysicalBone3D, car: ElevatorCar) -> bool:
	var shape := part.get_child(0) as CollisionShape3D
	var reach := (shape.shape as CapsuleShape3D).radius + 0.1
	var from := Ragdoll.center_of(part)
	var query := PhysicsRayQueryParameters3D.create(
		from, from - Vector3(0.0, reach, 0.0), GEOMETRY_MASK
	)
	query.exclude = [car.get_rid()]
	return not part.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Tears the body with the wall of cab [param car]: the parts [param inside] ride away
## with it as a separate piece, the rest stay where they lay (decision 11).
func tear(car: ElevatorCar, inside: PackedStringArray) -> void:
	torn = true
	var host := _holder.get_parent()
	var box := ragdoll.bounds()
	CorpsePiece.tear_off(self, _figure, host, inside)
	ragdoll.remove(inside)
	var middle := car.global_position.x
	var side := 1.0 if box.get_center().x < middle else -1.0
	var wall := middle - side * car.width() * 0.5
	Corpse.bleed(host, Vector3(wall, box.position.y, WorldSpace.PLAY_Z), side)


## Spatter and a puddle at the wall along which the body was torn; [param inside] is
## which side of the wall the cab is on.
static func bleed(host: Node, at: Vector3, inside: float) -> void:
	var spot := at + Vector3(0.0, Proportions.PRONE, 0.0)
	Blood.spray(host, spot, inside)
	Blood.spray(host, spot, -inside)
	Blood.puddle(host, at - Vector3(inside * TEAR_PUDDLE * 0.5, 0.0, 0.0), TEAR_PUDDLE)
