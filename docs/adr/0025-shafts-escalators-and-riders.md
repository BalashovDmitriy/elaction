# ADR-0025 · M18b: escalator as a structure, shaft light, double-deck pair, agents in cabs

- **Status:** accepted
- **Date:** 2026-09-22

## Context

M18b is the second half of the geometry milestone ([ADR-0024](0024-building-geometry.md),
decision 10). The first, M18a, is merged into `main` (PR #30): slot grid, threshold silhouette,
overlapping shafts, escalators as a band, interior walls and bot pathfinding over the building
graph. The layout is ready and checked; M18b touches look and movement, not reachability.

ADR-0024 was written for both halves, but its decisions about the second — 6, 7 and 8 — were made
before the check done right before M18b. The check corrected them, and the corrections are recorded
here.

### What the check showed

- **The original has two double-deck shafts, not one.** Elevator World: *"two shafts
  featured a kind of double-decker elevator"*. ADR-0024, decision 6 says "no more than one per
  building" — this is a divergence, and it is corrected.
- **Agents in the original ride in cabs but do not control them.** *"When Agent 17
  is in an elevator, he will have complete control of it… When Otto is not in an
  elevator, it will move from floor to floor automatically, even when enemy
  spies are in it."* That is, "an agent in the other deck" is not an invention of ADR-0024 but the
  original's behaviour, and it is arranged more cheaply than it seems: the agent is a passenger, not
  a dispatcher.
- **Escalators: two each on 17–20 and one on 16** were confirmed again: the band laid out in M18a
  landed correctly.
- **The cab doors open on two sides** — confirmed again. They are still not in the milestone: our cab
  has no doors at all, Otto enters from the side.
- **In the original the cab crushes agents** — as a separate scoring technique. We crush only Otto
  (`ElevatorCar._crush_those_underneath`). The divergence is recorded but not taken into M18b: it is
  a combat and scoring rule, and its place is in M18d next to the other numbers
  ([ADR-0016](0016-combat-balance.md)).
- **The light column in the shaft is not confirmed by the original in any way.** It is our debt from
  M12 ([ADR-0017](0017-spectrum-palette-and-shafts.md), decision 3) and our decision — and it is
  recorded as such.

### What the code showed

- **There are twelve shafts per building** (seed 1, `tools/dump_plan.gd`), from three to fourteen
  floors long. Candidates for a double-deck pair are those in the podium: there are up to five shafts
  per floor there.
- **Agents do not use elevators at all.** In all of `src/`, `ElevatorCar` knows only Otto, and
  `EnemyBrain` says so directly: "It still cannot ride the elevator, this has been postponed since
  [ADR-0006](0006-combat-and-enemies.md)". There was nothing to fulfil ADR-0024's promise "an agent
  may ride in the other deck" with.
- **The escalator is two belt boxes** (`Escalator._lay_belt`). There is no balustrade, steps, pads
  or framing of the opening.
- **There is no light source in the shaft.** `BuildingShafts` places guide rails, floor doors and
  buffer stops; only floor lamps and cab indicators give light.

## Decisions

### 1. Up to two double-deck pairs, in every building where there is room

ADR-0024, decision 6 is amended in two numbers and kept in its essence.

| | ADR-0024 | Here |
|---|---|---|
| Pairs per building | no more than one | **up to two** |
| How often | about one building in three | **in every one where there is room** |
| Where it is placed | a shaft that has another path on each of its floors | unchanged |

Two — because that is how many the original has. "In every building" — because "one in three" was a
chosen number, not measured and not confirmed by the original, and its cost is high: most games
would never see the curiosity, and checking it would require picking seeds.

**The placement condition is not relaxed.** The pair travels a shortened range and takes one floor
more; were such a shaft the only one on its floors, the descent could get stuck. It is placed only
where each of its floors has another path — a neighbouring shaft or an escalator.

**No candidate — the building stays without a pair.** "In every building" reads as "always when there
is room": the safety of the descent matters more than guaranteeing the curiosity. How frequent this
case is, is answered not by reasoning but by a test: it measures the share of seeds with a pair and
keeps it high, not equal to one.

### 2. The minimum shaft band is four floors

`BuildingRules.MIN_SHAFT_FLOORS` goes up from three to four: a pair of decks takes two floors, and in
a three-floor shaft it is left one move.

This **changes the layout of all buildings**, not only those where a pair came up: `shafts_on` ends
the growth of the number of paths one floor higher (`last = floors - MIN_SHAFT_FLOORS`), and the
shortest podium shafts disappear. So the bot run is re-measured entirely, and the death scale
([ADR-0016](0016-combat-balance.md), item 8) is set anew.

The cost is recorded here in advance. The second way — keep the minimum at three and just not place a
pair into short shafts — is cheaper by exactly this re-measurement, but leaves in the rules a shaft
into which half of the milestone's decisions do not fit.

### 3. The light column in the shaft is a real source, not emission

The shaft gets its own source for its full height, not a self-illuminated material.

Emission without a source is cheaper and solves half the problem: the shaft is visible. But on a
darkened floor it then hangs as a glowing strip in the blackness — the light falls neither on the
guide rails, nor on the doors, nor on the floor in front of the opening, and "the way down is here"
reads worse than a lamp that is no longer there. Light on relief is what the pivot was undertaken
for ([ADR-0019](0019-3d-pivot.md)).

**The source does not go out from a shot and does not take part in darkness zones**
([ADR-0023](0023-light-and-readability.md), decision 2). Darkness decides whether agents see Otto;
the shaft decides whether the player sees the way. These are different questions, and they do not
need a common switch: a darkened building must stay traversable by eye.

**The cost is measured, not assumed.** `tools/light_bench.gd` computes GPU time per frame; the budget
is 16.6 ms, 2.0 used at M17. The wide podium floor must be measured — there are up to five shafts per
floor there. If it does not fit, the first sacrifice is the shadow from this source: in the shaft it
shows almost nothing and costs more than everything else.

### 4. The escalator is built as a structure

The two belt boxes are replaced by a balustrade, steps in relief, upper and lower pads and a framing
of the opening. The steps are relief, not animation: decision 8 of
[ADR-0024](0024-building-geometry.md) is in force.

The ride mechanic is not touched: stand on the pad and press "up" or "down"
([ADR-0004](0004-elevator-mechanics.md), item 8), the escalator controls the passenger's position,
the path goes through the bend in the opening.

### 5. The balustrade is asymmetric: the far one solid, the near one a low guard

The camera looks from the side and slightly from above ([ADR-0023](0023-light-and-readability.md),
decision 1). A full balustrade on the camera side would cover a riding Otto up to the chest — and on
the escalator he is defenceless: input does not act, there is no way to dodge, and the ride lasts
more than a second.

So at the back wall the balustrade is full, with a handrail, and on the player's side there is a low
board right at the belt. The same choice as with the M18a wall: arcade readability matters more than
plausibility ([ADR-0019](0019-3d-pivot.md)).

### 6. Agents ride in cabs but do not control them

The debt from [ADR-0006](0006-combat-and-enemies.md) is closed — and closed exactly the way the
original is arranged.

- **The cab obeys only Otto.** It counts as occupied when he is inside; an agent inside is a
  passenger, and with him the cab goes by itself from floor to floor, like an empty one.
  `ElevatorMotion.update` already distinguishes the cases this way, the rule need not change.
- **An agent boards when the cab stands level with his floor**, and gets off on the one where he has
  something to do. He does not call the cab: nobody has a call button, including the player.
- **The live-agent cap and the ban on releasing right next to Otto do not change**
  ([ADR-0016](0016-combat-balance.md)). Riding adds reach to agents, not numbers.

**The level decides, not the agent.** Which cab stands level with his floor and where it leads is
known only to the level: it is also what hands out darkness and walls to agents every frame
(`_shroud_agent`). The agent receives one number — the cab's axis or NAN — and he cannot walk the
building graph; that remains the bot's privilege.

**The offer is sticky, and the nearest of the suitable ones is taken.** On a podium floor there are
up to five shafts, cabs come level and leave each in turn. While the offer was recomputed from
scratch every frame, an agent turned back and forth between two cabs and did not move from the spot
for half a minute.

**At the opening the agent waits rather than turning around.** The M17 rule "seeing Otto, the agent
stops at the edge; having lost him, turns around" does not fit someone walking to a cab: having
turned around, he immediately forgets why he was going. A departed cab leaves him standing at the
opening — and this is not waiting for a call but the same "I board the one that is standing", just
with a pause.

**What must not be done: gating on "sees Otto".** The first attempt let the agent go to the elevator
only while he did not see Otto. But `sees_target` means "Otto is not in shadow and not behind a
wall", not "Otto is within shooting distance": ten floors away it is also true, and elevators almost
never came into play.

This is the largest part of the milestone and the only one that moves combat. So it goes **last**:
the layout changes with decision 2, and there must be one re-measurement of the bot run, not two.

### 7. Two debts of the milestone are closed along the way

Both are recorded in `docs/STATUS.md` and both get in the way of exactly this milestone.

- **The combat run on seed 1 does not repeat** (the test gives 4–5 deaths, the tool on the same
  seed — 2, diverging from the first step). Decision 2 forces the death scale to be set anew, and it
  cannot be set on a non-reproducible seed.
- **`_moves` and `_links` in `BuildingRoute` are two counts of one graph.** Postponed in M18a as "not
  at the end of a milestone"; agents in cabs add a third reader to the graph, and a divergence of the
  counts would become more expensive than merging. The merge must keep the speed: `is_winnable` is
  called about ten times per building.

## What is not in the milestone

- **Cab doors on two sides.** The check names them again, but our cab has no doors at all.
- **Moving steps.** Relief — yes, belt animation — no.
- **Agents crushed by the cab.** The original has it, we do not; it is a combat and scoring rule —
  M18d.
- **Calling the cab by anyone.** Neither the agent nor the player is given it in the original.
- **Floor dressing** — M19.

## How we check

- No more than two double-deck pairs per building, and each has another path on all its floors — on
  hundreds of seeds.
- **A pair does not cut off a single floor piece.** The threshold is stricter than for a wall: for a
  wall `is_winnable` is enough — it watches documents and the exit — while a pair must leave reachable
  exactly what was reachable without it. Checked by counting reachable nodes before and after.
- The pair's travel range keeps both decks inside the shaft: the upper does not go above the top
  floor, the lower does not go below the bottom.
- The share of seeds where a pair came up is measured and recorded — as a number, not a word.
- A shaft band is nowhere shorter than four floors, and the number of shafts per floor still matches
  the rules' target on every floor.
- The bot completes the building on any seed, and the death scale is set anew, after decision 2 and
  after agents in cabs.
- A test run and a `tools/playthrough.gd` run on the same seed match step for step — including
  seed 1.
- An agent who has entered a cab does not control it: with him the cab follows its own schedule.
- The frame budget with light columns in the shafts is under 16.6 ms on a wide podium floor.
