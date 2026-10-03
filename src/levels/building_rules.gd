class_name BuildingRules
extends Resource

## The rules a building is assembled by.
##
## In the original, buildings are nearly identical and differ in where the red doors are
## (ADR-0008, point 2), so a building is not a list of floors but these rules
## plus a seed. Changing the rules from building to building gives rising difficulty in M5b.
##
## [b]Lengths here are metric[/b] — since M15 the world is measured in metres, 100 former
## pixels = 1 m (ADR-0019, decision 3). Proportions were not touched by the conversion: only
## constants were divided, and [code]test_proportions.gd[/code] checks this without changes.
## Metres were chosen because light falloff, fog density and material roughness
## depend on them — they cannot be set in pixels.

## Roof: the level above the building where the descent begins.
##
## Not a floor and so not part of [member floors]: it has no doors, no lamps,
## no agents, and sky above it instead of a ceiling slab. A separate index rather than floor
## zero — ADR-0014, point 1: floor zero used to be the roof and the top floor at once,
## and its clearance came out 20 px instead of 100.
const ROOF: int = -1

## The fewest floors a shaft serves.
##
## Two is already an elevator, but only for a single-deck cab. A double-deck pair
## ([ADR-0025](../../docs/adr/0025-shafts-escalators-and-riders.md), decision 2)
## is two floors tall, and it carries only between floors that either deck can
## reach — that is, between [code]top + 1[/code] and [code]bottom - 1[/code].
## A three-floor shaft leaves one such floor: there is nowhere to go. Hence the minimum
## is four, and it is not about the pair alone — a run shorter than four suits no one,
## and keeping two minimums in the rules would mean explaining the difference in every
## check.
##
## Both the layout and the checks need the rule, so it lives as one number rather than two
## identical constants in different files.
const MIN_SHAFT_FLOORS: int = 4

## Round palette: what the building is painted with and what light it burns with.
##
## Changes from round to round, like the colours in the original, and the set loops:
## [method BuildingPalette.of_round], ADR-0017, decision 2. By default the first palette
## of the set is taken — the very one in the port's frame.
@export var palette: BuildingPalette = BuildingPalette.of_round(1)

## Building time of day (ADR-0051): a draw by seed in [method Main._enter_building].
## Night by default — a building assembled by a test without a draw goes dark, as before M24j.
@export var time_of_day: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT

## Building kind ([BuildingIdentity]): the level sets it from the building draw. Floor
## roles depend on it ([method FloorRole.at], ADR-0057). Hotel by default,
## like the first building of a game.
@export var kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL

## Weather set by hand ([enum Weather.Kind]), or -1 — a draw by seed
## ([method Weather.of_building]). Shot tools and tests set it: a combination of
## time of day and weather is shot without hunting for a seed. Lives in the building
## rules, not globally: before the M24j code review it was a static field of [Weather], and
## a test that forgot to reset it left the weather to the next one.
@export var forced_weather: int = -1

## Floors in the building, not counting the roof. Zero is the top, the last one has the exit.
@export var floors: int = 30

## Floor height and ceiling slab thickness, m.
@export var floor_height: float = Proportions.FLOOR
@export var slab_height: float = Proportions.SLAB

## How much open sky is above the roof deck, m.
##
## More than a floor: Otto jumps 2.4 m, and above his head at the peak there
## must still be sky, not the frame edge. At one floor's height he cleared it
## barely, and the jump read as hitting his head on the edge of the screen.
@export var sky_height: float = 4.8

## Building width and margin from the walls, m.
##
## The width is derived from the slot pitch: sixteen pitches of [constant
## Proportions.SLOT] and two 2.4 m margins (ADR-0026, decision 3).
@export var width: float = Proportions.SLOT * 16.0 + 2.4 * 2.0
@export var margin: float = 2.4

## How many horizontal slots the widest level has. Everything on a floor
## takes a whole slot, so a shaft, an escalator, a door and a lamp cannot
## end up on top of each other.
##
## Slots are numbered globally and stand at the same x over the full height. Otherwise
## a shaft passing through floors of different widths would end up in its own column
## on each of them (ADR-0014, point 3).
##
## **The number must be odd.** The silhouette is measured by half-width from the middle
## ([method slot_reach]), and an even set has no middle: the outermost column
## becomes unreachable on all levels at once, and the bottom floor stops spanning
## the full building width. Checked by a test.
##
## Seventeen slots instead of nine — ADR-0024, decision 1: only on a fine grid does
## the narrow top fit in the frame and still hold a shaft, a door, a lamp and an escalator.
## 1.8 m pitch, as in the original: a 1.2 door and a 0.6 gap, the shaft exactly one pitch
## (ADR-0026, decision 3). So shafts do not go in adjacent slots — there would be no
## floor left between them.
@export var slots: int = 17

