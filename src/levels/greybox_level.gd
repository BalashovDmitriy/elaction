class_name GreyboxLevel
extends Node3D

## A building assembled from a [BuildingPlan].
##
## Where everything stands is decided by the layout from the rules and the seed; the level only
## places the nodes and wires them together. It started as grey boxes (ADR-0021);
## the boxes stayed as collision bodies, and the look — finish, dressing, light and
## pack models — is assembled by builders: [BuildingShell], [BuildingRibs],
## [BuildingShafts], [BuildingScenery] and others.
##
## The layout works in the rules plane, where Y grows downward. Everything the level
## puts into the scene goes through [WorldSpace] — and only through it: the Y flip
## lives in one place (ADR-0021, decision 2).

## Otto got into the car and it pulled away: while it drives off, the bonus is counted.
signal car_started
## The car with Otto has left the frame: the building is cleared.
signal building_cleared

## How many physics frames [method wait_for_the_landing] waits by default:
## the full intro with the helicopter lasts up to 12 s — 720 steps without time
## scaling, the rest is headroom (ADR-0038, decision 1; ADR-0052, decision 6).
const LANDING_PATIENCE: int = 900

const CAR_SCENE := preload("res://src/systems/elevators/elevator_car.tscn")
const ESCALATOR_SCENE := preload("res://src/systems/escalators/escalator.tscn")
const DOOR_SCENE := preload("res://src/systems/doors/door.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")

## How far below the ceiling the middle of the lamp hangs, m.
##
## Under the ceiling, as in the original: with a 3.0 m clearance the lamp bottom is at 2.52 —
## 84% of the clearance against 82% in the original. Those two percent are the margin that
## keeps it "not from a jump": Otto's head hits the ceiling when his feet
## have risen 1.32 m, and his bullet goes no higher than 2.47. The lamp is shot down from a cab,
## as in 1983 (ADR-0026, decision 5).
##
## From the ceiling, not from the floor: a floor of a different height — and tests build such —
## would otherwise hang the lamp inside the slab or in the middle of the room.
const LAMP_DROP: float = Proportions.LAMP_CORD + Proportions.LAMP.y * 0.5

## Height of the spot at the car door where Otto gets in. It grew together with Otto
## (ADR-0026, decision 7).
const EXIT_HEIGHT: float = Proportions.BODY * 0.95

## How much slower the cab responds during the alarm, s.
const ALARM_CAR_DELAY: float = 0.6

## How many floors beyond the visible band a door still releases agents.
##
## The margin keeps an agent from appearing in front of the player in the middle of the frame:
## the door hands him out beyond the edge, and he walks into the frame on his own.
const AGENT_SPAWN_MARGIN: int = 1

## How much farther than that margin an agent lives before he is removed.
##
## Larger than the release margin on purpose: if they matched, an agent at the very edge would
## appear and disappear with the camera jitter.
const AGENT_KEEP_MARGIN: int = 3

## How long Otto lies down before returning to play, s.
const OTTO_RESPAWN_DELAY: float = 1.2


## A post at an agent door: the door itself, its floor and the agent it has already released.
##
## The floor is computed once per building: doors do not move, and [method _tend_agents]
## iterates them every frame — no point deriving the floor from a coordinate sixty times
## a second for fifty doors.
class AgentPost:
	extends RefCounted

	var door: Door = null
	var floor_index: int = 0
	## Who stands behind the door right now. Empty — the door is free.
	var agent: Enemy = null
	## The door leaf is already opening for the next agent, but he has not shown up yet.
	##
	## A door in this state counts as occupied and takes a slot under the cap of
	## living agents: otherwise any number of doors could open during the telegraph,
	## and agents would pour out at once above the cap (ADR-0020).
	var opening: bool = false
	## Slot of the agent the door is releasing or has released; -1 — none.
	var slot: int = -1


## Building rules. Empty means defaults are used.
@export var rules: BuildingRules

## Building seed: the building number salted with the game ([method GameState.building_seed]).
@export var building_seed: int = 1

## Whether doors release agents. Turned off in traversal tests: they
## check that the building can be traversed, not that the fight can be won.
@export var spawn_agents: bool = true

## What building this is: hotel or office and its name (ADR-0033, decision 1).
var identity: BuildingIdentity = null
## Building music: a theme per kind and building half, the alarm (ADR-0057).
var soundtrack: BuildingMusic = null

