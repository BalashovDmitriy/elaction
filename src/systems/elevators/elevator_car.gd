class_name ElevatorCar
extends AnimatableBody3D

## Elevator cab.
##
## The movement decision is made by [ElevatorMotion]; the node only turns it into a
## coordinate and hands out events. The cab obeys Otto while he is inside, and moves
## on its own when empty (ADR-0004, points 1 and 4).
##
## Whoever stands on the roof is carried by physics: [member AnimatableBody3D.sync_to_physics].
## The cab cannot be controlled from the roof — same as in the original.
##
## [ElevatorMotion] works in rules coordinates, where down means growing Y. The node
## converts this to the scene in one place, [method _place], and knows nothing else about the Y
## flip: the movement rule was left untouched by the move (ADR-0021, decision 2).

## The cab is level with a floor and one can step out of it.
signal floor_reached(index: int)

## Cab start and stop: how far it is heard, m, and how much quieter than the hum, dB.
const CLUNK_REACH: float = 12.0
const CLUNK_DB: float = -4.0

## How far the cab hum is heard, m. Farther along the floor it no longer gets in the way.
const HUM_REACH: float = 10.8

## How much an arrow dims when there is no travel in that direction.
const ARROW_DIM: float = 0.18

## Indicators on the cab roof: size, spread from the middle as a fraction of cab
## width and how far their middle is above the roof, m. Two red indicator lights —
## cab readability on a darkened floor (ADR-0023, decision 6).
const INDICATOR_SIZE := Vector3(0.1, 0.06, 0.1)
const INDICATOR_SPREAD: float = 0.35
const INDICATOR_RISE: float = 0.03

## Arrows in the cab: spread from the middle as a fraction of cab width.
const ARROW_SPREAD: float = 0.275

## How much narrower the entry opening and the crush zone are than the cab itself, m: at the edges
## 6 cm remain on each side, so that someone standing on the floor right next to the shaft counts
## neither as a passenger nor as crushed.
const INNER_INSET: float = 0.12

## Thickness of the cab floor and roof, m. Set by the scene; it is needed here because
## the cab takes its height from the building rules, not from the scene.
const SLAB_THICKNESS: float = 0.18

## How far the feet may be from the cab floor for Otto to count as standing
## on it, m: for the engine's floor snap and for one frame of cab travel, and only for those.
const BOARD_REACH: float = 0.08

## Default floor clearance and shaft width, m — the same as in the standard
## rules. The cab is built from them until the level says otherwise — so a single
## cab spawned by a test without a building is still fully assembled.
const DEFAULT_CLEAR_HEIGHT: float = Proportions.CLEARANCE
const DEFAULT_WIDTH: float = Proportions.SHAFT

## How deep the arrows are recessed from the roof, m.
const ARROW_DROP: float = 0.3

## Tie rods between the decks of a pair: section, spread from the middle as a fraction of cab width
## and depth, m.
##
## The decks are tied together and move together, but stand a floor apart — between the lower one's
## roof and the upper one's bottom there is a floor of emptiness. Without rods these are two
## separate cabs that for some reason move together (ADR-0025, decision 1).
const TIE_WIDTH: float = 0.1
const TIE_SPREAD: float = 0.45
const TIE_DEPTH: float = 0.6

## Cab travel per ROM: 2 px per logic tick, a floor in 1.6 s (ADR-0027, decision 4).
## The band above the cab floor in which body parts lie on the threshold, m: below —
## on the slab, above — on the thickness of a lying body.
const TEAR_REACH: float = 0.25
const TEAR_HEIGHT: float = 0.45

@export var speed: float = Arcade.speed(Arcade.CAR_PX)
@export var floor_pause: float = 1.5

var _motion := ElevatorMotion.new()
var _occupant: PhysicsBody3D = null
var _command: float = 0.0
var _aligned_floor: int = -1

## The lead deck of a pair. Empty — the cab is regular and moves on its own.
var _leader: ElevatorCar = null
## The lower deck of a pair, if there is one. The lead holds it.
var _deck: ElevatorCar = null
## How far the lower deck is below the lead, m.
var _deck_drop: float = 0.0

