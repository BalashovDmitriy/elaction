class_name Arcade
extends RefCounted

## The rules of the arcade ROM — combat and building — in one table.
##
## Numbers and formulas are taken from the annotated ROM disassembly (jotd, Amiga port); conclusions
## with addresses are in `docs/reference/arcade-rom.md`, decisions are in
## [ADR-0027](../../docs/adr/0027-rom-combat.md) and
## [ADR-0028](../../docs/adr/0028-building-by-the-map.md). The address next to a number is its place
## in that project's `src/elevator_z80.asm`: the number can be rechecked by it.
##
## The original counts in logic ticks: a frame is 59.19 Hz (MAME driver `taitosj`), logic runs once
## every four frames. The table gives seconds and metres and keeps ticks to itself: this way a
## formula reads next to the ROM, and the rest of the code does not know about ticks.
##
## These are rules, not sizes: the heights of stances and bullets live in [Proportions].

## The pose in which the agent shoots.
enum Pose { STAND, CROUCH, PRONE, ON_THE_MOVE }

## Seconds per logic tick: 4 frames of 1/59.19 s.
const TICK: float = 4.0 / 59.19

## Cap on difficulty and anger (@592F, @5AFC).
const TOP: int = 15

## Alarm: 4096 ticks, ~277 s (@466E).
const ALARM_TICKS: int = 4096

## Bonus for a cleared building: the rate and from which building it stops growing (@5793).
const BUILDING_BONUS: int = 1000
const BUILDING_BONUS_TOP: int = 10

## Walking step of Otto and an agent, px per tick (@4450/@445F) — one routine for both.
const WALK_PX: float = 2.0

## Otto's bullet, px per tick (table_50D8).
const OTTO_BULLET_PX: float = 8.0

## How many times faster than the ROM bullets fly — Otto's and the agents' (ADR-0037, decision 5).
## **A deliberate departure from the original**, the user's decision: the ROM bullet crosses the
## frame in 2.6 s and reads as crawling. The ROM tables are left untouched — the multiplier sits on
## top of them as one number, and the ROM tests keep the old values.
##
## Along with the speed, the distance at which an agent notices a bullet grows too ([method
## dodge_reach]): the time to dodge stays the same as in the ROM.
const BULLET_PACE: float = 3.0

## Cab, px per tick (@45D8).
const CAR_PX: float = 2.0

## How many ticks the agents' alarm lasts after Otto's shot or an agent boarding a cab (@59C8,
## @1AED).
const ALERT_TICKS: int = 90

## How long Otto stays behind a red door, ticks: exactly 70, ~4.73 s ($82ED = $46, @2A5B). He cannot
## leave earlier — the user's decision (ADR-0038, decision 2); in the ROM you can, by pushing away
## from the door after 9 ticks.
const ROOM_TICKS: int = 70

## A lagging agent goes into the nearest door (@041F-04E5): if his feet are on screen 80 px or
## farther from Otto's feet — and only on ROM floors from the eighth. A floor is 48 px, so for one
## standing on the floor this is two floors.
##
## The third ROM condition — "except the twentieth" — is not taken, and this is not a departure: the
## ROM searches for the nearest door within its half of the floor (@049F, split by $7B), and the
## wall of the twentieth does not stand in the middle ($AC), so the agent would be sent to a door
## beyond the wall. Our search ([method AgentLifts.nearest_door]) already takes only a door that can
## be reached (ADR-0053, decision 6).
const LEAVE_PX: float = 80.0
const LEAVE_FROM_FLOOR: int = 8

## Crowd: if this many agents or more stand on Otto's floor, above or below — the extra ones go into
## the nearest door (@041F-0458), on the same ROM floors as the lagging ones. The [code]CROWD -
## 1[/code] closest to Otto remain (ADR-0053, decision 5).
const CROWD: int = 3

