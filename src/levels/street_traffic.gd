class_name StreetTraffic
extends Node3D

## Traffic along the street at the exit (M24h, ADR-0044, decisions 1 and 2).
##
## In the original there is no street with traffic: Otto's car drives off along an
## empty roadway. Here there are two lanes. The near one goes left — the same way Otto
## drives off, and he merges into it after waiting for a gap ([method is_clear_for],
## [method join]). The far one goes the opposite way, right. The cars are Cars Pack
## models, as at the exit; headlights and brake lights glow by emission, the headlight
## has a halo; the traffic has no real light sources: there are about half a dozen
## cars in the frame, and each with a spotlight would eat the light budget.
##
## The street ends at the building's end wall: beyond it, at street level, is the
## ground floor. Cars enter the roadway and leave it behind that end wall, as if the
## street turned a corner; the near lane comes out from around the corner, the far one
## goes around it. The street's left end is beyond the edge of the widest exit frame
## ([constant ExitStreet.FROM]).
##
## In the near lane cars keep their distance to the car ahead — and to Otto's car once
## it has merged: one coming up from behind slows down instead of passing through.
## The far lane has nobody to keep distance to: the lane speed is the same for all.
##
## The traffic draw comes from the building seed: every run of the same building is
## identical, and the building seed, salted by the game, differs in every game. The
## first draw is the traffic situation ([enum Density], ADR-0046, decision 3): a free
## street, where a gap is more often there right away, normal, and dense, where the
## wait is longer. Cars — by a draw of model and paint, each its own.
## The traffic moves only while the exit is in the frame ([method set_active]).

## Traffic situation at the exit: how densely the cars go.
enum Density { LIGHT, NORMAL, HEAVY }

## Traffic sound (ADR-0052, decision 7): how many seconds before the frame a car sounds
## its pass-by, how far it is heard, m, pass-by and horn volume, dB.
const PASS_LEAD: float = 1.6
const PASS_REACH: float = 40.0
const PASS_DB: float = -6.0
const HORN_DB: float = -4.0

## Lane middles along Z, m: the near one — between the sidewalk at the exit and the
## centre line, the far one — between the centre line and the car parked at the far curb.
const NEAR_LANE_Z: float = -3.2
const FAR_LANE_Z: float = -5.2
## Lane speed, m/s: drawn per building within these limits.
const SPEEDS := Vector2(8.0, 11.0)
## Gap between cars on entry, m bumper to bumper: drawn for each, within the limits of
## the [enum Density] situation.
const GAPS: Array[Vector2] = [Vector2(20.0, 48.0), Vector2(7.0, 24.0), Vector2(3.5, 11.0)]
## Shares of situations in the draw — free, normal, dense — by time of day
## ([enum TimeOfDay.Kind], ADR-0052, decision 2): in the daytime the street is densest,
## at night it is more often free.
const DENSITY_ODDS: Array[Array] = [
	[0.3, 0.45, 0.25],
	[0.15, 0.4, 0.45],
	[0.3, 0.45, 0.25],
	[0.5, 0.35, 0.15],
]
## How long Otto's car waits for a gap before the traffic suits it, s, by situation:
## in dense traffic the wait is longer.
const WAIT_LIMITS: Array[float] = [1.5, 2.2, 4.0]
## A car will not get closer than this to the one ahead, m bumper to bumper; from
## [constant SAFE_GAP] and farther it goes at full speed.
const MIN_GAP: float = 2.5
const SAFE_GAP: float = 9.0
## Acceleration and braking, m/s².
const ACCELERATION: float = 4.0
const BRAKING: float = 9.0
## How much empty lane Otto's car needs to merge, m: to the car coming up from behind
## and to the one that has already passed ahead.
const CLEAR_BEHIND: float = 16.0
const CLEAR_AHEAD: float = 8.0
## How far behind the building's end wall a car enters and disappears, m: entirely
## behind the side wall.
const BEHIND_CORNER: float = CarModel.LENGTH
## Headlight halo: height above the roadway and offset forward from the middle, fractions of length.
const HALO_HEIGHT: float = 0.55
const HALO_REACH: float = 0.47
## Salt of the traffic draw: its own, so the traffic does not march in step with the street.
const SALT: int = 0x7EAF_F1C0


