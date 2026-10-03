class_name CarModel
extends RefCounted

## The car at the exit: a model from the Quaternius Cars Pack (ADR-0032, decision 7).
##
## Every building has its own: which car and what color is a draw by the building seed.
## The first building of a game gets the red sports car, as in 1983. Taxis and police
## cars are not in the draw: a spy driving off in a patrol car is strange.
##
## Models are built by `tools/build_actors.py cars`: hood toward +X, origin between
## the wheels on the ground, length [constant Proportions.CAR_LENGTH], depth as much as
## fits between the back wall and Otto's body. Each body has the material
## `Paint` (the two-tone one also has `PaintShade`), and that is what the draw repaints.
## Headlights and brake lights glow by emission: the car adds no light sources. Since
## M24i each has a driver door opening, a hinged door `DriverDoor`, an interior
## `CarInterior`, a dome light point `DomeLight` and turn signals (ADR-0046, decision 1).

## Snow on the body in a snowfall ([method snow_on]).
const SNOW_CAP := preload("res://src/levels/snow_cap.gdshader")
## Length over the bumpers, m: the same by which [ExitCar] places the car at the exit.
const LENGTH: float = Proportions.CAR_LENGTH

## Models in the draw. The first one is the sports car, taken by the first building.
const MODELS: Array[PackedScene] = [
	preload("res://assets/models/cars/sports_car_2.glb"),
	preload("res://assets/models/cars/sports_car_1.glb"),
	preload("res://assets/models/cars/car_1.glb"),
	preload("res://assets/models/cars/car_2.glb"),
	preload("res://assets/models/cars/suv.glb"),
]

## Body paints. The first is the red of the first building. The tones are deep but not
## black: the car stands in a garage under a single lamp, and a dark one would vanish in
## the frame.
const PAINTS: Array[Color] = [
	Color(0.62, 0.08, 0.07),
	Color(0.08, 0.2, 0.45),
	Color(0.85, 0.82, 0.74),
	Color(0.12, 0.35, 0.2),
	# Not yellow: a yellow car of any model reads as a taxi, and taxis are not in the draw.
	Color(0.55, 0.62, 0.7),
	Color(0.45, 0.46, 0.5),
	Color(0.35, 0.12, 0.4),
	Color(0.05, 0.05, 0.06),
]

## How much darker the second paint of a two-tone body is.
const SHADE: float = 0.55

const HEADLIGHT := Color(1.0, 0.95, 0.8)
const TAILLIGHT := Color(1.0, 0.1, 0.08)
const INDICATOR_GLASS := Color(0.55, 0.3, 0.05)

## Salt of the car draw: its own, so that the car does not move in step with the layout.
const SALT: int = 0x0CA2_5EED

## Draw by building kind (ADR-0058, decision 4): weights of the models [constant MODELS]
## and paints [constant PAINTS]: the hotel has sports cars and a black sedan, the office
## dark executive sedans and SUVs, the residential building plain sedans and SUVs in
## faded colors. By [enum BuildingIdentity.Kind].
const MODEL_WEIGHTS: Array[Array] = [
	[3, 3, 2, 1, 0],
	[1, 0, 3, 3, 2],
	[0, 0, 2, 3, 3],
]
const PAINT_WEIGHTS: Array[Array] = [
	[1, 1, 2, 0, 0, 1, 2, 4],
	[0, 2, 0, 0, 2, 3, 0, 3],
	[0, 1, 2, 3, 2, 1, 1, 0],
]
## How much the residential building paint has faded toward gray: old cars of
## not-so-rich residents. By [enum BuildingIdentity.Kind].
const FADE: Array[float] = [0.0, 0.0, 0.3]
const FADED := Color(0.5, 0.5, 0.48)


## The building's draw: which model and which paint. [param building] is the building's
## number in the game, [param building_seed] its seed.
class Choice:
	extends RefCounted

	var model: int = 0
	var paint: int = 0
	## How much the paint has faded toward gray ([constant FADE]).
	var fade: float = 0.0