var _hum: AudioStreamPlayer3D = null
## Whether the cab moved in the previous step: on change — the start and stop sound.
var _was_moving: bool = false
## Indicator lights on the roof: [method fit_to_story] moves them when the height changes.
var _indicators: Array[MeshInstance3D] = []
## Cab width, m. Set by [method fit_to_story] from the building rules.
var _width: float = DEFAULT_WIDTH
## Walls, light fixture, control panel, ropes and counterweight — looks only (ADR-0031).
var _detail: CarDetail = null
## Bodies the bottom has started to cut: a fully cut one has no shape, and the crush
## zone no longer sees it, while the cut continues down to the floor.
var _cutting: Array[Corpse] = []
@onready var _interior: Area3D = $Interior
@onready var _crush_zone: Area3D = $CrushZone
@onready var _up_arrow: MeshInstance3D = $UpArrow
@onready var _down_arrow: MeshInstance3D = $DownArrow


func _ready() -> void:
	_interior.body_exited.connect(_on_body_exited)
	_hum = Sounds.source(self, Sounds.ELEVATOR_HUM, HUM_REACH)
	# The cab is what you stand on and ride in: it must read even on a
	# darkened floor (ADR-0019, decision 5). Two indicators on the roof
	# take care of this, and the cab itself is metal, like the shaft.
	var slab := GreyboxLook.metal(GreyboxLook.CAR)
	($FloorVisual as MeshInstance3D).material_override = slab
	($RoofVisual as MeshInstance3D).material_override = slab
	var arrow := GreyboxLook.marker(GreyboxLook.DOOR)
	_up_arrow.material_override = arrow
	_down_arrow.material_override = arrow

	for side: float in [-1.0, 1.0]:
		var indicator := GreyboxLook.box(INDICATOR_SIZE, GreyboxLook.light(GreyboxLook.INDICATOR))
		add_child(indicator)
		_indicators.append(indicator)
	_detail = CarDetail.new()
	_detail.name = "Detail"
	add_child(_detail)
	fit_to_story(DEFAULT_CLEAR_HEIGHT, DEFAULT_WIDTH)


## Dresses the cab by building kind (ADR-0057, decision 6). Call before
## [method fit_to_story]: that one assembles the dressing.
func dress_as(kind: BuildingIdentity.Kind) -> void:
	if _detail != null:
		_detail.dress_as(kind)


## Stretches the cab to the floor clearance and shaft width: floor on the storey floor, roof
## at the slab underside, sides at the shaft walls.
##
## **The cab fills the clearance entirely — as in the original.** Checked against a frame
## (256×224): floor pitch 48 px, slab 7, clearance 41, cab 40. Ours was
## 1.8 m with a 3.0 clearance — exactly half as tall, and this discrepancy was never
## decided anywhere: the size came from the M2 2D version and survived the M13 proportion
## recalculation (ADR-0025, decision 10).
##
## Full height does not hinder riding on the roof: the roof stands at the slab underside, and the
## slab is cut through by the shaft there — whoever stands on the roof stands in the opening, and
## the body goes into the floor above. The original works the same way.
##
## Sizes are set by the level from the building rules, not by the scene: [member
## BuildingRules.floor_height], [member BuildingRules.slab_height] and [member
## BuildingRules.shaft_width] are exported fields, and tests build buildings with other
## proportions. Width arrived here in M18c: the shaft grew
## to 1.8 m, while the cab from the scene would have stayed at 1.2 and rattled around in it
## (ADR-0026, decision 3).
func fit_to_story(clear_height: float, car_width: float) -> void:
	_width = car_width
	if _detail != null:
		_detail.build(car_width, clear_height)
	var roof_middle := clear_height - SLAB_THICKNESS * 0.5
	($RoofShape as CollisionShape3D).position.y = roof_middle
	($RoofVisual as MeshInstance3D).position.y = roof_middle
	for slab: String in ["FloorShape", "RoofShape"]:
		_resize(get_node(slab) as CollisionShape3D, car_width)
	for slab: String in ["FloorVisual", "RoofVisual"]:
		var visual := get_node(slab) as MeshInstance3D
		var mesh := (visual.mesh as BoxMesh).duplicate() as BoxMesh
		mesh.size.x = car_width
		visual.mesh = mesh
	_resize($CrushZone/CrushShape as CollisionShape3D, car_width - INNER_INSET)

	var room := clear_height - SLAB_THICKNESS
	var inside := $Interior/InteriorShape as CollisionShape3D
	_resize(inside, car_width - INNER_INSET, room)
	inside.position.y = room * 0.5

	_up_arrow.position = Vector3(-car_width * ARROW_SPREAD, clear_height - ARROW_DROP, 0.3)
	_down_arrow.position = Vector3(car_width * ARROW_SPREAD, clear_height - ARROW_DROP, 0.3)
	for index in _indicators.size():
		var side := -1.0 if index == 0 else 1.0
		_indicators[index].position = Vector3(
			side * car_width * INDICATOR_SPREAD,
			clear_height + INDICATOR_RISE + INDICATOR_SIZE.y * 0.5,
			0.3
		)