## Otto's return after death (@7633, @2FAA): no lower than the fifth ROM floor, at the floor's red
## door if the document behind it has not been taken yet, and without one — at point $67 of the 256
## px floor width, feet in the middle of the 8 px sprite. The floors' agents leave, the cells
## release them again after 10, 25, 40 and 55 ticks (@2F61) (ADR-0053, decision 2).
const RESPAWN_FROM_FLOOR: int = 5
const RESPAWN_SHARE: float = (0x67 + 4) / 256.0
const RESPAWN_WAIT_TICKS: Array[int] = [10, 25, 40, 55]

## How close Otto's bullet must come for an agent to dodge it, px (@05F5).
const DODGE_REACH_PX: float = 20.0

## In what band above the floor Otto's bullet makes an agent dodge, px (@05F5): above and below it
## misses anyway.
const DODGE_BAND_PX := Vector2(6.0, 24.0)

## Chance to dodge per tick by anger, out of 256 (odds_table_0659).
const DODGE_ODDS: Array[int] = [0, 0, 2, 2, 4, 8, 16, 16, 32, 32, 64, 64, 96, 128, 196, 255]

## Choice of shooting pose by anger — thresholds out of 256 for pairs of anger values (table_1D75
## for agents 1–2, table_1D95 for 3–4). A roll below the first — standing, below the second —
## crouching, below the third — lying, above — shooting on the move.
const POSE_THRESHOLDS: Array[Vector3i] = [
	Vector3i(0xC4, 0xC4, 0xC4),
	Vector3i(0x80, 0xC4, 0xC4),
	Vector3i(0x40, 0xC4, 0xC4),
	Vector3i(0x20, 0x80, 0xC4),
	Vector3i(0x08, 0x40, 0xC4),
	Vector3i(0x08, 0x20, 0xC4),
	Vector3i(0x08, 0x10, 0xC4),
	Vector3i(0x00, 0x08, 0xC4),
]
const POSE_THRESHOLDS_LATE: Array[Vector3i] = [
	Vector3i(0x40, 0x40, 0x40),
	Vector3i(0x30, 0x40, 0x40),
	Vector3i(0x20, 0x40, 0x40),
	Vector3i(0x18, 0x30, 0x40),
	Vector3i(0x10, 0x20, 0x40),
	Vector3i(0x08, 0x10, 0x40),
	Vector3i(0x00, 0x08, 0x40),
	Vector3i(0x00, 0x00, 0x40),
]

## Floors in the original building. Counted from the bottom: the first is the lowest, the thirtieth
## the top; zero is the basement with the car, we do not have it (ADR-0028, decision 1).
const FLOORS: int = 30

## Floor doors — a mask of eight places, floor 0..30 (table_280E). The original has one building,
## and its doors stand in the same places in every round.
const DOOR_MASKS: Array[int] = [
	0x00,
	0x81,
	0x81,
	0x81,
	0x81,
	0x81,
	0x81,
	0x00,
	0x7E,
	0x7E,
	0x66,
	0x66,
	0xE6,
	0x7E,
	0x7F,
	0x67,
	0xE6,
	0x66,
	0x7E,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
]

## Dark floors: there are no lamps on them at all (@2719), a kill is scored as in darkness (@56A1).
const DARK_FLOORS := Vector2i(11, 15)

## Red door bands: ROM floors inclusive and how many red doors in a band by skill 0..8 (@27D2,
## tables @282D–@2874). No more than one per floor.
const RED_DOOR_BANDS: Array[Vector2i] = [
	Vector2i(1, 6),
	Vector2i(8, 8),
	Vector2i(9, 11),
	Vector2i(12, 14),
	Vector2i(15, 17),
	Vector2i(18, 20),
	Vector2i(21, 25),
	Vector2i(26, 30),
]