## What stands at the exit of a building of kind [param kind]. The first building of a
## game gets the red sports car, whatever its kind.
static func choose(
	building: int, building_seed: int, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> Choice:
	var choice := Choice.new()
	if building <= 1:
		return choice
	var rng := RandomNumberGenerator.new()
	# The building number goes into the draw together with the seed: without the game salt
	# the seed is the number, and tools shoot different buildings on the same seed.
	rng.seed = hash([building_seed, building, SALT])
	return draw(rng, kind)


## The car of a building of kind [param kind] by draw [param rng] using the kind's
## weights. The paints [param banned] do not come up: red is Otto's car in the first
## building, black vanishes in the darkness by the curb.
static func draw(
	rng: RandomNumberGenerator, kind: BuildingIdentity.Kind, banned: Array[int] = []
) -> Choice:
	var choice := Choice.new()
	choice.model = _weighted(rng, MODEL_WEIGHTS[kind], [])
	choice.paint = _weighted(rng, PAINT_WEIGHTS[kind], banned)
	choice.fade = FADE[kind]
	return choice


## An index by weights [param weights] excluding the banned [param banned]. If only zeros
## are left, the draw is even across the allowed ones.
static func _weighted(rng: RandomNumberGenerator, weights: Array, banned: Array[int]) -> int:
	var total := 0
	for index: int in weights.size():
		if not banned.has(index):
			total += int(weights[index])
	if total <= 0:
		var allowed: Array[int] = []
		for index: int in weights.size():
			if not banned.has(index):
				allowed.append(index)
		return allowed[rng.randi_range(0, allowed.size() - 1)]
	var roll := rng.randi_range(0, total - 1)
	for index: int in weights.size():
		if banned.has(index):
			continue
		roll -= int(weights[index])
		if roll < 0:
			return index
	return weights.size() - 1


## Assembles the car as a node without bodies.
static func build(choice: Choice = Choice.new()) -> Node3D:
	var car := (MODELS[choice.model] as PackedScene).instantiate() as Node3D
	car.name = "Car"
	var paint := PAINTS[choice.paint].lerp(FADED, choice.fade)
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(surface)
			var wanted := _material_for(material.resource_name if material else "", paint)
			if wanted != null:
				mesh_instance.set_surface_override_material(surface, wanted)
	# Rain and snow die on the body instead of going through the car (ADR-0054).
	Shelter.over_meshes(car)
	return car


## Snow on the body ([code]snow_cap.gdshader[/code]) as an overlay material on
## its parts, on top of its own paint (ADR-0054). [param amount] is how much
## snow: 1 is a cap, less is a dusting. Wheels and interior get no snow: a rolling
## wheel would carry a white stripe over the top of the tire, and the seats under the
## glass would show white as a snowdrift in the interior.
static func snow_on(car: Node3D, amount: float = 1.0) -> void:
	var cap := ShaderMaterial.new()
	cap.shader = SNOW_CAP
	cap.set_shader_parameter("amount", amount)
	for node in car.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Wheel") or node.name.begins_with("CarInterior"):
			continue
		(node as MeshInstance3D).material_overlay = cap


## The car's wheels: nodes that spin when it drives.
static func wheels(car: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in car.find_children("Wheel*", "Node3D", true, false):
		found.append(node as Node3D)
	return found


## The middle of each wheel [param wheels] in its own coordinates: it spins around
## that. The pack's wheel node origin is not on the axle but at the car origin, and
## rotating around the origin would carry the wheels in a circle around the body
## (M21 code review).
static func hubs(wheels: Array[Node3D]) -> PackedVector3Array:
	var found := PackedVector3Array()
	for wheel: Node3D in wheels:
		var mesh := wheel as MeshInstance3D
		found.append(mesh.mesh.get_aabb().get_center() if mesh != null else Vector3.ZERO)
	return found


## Wheel radius from its mesh bounds, m; [param fallback] if there are no meshes.
static func wheel_radius(wheels: Array[Node3D], fallback: float) -> float:
	var radius := fallback
	for wheel: Node3D in wheels:
		var mesh := wheel as MeshInstance3D
		if mesh != null:
			radius = maxf(mesh.mesh.get_aabb().size.y * 0.5, 0.05)
	return radius


## Rolls the wheels [param wheels] around the axles [param hubs] over a path of
## [param travel], m: the angle is the path divided by the radius [param radius]. The
## hood points to +X, and a wheel rolling forward turns clockwise as seen from +Z, which
## is minus around +Z. A model turned backward rolls them forward in its own frame, so
## the sign is the same.
static func roll(
	wheels: Array[Node3D], hubs_of: PackedVector3Array, travel: float, radius: float
) -> void:
	var spin := Basis(Vector3.BACK, -travel / radius)
	for index: int in wheels.size():
		var hub := hubs_of[index]
		wheels[index].transform *= Transform3D(spin, hub - spin * hub)


## Replacing a pack material with a game one: paint, light. The rest is as in the pack.
static func _material_for(name: String, paint: Color) -> StandardMaterial3D:
	match name:
		"Paint":
			return GreyboxLook.polished(paint)
		"PaintShade":
			return GreyboxLook.polished(paint.darkened(SHADE))
		"Headlights":
			return GreyboxLook.light(HEADLIGHT)
		"TailLights":
			return GreyboxLook.light(TAILLIGHT)
		# Turn signals without light are amber plastic; only the right one on Otto's car
		# blinks, with its own material ([ExitCar]).
		"IndicatorLeft", "IndicatorRight":
			return GreyboxLook.polished(INDICATOR_GLASS)
	return null