## The full intro is in the first building of a game, 10–12 s; in the rest and in tests
## it is short (ADR-0052, decision 6). [Main] sets it before entering the tree.
var full_intro: bool = false
var _plan: BuildingPlan
var _doors: Array[Door] = []
var _cars: Array[ElevatorCar] = []
## Shaft dressing as a separate node: fifty parts per building must not get
## into every walk over the level's children. Room walls are there too, for the same reason.
var _shafts: BuildingShafts = null
var _shaft_hums: ShaftHums = null
## The building shell: slabs, walls and the room behind the corridor. The shell places them,
## and the level populates the result — ADR-0024 split this into nodes.
var _shell: BuildingShell = null
## Ribs — slab edges, skirting, pilasters — are also their own node (ADR-0023, decision 4).
var _ribs: BuildingRibs = null
var _lighting := FloorLighting.new()
## Which floors were lit in the previous frame: no need to recompute them every frame.
## (0, -1) serves as the empty band: its end is before its start, while (-1, -1) now
## means "the roof is lit" — that is a real level, and a match would stay silent.
var _lit_span := Vector2i(0, -1)
## Floors in the frame without margin: their lamps cast shadows (ADR-0042, decision 2).
var _shadowed_span := Vector2i(0, -1)
## The frame band along X in which lights are on ([method VisibleFloors.band]).
var _lit_band := Vector2.ZERO
## Building lamps: their light is turned off outside the frame. Fallen lamps remove
## themselves, so liveness is checked before access.
var _lamps: Array[Lamp] = []
## Building escalators: each has its own light, and it goes off outside the frame, like lamps.
var _escalators: Array[Escalator] = []
## Posts at agent doors, one per door. Building doors do not release everyone
## at once — only those whose floor is near the player (ADR-0014, point 4).
var _posts: Array[AgentPost] = []
## The agent release draw per ROM and how long the agent alarm still lasts, s.
var _spawn := AgentSpawn.new()
## Which agents wait at the door Otto is behind (ADR-0038, decision 2).
var _watch := DoorWatch.new()
## Extras in the previous frame's crowd: they keep walking out into a door ([AgentCrowd]).
var _crowd: Dictionary = {}
var _alert_left: float = 0.0
## The car at the exit: while it drives, the building is not cleared yet.
var _car: ExitCar = null
## Exit by car: Otto gets in, it drives away (ADR-0038, decision 4).
var _boarding: ExitBoarding = null
var _exit_position := Vector2.ZERO
## Garage on the bottom floor: gate, light fixtures, other cars (ADR-0038).
var _garage: Garage = null
## Intro: the helicopter brings Otto to the roof. While it runs, Otto ignores
## input, and agents and cabs stand still.
var _arrival := RoofArrival.new()

@onready var otto: Otto = $Otto


func _ready() -> void:
	if rules == null:
		rules = BuildingRules.new()
	_plan = BuildingPlan.generate(rules, building_seed)
	Ragdoll.abyss = WorldSpace.height_to_scene(rules.total_height() + Ragdoll.ABYSS_MARGIN)
	RunLog.write("building", {"seed": building_seed, "floors": rules.floors})
	_spawn.rng.seed = building_seed
	# Its own generator, not the release one: otherwise entering a door would change agent release.
	_watch.rng.seed = building_seed * 31 + 7
	# And a separate one for takedown scenes — for the same reason (ADR-0040).
	otto.takedown_rng.seed = building_seed * 17 + 3
	# Building kind: finish, dressing, sign (ADR-0033) and its family's palette (ADR-0056).
	identity = BuildingIdentity.of(GameState.instance().building, building_seed)
	rules.palette = BuildingPalette.of_kind(rules.palette, identity.kind)
	rules.kind = identity.kind
	soundtrack = BuildingMusic.new(rules, building_seed)
	_ribs = BuildingRibs.new()
	_ribs.name = "Ribs"
	_ribs.setup(rules, _plan, identity)
	add_child(_ribs)
	_shell = BuildingShell.new()
	_shell.name = "Shell"
	add_child(_shell)
	_shell.build(rules, _plan, _ribs)
	var signs := FloorSigns.new()
	signs.name = "FloorSigns"
	add_child(signs)
	signs.hang(rules)
	_spawn_shafts()
	_spawn_escalators()
	_spawn_doors()
	# After the doors: whether to lock the basement depends on the building's document count.
	var basement := BasementLock.new()
	add_child(basement)
	basement.setup(rules, _plan, _cars)
	_spawn_lamps()
	_build_garage()
	_spawn_exit()
	# Air, roof, dressing, city and weather — surroundings without gameplay (ADR-0029).
	var scenery := BuildingScenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.build(rules, _plan, building_seed, identity)
	scenery.catch_rain([_shell, _shafts, _ribs] as Array[Node])
	scenery.light_outdoors([_shell, _shafts, _ribs] as Array[Node], rules)

	# Otto starts on the roof, as in the original, and where there are no openings. The roof is
	# its own level above the building, not floor zero: ADR-0014, point 1.
	# The helicopter brings him, as in the ZX Spectrum port — in every building
	# (ADR-0038, decision 1). After a death there is no helicopter: [method _respawn_otto].
	var roof := BuildingRules.ROOF
	var landing := Vector2(_plan.safe_x(rules, roof), rules.floor_surface(roof))
	# A fall of more than a floor kills — a floor of this building (ADR-0037).
	otto.floor_height = rules.floor_height
	otto.died.connect(_on_otto_died)
	GameState.instance().alarm_raised.connect(_on_alarm_raised)
	if GameState.instance().alarm.raised:
		# The building is set up with the siren already on — rare, but it happens. No alarm
		# flash here — and no bell either.
		_on_alarm_raised(false)
	var bounds := Rect2(0.0, 0.0, rules.width, rules.total_height())
	var daytime := TimeOfDay.is_daytime(rules.time_of_day)
	# In snow the rotor kicks up snow dust (ADR-0054).
	var snowy := Weather.is_snowing(Weather.of_building(rules, building_seed))
	var snow := SnowLook.brightness(rules.time_of_day) if snowy else -1.0
	_arrival.begin(self, otto, landing, bounds, full_intro, daytime, snow)


