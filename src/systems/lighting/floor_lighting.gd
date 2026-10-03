class_name FloorLighting
extends RefCounted

## Building floor light — by lamp zones.
##
## A floor has several lamps, and each lights its own zone: the strip of the floor it
## is closer to than the others, with boundaries halfway between neighbours. A shot-down lamp
## darkens its zone, and the zone does not light up again (ADR-0023, decision 2).
##
## This is the second step away from the original: in 1983 the whole building went dark for
## a few seconds, ADR-0007 made darkness per floor and permanent, here it became per zone —
## otherwise with several lamps per floor any shot would be a switch for the whole floor.
##
## The class only remembers where the lamps are and which are out. The level sets up the
## picture and agent behaviour from it, so it is checked without a scene.

## Where a lamp keeps the relight of the frame it got a fill shadow slot in
## ([method show_in_frame]).
const RELIGHT := &"floor_lighting_relight"

## Lamps by floor: floor → x of the lamps in hanging order.
##
## The order is deliberately not touched after adding: a lamp's index in this list is
## the key of its darkness in [member _dark], and re-sorting the list would move
## darkness from one zone to another. Which one is further left is decided by
## [method _nearest] by x, not by the place in the list.
var _lamps: Dictionary = {}
## Lamps that are out: floor → {lamp index in the floor's list: true}.
var _dark: Dictionary = {}
## Dark floors of the map: they have no lamps, and they are dark from the start of the
## building (ADR-0028, decision 4). Floor → true.
var _unlit: Dictionary = {}
## Whether it is night: not at night a shot-down lamp does not darken its zone — daylight
## lights it (ADR-0051, decision 5).
var _night: bool = true


## Hangs a lamp on a floor. Called by the level while laying out the building: the zone is
## computed from what hangs, not from what was intended.
func hang(floor_index: int, x: float) -> void:
	if not _lamps.has(floor_index):
		_lamps[floor_index] = PackedFloat64Array()
	var xs: PackedFloat64Array = _lamps[floor_index]
	xs.append(x)
	_lamps[floor_index] = xs


## Declares a floor entirely dark: it has no lamps by the map, not for lack of room.
##
## A floor without lamps is lit by default — the city lights it, like the roof. A dark floor
## declares itself: the level calls this while laying out the building, as with [method hang].
func mark_unlit(floor_index: int) -> void:
	_unlit[floor_index] = true


## Takes the time of day and the map's dark floors from the building rules.
func follow(rules: BuildingRules) -> void:
	_night = rules.is_night()
	for index in rules.floors:
		if rules.is_unlit(index):
			mark_unlit(index)


## Darkens the zone of the lamp closest to [param x]. A lamp falls where it hung,
## so its place is its zone. Returns false if the zone was already dark
## or the floor has no lamps at all, and not at night — always: daylight lights the zone.
func darken(floor_index: int, x: float) -> bool:
	var index := _nearest(floor_index, x)
	if index < 0 or not _night:
		return false
	if not _dark.has(floor_index):
		_dark[floor_index] = {}
	var dark: Dictionary = _dark[floor_index]
	if dark.has(index):
		return false
	dark[index] = true
	return true


## Whether it is dark at a floor point: whether the zone of the lamp closest to it is dark.
## A dark floor of the map is dark everywhere; any other floor without lamps — the roof —
## never goes dark: the city lights it.
func is_dark_at(floor_index: int, x: float) -> bool:
	if _unlit.has(floor_index):
		return true
	var index := _nearest(floor_index, x)
	if index < 0 or not _dark.has(floor_index):
		return false
	return (_dark[floor_index] as Dictionary).has(index)


## Whether the whole floor is dark: all its zones, and it has at least one. A dark floor
## of the map is always dark.
func is_dark(floor_index: int) -> bool:
	if _unlit.has(floor_index):
		return true
	if not _lamps.has(floor_index) or not _dark.has(floor_index):
		return false
	var xs: PackedFloat64Array = _lamps[floor_index]
	return (_dark[floor_index] as Dictionary).size() >= xs.size()


## Where the lamp whose zone covers the point hangs. NAN if the floor has no lamps.
func zone_of(floor_index: int, x: float) -> float:
	var index := _nearest(floor_index, x)
	if index < 0:
		return NAN
	return (_lamps[floor_index] as PackedFloat64Array)[index]


## Index of the floor lamp closest to the point, or -1. At equal distance — the left one:
## a zone boundary belongs to the lamp closer to the start of the floor. Compared by
## x, not by place in the list: the hanging order must not decide the answer.
func _nearest(floor_index: int, x: float) -> int:
	if not _lamps.has(floor_index):
		return -1
	var xs: PackedFloat64Array = _lamps[floor_index]
	var best := -1
	var best_gap := INF
	for index in xs.size():
		var gap := absf(xs[index] - x)
		var tied := best >= 0 and is_equal_approx(gap, best_gap)
		if gap < best_gap or (tied and xs[index] < xs[best]):
			best_gap = gap
			best = index
	return best


