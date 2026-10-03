# ADR-0053 · Open questions and debt: check against the ROM and cleanup

- **Status:** accepted
- **Date:** 2026-10-02
- **Extends:** [ADR-0004](0004-elevator-mechanics.md) (item 6 — the player's cab),
  [ADR-0010](0010-lighting-and-atmosphere.md) (item 7 — darkness difficulty),
  [ADR-0020](0020-agent-doors.md) (release at a door),
  [ADR-0023](0023-light-and-readability.md) (decision 8 — shadow),
  [ADR-0027](0027-rom-combat.md) (combat per the ROM),
  [ADR-0051](0051-time-of-day.md) (facade atlas),
  [ADR-0052](0052-day-for-the-rest-and-arrival.md) (rotor downwash)

## Context

After M24k `docs/STATUS.md` had three open questions and a dozen debt items. Questions
4 and 9 depended on rules that were not in our notes on the ROM disassembly
(`docs/reference/arcade-rom.md`), question 8 — on the bot being unable to shoot out
lamps and so unable to check darkness.

**Check against the ROM** (2026-10-02, the same jotd666/elevator_action disassembly):

- **The player's cab** does not stop between floors. The up-down button only sets the
  direction; a released cab goes on until it is level with a floor (@5E1E), stands
  there 30 ticks and moves on by itself (@5E2B). The ROM has no "stop" command.
- **Return after death** (@7633, @2FAA, @2F44-2F6F): the floor is the same, but not
  lower than the fifth; the place is at the floor's red door if the document is not
  taken, otherwise the fixed point $67. No agents remain: all four slots are empty and
  release again after 10, 25, 40 and 55 ticks. There is no invulnerability — the hit
  check (@08F8) does not know the timer. Cabs are placed anew.
- **Release near Otto** (@5AAB): there is no check of the distance from the door to
  Otto. The agent is separated only by the time it takes to leave the door, 9–17 ticks.
- **The twentieth floor** (question 9): it is divided by a wall at $AC, not in the
  middle. The ROM looks for the nearest door to leave through on its own half of the
  floor (@049F, split at $7B), and on the twentieth an agent would be sent to a door
  behind the wall — that is why the floor is excluded.
- **Crowd** — a rule we did not have: if three or more agents stand on Otto's floor,
  above or below, the agents of that floor leave through doors (@041F-0458). In our
  notes it was written the other way round — "on the floor, except a crowded one".

## Decisions

Questions asked of the user on 2026-10-02, in two blocks.

1. **The player's cab goes on to the floor.** Released, it goes to the next floor in
   its direction and stops there, as in the ROM; it does not move on by itself — this
   is ours, in the arcade the cab started off without the player after 2 s (the user's
   choice: it is easier to control this way). The `stops_between_floors` switch and the
   "the cab was driven by a passenger" flag (ADR-0037, decision 1) are removed: the cab
   no longer stops between floors anywhere. Item 6 of ADR-0004 is closed by this.
2. **Return — per the ROM, invulnerability — ours.** The floor is no lower than the
   ROM's fifth floor ([`RespawnSpot.floor_for`](../../src/levels/respawn_spot.gd)), the
   place is at the red door with a document, and without one — the spot nearest to the
   fraction $67/256 of the floor width, not in a pocket shorter than 3 m (the M24g
   pocket, seed 3). All living agents leave, the slots release again after 10, 25, 40
   and 55 ticks (`AgentSpawn.after_death`). Corpses stay until the end of the building,
   as since M24a. The 1.5 s invulnerability after return is kept (the user's choice).
   Cabs are not re-placed: in the ROM this is a consequence of the screen redraw, while
   in ours the cab Otto was riding simply stays where it was.
3. **Release near Otto — no closer than 1.2 m.** First the `AGENT_SAFE_RELEASE` ban
   (2.88 m) was removed, as in the ROM — and the combat test at skill 0 went red: seed 1
   cost 9 deaths, seed 3 — 13 with a threshold of 5, and almost every one was next to an
   agent that had just come out a meter from Otto. Measurement `playthrough.gd
   --release-gap` on seeds 1–3: 0 m — 11 deaths, 1.2 m — 4, 2.88 m — 10. The user chose
   1.2 m (`BuildingRules.agent_release_gap`, 2026-10-02). The door leaf telegraph also
   stays (ADR-0020): an agent comes out only when the door has opened. With 1.2 m the
   combat test gives 1, 4 and 6 deaths; seed 3 was already at the threshold of 5 before,
   and the `DEATHS_ALLOWED` threshold is raised to 6 by measurement (the user's
   decision).
4. **The bot shoots out lamps, the shadow distance — by measurement.** A lamp can be
   shot out only from a cab (`test_a_lamp_is_out_of_reach_from_the_floor`), and the bot
   shoots at a hanging lamp in front of it when the barrel of the riding Otto is at its
   height ([`OttoBot._lamp_in_line`](../../src/actors/otto/otto_bot.gd)). A run of a real
   building checks that lamps fall. The measurement is below, in "Shadow measurement".
5. **A crowd leaves through doors** (@041F-0458). On Otto's floor, above and below, from
   ROM floor eight: of three or more agents standing on the floor the two nearest to
   Otto stay, the rest go to the nearest reachable door (`Arcade.crowd_leavers`,
   [`AgentCrowd.extras`](../../src/levels/agent_crowd.gd)). Those coming out of a door
   and those riding in a cab do not count. In the ROM all agents of an overcrowded floor
   leave; in ours — only the extra ones: otherwise a floor would empty at once because of
   one extra. One already heading to a door keeps leaving, even if he becomes one of the
   nearest on the way: the count runs every frame, and without this the leaving would
   pass from agent to agent.
6. **We do not exclude the twentieth floor.** Our search for a door to leave through
   ([`AgentLifts.nearest_door`](../../src/levels/agent_lifts.gd)) already takes only a
   reachable door — what the ROM ensured by excluding the twentieth. Question 9 is
   closed.
7. **A lamp does not swing after a shot** (the user's choice): a shot-out lamp falls
   immediately, as since ADR-0007. The item is struck from the debt.
8. **Darkness does not weaken with skill** (the user's choice). In the ROM darkness does
   not affect agents at all, ours is a deliberate divergence (ADR-0027, decision 9), and
   the same in all buildings. ADR-0010, item 7 — closed.
9. **Mipmaps — only for text in the scene.** Plaques, indicator boards, signs and garage
   markings take Exo 2 via `NeonStyle.scene_font` — a copy of the font with mipmaps; the
   HUD and menu use the previous `NeonStyle.font` without them. The font import did not
   change: enabling mipmaps there would soften the whole interface too.
10. **Shaft indicator board arrows — as geometry.** ▲ and ▼ were in neither Exo 2 nor
    the old Pixellari; they were drawn by the system fallback font. Now the arrow is a
    triangle next to the digits, and a test checks that everything the indicator board
    writes as text exists in the game font.
11. **The facade atlas with padding.** Between the style columns — 0.5 m (32 px) on each
    side, filled with a continuation of the same tile; the atlas is 1920×448, a 320 px
    column is a multiple of 64, and down to the sixth mip the neighboring style does not
    bleed onto the seam. Built by `tools/build_city.py`, the shader takes the padding as
    a parameter.
12. **Manual weather — in the building rules.** `Weather.forced` — a static field that a
    test could forget to reset — is replaced by `BuildingRules.forced_weather` next to
    `time_of_day`: each building has its own, there is nowhere to leak.
13. **The rotor downwash also drives the rain.** Under the rotor axis, while the
    helicopter hovers low, there is a particle repeller (`Downwash.gust`): rain streaks
    are blown down and to the sides, and they lie slanted — by velocity, as they are
    drawn.
14. **Not debt, but notes.** Ray tracing is an item to check on engine updates, not
    debt: it is not in Godot's main branch. The note "a new `class_name` is not visible
    until reimport" is moved to [`docs/conventions.md`](../conventions.md).

## Shadow measurement

Run `tools/playthrough.gd --agents --endless --skill=4` on seeds 1–6 (2026-10-02),
deaths per seed and in total. Taken before the no-closer-than-1.2 m release and before
the code review fixes to the bot, so it will not repeat step for step; the conclusion
is the order, not the numbers:

| Variant | Seeds 1–6 | Total |
|---|---|---|
| bot does not shoot out lamps (`--no-lamps`) | 3, 0, 27, 11, 13, 3 | 57 |
| `--dark-range=0` | 14, 3, 28, 2, 2, 7 | 56 |
| `--dark-range=1.2` | 14, 4, 28, 2, 7, 3 | 58 |
| **`--dark-range=1.8`** | 0, 4, 12, 2, 18, 3 | **39** |
| `--dark-range=2.4` | 0, 4, 17, 6, 16, 3 | 46 |
| `--dark-range=3.6` | 0, 4, 28, 6, 10, 3 | 51 |

Per building the bot shoots out 0–14 lamps of 45. The spread between seeds is larger
than the difference between variants, and the series is not monotonic: even full
invisibility in shadow (0 m) does not reduce deaths — the bot shoots out lamps but does
not deliberately hide in the dark, and the game diverges from the first different fork.
So the measurement does not pick the number precisely but checks that the chosen one is
no worse than its neighbors: **1.8 m is kept** — it has the smallest total, a third
less than without lamps. Question 8 is closed; more precise tuning would need a bot that
seeks shadow — that is no longer debt but a separate task, if darkness becomes a subject
of balance.

## Consequences

- The ROM notes are fixed: the crowd rule is written correctly, the cab, return,
  release and the twentieth floor are added.
- No open questions remain in `docs/STATUS.md`.
- The return test now checks the ROM point and the agents leaving, not "farther from an
  agent"; the new `tests/test_respawn.gd` checks the return floor and place on any
  generated building.