## Turns off everything that has left the frame. There are thirty lamps in the building, and the
## frame fits two and a half floors — ADR-0010, point 8.
##
## Light and sound by Otto's position are here: both are part of the frame, and computing them
## more often than a frame is pointless.
func _process(_delta: float) -> void:
	_listen_where_otto_is()
	var seen := otto.camera_view()
	var span := VisibleFloors.around(rules, seen)
	# Exit light — only when the frame has moved past the building end wall to the gate: in play
	# the camera never goes there, and the street lamp and neon are not lit there at all.
	if _garage != null and _garage.gate != null:
		var bottom := rules.floors - 1
		_garage.gate.show_street(
			(
				seen.position.x < rules.floor_span(bottom).x
				and (VisibleFloors.covers(span, bottom) or VisibleFloors.covers(span, bottom - 1))
			)
		)
	var in_frame := VisibleFloors.seen(rules, seen)
	var strip := VisibleFloors.band(seen)
	if span == _lit_span and in_frame == _shadowed_span and strip == _lit_band:
		return

	_lit_span = span
	_shadowed_span = in_frame
	_lit_band = strip
	FloorLighting.show_in_frame(rules, seen, _lamps, _doors)
	# Shaft columns follow the same rule: there are three times more of them than lamps.
	if _shafts != null:
		_shafts.light_span(span, strip)
	# Light of special floor halls — likewise (ADR-0057).
	if _shell != null and _shell.halls != null:
		_shell.halls.light_span(span, strip)
	# Light of the garage tubes — likewise.
	if _garage != null:
		_garage.show_lights(VisibleFloors.covers(span, rules.floors - 1))
	FloorLighting.show_escalators(span, strip, _escalators)


## The layout the building was assembled from.
func plan() -> BuildingPlan:
	return _plan


## Hanging lamps of the building. A fallen one removes itself ([method Lamp._land]).
func lamps() -> Array[Lamp]:
	var hanging: Array[Lamp] = []
	for lamp in _lamps:
		if is_instance_valid(lamp) and lamp.is_hanging():
			hanging.append(lamp)
	return hanging


## Building doors: they show which red ones have not been collected yet.
func doors() -> Array[Door]:
	return _doors


## Doors agents come out of.
##
## Not the same as the regular building doors: a red one gets here once its
## document is taken (ADR-0020, decision 6). Counted by posts, not by the list
## of doors, because a post is exactly "a door on the payroll".
func agent_doors() -> Array[Door]:
	var serving: Array[Door] = []
	for post: AgentPost in _posts:
		serving.append(post.door)
	return serving


## The door the agent came out of, or null. Not the nearest one to him: since M18e doors
## stand every other slot, and an agent who came out is sometimes closer to a neighbour (ADR-0028).
func door_of(agent: Enemy) -> Door:
	for post: AgentPost in _posts:
		if post.agent == agent:
			return post.door
	return null


## Where the building exit is — the car's driver door — in the rules plane.
func exit_position() -> Vector2:
	return _exit_position


## Garage on the bottom floor: it has a gate ([method Garage.open_gate]).
func garage() -> Garage:
	return _garage


## Waits until Otto slides down the rope and stands on the roof; true — he landed.
##
## A building starts with the intro: the helicopter brings Otto, and until landing he
## ignores input (ADR-0038, decision 1). Wait for it by state, not by
## a delay: the intro length will still change, and under [member Engine.time_scale]
## a delay lies outright. One place for shots and tests — copies of this loop
## drifted apart in four places across the project.
func wait_for_the_landing(patience: int = LANDING_PATIENCE) -> bool:
	var left := patience
	while not otto.is_grounded() and left > 0:
		await get_tree().physics_frame
		left -= 1
	return otto.is_grounded()


## The building intro — for tests and shots: which step is running, whether it is full.
func arrival() -> RoofArrival:
	return _arrival


## Skips the intro: Otto is on the roof right away, the helicopter leaves. Returns
## whether an intro was running — [Main] uses it to decide between pause and skip.
func skip_the_intro() -> bool:
	return _arrival.skip()


## Whether the intro is running.
func is_in_the_intro() -> bool:
	return _arrival.is_playing()


## The intro helicopter; null once it has flown away.
func helicopter() -> Helicopter:
	return _arrival.helicopter()


## Whether the whole floor is dark — all its zones. They go out for good: a shot-down lamp
## does not light up again.
func is_dark(floor_index: int) -> bool:
	return _lighting.is_dark(floor_index)


## Whether a point on a floor is dark: whether the zone of the lamp nearest to it is out (ADR-0023).
func is_dark_at(floor_index: int, x: float) -> bool:
	return _lighting.is_dark_at(floor_index, x)


func _spawn_shafts() -> void:
	_shafts = BuildingShafts.new()
	add_child(_shafts)
	_shafts.dress(rules, _plan)
	_shaft_hums = ShaftHums.new()
	_shaft_hums.name = "ShaftHums"
	add_child(_shaft_hums)
	for shaft in _plan.shafts:
		# The upper deck of a pair does not go down to the shaft's bottom floor: the lower one would
		# hit the bottom. So stops are counted by the lead cab, not by the band.
		var lowest := shaft.bottom - 1 if shaft.double_deck else shaft.bottom
		var stops := PackedFloat32Array()
		for index in range(shaft.top, lowest + 1):
			stops.append(rules.floor_surface(index))

		var car := CAR_SCENE.instantiate() as ElevatorCar
		car.position.x = shaft.x
		add_child(car)
		# The cab fills the floor clearance entirely, as in the original: it takes its height
		# from the rules, not from its scene (ADR-0025, decision 10).
		car.dress_as(rules.kind)
		car.fit_to_story(rules.floor_height - rules.slab_height, rules.shaft_width)
		car.setup(stops)
		car.set_shaft_top(_shafts.top_of(shaft))
		_cars.append(car)
		# Indicator boards at the portals show where this cab is (ADR-0033, decision 7).
		_shafts.watch(car, shaft)
		if shaft.double_deck:
			_spawn_lower_deck(car, shaft)
		_shaft_hums.add(shaft, _shafts.top_of(shaft), rules.floor_surface(shaft.bottom))