## One traffic car.
class Car:
	extends RefCounted

	var node: Node3D
	var x: float = 0.0
	var speed: float = 0.0
	var wheels: Array[Node3D] = []
	var hubs := PackedVector3Array()
	var radius: float = 0.3
	## Whether it has already sounded passing by, and whether it honked (ADR-0052, decision 7).
	var heard: bool = false
	var honked: bool = false


## One lane: where it goes, where it is, how fast and who is on it.
class Lane:
	extends RefCounted

	var z: float = 0.0
	## -1 — left, +1 — right.
	var towards: float = -1.0
	var speed: float = 9.0
	## Where cars enter and where they disappear, along X.
	var entry: float = 0.0
	var exit: float = 0.0
	## Cars, the frontmost in the direction of travel first.
	var cars: Array[Car] = []
	## How much empty lane to leave behind the last one that entered, m.
	var next_gap: float = 10.0
	## Whether the entry is held: no new cars enter the lane Otto merges into while he
	## has been waiting too long.
	var held: bool = false


## This exit's situation.
var density: Density = Density.NORMAL
## Whether the traffic's headlights are on: not in the daytime in clear weather
## (ADR-0052, decision 3).
var headlights: bool = true

## Whether it is snowing: then the traffic cars have snow on them (ADR-0054).
var _snowy: bool = false
var _rng := RandomNumberGenerator.new()
var _street: float = 0.0
var _near := Lane.new()
var _far := Lane.new()
## Otto's car merged into the near lane: others keep their distance behind it.
var _guest: Node3D = null
## Whether Otto's car keeps the traffic running ([method keep_running]).
var _kept: bool = false
## Depth of each pack model, m: the car is squeezed to the lane width by it.
var _depths: Dictionary = {}


## Builds the traffic on the street at end wall [param left], the street level is
## [param street] in the rules plane. The lanes are filled from the first frame: the
## street is already alive when the exit comes into view. [param time] — time of day,
## the density depends on it; [param lights] — whether headlights are on.
func build(
	left: float,
	street: float,
	building_seed: int,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	lights: bool = true,
	snowy: bool = false
) -> void:
	name = "Traffic"
	_snowy = snowy
	_street = street
	headlights = lights
	_rng.seed = hash([building_seed, SALT])
	density = _draw_density(_rng.randf(), time)
	var far_end := left - ExitStreet.FROM - BEHIND_CORNER
	var corner := left + BEHIND_CORNER
	_near.z = NEAR_LANE_Z
	_near.towards = -1.0
	_near.entry = corner
	_near.exit = far_end
	_far.z = FAR_LANE_Z
	_far.towards = 1.0
	_far.entry = far_end
	_far.exit = corner
	for lane: Lane in [_near, _far]:
		lane.speed = _rng.randf_range(SPEEDS.x, SPEEDS.y)
		_fill(lane)
	set_active(false)


## The situation by fraction [param roll] from [0, 1) at time [param time]: by the
## shares in [constant DENSITY_ODDS].
static func _draw_density(roll: float, time: TimeOfDay.Kind) -> Density:
	var odds: Array = DENSITY_ODDS[time]
	var upto := 0.0
	for index: int in odds.size():
		upto += float(odds[index])
		if roll < upto:
			return index as Density
	return Density.HEAVY


## Which situation the building with seed [param building_seed] gets at time
## [param time]: the same first draw as in [method build]. For tests — to find a
## building with the needed one.
static func density_for(building_seed: int, time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT) -> Density:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	return _draw_density(rng.randf(), time)


## How long Otto's car waits for a gap before the traffic suits it, s.
func wait_limit() -> float:
	return WAIT_LIMITS[density]


## Whether the traffic moves: only while the exit is in the frame — or while Otto's
## car waits for it ([method keep_running]).
func set_active(on: bool) -> void:
	set_physics_process(on or _kept)


## The traffic moves whatever the frame shows: Otto's car is waiting for it, and
## stopped traffic would hold it at the roadway's edge forever.
func keep_running() -> void:
	_kept = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	step(delta)