## Slots on the narrowest level — at the top of the building.
##
## The profile is set in slots and the width derived from them, not vice versa: deriving
## from width produced floors that could not fit the must-haves — a shaft, two doors, a lamp.
@export var top_slots: int = 7

## The floor where the wide part of the building begins.
##
## The silhouette is set by a threshold, not by equal steps (ADR-0024, decision 2): above
## the threshold is a narrow tower of [member top_slots] slots that fits in the frame whole,
## at the threshold and below is the podium across all [member slots], twice the frame width.
@export var wide_from: int = 20

## How many floors a shaft serves. A shaft does not run through: reached the end —
## change over, and that is the whole descent (ADR-0008).
##
## Since M18 shafts overlap: ones opening on different floors close on different ones,
## and changing over is not only by escalator (ADR-0024, decision 3).
@export var shaft_span: int = 6

## By how many floors a shaft's run may differ from [member shaft_span].
##
## Without spread, shafts opening on one level close on one level, and
## there is no overlap at all. In the original the lengths differ: 5, 6, 7, 3, 12.
@export var shaft_span_spread: int = 2

## How many floors the top shaft serves — the one running from the roof.
##
## Longer than usual: in the original it is 19–30 with the roof, twelve floors on one
## shaft. The top third of the building has no alternative, and that is its character.
##
## One level deeper than the single-shaft zone ([member single_shaft_until] plus the roof
## plus one): the tower shaft reaches into the podium, and the joint at the threshold is
## closed by overlap. Without this reach the descent of the whole building would depend on
## whether an escalator finds room on the tightest floor — and with seven slots, four of
## which the band has already eaten, it does not always.
@export var top_shaft_span: int = 14

## How far down the building makes do with one shaft. Below this floor there are
## more paths — [method shafts_on].
@export var single_shaft_until: int = 11

## How many shafts serve the floor above the basement. Five — as in the original, where
## 1–5, 1–6 and three 1–7 reach the ground together; one of them goes down to the basement
## ([method shafts_on]).
@export var shafts_max: int = 5

## How many bottom floors of the single-shaft zone are given to escalators.
##
## The band at the threshold: the tower shaft ends above the podium, and an escalator leads
## down (ADR-0024, decision 4). In the original these are floors 16–20.
@export var escalator_band: int = 5

## Shaft width, which is also the cab width: there must be no gaps at the sides.
##
## Exactly one slot pitch, 60% of the clearance — as in the original (ADR-0026, decision 3).
@export var shaft_width: float = Proportions.SHAFT

## Thickness of the inner wall dividing a floor in two, m, and the probability
## that it appears on a floor.
##
## Not on every floor: a wall is a detour through another floor, and on every floor in a row
## the descent would turn into a maze (ADR-0024, decision 5).
##
## Almost a metre, not the outer wall thickness: in the milestone's first shots a wall
## 0.48 m wide was indistinguishable from a pilaster (0.45), and "no way through" read as
## decoration. Arcade readability matters more than realism — the pivot rule
## ([ADR-0019](0019-3d-pivot.md)). It costs no slot: the wall stands on the boundary
## between slots, and the grid pitch is 1.8 m.
@export var inner_wall_width: float = 0.9
@export var wall_chance: float = 0.35

## Escalator opening: how far it is set back from the landing and how wide it is, m.
## Lives here, not in the level, because the layout learns from it where the floor has a hole:
## otherwise the opening geometry would be written twice and would drift apart.
##
## Since M24g the opening runs from the landing to the floor edge
## ([method EscalatorSpot.gap]): it has no width, only a setback from the
## landing.
@export var escalator_gap_offset: float = 0.12

## Escalator slope, degrees (ADR-0043, decision 15). Before M24g the run fit into
## two slots and stood at ~66°; at 30°, like a real one, it read in the frame as
## too flat — the user's decision, 45°.
@export var escalator_angle: float = 45.0

## Distance from the floor edge to the lower landing, m: the landing with a rider on it and
## the gap to the wall.
@export var escalator_edge_margin: float = Proportions.BODY_WIDTH * 0.5 + 0.52