## Building progress: the intro, the car driving off, agents at doors.
##
## All of this is physics, not a frame, and it used to live in [method Node._process]. The
## difference is not cosmetic: a frame runs by the wall clock, physics by an even step, and the bot
## drives Otto by physics steps. Agent release driven by frame delta meant that on a
## fast machine more of them came out for the same bot step, and the same seed
## gave four deaths one time and five another. Exactly this debt dragged on since M18a.
func _physics_process(delta: float) -> void:
	RunLog.tick(delta)
	if _arrival.is_playing():
		_arrival.advance(delta)
		return
	_arrival.linger(delta)

	# The rules frame, not the player's smoothed frame: that one moves in _process by the wall
	# clock, and the agent release band after Otto's jump depended on machine
	# speed — in CI the combat test failed every other run (M20).
	var view := otto.camera_view(true)
	if _boarding != null:
		var ready_to_go := GameState.instance().all_documents_collected()
		match _boarding.step(delta, otto, ready_to_go, view):
			ExitBoarding.Event.STARTED:
				car_started.emit()
			ExitBoarding.Event.LEFT:
				building_cleared.emit()

	_stir_agents(delta)
	_shroud_agents()
	# Agents are recounted every step, not only when the band changes: a door waits
	# for its pause, and having missed the change step it would not release anyone until the next.
	if spawn_agents:
		_tend_agents(VisibleFloors.around(rules, view), delta)


## The lower deck of a two-storey pair: one floor below the lead cab and on its travel.
##
## It is placed after the lead cab, and that is not an accident: the deck takes the lead's height
## in the same frame, and nodes are visited in tree order.
func _spawn_lower_deck(leader: ElevatorCar, shaft: BuildingPlan.ShaftSpot) -> void:
	var deck := CAR_SCENE.instantiate() as ElevatorCar
	deck.position.x = shaft.x
	add_child(deck)
	deck.dress_as(rules.kind)
	deck.fit_to_story(rules.floor_height - rules.slab_height, rules.shaft_width)
	deck.serve_as_deck(leader, rules.floor_height)
	# The deck joins the common list on a par with the lead: an agent boards the one standing
	# level with his floor, and which of the two it is does not matter to him.
	_cars.append(deck)


func _spawn_escalators() -> void:
	for spot in _plan.escalators:
		var escalator := ESCALATOR_SCENE.instantiate() as Escalator
		escalator.position = WorldSpace.to_scene(
			Vector2(spot.x, rules.floor_surface(spot.floor_index))
		)
		# The floor is known here, and it is not derived back from a coordinate: by it
		# the level turns off the flight's light outside the frame.
		escalator.floor_index = spot.floor_index
		add_child(escalator)
		_escalators.append(escalator)

		var descent := Vector2(spot.towards * rules.escalator_run, rules.floor_height)
		# The bend is in the opening itself: both the belt and the ride go through it, so
		# the passenger passes through the hole, not through the slab.
		var gap := spot.hole(rules)
		# The opening is in escalator coordinates: the escalator places the framing itself, and the rules
		# do not have to know where its node stands.
		var edges := Vector2(gap.x - spot.x, gap.y - spot.x)
		escalator.setup(descent, spot.bend(rules), edges, rules.slab_height)


func _spawn_doors() -> void:
	# The level does not touch the score: it accumulates from building to building and is reset by
	# whoever starts the game. Here we only announce how many documents there are.
	var game := GameState.instance()
	var documents := 0
	var sky := Weather.of_building(rules, building_seed)
	for spot in _plan.doors:
		var door := DOOR_SCENE.instantiate() as Door
		door.position = WorldSpace.to_scene(Vector2(spot.x, rules.floor_surface(spot.floor_index)))
		door.has_document = spot.has_document
		var room_seed := hash([building_seed, spot.floor_index, roundi(spot.x * 10.0)])
		var span := rules.floor_span(spot.floor_index) - Vector2(spot.x, spot.x)
		var unlit := rules.is_unlit(spot.floor_index)
		door.furnish(identity, room_seed, span, unlit, rules.time_of_day, sky)
		door.opens_into_hall = FloorRole.hall_at(rules, spot.floor_index)
		add_child(door)
		_doors.append(door)
		door.otto_hid.connect(_on_otto_hid.bind(door))
		door.otto_came_out.connect(_watch.end)

		if not door.is_pending():
			_enlist_door(door)
			continue
		documents += 1
		door.document_taken.connect(game.collect_document)
		# An emptied door becomes a regular one and starts releasing agents:
		# it looks regular too (ADR-0020, decision 6). Previously a red door
		# stayed a permanent cover for the whole building.
		door.document_taken.connect(_enlist_door.bind(door))
	game.start_building(documents)


## How far above the floor the middle of the lamp hangs under these rules, m.
static func lamp_height(of_rules: BuildingRules) -> float:
	return of_rules.floor_height - of_rules.slab_height - LAMP_DROP