## Cab width, m.
func width() -> float:
	return _width


## Height of the bottom underside in the scene, m: by it the cab cuts those below it.
func bottom() -> float:
	return global_position.y + _under_the_floor()


## Changes the shape's size by width and, if given, by height.
##
## Each cab has its own shape: the scene subresource is shared by all its copies, and
## resizing it in place would stretch all the other cabs of the building as well.
static func _resize(shape: CollisionShape3D, box_width: float, box_height: float = -1.0) -> void:
	var box := (shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size.x = box_width
	if box_height > 0.0:
		box.size.y = box_height
	shape.shape = box


func _physics_process(delta: float) -> void:
	_admit_riders()
	# The freight cab grille is the look of the ROM step-out window (ADR-0057, decision 6);
	# only the cab with Otto clangs, as with start and stop.
	_detail.tend_gate(can_step_out(), delta, _carries_otto())
	if _leader != null:
		_ride_along()
		return

	# A passenger of either deck drives the whole pair: the decks are tied, and the lower one
	# has no travel of its own.
	var occupied := has_rider() or (_deck != null and _deck.has_rider())
	_place(_motion.update(delta, _command if occupied else 0.0, occupied))
	_detail.follow(global_position.y, global_position.x)

	var reached := _motion.aligned_floor()
	if reached != _aligned_floor:
		_aligned_floor = reached
		if reached >= 0:
			# There is no floor bell since M21: the user's decision — all cabs rang,
			# empty ones too, on every floor passed, as if someone rang the doorbell.
			floor_reached.emit(reached)

	# The hum plays while the cab moves. The source is positional: there are five shafts in a
	# building, and only the one you stand next to should be heard.
	var moving := not is_zero_approx(_motion.velocity)
	Sounds.keep_playing(_hum, moving)
	if moving != _was_moving:
		_was_moving = moving
		# Starts and stops with a clang, only the cab with Otto: empty cabs ringing on every
		# floor were already rejected by the user in M21 (ADR-0052, decision 7).
		if _carries_otto():
			var clunk := Sounds.ELEVATOR_START if moving else Sounds.ELEVATOR_STOP
			Sounds.play_at(self, clunk, global_position, CLUNK_REACH, CLUNK_DB)

	_show_arrows()
	_crush_those_underneath(_motion.velocity)
	_tear_across_the_walls(_motion.velocity)


## Sets the shaft: coordinates of the stop floors in the rules and the floor the
## cab starts from.
func setup(stops: PackedFloat32Array, start_floor: int = 0) -> void:
	_motion.speed = speed
	_motion.floor_pause = floor_pause
	_motion.setup(stops, start_floor)
	_place(_motion.position)
	_aligned_floor = _motion.aligned_floor()
	# Ropes and counterweight: stops are rules heights, the scene's y axis points up.
	if _detail != null and not stops.is_empty():
		var low := WorldSpace.height_to_scene(Array(stops).max())
		var high := WorldSpace.height_to_scene(Array(stops).min())
		var room := ($RoofVisual as MeshInstance3D).position.y + SLAB_THICKNESS * 0.5
		_detail.hang_cables(low, high, high + room)
		_detail.follow(global_position.y, global_position.x)


## Top of the shaft [param top] in the rules plane: how far the ropes and counterweight go.
##
## Without this the top is the ceiling of the highest stop. A shaft to the roof has sky above the
## highest stop, and the ropes would go three metres above the deck — higher than the
## machine room. The level gives it the top: [method BuildingShafts.top_of].
func set_shaft_top(top: float) -> void:
	if _detail == null:
		return
	_detail.set_top(WorldSpace.height_to_scene(top))
	_detail.follow(global_position.y, global_position.x)


## Makes the cab the lower deck of a pair: it no longer has travel of its own, it keeps
## [param drop] metres below the lead and passes it everything asked of it.
##
## As its own node, not a second body inside the lead: people enter the cab, stand on its
## roof and die under its bottom — the deck needs its own entry [Area3D], its own
## crush zone and its own roof. A copy of the scene gives all of this at once.
func serve_as_deck(leader: ElevatorCar, drop: float) -> void:
	_leader = leader
	_deck_drop = drop
	leader.take_a_deck(self, drop)
	_ride_along()
	# The deck keeps its own sound sources, but they are silent: the lead hums and rings,
	# and a pair in one shaft would sound twice as loud as a single cab.


## Whether anyone is in this cab.
func has_rider() -> bool:
	return _occupant != null


## Whether this is a deck of a two-storey pair. A deck has no travel of its own: it keeps
## to the lead and passes all movement questions to it.
func is_deck() -> bool:
	return _leader != null


## Whether the cab can still go in this direction. For a pair's deck the lead decides.
func can_go(towards: float) -> bool:
	return _leader.can_go(towards) if _leader != null else _motion.can_go(towards)


## Locks or unlocks the shaft's bottom stop ([member ElevatorMotion.bottom_locked]).
##
## A pair's deck has no travel of its own — the lead locks: for a two-storey pair its
## bottom stop is exactly where the lower deck stands at the bottom of the shaft.
func lock_bottom_stop(locked: bool) -> void:
	if _leader != null:
		_leader.lock_bottom_stop(locked)
		return
	_motion.bottom_locked = locked


## Whether the shaft's bottom stop is locked.
func is_bottom_locked() -> bool:
	return _leader.is_bottom_locked() if _leader != null else _motion.bottom_locked


## How far down the pair goes, in the rules plane: the lower deck's floor at the lead's
## bottom stop. For a single cab — simply its bottom stop; NAN —
## no stops.
func bottom_reach() -> float:
	if _leader != null:
		return _leader.bottom_reach()
	if _motion.floors.is_empty():
		return NAN
	var lowest := _motion.floors[_motion.floors.size() - 1]
	return lowest + (_deck._deck_drop if _deck != null else 0.0)


## Response delay to a command, s. During the alarm the cab responds worse.
##
## A pair's deck has no travel of its own, and the lead takes the delay: the level's
## cab list holds both, because one can board either.
func set_response_delay(value: float) -> void:
	if _leader != null:
		_leader.set_response_delay(value)
		return
	_motion.response_delay = maxf(value, 0.0)
	# So that the new delay also catches the ride already in progress.
	_motion.forget_command()


## Passenger command for this frame: -1 up, +1 down, 0 released.
##
## The cab accepts it, but executes it only from whoever is inside. A pair's deck
## passes it to the lead: the decks are tied, and the lower one has no will of its own.
func drive(command: float) -> void:
	if _leader != null:
		_leader.drive(command)
		return
	_command = command


## Whether the cab floor is level with the storey floor.
##
## Nothing to ask a pair's deck: the travel is shared, and the floor pitch is the same
## over the whole building height — so either both decks are level or neither.
func is_aligned() -> bool:
	return _leader.is_aligned() if _leader != null else _motion.is_aligned()


## Whether one can step from the cab onto the floor now — [method ElevatorMotion.can_step_out].
## For a pair's deck the lead answers: the floor pitch is the same over the whole height, and the
## deck is as far above the floor below it as the lead is.
func can_step_out() -> bool:
	return _leader.can_step_out() if _leader != null else _motion.can_step_out()


## Takes the lower deck under itself and ties it with rods.
##
## Calls [method serve_as_deck], and only it does: the pair is set from one side,
## otherwise half of the link would one day stay unset.
func take_a_deck(deck: ElevatorCar, drop: float) -> void:
	_deck = deck
	# The upper deck's crush zone stays: there is a floor of emptiness between the decks,
	# one can stand on the lower one's roof, and a descending pair will press whoever stands there.
	var tie := GreyboxLook.metal(GreyboxLook.CAR)
	var length := drop - _body_height()
	if length <= 0.0:
		return
	for side: float in [-1.0, 1.0]:
		var strut := GreyboxLook.box(Vector3(TIE_WIDTH, length, TIE_DEPTH), tie)
		strut.position = Vector3(side * _width * TIE_SPREAD, _under_the_floor() - length * 0.5, 0.0)
		add_child(strut)


## Cab height from the bottom to the top of the roof, m.
func _body_height() -> float:
	return _roof_top() - _under_the_floor()


## Top of the roof in its own coordinates, m.
func _roof_top() -> float:
	return ($RoofVisual as MeshInstance3D).position.y + SLAB_THICKNESS * 0.5


## Bottom underside in its own coordinates, m.
func _under_the_floor() -> float:
	return ($FloorVisual as MeshInstance3D).position.y - SLAB_THICKNESS * 0.5


## Keeps the lower deck under the lead.
##
## The lead stands higher in the tree and gets to its place first, so
## the deck takes its current height, not the previous one: they must not drift apart for a
## frame — "both level or neither" rests on this.
func _ride_along() -> void:
	position.y = _leader.position.y - _deck_drop
	_show_arrows()
	_crush_those_underneath(_leader.speed_now())
	_tear_across_the_walls(_leader.speed_now())


## Stay at the floor for at least [param seconds] more — see [method ElevatorMotion.hold].
## A pair's deck has no travel of its own — the lead stays, and the deck with it: nobody reads
## the deck's own counter, and a held deck would drive off with the pair.
func hold(seconds: float) -> void:
	if _leader != null:
		_leader.hold(seconds)
		return
	_motion.hold(seconds)


## Cab speed over the last frame: the lower deck asks for it to decide
## whether it crushes. A pair's deck has no travel of its own — the lead answers for it, otherwise
## a deck going down would report zero and crush no one.
func speed_now() -> float:
	return _leader.speed_now() if _leader != null else _motion.velocity


## Arrows: a dimmed arrow explains why the cab goes no farther.
func _show_arrows() -> void:
	_up_arrow.transparency = 0.0 if can_go(Intent.UP) else 1.0 - ARROW_DIM
	_down_arrow.transparency = 0.0 if can_go(Intent.DOWN) else 1.0 - ARROW_DIM


## Puts the cab at the height computed by the rules.
func _place(height_in_plane: float) -> void:
	position.y = WorldSpace.height_to_scene(height_in_plane)


## Crushes those who ended up under the bottom of a cab going down, and cuts with the bottom
## the bodies under it (ADR-0043, decisions 7–9).
func _crush_those_underneath(speed: float) -> void:
	if speed <= 0.0:
		return
	for corpse: Corpse in _cutting.duplicate():
		corpse.cut_under(self)
		if corpse.cut == null or corpse.cut.done:
			_cutting.erase(corpse)
	for body: Node3D in _crush_zone.get_overlapping_bodies():
		var part := body as PhysicalBone3D
		if part != null:
			# A part of a fallen body under the bottom, not on the cab floor: one lying
			# on the floor has its middle above the bottom by a slab or more.
			if Ragdoll.center_of(part).y < bottom():
				_start_cutting(Corpse.of(part))
			continue
		var agent := body as Enemy
		if agent != null:
			# The cab crushes agents too, as in the ROM (ADR-0027, decision 6). The zone
			# reaches above the bottom on the cab floor, and a passenger's feet get into it:
			# a passenger is whoever stands on the cab floor, and a victim is whoever is under
			# the bottom. Feet height tells them apart.
			var riding := to_local(agent.global_position).y > _under_the_floor()
			if agent.is_dead() or not _pinned(speed, agent, agent.is_on_floor(), riding):
				continue
			agent.kill(true)
			Sounds.play_at(get_parent(), Sounds.CRUSH, agent.global_position, CLUNK_REACH)
			# 300 points — only if the crushing cab is the one Otto rides (@4A97
			# ROM, ADR-0044, decision 7). The darkness bonus is the same as for
			# a bullet and a lamp (ADR-0010).
			if _carries_otto():
				var points := GameState.kill_score(GameState.CRUSH_SCORE, agent.is_in_the_dark())
				GameState.instance().add_score(points, agent.global_position + GameState.OVER_HEAD)
			continue
		var victim := body as Otto
		if victim == null:
			continue
		if _pinned(speed, victim, victim.is_grounded(), victim == _occupant):
			victim.kill(true)


## Whether the bottom pinned [param body]: it is entirely under the cab and has nowhere
## to go. One clipped by the edge is pushed to the shaft edge and released alive
## (ADR-0044, decision 6).
func _pinned(speed: float, body: Node3D, grounded: bool, passenger: bool) -> bool:
	if not ShaftHazards.crushes(speed, grounded, passenger):
		return false
	var x := global_position.x
	var body_x := body.global_position.x
	if ShaftHazards.is_fully_under(body_x, Proportions.BODY_WIDTH, x, _width):
		return true
	body.global_position.x = ShaftHazards.push_out(body_x, Proportions.BODY_WIDTH, x, _width)
	return false


## Whether Otto rides in this cab — or in the pair it is tied to.
func _carries_otto() -> bool:
	if _leader != null:
		return _leader._carries_otto()
	return has_rider() or (_deck != null and _deck.has_rider())


## Starts cutting the body [param corpse] with the bottom; from then on the list drives the cut:
## the cut part disappears, and the crush zone no longer sees it.
func _start_cutting(corpse: Corpse) -> void:
	if corpse == null or corpse.cut != null or corpse.gone:
		return
	corpse.cut_under(self)
	if corpse.cut != null and not corpse.cut.done:
		_cutting.append(corpse)


## Tears with the wall bodies lying across the threshold of a moving cab (ADR-0043,
## decision 11): parts inside ride away with the cab, parts outside stay. Without
## blood it does not tear — the joints pull the body.
func _tear_across_the_walls(speed: float) -> void:
	if not Blood.enabled or is_zero_approx(speed):
		return
	var floor_top := bottom() + SLAB_THICKNESS
	var low := floor_top - TEAR_REACH
	var high := floor_top + TEAR_HEIGHT
	var x := global_position.x
	for node: Node in get_tree().get_nodes_in_group(Corpse.GROUP):
		var corpse := Corpse.of(node)
		if corpse == null or corpse.gone or corpse.torn or corpse.cut != null:
			continue
		# There are many corpses until the end of the building, and every cab in motion: first
		# a cheap estimate by one part, the bounds — only for close ones.
		if not corpse.near(x, _width):
			continue
		var reach := corpse.span()
		if reach.y < x - _width or reach.x > x + _width:
			continue
		var inside := corpse.across(self, low, high, global_position.y + _roof_top())
		if not inside.is_empty():
			corpse.tear(self, inside)


## Boards Otto if he is in the opening and the cab can be entered (ADR-0037, decision 1).
##
## Overlap alone is not enough: the cab opening is as tall as the clearance, and the body enters it
## long before the cab has arrived. That used to be enough — and Otto
## became a passenger of a cab standing a couple of metres below the floor. An occupied
## cab without a command stands still, and one cannot step out of it unless level: both
## froze forever. On top of that, occupancy also saved whoever stood under the bottom
## from being crushed.
##
## So a passenger is whoever entered a cab standing level or already stands on
## its floor. Overlap is checked every frame while the cab is empty: entering the zone
## happens once, but one can enter later too — when the cab arrives.
func _admit_riders() -> void:
	if _occupant != null:
		return
	for body: Node3D in _interior.get_overlapping_bodies():
		var rider := body as Otto
		if rider == null or rider.is_dead() or not _can_board(rider):
			continue
		_occupant = rider
		rider.board(self)
		return


## Whether Otto can enter the cab right now: it is level with the floor or he already
## stands on its floor.
##
## Standing on the floor means feet near the top of the bottom within [constant
## BOARD_REACH]; whoever is in the opening above a lowered cab is still falling onto its
## floor and will board once he lands.
func _can_board(rider: Otto) -> bool:
	if is_aligned():
		return true
	return rider.is_grounded() and absf(to_local(rider.global_position).y) <= BOARD_REACH


func _on_body_exited(body: Node3D) -> void:
	var rider := body as Otto
	if rider == null or rider != _occupant:
		return
	_occupant = null
	# Through [method drive], not a field: for a pair's deck the lead executes the command,
	# and a "down" left over on it would start the pair the frame the next one
	# enters — before he even gets to press anything.
	drive(0.0)
	rider.leave(self)