## How much of the run above the floor below is taken under it, m from the lower landing:
## there the belt is below door height, and neither a door nor a lamp belongs under it.
@export var escalator_low_span: float = 2.7

## Red doors per building set by hand; −1 — 5 to 10 by a draw on the building seed
## ([method BuildingDocuments.count], ADR-0037, decision 8). For tests and
## runs that need a building with one document or none at all
## (ADR-0028, decision 3).
##
## A manual number is spread evenly over the height; ROM-driven ones follow the original's bands.
@export var documents_cap: int = -1

## Doors per floor set by hand, counting the red one; zero — by ROM per screen width
## ([method doors_on]). For tests that need a tight floor.
@export var doors_cap: int = 0

## Cap on lamps per floor. How many there actually are is decided by floor width —
## [method lamps_on]: the narrow top makes do with one, the wide bottom gets three.
@export var lamps_per_floor: int = 3

## Building skill: the game's difficulty level (the cabinet's DIP switch, 0–3)
## plus buildings cleared. From it and from time in the building [Arcade] computes all
## the rest — difficulty, agent aggression, their bullet speed (ADR-0027).
@export var skill: int = 0

## Range at which an agent notices Otto standing in darkness, m (ADR-0023,
## decision 8). Otto's shadow decides, not the agent's: from the shadow the lit one is seen,
## the lit one does not see into the shadow. There is no fire range as such: in ROM an agent
## shoots across the whole floor, here — while he is in frame (ADR-0027, decision 3a).
@export var agent_dark_fire_range: float = 1.8

## Closer than this to Otto, a door on his floor does not release an agent, m. ROM has no
## such ban (@5AAB), but exiting point-blank cost the bot twice as many deaths: 1.2 m — by
## measurement, less than the former 2.88 (ADR-0053, decision 3).
@export var agent_release_gap: float = 1.2

## For this long after Otto comes back, a door on his floor does not release an agent
## closer to him than [member agent_respawn_gap], s and m. Our deviation from the ROM,
## which has no distance check (@5AAB): an agent from the next door used to lie down
## a step away and kill the returned Otto two seconds later, again and again
## (ADR-0059, decision 3, user's choice).
@export var agent_respawn_calm: float = 4.0
@export var agent_respawn_gap: float = 4.0

## Whether agents never shoot. For shots and checks that need an agent
## who walks and dodges but does not kill; always off in the game.
@export var agents_hold_fire: bool = false

## Cap on agents in the building set by hand; zero — by ROM, three or four
## ([method Arcade.agents_at_once]). For experiment runs.
@export var agents_at_once_cap: int = 0

## Agent height kneeling and lying, m. Standing height is taken from the scene's collision shape.
##
## The numbers are in [Proportions]: kneeling and lying are checked against the original's
## frame the same way as height (ADR-0026, decision 2).
@export var agent_kneel_height: float = Proportions.KNEEL
@export var agent_prone_height: float = Proportions.PRONE

## How far sideways an escalator goes descending one floor, m: by the slope.
var escalator_run: float:
	get:
		return floor_height / tan(deg_to_rad(escalator_angle))


## Rules of the next building: skill grows with each one cleared (@0A0A), the palette
## changes. [param level] is the game's difficulty level, DIP 0–3.
static func for_building(number: int, level: int = 0) -> BuildingRules:
	var rules := BuildingRules.new()
	rules.skill = Arcade.skill(level, number)
	# Colour is the same kind of building rule: in the original the layout barely changes,
	# but the palette changes every round.
	rules.palette = BuildingPalette.of_round(number)
	return rules


## How many agents are in the building at once now: the manual cap or by ROM.
func agents_at_once(time: float) -> int:
	return agents_at_once_cap if agents_at_once_cap > 0 else Arcade.agents_at_once(skill, time)


## Horizontal coordinate of a slot.
func slot_x(slot: int) -> float:
	if slots <= 1:
		return width * 0.5
	var usable := width - margin * 2.0
	return margin + usable * float(slot) / float(slots - 1)


## The level surface that is stood on: [constant ROOF] is the roof deck,
## zero is the top floor of the building.
##
## One formula for the roof and floors: the roof is [code]index = -1[/code], and
## it needs no separate count. That way the clearance comes out equal on all levels,
## which it did not while floor zero served as the roof (ADR-0014, point 1).
func floor_surface(index: int) -> float:
	return sky_height + floor_height * float(index + 1)


