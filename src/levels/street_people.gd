class_name StreetPeople
extends Node3D

## Pedestrians by the exit (ADR-0054, decision 3): townspeople from the Quaternius packs walk
## along the far sidewalk both ways and go off past the edge of the street, and others
## come from there. By day there are more of them, at night just a few; in rain most have
## an umbrella, in snow hats and scarves, no umbrellas. Raindrops and flakes die on them
## ([Shelter]) rather than going through.
##
## A pedestrian is assembled from pack model parts ([Passerby]) and walks with the pack's
## walk: the step is matched to the speed, and the feet do not slide. Pedestrians have no
## mechanics: they do not interfere with the game.

## How many pedestrians are on the street by time of day: morning, day, evening, night.
const COUNT: Array[int] = [4, 7, 5, 2]
## Two sidewalk lanes in depth, m: nearer the curb they walk left, by the shop windows —
## right.
const LANES := Vector2(-9.2, -9.68)
## Walking speed, m/s, and the one the pack's walk was recorded at: the step is matched
## to it, otherwise the feet would slide.
const SPEED := Vector2(1.05, 1.45)
const CLIP_SPEED: float = 1.05
## A pedestrian's height is the same as Otto's: the street is at the same scale.
const HEIGHT: float = Proportions.BODY
## What share of pedestrians walk under an umbrella in the rain.
const UMBRELLA_SHARE: float = 0.7
## Umbrella: canopy radius and height, shaft length from the hand, m; canopy colours.
const CANOPY := Vector2(0.47, 0.26)
const SHAFT: float = 0.82
## How much the canopy base is above the hand, m: the hand is at the chest, the canopy above
## the head.
const ABOVE_HAND: float = 0.62
const CANOPY_TONES: Array[Color] = [
	Color(0.06, 0.06, 0.07), Color(0.32, 0.05, 0.06), Color(0.08, 0.12, 0.22), Color(0.2, 0.2, 0.22)
]
## At what gap along the way people coming towards each other already raise the umbrella,
## m: in advance, not when the canopies have met.
const PASSING: float = 0.9
## How much the canopy is flattened in height and at what height above the sidewalk is the
## hand that holds it, m.
const CANOPY_FLATTEN: float = 0.75
const HAND_HEIGHT: float = 1.05
## How far past the edge of the street a pedestrian goes before coming back from the other
## side, m.
const BEYOND: float = 3.0


## A pedestrian: node, signed speed, his walk and umbrella grip — or null.
class Walker:
	extends RefCounted
	var node: Node3D = null
	var speed: float = 0.0
	var player: AnimationPlayer = null
	var grip: UmbrellaGrip = null


var _walkers: Array[Walker] = []
var _span := Vector2.ZERO
var _rng := RandomNumberGenerator.new()
var _dress := Passerby.Dress.LIGHT
var _active: bool = true


## Brings pedestrians onto the sidewalk from [param from] to [param to] along scene x, at
## sidewalk height [param walk] of the scene, at time of day [param time] and in weather
## [param weather].
func build(
	from: float,
	to: float,
	walk: float,
	building_seed: int,
	time: TimeOfDay.Kind,
	weather: Weather.Kind
) -> void:
	name = "People"
	_span = Vector2(from - BEYOND, to + BEYOND)
	_rng.seed = hash([building_seed, "people"])
	# Umbrellas only in rain: nobody walks under an umbrella in snow (the user's request).
	var rainy := Weather.is_raining(weather)
	_dress = Passerby.dress_for(weather, time)
	for index in COUNT[time]:
		var walker := Walker.new()
		var leftward := index % 2 == 0
		walker.speed = _rng.randf_range(SPEED.x, SPEED.y) * (-1.0 if leftward else 1.0)
		walker.node = _person(rainy and _rng.randf() < UMBRELLA_SHARE, leftward)
		walker.node.position = Vector3(
			_rng.randf_range(_span.x, _span.y), walk, LANES.x if leftward else LANES.y
		)
		walker.node.rotation.y = -PI * 0.5 if leftward else PI * 0.5
		add_child(walker.node)
		walker.grip = walker.node.find_child("Grip", true, false) as UmbrellaGrip
		var player := walker.node.find_child("AnimationPlayer", true, false) as AnimationPlayer
		walker.player = player
		if player != null:
			# The pack's walk comes from glTF without a loop: having played the step, a pedestrian
			# froze and floated along the sidewalk like a statue.
			player.get_animation(&"Walk").loop_mode = Animation.LOOP_LINEAR
			player.play(&"Walk")
			player.speed_scale = absf(walker.speed) / CLIP_SPEED
			# Each starts from his own step phase: a crowd walking in step reads as puppets.
			player.seek(_rng.randf() * player.current_animation_length, true)
		Outdoors.mark(walker.node)
		_walkers.append(walker)


