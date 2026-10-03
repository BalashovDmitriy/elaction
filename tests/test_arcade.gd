extends GutTest

## Combat formulas are checked against the numbers of the arcade ROM (ADR-0027).
##
## Every assertion is an extreme value read in the disassembly: the address is next to it,
## conclusions are in `docs/reference/arcade-rom.md`. If it diverges, the formula was rewritten
## rather than carried over.


## 14.8 ticks per second: a frame is 59.19 Hz, logic once every four frames (MAME taitosj).
func test_a_tick_is_four_frames_of_the_arcade() -> void:
	assert_almost_eq(Arcade.TICK, 0.0676, 0.0001)
	assert_almost_eq(Arcade.seconds(Arcade.ALARM_TICKS), 277.0, 0.5, "alarm — ~277 s")


## A step of 2 px per tick is 2.2 m/s; Otto's bullet at 8 px is 8.9 m/s (table_50D8).
func test_speeds_in_metres() -> void:
	assert_almost_eq(Arcade.speed(Arcade.WALK_PX), 2.22, 0.01, "walk")
	assert_almost_eq(Arcade.speed(Arcade.OTTO_BULLET_PX), 8.88, 0.01, "Otto bullet")


## Difficulty: +1 every 1024 ticks before the alarm, every 256 after, cap 15 (@592F).
func test_difficulty_grows_with_time_and_alarm() -> void:
	assert_eq(Arcade.difficulty(0, 0.0), 0)
	assert_eq(Arcade.difficulty(0, Arcade.seconds(1023)), 0, "before 1024 ticks — unchanged")
	assert_eq(Arcade.difficulty(0, Arcade.seconds(1024)), 1)
	assert_eq(Arcade.difficulty(0, Arcade.seconds(4096)), 4, "on alarm — +4")
	assert_eq(Arcade.difficulty(0, Arcade.seconds(4096 + 256)), 5, "after — every 256")
	assert_eq(Arcade.difficulty(20, 0.0), Arcade.TOP, "ceiling 15")


## Agent anger: on coming out — the difficulty, +1 every 256 ticks (@5AFC).
func test_aggression_grows_with_age() -> void:
	assert_eq(Arcade.aggression(3, 0.0), 3)
	assert_eq(Arcade.aggression(3, Arcade.seconds(512)), 5)
	assert_eq(Arcade.aggression(14, Arcade.seconds(10000)), Arcade.TOP)


## Wind-up max(0, 10 − anger), pause max(0, 80 − 8·anger) ticks (@1BDF, @0055).
func test_wind_up_and_cooldown() -> void:
	assert_almost_eq(Arcade.wind_up(0), Arcade.seconds(10), 0.0001)
	assert_eq(Arcade.wind_up(12), 0.0, "an angry one shoots without a wind-up")
	assert_almost_eq(Arcade.cooldown(0), 5.41, 0.01, "5.4 s for a calm one")
	assert_eq(Arcade.cooldown(10), 0.0, "and zero for an angry one")


## Agents at once: 3, four when skill·4 + time ≥ 14 (@594D).
func test_four_agents_only_late_or_on_high_skill() -> void:
	assert_eq(Arcade.agents_at_once(0, 0.0), 3)
	assert_eq(Arcade.agents_at_once(4, 0.0), 4, "skill 4 — four at once")
	assert_eq(
		Arcade.agents_at_once(0, Arcade.seconds(14 * 256)), 4, "or 14×256 ticks in the building"
	)


## On the floor: 1, 2, 3 by time — only under the alarm and while Otto is on his feet (@5905).
func test_agents_per_floor() -> void:
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(5000), true, false), 1, "no alarm — one")
	assert_eq(
		Arcade.agents_per_floor(Arcade.seconds(5000), false, true), 1, "Otto in the car — one"
	)
	assert_eq(Arcade.agents_per_floor(0.0, true, true), 1)
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(3 * 256), true, true), 2)
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(12 * 256), true, true), 3)


## Agent bullet: min(8, skill/4 + 6) px per tick, during the alarm one step faster (@463D).
func test_agent_bullet_speed() -> void:
	assert_almost_eq(Arcade.agent_bullet_speed(0, false), Arcade.speed(6.0), 0.001)
	assert_almost_eq(Arcade.agent_bullet_speed(0, true), Arcade.speed(7.0), 0.001)
	assert_almost_eq(Arcade.agent_bullet_speed(40, true), Arcade.speed(8.0), 0.001, "not above 8")


## Shooting poses by anger (table_1D75): a calm one does not lie down, an angry one lies down most
## often.
func test_fire_pose_follows_the_table() -> void:
	var calm := _share(0, Arcade.Pose.PRONE)
	var mean := _share(14, Arcade.Pose.PRONE)
	assert_eq(calm, 0.0, "a calm one does not shoot while prone")
	assert_almost_eq(_share(0, Arcade.Pose.STAND), 196.0 / 256.0, 0.001, "standing 77%")
	assert_almost_eq(mean, 188.0 / 256.0, 0.001, "angry — prone 73%")