func _spawn_lamps() -> void:
	var style := BuildingStyle.of(identity)
	for spot in _plan.lamps:
		var lamp := LAMP_SCENE.instantiate() as Lamp
		var hang := rules.floor_surface(spot.floor_index) - lamp_height(rules)
		lamp.position = WorldSpace.to_scene(Vector2(spot.x, hang))
		# The lamp's floor is known here, and it is not derived back from a coordinate: under
		# the ceiling it is closer to the floor above than to its own.
		lamp.floor_index = spot.floor_index
		lamp.dress_as(style)
		# The lamp zone is counted from what hangs: the darkness rule learns about the
		# lamp in the same place where it is hung.
		_lighting.hang(spot.floor_index, spot.x)
		lamp.crushed.connect(_on_lamp_crushed)
		lamp.fell.connect(_on_lamp_fell.bind(lamp.floor_index, spot.x))
		add_child(lamp)
		lamp.hang(lamp_height(rules), rules.floor_height - rules.slab_height)
		_lamps.append(lamp)
	# Dark floors get no lamp map, and darkness is declared for them here,
	# where lamps are hung: otherwise a floor without lamps is lit for the darkness rule (ADR-0028).
	_lighting.follow(rules)


## The building exit. Without all documents the basement is out of reach — it is locked by
## [BasementLock]; in the basement Otto walks to the car and gets in (ADR-0038, decision 4).
##
## Here — the car and the boarding spot at its door. The gate it drives through
## and the green sign above it are [Garage] (ADR-0038, decision 3).
func _spawn_exit() -> void:
	var bottom := rules.floors - 1
	var surface := rules.floor_surface(bottom)
	var centre := _plan.exit_x
	_spawn_car(centre, surface)


## The garage on the bottom floor — looks only, no bodies: hall, columns, light fixtures, other
## cars and the gate in the left end wall (ADR-0038, decision 3).
func _build_garage() -> void:
	_garage = Garage.new()
	_garage.name = "Garage"
	add_child(_garage)
	_garage.build(rules, _plan, building_seed)


## The car at the exit: [ExitCar] places it at the gate, on the bottom floor. You can get in
## at the driver door — that is where [method exit_position] leads.
func _spawn_car(exit_x: float, surface: float) -> void:
	_car = ExitCar.new()
	var choice := CarModel.choose(GameState.instance().building, building_seed, rules.kind)
	_car.park(exit_x, surface, rules, _plan, choice)
	add_child(_car)
	# A parked car stands with dark headlights: they turn on when it drives off.
	_car.set_lights(false)
	if _garage != null and _garage.gate != null and _garage.gate.ramp() != null:
		_car.traffic = _garage.gate.ramp().traffic()
	_boarding = ExitBoarding.new(_car, surface, _garage, ExitBoarding.exit_frame(rules))
	_exit_position = _boarding.door_point()


## A lamp covered an agent on its way down — the most expensive way to kill.
func _on_lamp_crushed(agent: Enemy) -> void:
	if agent.is_dead():
		return
	agent.kill(true)
	var points := GameState.kill_score(GameState.LAMP_SCORE, agent.is_in_the_dark())
	GameState.instance().add_score(points, agent.global_position + GameState.OVER_HEAD)


## The lamp reached the floor: its zone goes dark and does not light up again.
##
## Nothing to turn off: the lamp's light went with it. What remains here is the rule —
## remember the darkness; who stands in it is recomputed by [method _shroud_agents].
func _on_lamp_fell(index: int, x: float) -> void:
	if _lighting.darken(index, x) and index == rules.floors - 1 and _garage != null:
		# Garage light fixtures in the lamp's zone go out with it.
		_garage.darken(x)
	_shroud_agents()


## Hands out darkness to agents: their own — a kill in it is worth more — and Otto's shadow,
## which decides whether they see him at all (ADR-0023, decision 8).
##
## Every frame, not on an event: agents walk along the floor, and the zone under them
## changes on the go. There are no more than four living agents in the building, but [method agents]
## finds them by iterating all the level's children, and there are about three hundred: if a frame
## ever hits a limit on this, agents should be kept in a list rather than searched for anew.
##
## The same pass also hands out the agent alarm ([method _stir_agents]).
func _shroud_agents() -> void:
	var here := _floor_of(otto)
	var otto_in_the_dark := _lighting.is_dark_at(here, otto.global_position.x)
	_watch.start_frame()
	# Obstacles on the floor where Otto hides are the same for all his agents: there is only one
	# such floor ([method DoorWatch.covers]), and computing them for each agent is pointless.
	var watch_blocks: Array[Vector2] = []
	var blocks_counted := false
	var everyone := agents()
	_crowd = AgentCrowd.extras(everyone, rules, here, otto.global_position.x, _crowd)
	for agent in everyone:
		if agent.is_dead():
			continue
		var where := _floor_of(agent)
		_shroud_agent(
			agent, where, agent.global_position.x, here, otto_in_the_dark, _crowd.has(agent)
		)
		if not blocks_counted and _watch.covers(where):
			watch_blocks = _plan.blocks_on(rules, where)
			blocks_counted = true
		_post_agent(agent, where, watch_blocks)
		if _alert_left > 0.0:
			agent.alert_for(_alert_left)