## Red door quotas by band [constant RED_DOOR_BANDS] and skill 0..8.
##
## Rows are [Array], not [PackedInt32Array]: a constant made of literals typed as a packed array
## reads garbage by index (Godot 4.7).
const RED_DOOR_QUOTAS: Array[Array] = [
	[0, 1, 2, 2, 2, 2, 3, 4, 5],
	[0, 0, 0, 1, 1, 1, 1, 1, 1],
	[2, 2, 2, 1, 1, 2, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[0, 0, 0, 1, 1, 1, 1, 1, 0],
	[0, 0, 0, 0, 1, 1, 1, 0, 0],
]

## Above this skill red door quotas do not grow (@27D6).
const RED_DOOR_SKILL_TOP: int = 8


## Ticks to seconds.
static func seconds(ticks: float) -> float:
	return ticks * TICK


## Seconds to ticks.
static func ticks(time: float) -> float:
	return time / TICK


## Speed in metres per second from a step in pixels per tick.
static func speed(px_per_tick: float) -> float:
	return px_per_tick * Proportions.PX / TICK


## Game skill: difficulty level (DIP 0–3) plus cleared buildings (@2EAD, @0A0A).
static func skill(level: int, building: int) -> int:
	return maxi(level, 0) + maxi(building - 1, 0)


## Difficulty now: skill plus time in the building (compute_difficulty_592F).
##
## Before the alarm +1 every 1024 ticks (~69 s), after — every 256 (~17 s).
static func difficulty(skill_level: int, time: float) -> int:
	var msb := int(ticks(time) / 256.0)
	var grown := msb - 12 if msb >= 16 else msb / 4
	return mini(TOP, skill_level + grown)


## Agent anger: on coming out — the difficulty, then +1 every 256 ticks (@5AA4, @5AFC).
static func aggression(at_spawn: int, age: float) -> int:
	return mini(TOP, at_spawn + int(ticks(age) / 256.0))


## How many agents in the building at once: 3, and 4 when skill·4 + time ≥ 14 (@594D).
static func agents_at_once(skill_level: int, time: float) -> int:
	var msb := int(ticks(time) / 256.0)
	return 4 if skill_level * 4 + msb >= 14 else 3


## How many agents at once on the floor near Otto: 1 for the first ~51 s, 2 until ~3.4 min, then 3
## (@5905). While Otto is not on the floor and there is no agent alarm — 1 (@59F4).
static func agents_per_floor(time: float, otto_on_foot: bool, alert: bool) -> int:
	if not otto_on_foot or not alert:
		return 1
	var msb := int(ticks(time) / 256.0)
	if msb < 3:
		return 1
	return 2 if msb < 12 else 3


## Chance that an agent comes out exactly on Otto's floor, out of 1 (@5A4C).
static func own_floor_chance(level: int) -> float:
	return float(level * 4) / 256.0


## How long a door waits for a change after an agent, s: max(0, 80 − 6·difficulty) (@3866).
static func respawn_wait(level: int) -> float:
	return seconds(maxi(0, 0x50 - 6 * level))


## Wind-up before a shot, s: max(0, 10 − anger) ticks (@1BDF).
static func wind_up(anger: int) -> float:
	return seconds(maxi(0, 10 - anger))


## Pause after a shot, s: max(0, 80 − 8·anger) ticks (@0055).
static func cooldown(anger: int) -> float:
	return seconds(maxi(0, 80 - 8 * anger))


## How long an agent action lasts — a shot or a dodge, s: max(7, wind-up + 2) ticks (@1C7A).
static func action_time(anger: int) -> float:
	return seconds(maxi(7, maxi(0, 10 - anger) + 2))


## Agent bullet speed, m/s: min(8, skill/4 + 6) px per tick, during the alarm one step faster, but
## no higher than 8 (@463D).
static func agent_bullet_speed(skill_level: int, alarmed: bool) -> float:
	var step := mini(8, skill_level / 4 + 6)
	if alarmed:
		step = mini(8, step + 1)
	return speed(float(step))


## Bullet speed in the game, m/s, from a ROM step in pixels per tick: the ROM multiplied by
## [constant BULLET_PACE] (ADR-0037, decision 5).
static func bullet_speed(px_per_tick: float) -> float:
	return speed(px_per_tick) * BULLET_PACE


## Agent bullet speed in the game, m/s: [method agent_bullet_speed] with [constant BULLET_PACE].
static func agent_shot_speed(skill_level: int, alarmed: bool) -> float:
	return agent_bullet_speed(skill_level, alarmed) * BULLET_PACE


## From what distance an agent notices Otto's bullet flying at him, m: 20 ROM px (@05F5), stretched
## by [constant BULLET_PACE]. The bullet is faster by the same factor, and the same time passes from
## noticing to impact as in the ROM.
static func dodge_reach() -> float:
	return DODGE_REACH_PX * Proportions.PX * BULLET_PACE


## Shooting pose by anger and a roll 0..255. [param late] — agents 3–4, they have their own table:
## they shoot on the move more often.
static func fire_pose(anger: int, roll: int, late: bool = false) -> Pose:
	var table := POSE_THRESHOLDS_LATE if late else POSE_THRESHOLDS
	var limits: Vector3i = table[clampi(anger, 0, TOP) / 2]
	if roll < limits.x:
		return Pose.STAND
	if roll < limits.y:
		return Pose.CROUCH
	if roll < limits.z:
		return Pose.PRONE
	return Pose.ON_THE_MOVE


## Chance to dodge a bullet in one tick by anger, out of 1.
static func dodge_chance(anger: int) -> float:
	return float(DODGE_ODDS[clampi(anger, 0, TOP)]) / 256.0


## ROM floor for our floor: our count goes from the top, the ROM's from the bottom (ADR-0028,
## decision 1). A building of a different height stretches the map by the share of height rather
## than cutting it off: tests assemble six-floor ones too.
static func rom_floor(index: int, floors: int) -> int:
	var from_bottom := float(floors - index) * float(FLOORS) / float(maxi(floors, 1))
	return clampi(roundi(from_bottom), 1, FLOORS)


## How many doors are on a ROM floor — places in its mask (table_280E).
static func doors_on_floor(rom: int) -> int:
	var mask := DOOR_MASKS[clampi(rom, 0, FLOORS)]
	var count := 0
	while mask > 0:
		count += mask & 1
		mask >>= 1
	return count


## Whether a ROM floor is dark: no lamps and a kill priced as in darkness (@2719, @56A1).
static func is_dark_floor(rom: int) -> bool:
	return rom >= DARK_FLOORS.x and rom <= DARK_FLOORS.y


## How many red doors are in band [param band] at this skill (@27D2).
static func red_doors_in_band(band: int, skill_level: int) -> int:
	var quotas: Array = RED_DOOR_QUOTAS[band]
	return int(quotas[clampi(skill_level, 0, RED_DOOR_SKILL_TOP)])


## How many red doors are in the building at this skill: 5, 6 … 10.
static func red_doors(skill_level: int) -> int:
	var total := 0
	for band in RED_DOOR_BANDS.size():
		total += red_doors_in_band(band, skill_level)
	return total


## Bonus for cleared building [param building]: 1000 × min(10, skill − DIP + 1) (@5793). Skill is
## DIP plus cleared buildings ([method skill]), so the multiplier is the building number, and from
## the tenth the bonus no longer grows.
static func building_bonus(building: int) -> int:
	return BUILDING_BONUS * clampi(building, 1, BUILDING_BONUS_TOP)


## Whether an agent on ROM floor [param rom], lagging behind Otto by [param floors_apart] floors,
## goes into a door (@041F-04E5). The shaft toward Otto is our own separate condition (ADR-0027,
## decision 3a), the level checks it.
static func agent_leaves(rom: int, floors_apart: int) -> bool:
	var apart_px := absf(float(floors_apart)) * Proportions.FLOOR / Proportions.PX
	return apart_px >= LEAVE_PX and rom >= LEAVE_FROM_FLOOR


## How many agents on ROM floor [param rom], where [param count] of them stand, must go into doors
## (@041F-0458): the extra ones beyond [code]CROWD - 1[/code], and only from the eighth ROM floor,
## like the lagging ones. The floors are Otto's, above and below; the level selects them.
static func crowd_leavers(rom: int, count: int) -> int:
	if rom < LEAVE_FROM_FLOOR or count < CROWD:
		return 0
	return count - (CROWD - 1)