## [param count] hanging lamps from [param lamps] closest to frame point
## [param centre] in the rules plane: they get the fill shadow (ADR-0044, decision 11).
##
## They are picked only from those that cast a shadow at all: within band [param band] and
## on floors [param floors]. A lamp on a spare floor or beyond the frame edge casts no
## shadow, and the slot it got would be wasted for a lamp in frame (code review M24h).
static func nearest(
	lamps: Array[Lamp],
	centre: Vector2,
	count: int,
	band: Vector2 = Vector2(-INF, INF),
	floors: Vector2i = Vector2i(BuildingRules.ROOF, 1_000_000)
) -> Array[Lamp]:
	var alive: Array[Lamp] = []
	for lamp: Lamp in lamps:
		# A shot lamp is out, falling or not: its slot goes to a lamp that still shines
		# (ADR-0060).
		if not is_instance_valid(lamp) or not lamp.is_hanging():
			continue
		if not VisibleFloors.covers(floors, lamp.floor_index):
			continue
		if VisibleFloors.in_band(band, lamp.global_position.x):
			alive.append(lamp)
	alive.sort_custom(
		func(a: Lamp, b: Lamp) -> bool:
			return (
				WorldSpace.to_plane(a.global_position).distance_squared_to(centre)
				< WorldSpace.to_plane(b.global_position).distance_squared_to(centre)
			)
	)
	return alive.slice(0, count)


## Light of frame [param seen]: lamps and red door sconces are lit only on floors
## in frame and nearby (ADR-0010, item 8). Lamp light casts shadows, i.e. it is
## expensive, and is lit only in frame; on spare floors — without shadow (ADR-0042,
## decision 2). Sconces — by the same rule (ADR-0042, decision 8).
static func show_in_frame(
	rules: BuildingRules, seen: Rect2, lamps: Array[Lamp], doors: Array[Door]
) -> void:
	var span := VisibleFloors.around(rules, seen)
	var in_frame := VisibleFloors.seen(rules, seen)
	var strip := VisibleFloors.band(seen)
	var shade := VisibleFloors.band(seen, VisibleFloors.SHADOW_REACH)
	var filled := nearest(lamps, seen.get_center(), Lamp.FILL_SHADOW_CAP, shade, in_frame)
	# The level lights the frame anew only when the camera moves floors or the band: a lamp
	# that falls hands its fill shadow slot on at once by lighting this same frame again
	# (ADR-0060). Only the lamps holding a slot need it, and only for the latest frame.
	var relight := func() -> void: show_in_frame(rules, seen, lamps, doors)
	for lamp: Lamp in lamps:
		if not is_instance_valid(lamp):
			continue
		_hand_on_fall(lamp, relight if filled.has(lamp) else Callable())
		var x := lamp.global_position.x
		lamp.set_light_visible(
			VisibleFloors.in_band(strip, x) and VisibleFloors.covers(span, lamp.floor_index),
			VisibleFloors.in_band(shade, x) and VisibleFloors.covers(in_frame, lamp.floor_index),
			filled.has(lamp)
		)
	for door: Door in doors:
		if is_instance_valid(door):
			var index := rules.floor_index_near(WorldSpace.to_plane(door.position).y)
			door.set_light_in_view(
				VisibleFloors.covers(span, index) and VisibleFloors.in_band(strip, door.position.x)
			)


## Connects [param relight] to the fall of [param lamp] in place of the one from an earlier
## frame; an empty one only disconnects.
static func _hand_on_fall(lamp: Lamp, relight: Callable) -> void:
	if lamp.has_meta(RELIGHT):
		var old: Callable = lamp.get_meta(RELIGHT)
		if lamp.fell.is_connected(old):
			lamp.fell.disconnect(old)
		lamp.remove_meta(RELIGHT)
	if relight.is_valid():
		lamp.fell.connect(relight)
		lamp.set_meta(RELIGHT, relight)


## An escalator shines into the opening between two floors: it is lit while at least
## one of them is in frame.
static func show_escalators(span: Vector2i, strip: Vector2, escalators: Array[Escalator]) -> void:
	for escalator: Escalator in escalators:
		escalator.set_light_visible(
			(
				VisibleFloors.in_band(strip, escalator.global_position.x)
				and (
					VisibleFloors.covers(span, escalator.floor_index)
					or VisibleFloors.covers(span, escalator.floor_index + 1)
				)
			)
		)