## What an agent knows about Otto and about himself: his own darkness, Otto's shadow and a blank
## wall between them.
##
## One place for both callers: [method _shroud_agents] recomputes this
## every frame, and [method _release_agent] — once, before the new agent's first
## frame. They must not diverge, otherwise the agent would take his first step by different
## rules than all the following ones — with the wall this nearly happened.
##
## The Otto part ([param here], [param target_in_the_dark]) is computed outside: agents are
## up to four, Otto is one, and four identical computations per frame are useless.
## [param where] and [param x] — also outside: a freshly released agent still has
## the door mat's coordinate, not his body's. [param crowded] — the agent is an extra in
## the crowd on his floor ([AgentCrowd]) and leaves through a door.
func _shroud_agent(
	agent: Enemy, where: int, x: float, here: int, target_in_the_dark: bool, crowded: bool = false
) -> void:
	agent.set_in_the_dark(_lighting.is_dark_at(where, x))
	agent.set_target_in_the_dark(target_in_the_dark)
	# The wall divides only its own floor: from another floor Otto is out of reach anyway.
	agent.set_target_behind_a_wall(
		where == here and _plan.wall_between(here, x, otto.global_position.x)
	)
	# An extra in the crowd is not offered a cab: for an agent a cab beats a door, and he
	# would ride to Otto instead of leaving — the crowd at Otto would only grow.
	var lift := NAN if crowded else AgentLifts.offer(_plan, rules, _cars, where, x, here)
	agent.set_lift_at(lift)
	# An agent who has fallen far behind leaves through the nearest door instead of wandering to the
	# end of the building: his slot is needed more where the player is. When — the ROM decides (@041F):
	# distance and floor. But only one who has nothing to ride: one with a shaft heading
	# toward Otto close by waits for the cab.
	var stranded := (
		Arcade.agent_leaves(Arcade.rom_floor(where, rules.floors), where - here)
		and is_nan(lift)
		and not AgentLifts.can_ride(_plan, rules, where, x, here)
	)
	var leaves := stranded or crowded
	agent.set_exit_at(AgentLifts.nearest_door(_plan, rules, _cars, where, x) if leaves else NAN)


## Sets an agent to wait at the door Otto is behind, or takes him off the post
## ([DoorWatch]). Only from the per-frame pass, not on release: the draw is made
## at the first look at an agent, and a freshly released one gets it a frame later —
## while he is in the opening, a spot at the door is no use to him anyway. [param blocks] —
## obstacles on Otto's floor; on other floors [DoorWatch] does not look at them.
func _post_agent(agent: Enemy, where: int, blocks: Array[Vector2]) -> void:
	var x := WorldSpace.to_plane(agent.global_position).x
	agent.watch_at = _watch.post_for(agent.get_instance_id(), where, x, blocks)
	agent.watch_door = _watch.door_x()


## Otto hid behind door [param door]: agents on his floor may go wait for him there.
func _on_otto_hid(door: Door) -> void:
	var mat := door.mat_position()
	_watch.begin(rules.floor_index_near(mat.y), mat.x)


## All agents of the building: they sit directly in the level, next to the geometry.
##
## Public: the bot and the run outside look for exactly the same thing, and three copies of one
## child iteration would diverge at the first edit of the level tree.
func agents() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for child in get_children():
		var agent := child as Enemy
		if agent != null:
			found.append(agent)
	return found


## Building music by kind ([BuildingMusic], ADR-0057, decision 7): the theme of
## the building half where Otto is, or the alarm [param alarm].
func music(alarm: bool) -> void:
	soundtrack.play(alarm, _floor_of(otto))


## Sound by Otto's position — the rules are in [PlaceSound]: on the roof and at the garage gate
## the street is at full strength, on floors — through glass; steps on the building floor.
func _listen_where_otto_is() -> void:
	var index := _floor_of(otto)
	# The theme is not touched by the alarm, the intro or Otto's death: under the last death
	# of the game the ending track is already playing, and a body that rode through the middle of
	# the building must not bring the building theme back (code review M24o).
	soundtrack.follow(
		index, GameState.instance().alarm.raised or _arrival.is_playing() or otto.is_dead()
	)
	Sounds.set_building(rules.kind, Sounds.hall_tone_of(FloorRole.at(rules, index)))
	var at := WorldSpace.to_plane(otto.global_position)
	Sounds.set_outdoors(PlaceSound.hears_street(rules, index, at.x, Garage.gate_x(rules)))
	var on_concrete := index == BuildingRules.ROOF or index == rules.floors - 1
	otto.step_sound = PlaceSound.step_at(on_concrete, identity)
	_shaft_hums.follow(at.y)


## The floor a node stands on. The only place where scene height becomes
## rules height again.
func _floor_of(node: Node3D) -> int:
	return rules.floor_index_near(WorldSpace.to_plane(node.global_position).y)


