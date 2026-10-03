class_name DemoRun
extends Node

## One demo (ADR-0041): a building, a bot playing Otto and a countdown to the end.
##
## Puts Otto at the [DemoPlan] start point, drives the bot at the same pace as in tests —
## a decision every two physics steps (the M13 rule, `docs/testing.md`) — and emits
## [signal finished] when time is up or Otto has died. It lives under the building: if the
## building is thrown away, the demo goes with it.

## The demo ended on its own: time is up or Otto died.
signal finished

## How long the cabs at the start floor stand after the bot has started moving, s: the way
## to the shaft with margin. From the roof the demo goes through
## the helicopter, and during the intro the cabs drove down on schedule — the bot then waited
## for them at the shaft for twenty seconds, half the demo standing still.
const CAR_WAIT: float = 8.0

var _level: GreyboxLevel = null
var _bot: OttoBot = null
var _point: int = DemoPlan.Point.ROOF
var _time: float = 0.0
## The start floor: the cabs' stay there is extended until Otto starts moving.
var _start_level: int = BuildingRules.ROOF
var _frame: int = 0
var _done: bool = false


## A demo in building [param level] from point [param point]. The node goes under the building.
static func start(level: GreyboxLevel, point: int) -> DemoRun:
	var run := DemoRun.new()
	run.name = "Demo"
	run._level = level
	run._point = point
	level.add_child(run)
	return run


func _ready() -> void:
	_level.otto.died.connect(_finish)
	if _point != DemoPlan.Point.ROOF:
		_place()


## Stops the bot: releases everything it holds. The building lives on —
## stopping it is the business of whoever ends the demo.
func stop() -> void:
	_done = true
	if _bot != null:
		_bot.release()


func _physics_process(delta: float) -> void:
	if _done:
		return
	# Cabs settle at their stops already in the tree, not by the demo's [method Node._ready] —
	# so the stay at the start floor is extended every step until the bot starts moving.
	if _bot == null:
		_hold_cars_at(_start_level)
	_time += delta
	if _time >= DemoPlan.LENGTH:
		_finish()
		return
	# The helicopter intro is watched, not skipped: the bot presses fire and jump,
	# and those are exactly what skip the intro.
	if _level.is_in_the_intro() or (_bot == null and not _level.otto.is_grounded()):
		return
	if _bot == null:
		_bot = OttoBot.new(_level)
	_frame += 1
	if _frame % 2 == 0:
		_bot.step()


## Middle and bottom: Otto is at a shaft whose cab starts from this floor, near the ROM
## floor. Cabs start from the top stop of their shaft: Otto in the middle of a random
## floor waited for a cab half the demo standing still (M24E frames). From below the basement is
## open: documents from the floors above are counted, and the bot goes to the exit, not up for them.
##
## The relocation itself removes the intro, not [method GreyboxLevel.skip_the_intro]:
## the intro releases a relocated Otto and snaps the frame onto him. The skip
## left the intro frame on the roof, and the camera rode to Otto through the whole building
## (code review M24e).
func _place() -> void:
	var rules := _level.rules
	var wanted := DemoPlan.floor_of(_point, rules.floors)
	var index := wanted
	var near_x := NAN
	var best := DemoPlan.SHAFT_SEARCH + 1
	for shaft: BuildingPlan.ShaftSpot in _level.plan().shafts:
		var gap := absi(shaft.top - wanted)
		if shaft.top >= 0 and gap < best:
			best = gap
			index = shaft.top
			near_x = shaft.x
	_start_level = index
	var spots := _level.plan().safe_spots(rules, index)
	if spots.is_empty():
		_level.skip_the_intro()
		return
	var x: float = spots[spots.size() / 2]
	if not is_nan(near_x):
		# A spot next to the shaft: where the bot waits for the cab.
		var closest := INF
		for spot: float in spots:
			var gap := absf(absf(spot - near_x) - OttoBot.WAIT_ASIDE)
			if gap < closest:
				closest = gap
				x = spot
	_level.otto.global_position = WorldSpace.to_scene(Vector2(x, rules.floor_surface(index)))
	if _point == DemoPlan.Point.BOTTOM:
		var game := GameState.instance()
		for door: Door in _level.doors():
			if door.is_pending() and rules.floor_index_near(door.mat_position().y) < index:
				door.has_document = false
				game.collect_document(false)


## The cabs at floor [param level] stand while the intro runs and the bot walks to the shaft.
## The cab is alive meanwhile: it sees whoever boards and carries him.
func _hold_cars_at(level: int) -> void:
	var surface := _level.rules.floor_surface(level)
	for child: Node in _level.get_children():
		var car := child as ElevatorCar
		if car != null and absf(WorldSpace.to_plane(car.global_position).y - surface) < 0.5:
			car.hold(CAR_WAIT)


func _finish() -> void:
	if _done:
		return
	stop()
	finished.emit()