## Traffic step. Separate from [method _physics_process]: tests drive it themselves.
func step(delta: float) -> void:
	# One camera per step: cars decide by it when to sound their pass-by.
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for lane: Lane in [_near, _far]:
		_drive(lane, delta, camera)
		_let_in(lane)
		_let_go(lane)


## Middle of the near lane along Z: Otto's car merges there.
func near_lane_z() -> float:
	return _near.z


## Near lane speed, m/s: the merged Otto's car drives at it.
func near_speed() -> float:
	return _near.speed


## The lane's cars: the near one with [param near], otherwise the far one. For tests.
func cars(near: bool) -> Array[Car]:
	return _near.cars if near else _far.cars


## Whether the near lane is clear to merge into at point [param x]: nobody behind is
## coming closer than [constant CLEAR_BEHIND], nobody ahead is closer than
## [constant CLEAR_AHEAD].
func is_clear_for(x: float) -> bool:
	for car: Car in _near.cars:
		# The near lane goes left: behind is to the right, ahead is to the left. The gap
		# is bumper to bumper: middle to middle minus the car's length.
		var gap := car.x - x
		if gap >= 0.0 and gap - CarModel.LENGTH < CLEAR_BEHIND:
			return false
		if gap < 0.0 and -gap - CarModel.LENGTH < CLEAR_AHEAD:
			return false
	return true


## Whether to hold the near lane's entry: Otto has been waiting too long, and a gap
## must happen.
func hold_back(on: bool) -> void:
	# Otto has been waiting for a gap too long — those behind honk.
	if on and not _near.held and not _near.cars.is_empty():
		_honk(_near.cars[_near.cars.size() - 1])
	_near.held = on


## Otto's car merged into the near lane: those coming up from behind keep their
## distance to it too.
func join(car: Node3D) -> void:
	_guest = car


## Moves the lane's cars one step: full speed, but no closer than the distance to the
## one ahead. [param camera] — the frame, by which the pass-by sounds ([method _pass_by]).
func _drive(lane: Lane, delta: float, camera: Camera3D) -> void:
	for index: int in lane.cars.size():
		var car := lane.cars[index]
		var wanted := lane.speed
		var ahead := _ahead_of(lane, index)
		if not is_nan(ahead):
			var gap := (ahead - car.x) * lane.towards - CarModel.LENGTH
			wanted *= clampf((gap - MIN_GAP) / (SAFE_GAP - MIN_GAP), 0.0, 1.0)
		var change := ACCELERATION if wanted > car.speed else BRAKING
		# Brakes hard behind Otto's car — honks. Specifically behind it: behind a traffic
		# car they brake silently.
		if wanted < car.speed * 0.4 and not car.honked and _behind_the_guest(lane, ahead):
			_honk(car)
		car.speed = move_toward(car.speed, wanted, change * delta)
		_pass_by(car, camera)
		car.x += lane.towards * car.speed * delta
		car.node.position.x = car.x
		# The wheels roll, like those of Otto's car ([method CarModel.roll]).
		CarModel.roll(car.wheels, car.hubs, car.speed * delta, car.radius)


## A car approaching the frame sounds its pass-by on itself: the pass-by recording
## peaks in the middle, and it is started in advance, by the car's speed.
func _pass_by(car: Car, camera: Camera3D) -> void:
	if car.heard or camera == null:
		return
	if absf(car.x - camera.global_position.x) > maxf(car.speed, 1.0) * PASS_LEAD:
		return
	car.heard = true
	# In snow the tyres hiss through slush (ADR-0054).
	var tyres := Sounds.CAR_PASS_SLUSH if _snowy else Sounds.CAR_PASS
	var voice := Sounds.source(car.node, tyres, PASS_REACH)
	voice.volume_db = PASS_DB
	voice.finished.connect(voice.queue_free)
	voice.play()


## The car ahead of a near-lane car is Otto's car: [param ahead] from
## [method _ahead_of] matched it.
func _behind_the_guest(lane: Lane, ahead: float) -> bool:
	if lane != _near or is_nan(ahead) or _guest == null or not is_instance_valid(_guest):
		return false
	return is_equal_approx(ahead, _guest.position.x)