## Keeps in the building exactly the agents the player cares about — by the release
## rules of the arcade ROM (ADR-0027, decision 2).
##
## There are no more than three agents in the building, and late and at high skill — four:
## that many slots the ROM holds (@594D). Once per logic tick the level makes a draw:
## Otto's floor, above or below — and with a difficulty-based chance Otto's floor exactly (@5A4C) —
## and a random free blue door on it. There are no more agents on a floor than
## time in the building allows; while Otto is not on his feet or there is no agent alarm — one
## (@5905, @59F4).
##
## On top of the ROM the door leaf telegraph remains (ADR-0020): a door right next to Otto
## releases, as in the ROM (@5AAB), but the agent comes out only once it has opened
## (ADR-0053, decision 3). Agents who fell several floors behind beyond the frame
## are removed, as before: their slot is needed more where the player is.
func _tend_agents(span: Vector2i, delta: float) -> void:
	var live := 0
	var per_floor: Dictionary = {}
	for post: AgentPost in _posts:
		# Liveness is checked directly on the field: a door has only one agent of its own, and nobody
		# can put someone else's here.
		if is_instance_valid(post.agent) and not post.agent.is_dead():
			if not _within(span, post.floor_index, AGENT_KEEP_MARGIN):
				post.agent.queue_free()
				post.agent = null
				post.door.dismiss_agent()
				_free_slot(post)
				continue
			live += 1
			var where := _floor_of(post.agent)
			per_floor[where] = int(per_floor.get(where, 0)) + 1
			# The leaf goes back as soon as the agent has cleared the opening: an open
			# door in the frame means "someone is about to come out", and keeping it
			# open while the agent is alive blurs the sign (ADR-0020, decision 4).
			if not post.agent.is_emerging():
				post.door.dismiss_agent()
			continue

		# The leaf is already moving: wait until it opens, and only then release.
		# The agent takes the slot right now.
		if post.opening:
			if not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
				post.door.dismiss_agent()
				post.opening = false
				_free_slot(post)
				continue
			live += 1
			per_floor[post.floor_index] = int(per_floor.get(post.floor_index, 0)) + 1
			if post.door.agent_may_step_out():
				post.agent = _release_agent(post)
				post.opening = false
			continue

		# The opening is clear: the agent was killed or left. The leaf goes back
		# from here too — one killed exactly in the frame he stopped being invulnerable
		# never reaches the living branch, and a door nobody told about it
		# would stay open forever. A call on a closed one is a no-op.
		post.agent = null
		post.door.dismiss_agent()

	if _spawn.tick(delta):
		_try_to_spawn(span, live, per_floor)


## One release draw: slot, floor, door (try_to_spawn_an_enemy_5A26).
func _try_to_spawn(span: Vector2i, live: int, per_floor: Dictionary) -> void:
	var time := _building_time()
	var available := rules.agents_at_once(time)
	if live >= available:
		return
	var slot := _spawn.open_slot(available, Door.AGENT_OPEN_TIME)
	if slot < 0:
		return

	var here := _floor_of(otto)
	var floor_index := _spawn.pick_floor(here, _difficulty())
	var cap := Arcade.agents_per_floor(time, otto.is_on_foot(), _alert_left > 0.0)
	if int(per_floor.get(floor_index, 0)) >= cap:
		return

	var free: Array[AgentPost] = []
	for post: AgentPost in _posts:
		if post.floor_index != floor_index or post.opening or is_instance_valid(post.agent):
			continue
		if not _within(span, post.floor_index, AGENT_SPAWN_MARGIN):
			continue
		# The leaf is still moving for the previous agent — the door does not count.
		var door_x := post.door.mat_position().x
		if not post.door.can_summon() or _spawn.hugs(rules, post.floor_index, here, door_x, otto):
			continue
		free.append(post)
	if free.is_empty():
		return

	var chosen := free[_spawn.pick(free.size())]
	# Not an agent but a request to open: he will show up when the leaf gets there.
	chosen.opening = chosen.door.summon_agent()
	if chosen.opening:
		chosen.slot = slot
		_spawn.take(slot)


## Frees a post's slot: its replacement comes after a difficulty-based pause.
func _free_slot(post: AgentPost) -> void:
	_spawn.release(post.slot, _difficulty())
	post.slot = -1


## How long the building has been running, s: difficulty grows with it (ADR-0027, decision 1).
func _building_time() -> float:
	return GameState.instance().alarm.elapsed()


## Building difficulty right now: skill plus time (compute_difficulty_592F).
func _difficulty() -> int:
	return Arcade.difficulty(rules.skill, _building_time())


## Agent alarm: Otto's bullet in the frame at difficulty above zero — 90 ticks
## (@59C8). Under it release goes by the full floor cap, and agents shoot
## without looking (ADR-0027, decision 5).
##
## [method _shroud_agents] hands it out to the agents themselves in the same pass as
## darkness: a second iteration over three hundred level children per frame is pointless.
func _stir_agents(delta: float) -> void:
	_alert_left = maxf(_alert_left - delta, 0.0)
	if _difficulty() > 0 and Bullet.any_in_flight(get_tree(), Bullet.FROM_OTTO):
		_alert_left = Arcade.seconds(Arcade.ALERT_TICKS)


## Puts a door on the payroll: from this moment it releases agents.
##
## Nobody releases an agent here: the door hands out its own when its floor
## comes close to the player. Previously all 55 came out at once on building assembly, and two of
## them stood on the roof in the line of fire from the starting point — ADR-0014, point 4.
##
## The floor is computed once: doors do not move, and [method _tend_agents] iterates
## them every frame.
func _enlist_door(door: Door) -> void:
	var post := AgentPost.new()
	post.door = door
	post.floor_index = rules.floor_index_near(door.mat_position().y)
	_posts.append(post)


## Whether a level falls into the band [param span] widened by [param margin] floors.
static func _within(span: Vector2i, index: int, margin: int) -> bool:
	return index >= span.x - margin and index <= span.y + margin