## How many pedestrians are on the street — for a test.
func count() -> int:
	return _walkers.size()


## Pedestrians walk only while the exit is in frame, like the car traffic
## ([method StreetTraffic.set_active]): skeleton walking and the umbrella grip every
## frame is work for the whole building, and the street is visible only at the exit (code
## review M24l). The street calls this every frame, so — only on change.
func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	set_process(on)
	for walker in _walkers:
		if walker.player != null:
			walker.player.active = on
		if walker.grip != null:
			walker.grip.active = on


## Whether pedestrians are walking — for a test.
func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	_make_way()
	for walker in _walkers:
		var at := walker.node.position
		at.x += walker.speed * delta
		if walker.speed < 0.0 and at.x < _span.x:
			at.x = _span.y
		elif walker.speed > 0.0 and at.x > _span.y:
			at.x = _span.x
		walker.node.position = at


## People under umbrellas coming towards each other give way: the one by the shop windows
## raises his umbrella above the other's while the canopies overlap along the way, then
## lowers it.
func _make_way() -> void:
	for walker in _walkers:
		if walker.grip == null or walker.speed < 0.0:
			continue
		var near := false
		for other in _walkers:
			if other.grip == null or other.speed > 0.0:
				continue
			if absf(other.node.position.x - walker.node.position.x) < CANOPY.x * 2.0 + PASSING:
				near = true
				break
		walker.grip.raised = near


## A pedestrian: assembled from pack parts as tall as Otto, dressed for the weather, with
## or without an umbrella.
func _person(umbrella: bool, leftward: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Walker"
	var model := Passerby.make(_rng, HEIGHT, _dress)
	root.add_child(model)
	var cover := Vector3(Proportions.BODY_WIDTH, HEIGHT, WorldSpace.BODY_DEPTH)
	if umbrella:
		var canopy := _umbrella()
		root.add_child(canopy)
		# Umbrella in hand: the hand holds the handle, the umbrella follows the hand
		# ([UmbrellaGrip]).
		var grip := UmbrellaGrip.new()
		grip.name = "Grip"
		grip.umbrella = canopy
		grip.forward = Vector3.LEFT if leftward else Vector3.RIGHT
		# The arm nearer the camera: for one walking left — the left one, right — the right one.
		grip.side = "L" if leftward else "R"
		(model.find_child("Skeleton3D", true, false) as Skeleton3D).add_child(grip)
		# Under an umbrella it is dry from the canopy to the ground: the catcher rides with the
		# umbrella rather than standing at the middle of the body — the canopy is at the arm, to its
		# side.
		var top := ABOVE_HAND + CANOPY.y * CANOPY_FLATTEN
		var dry := Shelter.over(canopy, Vector3(CANOPY.x * 2.0, top + HAND_HEIGHT, CANOPY.x * 2.0))
		dry.size = Vector3(CANOPY.x * 2.0, top + HAND_HEIGHT, CANOPY.x * 2.0)
		dry.position = Vector3(0.0, top - dry.size.y * 0.5, 0.0)
		return root
	Shelter.over(root, cover)
	return root


## Umbrella in rain: origin — the handle in the hand, above it the shaft and the canopy over
## the head.
func _umbrella() -> Node3D:
	var umbrella := Node3D.new()
	umbrella.name = "Umbrella"
	var look := StandardMaterial3D.new()
	look.albedo_color = CANOPY_TONES[_rng.randi_range(0, CANOPY_TONES.size() - 1)]
	look.roughness = 0.6
	# The canopy is visible from inside too: a hemisphere without a bottom.
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The canopy is convex, not a cone: as a cone the umbrella read as a straw hat.
	var dome := SphereMesh.new()
	dome.radius = CANOPY.x
	dome.height = CANOPY.y * 2.0
	dome.is_hemisphere = true
	dome.radial_segments = 28
	dome.rings = 10
	dome.material = look
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = dome
	canopy.position = Vector3(0.0, ABOVE_HAND, 0.0)
	canopy.scale = Vector3(1.0, CANOPY_FLATTEN, 1.0)
	umbrella.add_child(canopy)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.012
	stick.bottom_radius = 0.012
	stick.height = SHAFT
	stick.material = look
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	pole.mesh = stick
	pole.position = Vector3(0.0, SHAFT * 0.5, 0.0)
	umbrella.add_child(pole)
	return umbrella
