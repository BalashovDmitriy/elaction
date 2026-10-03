class_name Bullet
extends Area3D

## Bullet.
##
## Flies horizontally and dies against geometry, against a victim or at its range. Flight
## height is set by the shot point: you crouch under a high bullet and jump over a low one.
## No separate rule for dodging is needed — collision shapes decide everything, and
## Otto's differ standing and crouching (ADR-0006, point 3).
##
## Whom to hit is decided by the mask: Otto's bullet does not touch him, an enemy one
## does not touch other enemies.
##
## Flies in the play plane and only in it: Z does not change by a centimetre
## (ADR-0021, decision 1). The camera tilt, when it appears in M17, does not affect
## hits — it is a property of the camera, not the world (ADR-0019, decision 6).
##
## **The path per frame is checked whole** (ADR-0037, decision 5): since M24a the bullet is three
## times faster than ROM and per physics frame covers almost a wall's thickness, and under the
## tests' [member Engine.time_scale] four times more. The [Area3D] shape overlap was enough while
## the step was shorter than a wall; now before the step the bullet sweeps its shape along the whole
## path ([method PhysicsDirectSpaceState3D.cast_motion]) and dies against the first thing it meets —
## it cannot slip through a wall, a door, an agent or Otto.

## The bullet hit something. Whoever fired it deals with it: he knows whether it is his own
## side or the others, and the points go to him.
signal hit_target(target: Node3D)

## What the bullet hits. Layers: 1 — geometry, 2 — Otto, 4 — enemies, 8 — lamps.
##
## Named by the shooter, not by the target: Otto's bullet hits both agents and
## lamps, and there is no single word for that.
const FROM_OTTO: int = 1 | 4 | 8
const FROM_ENEMY: int = 1 | 2

## Layers whose hit sounds like a blow to a body, not a knock on a wall.
const LIVING: int = 2 | 4
## Geometry layer: walls, slabs, cabs.
const GEOMETRY: int = 1
## How far short of the wall a bullet fired into it is born, m.
const WALL_STANDOFF: float = 0.02

## Lamp layer: a bullet hits a lamp without sparks or a mark — the lamp throws them itself.
const LAMPS: int = 8

## Bullet group: an agent finds by it what to dodge. He cannot iterate the level's
## children — there are about three hundred, and at most four bullets on screen.
const GROUP := &"bullets"

## Default bullet range, m: the agent's aim laser reaches as far.
const RANGE: float = 14.4

@export var speed: float = 6.6

## Beyond this the bullet dies by itself, even without meeting an obstacle.
@export var max_range: float = RANGE

## Where it flies: -1 left, +1 right.
var direction: float = 1.0

var _travelled: float = 0.0
var _look: BulletLook = null
## The bullet has already hit something and lives out the end of the frame.
var _spent: bool = false
## The muzzle flash has already been given. It is given on the first physics frame or by a
## point-blank hit, if that comes earlier — but not in [method _ready]: the shooter puts the bullet
## in place only after adding it to the tree.
var _flashed: bool = false


## Where the bullet is born: at the muzzle [param muzzle] if there is no wall between the shooter
## [param from] and the muzzle, and if there is — at the wall itself, and with its very first
## step the bullet hits it. The muzzle is ahead of the body, and at a wall it goes into it or
## past it: a bullet born there did not see the wall and hit through it (M24g, seed 3).
static func spawn_point(world: World3D, from: Vector3, muzzle: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, muzzle, GEOMETRY)
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return muzzle
	var wall: Vector3 = hit["position"]
	return wall - (muzzle - from).normalized() * WALL_STANDOFF


func _ready() -> void:
	add_to_group(GROUP)
	# Overlaps are checked by the bullet itself ([method _strike_overlap]), not by the
	# engine's monitoring: Jolt reported a point-blank overlap only on some runs, and the
	# same seed then ended differently (ADR-0059, decision 1).
	monitoring = false
	# The look is a thin tracer with a tail ([BulletLook]); the shooter sets the direction
	# before the bullet enters the tree.
	_look = BulletLook.make(direction)
	add_child(_look)


## Whether at least one bullet with mask [param mask] is flying now. On Otto's bullet in frame
## the agents raise the alarm (ADR-0027, decision 5).
static func any_in_flight(tree: SceneTree, mask: int) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		var bullet := node as Bullet
		if bullet != null and bullet.collision_mask == mask:
			return true
	return false


## Half the bullet's length, m.
##
## It is used to work out whether the bullet has left a body's extent: having passed its middle, it
## still overlaps the chest by this half, and one who straightened up under it still
## catches it. Taken from the shape itself, not written as a number nearby — otherwise
## a scene edit would silently diverge from those who dodge it.
func half_length() -> float:
	return (($Shape as CollisionShape3D).shape as BoxShape3D).size.x * 0.5


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_flash_once()
	if _strike_overlap():
		return
	# The bullet does not go beyond its range even on the last step: otherwise on a fast frame
	# it would reach half a step further than its range.
	var length := minf(speed * delta, max_range - _travelled)
	var step := length * signf(direction)
	if not is_zero_approx(step) and _sweep(step):
		return
	position.x += step
	_travelled += absf(step)
	_look.follow(_travelled)
	if _travelled >= max_range - 0.0001:
		queue_free()