## Places an agent in the open doorway and releases him: the door remembers its own so as not to
## release a second one while the first is alive.
##
## Called only when the leaf is already open: before that the door has no opening
## to walk out of.
func _release_agent(post: AgentPost) -> Enemy:
	var mat := post.door.mat_position()
	var agent := ENEMY_SCENE.instantiate() as Enemy
	# Rules are handed over before the tree: this way the agent enters it already configured, and
	# does not have to set up default values for itself.
	agent.apply_rules(rules)
	AgentWardrobe.dress(agent, identity)
	# Seeded before [method Enemy.setup]: walking out of the door already pulls from the generator
	# the length of the first move, and unseeded it would make it random — the bot run
	# would stop repeating from the very first agent.
	agent.seed_decisions(_spawn.rng.randi())
	add_child(agent)
	agent.global_position = WorldSpace.to_scene(mat)
	agent.setup(otto, signf(otto.global_position.x - mat.x))
	# Otto's shadow and the wall are handed over right away, without waiting for a frame: otherwise
	# the agent would take his first step seeing Otto where he cannot be seen.
	var here := _floor_of(otto)
	_shroud_agent(
		agent, post.floor_index, mat.x, here, _lighting.is_dark_at(here, otto.global_position.x)
	)
	agent.set_threat(_difficulty(), rules.skill, GameState.instance().alarm.raised)
	agent.set_late(post.slot >= 2)
	# The agent's step — on the building floor, like Otto's on floors.
	agent.step_sound = PlaceSound.step_at(false, identity)
	if _alert_left > 0.0:
		agent.alert_for(_alert_left)
	agent.died.connect(_on_agent_died.bind(post))
	agent.left_building.connect(_on_agent_left.bind(post))
	RunLog.write("agent_spawn", {"at": mat, "floor": post.floor_index, "otto": RunLog.at(otto)})
	return agent


## Siren: agents get angry, cabs start responding with a delay. [param ring] —
## the alarm went off just now, and the bell rings; false — the building was set up with it.
func _on_alarm_raised(ring: bool = true) -> void:
	# The siren has worked since M5b, but it had nothing to sound with: now instead of the building
	# theme the alarm motif plays, and only a new building removes it.
	music(true)
	# The siren itself — at the moment of the alarm, over the track change (ADR-0052, decision 7).
	if ring:
		Sounds.play(Sounds.ALARM)
	for car in _cars:
		car.set_response_delay(ALARM_CAR_DELAY)
	for agent in agents():
		agent.set_alarmed(true)


func _on_agent_died(agent: Enemy, post: AgentPost) -> void:
	RunLog.write("agent_death", {"at": RunLog.at(agent), "floor": post.floor_index})
	# The slot is freed with a difficulty-based replacement (@3866): the next one is released by
	# the draw, not by this same door.
	_free_slot(post)


## The agent reached a door and went into it (@55B0): the body is removed, the slot is free.
func _on_agent_left(agent: Enemy, post: AgentPost) -> void:
	agent.queue_free()
	if post.agent == agent:
		post.agent = null
	_free_slot(post)


func _on_otto_died() -> void:
	# The cause is on Otto: a cab crushed him or a bullet, and whose (run log).
	RunLog.write(
		"otto_death",
		{
			"at": RunLog.at(otto),
			"floor": _floor_of(otto),
			"cause": otto.get_meta(&"death_cause", "fall"),
			"shooter": otto.get_meta(&"shooter", []),
			"riding": otto.is_riding(),
			"agents":
			(
				agents()
				. filter(func(a: Enemy) -> bool: return not a.is_dead())
				. map(func(a: Enemy) -> Array: return RunLog.at(a))
			),
		}
	)
	# A life is taken right away so the counter does not lie while the body lies there.
	if not GameState.instance().lose_life():
		return
	# Like an agent replacement, returning to play does not run during pause — and it is counted
	# in physics steps, not frames: otherwise on a fast machine Otto returns
	# earlier than on a slow one, and the bot run stops repeating.
	var timer := get_tree().create_timer(OTTO_RESPAWN_DELAY, false, true)
	timer.timeout.connect(_respawn_otto)


## Returns Otto to play by the ROM rule ([RespawnSpot]): a floor no lower than the fifth
## ROM floor, the spot — at a red door or at the floor's point. Living agents leave,
## and the slots release them again with delays (@2F44-2F6F): so the return does not
## meet the same gun that killed. Corpses stay, as before M24a, until the end of the
## building. Invulnerability after the return is ours, the ROM does not have it
## (ADR-0053, decision 2).
func _respawn_otto() -> void:
	# The timer hangs on the tree, not on the level, and outlives it: a dead Otto
	# whose level was removed — by exiting to the menu or at the end of a test — would return
	# to a building that no longer exists.
	if not is_inside_tree():
		return
	_clear_agents()
	var index := RespawnSpot.floor_for(rules, _floor_of(otto))
	var x := RespawnSpot.choose(_plan, rules, index, RespawnSpot.red_door_x(_doors, rules, index))
	otto.global_position = WorldSpace.to_scene(Vector2(x, rules.floor_surface(index)))
	otto.revive()
	Sounds.play(Sounds.RESPAWN)
	RunLog.write("respawn", {"at": RunLog.at(otto), "floor": index})


## Removes living agents and those whose door is already opening, and puts the slots on
## ROM delays ([method AgentSpawn.after_death]).
func _clear_agents() -> void:
	for agent in agents():
		if not agent.is_dead():
			agent.queue_free()
	for post: AgentPost in _posts:
		post.agent = null
		post.opening = false
		post.slot = -1
		post.door.dismiss_agent()
	_spawn.after_death()