## Height of the whole building, m. The sky above the roof is included: it is part of the world
## that the camera moves over.
func total_height() -> float:
	return floor_surface(floors - 1) + slab_height


## The level vertically nearest to a point. May return [constant ROOF].
func floor_index_near(y: float) -> int:
	var raw := roundf((y - sky_height) / floor_height) - 1.0
	return clampi(int(raw), ROOF, floors - 1)


## Level ceiling: the bottom of the slab above. The roof has no ceiling — there is sky above it,
## and the band is measured from the top of the world.
func story_top(index: int) -> float:
	return 0.0 if index <= ROOF else floor_surface(index - 1) + slab_height


## All levels top to bottom, the roof included. One traversal for the whole project: walking
## [code]range(floors)[/code] and forgetting the roof is exactly the mistake that
## put doors on it.
func levels() -> Array[int]:
	var all: Array[int] = []
	for index in range(ROOF, floors):
		all.append(index)
	return all


## Whether the level is in the wide part of the building. One threshold for both the
## silhouette and everything that depends on width: doors, lamps, slots (ADR-0024, decision 2).
##
## The roof is always narrow: [constant ROOF] is below any threshold.
func is_wide(index: int) -> bool:
	return index >= wide_from


## How many shafts serve the level.
##
## At the top one — this is the original's 19–30 shaft, where the descent has no alternative.
## Below the single-shaft zone threshold it grows from two to [member shafts_max] toward the bottom,
## where five meet in the original (ADR-0024, decision 3).
##
## This is the layout's target, not the result: a shaft lives many floors, and the number on
## a floor adds up from those that are open. [method BuildingPlan.generate] goes
## top to bottom and opens the missing ones.
##
## **No more than a third of the level's slots.** Shafts do not go in adjacent slots
## (ADR-0026, decision 3), and each one, wherever it stands, eats no more than three slots
## with its neighbours — so a third of the slots, rounded up, always fits, however the
## earlier ones fell. A narrow tower of seven slots gets three shafts, a podium
## of seventeen gets six, so the [member shafts_max] cap is not reached.
##
## The basement — the bottom floor — is served by one shaft: in ROM one of the five goes down
## there, by a draw (ADR-0038, decision 3). The five meet one floor above.
func shafts_on(index: int) -> int:
	if index >= floors - 1:
		return mini(1, _shafts_wanted(index))
	var span := slot_range(index)
	var room := (span.y - span.x + 1 + 2) / 3
	return mini(_shafts_wanted(index), maxi(room, 1))


func _shafts_wanted(index: int) -> int:
	var most := maxi(shafts_max, 1)
	if index <= single_shaft_until:
		return 1
	var first := single_shaft_until + 1
	# The growth in paths ends where a shaft can still be opened. A new shaft
	# adds a path to a floor only if it opens on that floor itself, and it can open
	# no lower than [constant MIN_SHAFT_FLOORS] floors above the bottom: there is no shorter
	# run. Demand the growth rule all the way down and the layout could not
	# satisfy it, and the bottom floors would end up poorer than promised.
	#
	# Same in the original: runs 1–5, 1–6 and 1–7 reach the ground, having started
	# high, and none opens one floor above it.
	#
	# The bottom of the runs is the floor above the basement: one shaft of those that reach it
	# goes down to the basement (ADR-0038, decision 3), so the count per floor is shorter.
	var last := floors - 1 - MIN_SHAFT_FLOORS
	var fewest := mini(2, most)
	if last <= first:
		return fewest
	var depth := float(mini(index, last) - first) / float(last - first)
	return clampi(fewest + int(roundf(depth * float(most - fewest))), fewest, most)


## Whether the level falls into the escalator band — the bottom floors of the single-shaft zone.
##
## There the tower shaft ends and the podium has not begun yet, and an escalator leads
## down (ADR-0024, decision 4). An escalator in the band is an alternative to a shaft, not
## the only path: in the original 19–30 passes through 19–20, where there are
## escalators too.
func in_escalator_band(index: int) -> bool:
	if index <= ROOF or index > single_shaft_until:
		return false
	return index > single_shaft_until - maxi(escalator_band, 0)


## How many slots right and left of the middle are available on the level.
##
## Counted by half-width, so the number of slots is always odd and they lie
## symmetrically: a floor with an even number of slots would be offset relative to
## the shaft passing through it.
func slot_reach(index: int) -> int:
	var full := (slots - 1) / 2
	var narrow := clampi((top_slots - 1) / 2, 0, full)
	return full if is_wide(index) else narrow


