# ADR-0009 · Game loop, alarm and difficulty growth

- **Status:** accepted; item 2 replaced — building difficulty and agent anger by ROM
  ([ADR-0027](0027-rom-combat.md), decision 1), agents dodge since M11
  ([ADR-0016](0016-combat-balance.md)); time to alarm is 277 s instead of 300 from
  item 5 ([ADR-0027](0027-rom-combat.md), decision 7)
- **Date:** 2026-09-12

## Context

M5b is the second half of the split milestone M5 (see [ADR-0008](0008-building-generation.md)).
The building is already assembled by generation; here comes what ties buildings into a session:
the transition between them, the timed alarm and increasing difficulty.

The check was done before M5 as a whole, so this records decisions. Taito's manual is still
unavailable, and three numbers have to be taken by eye — they are listed below.

## Decisions

### 1. The alarm turns on after a fixed time per building

No source gives the trigger moment. A constant time per building is taken, the same for all,
moved into a parameter: after a check in MAME one number will need changing, not the mechanic.

The alarm behaviour itself follows the original, in full:

> If Otto takes too much time to clear a level, an alarm will sound; the enemy agents
> then become more aggressive, and the elevators will be slower to respond.

> The alarm does not go off when the player loses a life, it only resets after
> finishing a building.

**Death does not clear the alarm.** It is a penalty for the whole run through the building, not
for an attempt, and the only thing limiting the point farm on a darkened floor — mentioned
in [ADR-0007](0007-lamps-and-darkness.md), item 3.

### 2. From building to building, agents get angrier and more numerous

The sources name three ways difficulty grows: agents shoot more often, the elevators lower down
are more tangled, and in later buildings agents lie down on the floor, making them almost
impossible to hit.

Only the first is taken. It is expressed by numbers in the already finished `EnemyBrain` and
the building rules — range, pause between shots, how often a door releases a new one — that
is, it is tested and requires no new mechanics.

The other two are recorded as not done: tangled shafts are generation rules, and lying agents
are a new behaviour and a new pose; both amount to separate work.

### 3. Building bonus — 1000 × number

The decision was made in [ADR-0008](0008-building-generation.md), item 5, and is only
implemented here. The sources disagree: one gives a flat 1000, another a multiplier.
**Not checked.**

### 4. Pause — not an original mechanic, but needed

The arcade has no pause: there you pay a coin per game. Esc currently just closes the game,
which is inconvenient both in development and for the player.

Esc pauses the game and shows a hint: continue, restart or quit. The real menu is in M8; here
only the mechanic, so as not to breed UI that will be thrown away.

The alarm does not run while paused: otherwise pausing would cost the player the building.

### 5. Time to alarm — 300 s, temporarily, until live play

*Addendum of 2026-09-22, milestone M18a.*

The hundred seconds of item 1 were set when the descent was greedy: the bot took the nearest
shaft and went down. The M18a layout reversed that — shafts overlap, a floor can be cut by a
wall and an open opening, and the route is built over the reachability graph, that is, it
consists of transfers and sometimes even a climb.

Measurement with `tools/playthrough.gd` on five seeds, without combat: **5352–6773 frames, that
is 89–113 s**. With a hundred-second limit the siren managed to turn on before the end of a
flawless run on four seeds out of five. And this is not cosmetic: the siren adds a delay to all
cabs (`GreyboxLevel.ALARM_CAR_DELAY`) — exactly what the descent now consists of. It formed a
loop: longer route → siren → slower cabs → even longer.

**Decision: 300 s, and this is a temporary number, not measured balance.** The measurement gives
a lower bound (the bot does not dawdle, but does not explore the building either); the upper
bound would come from live play, which has not happened yet. The margin is taken in excess
deliberately: the milestone has already made the run harder, and extra time pressure during
combat measurements would only muddle the picture. The number is refined after a human plays
through the building.

**The cost of the margin.** At five minutes the siren does not turn on at all in a normal
session. So until crouching has a cost (open question No. 7, parked by milestone M16a),
nothing punishes sitting it out: no shot hits a crouching Otto, and the siren was the only
thing preventing it.

## What remains unchecked

| Question | How to close it |
|---|---|
| After how long the alarm turns on | MAME, frame-by-frame measurement |
| Building bonus: 1000 or 1000 × number | MAME |
| How much exactly the elevator "responds slower" during the alarm | MAME |

## What remains not done

- **Shafts do not get more tangled in later buildings**, although they do in the original.
  These are generation rules, and they must change together with the traversability check.
- **Agents do not lie down on the floor.** The mechanic was found in the check before M5 and
  was not in the epic; it is a new behaviour and a new pose, work for a separate milestone.

## Consequences

- **A session appears, not a level.** `GameState` starts storing the building number and seed,
  and `main` rebuilds the level on transition. Until now there was one level per launch.
- **The alarm is the first session state that changes the behaviour of finished systems.**
  It touches both agents and the elevator cab, that is, M2 and M4a.
- **Pause requires separating what freezes and what does not.** Pause input must work while
  paused, and the alarm must not.

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Elevator Action — Video Game History Wiki](https://videogamehistory.fandom.com/wiki/Elevator_Action)
- [Elevator Action — Codex Gamicus](https://gamicus.fandom.com/wiki/Elevator_Action)