## Dodge: chance per tick by anger (odds_table_0659) — zero for a calm one, almost certain for the
## angriest.
func test_dodge_chance() -> void:
	assert_eq(Arcade.dodge_chance(0), 0.0)
	assert_almost_eq(Arcade.dodge_chance(15), 255.0 / 256.0, 0.0001)


func _share(anger: int, pose: Arcade.Pose) -> float:
	var hits := 0
	for roll in 256:
		if Arcade.fire_pose(anger, roll) == pose:
			hits += 1
	return float(hits) / 256.0


## Doors of ROM floors (table_280E), bottom to top — our own table, not the `Arcade` masks:
## otherwise the test would compare the table with itself (ADR-0028).
func test_doors_per_floor_follow_the_rom_map() -> void:
	var expected: Array[int] = [
		0,
		2,
		2,
		2,
		2,
		2,
		2,
		0,
		6,
		6,
		4,
		4,
		5,
		6,
		7,
		5,
		5,
		4,
		6,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
		4,
	]
	for rom: int in expected.size():
		assert_eq(Arcade.doors_on_floor(rom), expected[rom], "ROM floor %d" % rom)


## Red doors 5, 6 … 10 by skill, does not grow above eight (@27D2).
func test_red_doors_grow_with_skill_up_to_ten() -> void:
	var expected: Array[int] = [5, 6, 7, 8, 9, 10, 10, 10, 10, 10, 10]
	for skill: int in expected.size():
		assert_eq(Arcade.red_doors(skill), expected[skill], "skill %d" % skill)
	assert_eq(Arcade.red_doors_in_band(7, 0), 0, "in the first building the top is empty")
	assert_eq(Arcade.red_doors_in_band(0, 8), 5, "on the eighth the bottom is five")


## Dark floors are 11–15 and only those (@2719, @56A1).
func test_dark_floors_are_eleven_to_fifteen() -> void:
	for rom: int in range(1, Arcade.FLOORS + 1):
		assert_eq(Arcade.is_dark_floor(rom), rom >= 11 and rom <= 15, "ROM floor %d" % rom)


## Our count is from the top, the ROM's from the bottom; a different height stretches the map
## without going beyond its edges.
func test_rom_floor_counts_from_the_bottom() -> void:
	assert_eq(Arcade.rom_floor(0, 30), 30, "our top is the thirtieth")
	assert_eq(Arcade.rom_floor(29, 30), 1, "our bottom is the first")
	var previous := Arcade.FLOORS + 1
	for index: int in 6:
		var rom := Arcade.rom_floor(index, 6)
		assert_between(rom, 1, Arcade.FLOORS, "six-floor building: floor %d" % index)
		assert_lt(rom, previous, "the ROM number decreases going down")
		previous = rom


func test_the_building_bonus_stops_growing_at_the_tenth() -> void:
	# @5793: 1000 × min(10, …). Without a cap the bonus would grow forever, but in the arcade the
	# hundredth building pays as much as the tenth.
	assert_eq(Arcade.building_bonus(1), 1000)
	assert_eq(Arcade.building_bonus(3), 3000)
	assert_eq(Arcade.building_bonus(10), 10000)
	assert_eq(Arcade.building_bonus(11), 10000)
	assert_eq(Arcade.building_bonus(40), 10000)


func test_an_agent_left_behind_goes_home_only_where_rom_lets_him() -> void:
	# @041F: 80 px is two floors of 48; ROM floor from the eighth. "Except the twentieth" from the ROM
	# is not taken — see the comment on Arcade.LEAVE_FROM_FLOOR.
	assert_false(Arcade.agent_leaves(12, 1), "a floor is 48 px, less than 80")
	assert_true(Arcade.agent_leaves(12, 2), "two floors — 96 px")
	assert_true(Arcade.agent_leaves(12, -3), "above or below — no matter")
	assert_false(Arcade.agent_leaves(7, 5), "below the eighth they do not leave")
	assert_true(Arcade.agent_leaves(8, 2), "the eighth — already yes")
	assert_true(Arcade.agent_leaves(20, 5), "the twentieth is no exception here")


## Bullets three times faster than the ROM — for both sides (ADR-0037, decision 5): Otto's ~27 m/s,
## the agent's from ~20 to ~27. The ROM table under the multiplier is the same.
func test_bullets_fly_three_times_faster_than_the_rom() -> void:
	assert_almost_eq(Arcade.bullet_speed(Arcade.OTTO_BULLET_PX), 26.6, 0.1, "Otto bullet")
	assert_almost_eq(
		Arcade.agent_shot_speed(0, false), Arcade.agent_bullet_speed(0, false) * 3.0, 0.001
	)
	assert_almost_eq(
		Arcade.agent_shot_speed(40, true), 26.6, 0.1, "agent — not above Otto's bullet"
	)


## An agent notices a bullet three times farther away and so dodges in the same time as in the ROM:
## 20 px at 8 px per tick is two and a half ticks (@05F5).
func test_the_dodge_window_keeps_the_rom_time() -> void:
	var window := Arcade.dodge_reach() / Arcade.bullet_speed(Arcade.OTTO_BULLET_PX)
	var rom := Arcade.seconds(Arcade.DODGE_REACH_PX / Arcade.OTTO_BULLET_PX)
	assert_almost_eq(window, rom, 0.0001, "time to dodge — as in the ROM")