## First and last available slot of the level, inclusive.
func slot_range(index: int) -> Vector2i:
	var middle := (slots - 1) / 2
	var reach := slot_reach(index)
	return Vector2i(maxi(middle - reach, 0), mini(middle + reach, slots - 1))


## Whether a slot exists on this level. Outside the silhouette there is no slot: it is the street.
func slot_available(slot: int, index: int) -> bool:
	var span := slot_range(index)
	return slot >= span.x and slot <= span.y


## Level bounds: the outer edges of the walls, left and right.
##
## Derived from the outermost available slots, not from a fraction of width: a slot must be
## [member margin] away from the wall, as on a full-width building.
func floor_span(index: int) -> Vector2:
	var span := slot_range(index)
	return Vector2(slot_x(span.x) - margin, slot_x(span.y) + margin)


## Bounds of the level's slab: it is both the floor of its level and the ceiling of the one
## below, so the wider of the two is taken.
##
## Without this, on every step of the silhouette the lower, wider floor would be left
## without a ceiling over its outer band: open sky inside the building, and
## a lamp that landed on the outermost slot there would hang from nothing at all.
##
## That ledge cannot be walked on — it is outside its level's walls — so
## the reachability graph counts pieces by [method floor_span] and does not depend on it.
func slab_span(index: int) -> Vector2:
	var own := floor_span(index)
	if index >= floors - 1:
		return own
	var below := floor_span(index + 1)
	return Vector2(minf(own.x, below.x), maxf(own.y, below.y))


## Whether the floor is dark per the original's map: it has no lamps and is dark from the
## start of the building (ADR-0028, decision 4). The roof is never dark — the city lights it.
## Dark floors exist only at night (ADR-0051, decision 5).
func is_unlit(index: int) -> bool:
	if not is_night():
		return false
	return index > ROOF and index < floors and Arcade.is_dark_floor(Arcade.rom_floor(index, floors))


## Whether it is night in the building: only at night does a shot lamp darken its zone, and
## the map's floors are dark (ADR-0051, decision 5).
func is_night() -> bool:
	return TimeOfDay.is_night(time_of_day)


## How many original screens the level width spans, at least one. The tower is
## one, the podium two (ADR-0028, decision 2).
func _screens(index: int) -> int:
	return maxi(1, roundi(floor_width(index) / Proportions.FIELD_WIDTH))


## How many doors are on a floor, counting the red one: the ROM number times width in screens
## (ADR-0028, decision 2). Density in frame is as in the original: the tower gets
## four, the middle up to seven, the wide bottom twice as many.
##
## This is a target, not a promise: shafts, escalators and the exit are placed first, and
## only one of these doors is mandatory: the rest take what is left after the
## lamps — otherwise an escalator would find no room on a tight floor.
func doors_on(index: int) -> int:
	if index <= ROOF or index == floors - 1:
		# The exit floor is a garage, like the original's basement (mask 00): the car does not
		# stand among doors (ADR-0031, decision 4).
		return 0
	if doors_cap > 0:
		return doors_cap
	return Arcade.doors_on_floor(Arcade.rom_floor(index, floors)) * _screens(index)


## How many lamps to hang on a level: a row of ceiling fixtures, as in the reference
## (ADR-0023, decision 2), and each one's zone is a unit of darkness: a shot one darkens its
## own, the neighbours stay lit.
##
## Counted as the floor width's share of the building width: full width gets [member
## lamps_per_floor], the narrow top makes do with one. Not by the floor's slots, as before
## M18: on the fine ADR-0024 grid a count by slots would give the top two lamps instead of
## one — the slots doubled while the floor stayed the same width. And not by metres:
## an absolute lamp spacing would not survive a building of other dimensions, and tests
## assemble those.
##
## Dark floors on the map get zero: they are dark from the start ([method is_unlit]).
##
## The roof gets zero: there is sky above it, nothing to hang a fixture from, and the city
## lights it (ADR-0014). Answering "one" would promise a lamp to whoever asks across
## all levels at once: the layout skips the roof, and the rule would claim
## the opposite.
func lamps_on(index: int) -> int:
	if index <= ROOF or is_unlit(index):
		return 0
	var most := maxi(lamps_per_floor, 1)
	var share := floor_width(index) / maxf(width, 0.1)
	return clampi(int(roundf(share * float(most))), 1, most)


## Level width, m.
func floor_width(index: int) -> float:
	var span := floor_span(index)
	return span.y - span.x