## Sweeps the bullet shape along path [param step] for this frame and kills it against the first
## body on it. Returns whether there was a hit.
##
## Asks physics twice: first — at what fraction of the path the shape first touches
## something, then — what exactly, at that spot. This is enough because
## the bullet flies only along X and only in the play plane.
func _sweep(step: float) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ($Shape as CollisionShape3D).shape
	query.transform = global_transform
	query.motion = Vector3(step, 0.0, 0.0)
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var fractions := space.cast_motion(query)
	if fractions.size() < 2 or fractions[1] >= 1.0:
		return false
	# What was hit is asked at the touch point, but the bullet is moved there
	# only when a body is found: otherwise it would go a fraction of the path and beyond it
	# a whole step more — through that very thin wall.
	var unsafe: float = fractions[1]
	var contact := global_transform.translated(Vector3(step * unsafe, 0.0, 0.0))
	query.transform = contact
	query.motion = Vector3.ZERO
	var point := contact.origin + Vector3(signf(step) * half_length(), 0.0, 0.0)
	var body: Node3D = null
	var rest := space.get_rest_info(query)
	if not rest.is_empty():
		body = instance_from_id(int(rest.get("collider_id", 0))) as Node3D
		point = rest.get("point", point)
	if body == null:
		# A touch finer than the [method PhysicsDirectSpaceState3D.get_rest_info] threshold:
		# the same question by overlap, without depth.
		var touching := space.intersect_shape(query, 1)
		if not touching.is_empty():
			body = touching[0].get("collider") as Node3D
	if body == null:
		return false
	# Moves to where it touched — splashes and sparks land at the impact point.
	global_position = contact.origin
	_travelled += absf(step * unsafe)
	_look.follow(_travelled)
	_hit(body, point)
	return true


## Flash and smoke are at the muzzle the bullet left: they are hung on the bullet's owner and
## stay in place while it flies (ADR-0037, decision 5). Once per bullet.
func _flash_once() -> void:
	if _flashed:
		return
	_flashed = true
	ShotFx.muzzle(get_parent(), global_position, direction)


## Called by the shooter right after placing the bullet: a point-blank shot hits in the
## same physics frame it is fired, as the engine's overlap used to report it.
func strike_point_blank() -> void:
	if not _spent:
		_strike_overlap()


## Hits whatever the bullet's shape already overlaps: point blank, when it is born
## inside a body, or when a body has moved into it since the last frame. A direct
## query gives the same answer for the same positions on every run; the engine's
## overlap events did not. Returns whether something was hit.
func _strike_overlap() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ($Shape as CollisionShape3D).shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var touching := get_world_3d().direct_space_state.intersect_shape(query, 1)
	if touching.is_empty():
		return false
	var body := touching[0].get("collider") as Node3D
	if body == null:
		return false
	_hit(body, global_position)
	return true


## Hit on [param body] at point [param point].
func _hit(body: Node3D, point: Vector3) -> void:
	# queue_free() removes the node only at the end of the frame, and several bodies can be
	# hit in one frame: without this mark one bullet would kill two at once and
	# bring points for each.
	if _spent:
		return
	# A point-blank bullet hits on its very first frame, before it has moved; the
	# muzzle flash is shown then too.
	_flash_once()
	_spent = true
	# A layer, not a class: [Otto] and [Enemy] load the bullet scene themselves, and a reference
	# from here to them would close the load into a ring — the scene would stop parsing at all.
	var target := body as CollisionObject3D
	if target != null and (target.collision_layer & LIVING) != 0:
		# A hit has no sound of its own (ADR-0036): it is heard as the death of the one who was hit.
		# Splashes at the bullet itself, along its travel (ADR-0031): they stay in place even when
		# the bullet is already removed. The bullet does not wound an invulnerable one — splashes
		# would show a hit that is not there, and invulnerability is shown only by blinking. Asked
		# as a property, not a class: a reference to [Otto] would close the load into a ring. An
		# agent has no such property, and [method Object.get] returns null.
		if body.get(&"invulnerable") != true:
			Blood.spray(get_parent(), global_position, direction)
			# Where the bullet struck: the one it killed falls with his body along its travel
			# (ADR-0043, decision 12). Labels are strings, not [Corpse] constants: a reference to it
			# pulls in the cab, and that pulls Otto with this bullet's scene, and the load closes
			# into a ring.
			body.set_meta(&"hit_from", signf(direction))
			body.set_meta(&"hit_at", global_position)
	elif target == null or (target.collision_layer & LAMPS) == 0:
		# Wall, door, cab: sparks, dust and a mark on the front face (ADR-0037,
		# decision 5). Into a lamp — without them: the lamp throws sparks itself.
		ShotFx.impact(
			get_parent(), Vector3(point.x, global_position.y, global_position.z), direction, body
		)
	# Geometry simply kills the bullet, the shooter deals with the living.
	hit_target.emit(body)
	queue_free()