## Horn of car [param car] — once per car.
func _honk(car: Car) -> void:
	car.honked = true
	if car.node.is_inside_tree():
		Sounds.play_at(car.node, Sounds.HORN, car.node.global_position, PASS_REACH, HORN_DB)


## Where the car ahead of car [param index] is, along X; NAN — nobody ahead.
## Otto's car counts as the car ahead for everyone in the near lane behind it.
func _ahead_of(lane: Lane, index: int) -> float:
	var ahead := NAN
	if index > 0:
		ahead = lane.cars[index - 1].x
	if lane == _near and _guest != null and is_instance_valid(_guest):
		var guest := _guest.position.x
		var car := lane.cars[index].x
		if (guest - car) * lane.towards > 0.0:
			if is_nan(ahead) or (ahead - guest) * lane.towards > 0.0:
				ahead = guest
	return ahead


## Lets a new car into the lane when enough gap has built up behind the last one.
func _let_in(lane: Lane) -> void:
	if lane.held:
		return
	if not lane.cars.is_empty():
		var last := lane.cars[lane.cars.size() - 1]
		if (last.x - lane.entry) * lane.towards < lane.next_gap + CarModel.LENGTH:
			return
	lane.cars.append(_add_car(lane, lane.entry))
	lane.next_gap = _next_gap()


## Removes those that drove past the end of the street.
func _let_go(lane: Lane) -> void:
	while not lane.cars.is_empty():
		var first := lane.cars[0]
		if (first.x - lane.exit) * lane.towards < 0.0:
			return
		first.node.queue_free()
		lane.cars.remove_at(0)


## Fills the lane with cars from the end to the entry with drawn gaps.
func _fill(lane: Lane) -> void:
	var x := lane.exit - lane.towards * _rng.randf_range(0.0, GAPS[density].y)
	while (lane.entry - x) * -lane.towards > 0.0:
		lane.cars.append(_add_car(lane, x))
		x -= lane.towards * (CarModel.LENGTH + _next_gap())
	lane.next_gap = _next_gap()


## Gap to the next car, m: drawn within the situation's limits.
func _next_gap() -> float:
	var span := GAPS[density]
	return _rng.randf_range(span.x, span.y)


func _add_car(lane: Lane, x: float) -> Car:
	var choice := CarModel.Choice.new()
	choice.model = _rng.randi_range(0, CarModel.MODELS.size() - 1)
	# Without black — the last one: at night it would vanish on the roadway.
	choice.paint = _rng.randi_range(0, CarModel.PAINTS.size() - 2)
	var root := Node3D.new()
	root.name = "TrafficCar"
	var model := CarModel.build(choice)
	model.scale = Vector3(1.0, 1.0, Garage.CAR_WIDTH / _depth_of(choice.model, model))
	root.add_child(model)
	if _snowy:
		CarModel.snow_on(model)
	if headlights:
		var halo := ExitCar.halo()
		# Under its own name: "Halo" is the rain halo ([RainLook]), and in dry weather it
		# must not be in the building; traffic headlights shine in dry weather too.
		halo.name = "HeadlightGlow"
		halo.position = Vector3(CarModel.LENGTH * HALO_REACH, HALO_HEIGHT, 0.0)
		root.add_child(halo)
	else:
		# In clear daytime headlights are off.
		Garage.switch_lights_off(model)
	# The model's hood faces +X; for the left-bound lane the car is turned around entirely.
	if lane.towards < 0.0:
		root.rotation.y = PI
	root.position = WorldSpace.to_scene(Vector2(x, _street))
	root.position.z = lane.z
	add_child(root)
	# Cars enter after the street is built too: the sun is given to them right away.
	Outdoors.mark(root)
	var car := Car.new()
	car.node = root
	car.x = x
	car.speed = lane.speed
	car.wheels = CarModel.wheels(model)
	car.hubs = CarModel.hubs(car.wheels)
	car.radius = CarModel.wheel_radius(car.wheels, car.radius)
	return car


## Depth of a pack model, once per model: measuring it for every traffic car would mean
## walking all the meshes again.
func _depth_of(index: int, model: Node3D) -> float:
	if not _depths.has(index):
		_depths[index] = maxf(Garage.depth_of(model), 0.1)
	return float(_depths[index])
