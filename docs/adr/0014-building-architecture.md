# ADR-0014 · Roof, building silhouette and agent release

- **Status:** accepted; item 3 replaced by a threshold silhouette
  ([ADR-0024](0024-building-geometry.md), decision 2), item 4 by doors from the ROM map
  ([ADR-0028](0028-building-by-the-map.md), decision 2), item 5 by agent release
  by ROM rules ([ADR-0027](0027-rom-combat.md), decision 2). Everything from "What is not in
  the milestone" was done later: the rope — ADR-0017, walls and shafts of different lengths —
  ADR-0024, dark floors — ADR-0028
- **Date:** 2026-09-16

## Context

M9 closed the builds, and before the first tag the game was played through in full — by a bot,
on the real thirty-floor building rather than a test one. The run found three things that would
have made the built archive unplayable.

### The roof is squashed into a floor slab

`BuildingRules.floor_surface(0)` returned `slab_height`, and `story_top(0)` returned zero.
The clearance of floor zero came out at 20 px versus 100 px on all the others:

```
floor  0: floor y=20,   ceiling y=0,    clearance  20 px
floor  1: floor y=140,  ceiling y=40,   clearance 100 px
floor 29: floor y=3500, ceiling y=3400, clearance 100 px
```

Otto, 28 px tall by collision and 34 px by sprite, stood with his feet at y=20, that is, with
the top of his head at y=−14. The camera has `limit_top = 0`, the frame starts at zero — the
head was cut off by the screen edge from the first frame of the game. An 80 px jump took the top
of the head to y=−94, 94 px above the visible area, and the camera did not go up there.

The cause is that floor zero played two roles at once: both the roof and the top floor of the
building. The code partly knew this already: `_lay_lamps` started from the first floor with the
comment "roof, nothing to hang a lamp on", `_build_back_walls` also from the first. But
`_lay_doors` went from zero, and two doors stood on the roof in the open sky.

### The building cannot be completed with agents

`_ready()` released agents from all agent doors at once: 60 doors, 5 red, 55 agents, alive
simultaneously and permanently — a door replaced a killed one after three seconds. Two of them
stood on the roof, 131 px from the start point with a `fire_range` of 200 px. Otto appeared
already inside the fire zone, and respawn brought him back to the same spot.

Bot run on seeds 1, 2 and 3: three deaths on floor zero within 64–113 frames, game over, zero
documents, not a single floor down. Without agents the same seeds complete in full in ~5000
frames.

### The building is uniform, but the original is not

Check against available sources:

- **Floors 30–21:** one central elevator, two doors on each side.
- **Floors 20–17:** escalators left and right. **Floor 16:** escalator on the right only.
- **Below:** a "maze of elevators", walls dividing the floor in halves, dark floors.
- Shafts of different lengths: 19–30 is twelve floors, below they go by three.
- Otto gets onto the roof **by sliding down a rope** and only then enters the elevator.
- The top of the building is described as narrow; toward the bottom it widens and gets more
  tangled.

We had five shafts of exactly six floors each, all floors the same width, two doors and one
lamp everywhere, an escalator strictly at every band junction.

A caveat about width: the wording "starts narrow at the top and widens toward the bottom" comes
from two independent reviews, but these are secondary sources, and they describe a gradient of
traversable width and difficulty rather than a literally narrowing silhouette. Direct quotes
confirm only that the building is **non-uniform in height**. The decision below was made with
this knowledge: the silhouette is chosen as a readable embodiment of the confirmed
non-uniformity, not as a reconstruction of the original's pixels.

### Why this survived to release

Not one test assembled the building the player plays in, and not one enabled agents:

| Test | Floors | Agents |
|---|---|---|
| `test_building_playthrough` | 4 | off |
| `test_building_assembly` | 8 | off |
| `test_sprite_assets` | 6 | off |
| `test_exit_car` | 4 | off |

241 tests were green while the game could not be completed. The milestone requirement "check
any building that gets generated" was met formally: the building checked was one that never
occurs in the game.

## Decisions

### 1. The roof is a separate level with index −1

The roof stops being floor zero and becomes its own level above the building.
Constant `BuildingRules.ROOF = -1`. Building floors stay 0…`floors-1`.

Coordinates are computed by one formula, and the roof enters it as `index = -1`:

```gdscript
func floor_surface(index: int) -> float:
    return sky_height + floor_height * float(index + 1)
```

With `sky_height = 160` the roof lies at y=160, floor zero at y=280, and all levels have the
same clearance — 100 px. `story_top(ROOF)` is zero: above the roof is sky, not a slab. Otto
stands with the top of his head at y=126 and in a jump goes to y=46 — both times inside the
frame.

There is more sky above the roof than a floor takes, on purpose: at 120 px the top of the head
at the top of a jump passed six pixels from the edge, and the jump read as hitting the head on
the edge of the screen.

Why not "just give floor zero clearance": the roof in the original is a place, not a utility
offset. Otto descends onto it by rope, and there are no doors or agents on it. A separate index
makes this a generator rule rather than a set of `if index == 0` checks scattered through the
code — and there were already three of them.

### 2. The roof has no doors, lamps or agents, but has an elevator

Doors and lamps are laid out over `0…floors-1`; the roof is not in the range.
A lamp was not hung on the roof before either; now this follows from the rule rather than a
separate check, and floor zero finally gets a lamp — it now has a ceiling.

The top shaft is extended to the roof: in the original Otto "enters the building in the
elevator", that is, the elevator comes to the roof. This is the only opening in its deck.

### 3. Silhouette: the building widens downward in steps

The profile is set not by width but by the number of available slots, and the width is derived
from them. The reverse order — width, and slots from it — produced floors with fewer slots than
needed: a shaft, two doors and a lamp require four.

- `width_steps = 3` — three steps of the silhouette.
- `top_slots = 5` — slots at the narrowest level, with `slots = 9` at the bottom.

Slots are available symmetrically from the middle, so the count is always odd: 5 → 7 → 9.
Floor bounds are derived from the outermost available slots plus `margin`, so the width goes
720 → 1000 → 1280 px. Thirty-one levels are divided evenly among the steps, and this fits the
original: the top third is simple, the bottom is the widest.

Slots are numbered globally and stand at the same x over the whole height. Otherwise a shaft
passing through several floors would end up in a different column on each. Width only grows
downward, so a slot available on the top floor of a band is available on all floors below it —
that is what keeps the shaft together.

The slab is then wider than the walls of its level: it is both the floor of its storey and the
ceiling of the one below, and the one below is a step wider. Slab bounds come from `slab_span`,
wall and floor-piece bounds from `floor_span`. Without this distinction there was open sky inside
the building above the outer strip of the lower floor, and a lamp landing on an outermost slot
there would hang on nothing at all. The ledge is not walked on — it is outside the walls of its
level — so the reachability graph counts pieces by `floor_span` and does not depend on
`slab_span`.

### 4. Fewer doors at the top than at the bottom

By the same step as width: `top_doors` on narrow levels, `doors_per_floor` on wide ones. The
sources describe the top as sparsely populated and the bottom as cramped and mean; before the
milestone doors were spread evenly over the whole height, and the descent started with the same
density of fire it ended with.

A side effect is arithmetical: a narrow level has only five slots, and a shaft, doors and a lamp
have to be placed. With the old density the layout hit the ceiling on every top floor.

### 5. Agents are released near the player

`_ready()` no longer releases anyone. A door releases an agent when its floor enters the band of
visible floors and removes him when the floor has gone far away. The selection is the same
`VisibleFloors` that already turns off the light (ADR-0010, item 8).

A handful of agents stay in the frame instead of 55 across the whole building. This is closer to
the original, where agents come out of doors as the descent progresses, and removes the constant
load of 55 bodies with physics and AI.

No invulnerability pause at the start: the roof is empty, and the player will approach the first
agent on his own.

### 6. Returning to play — with a breather and away from the killer

The run found a death loop: Otto returned to the same spot where he died, and the agent who
killed him had not gone anywhere and stood in his fire zone. The second death came a quarter of
a second after the first, and three lives burned on one patch.

Hence two changes, both about returning, not about combat:

- **The spot is chosen by live agents:** of the free spots on the floor, the farthest from them
  is taken. On an empty floor the choice degenerates into the former "first free".
- **A second and a half of invulnerability**, and Otto blinks during it. The invulnerability is
  shared across all causes of death: being revived under a cab is as frustrating as under a
  shot.

A consequence accepted deliberately: a fall into a shaft that starts during the breather is one
Otto survives. The shaft bottom is a `body_entered`, and on an invulnerable Otto it fires for
nothing; it re-arms on the next entry, so the hole is limited to one fall per death rather than
staying forever. Fixing it would mean making exceptions to the invulnerability, and it is needed
precisely as a rule without exceptions.

The original's respawn rules could not be found — they are marked for checking both in ADR-0006
and in open question No. 4. A second and a half is taken as a usual arcade breather, not
confirmed by the original.

### 7. The run on the real building moves into tests

`tools/playthrough.gd` — a bot run on the building the game assembles — is exactly the check that
was missing. It becomes a test, and the playthrough test runs the real rules, not four floors.

The small buildings are not removed from the tests: they are fast and catch something else —
degenerate layouts. The real one is added.

## What the milestone did not close: combat on narrow floors

The milestone DoD was intended as "the bot completes the real building with agents enabled".
It **was not reached**, and here is what is known about it for certain.

- **The building is traversable:** the bot completes the real thirty floors on five seeds out of
  five, collecting all five documents — but with agents off.
- **The start is fixed:** with agents, Otto now survives the start doing nothing.
  Previously the game ended on the roof within 64–113 frames.
- **Further on the bot runs into combat.** With agents enabled and unlimited lives it reaches the
  fifth floor and gets stuck there: an agent takes a position at 130 px, Otto returns to play,
  walks to the escalator and loses the duel — again and again.

Whose fault this is — the game's or the bot's — the milestone does not decide, on purpose.

**The bot cannot dodge.** It walks and shoots, but does not crouch or jump, and per ADR-0006,
item 3, crouching and jumping are exactly how bullets are dodged: a bullet has its own flight
height. So the bot loses duels a player would win, and "the bot did not make it" does not prove
"the game cannot be completed".

What to do about it is a balance question: agents' range and rate of fire, their density at
doors, the length of the breather. This is a separate decision and a separate check, and quietly
tweaking numbers while fixing geometry is a sure way not to know what exactly helped. So the
milestone DoD is reduced to what it actually proves, and combat is moved to the next one.

## Consequences

- `floor_surface` changes its origin, and all building coordinates move with it. Everything that
  computed y by floors is recomputed through the same rule methods.
- The level index stops being non-negative. Lists that were indexed by floor number switch to
  dictionaries: `Array[-1]` in GDScript takes the last element, and such access stays silent
  instead of failing.
- Floor width stops being a building constant. `slab_segments`, back walls, windows, light bands
  and the reachability graph take the floor bounds.
- The building gets no more expensive in node count at the top levels than it was: narrow floors
  are shorter, and there are fewer agents in the frame.

## What is not in the milestone

- **Interior walls dividing the floor in halves.** The original has them, but they bring a
  separate reachability-graph pass and rules for placing elevators on both sides of the wall.
  Separate work.
- **Shafts of different lengths by height.** The original has one long one at the top and short
  ones at the bottom. The rule is simple but changes the pace of the whole descent and requires
  its own check.
- **Dark floors as part of the layout.** Currently a floor goes dark only from a shot-down lamp.
- **The rope descent as an animation.** There is a roof, but no rope: Otto appears on it
  standing. This is an intro shot, not a mechanic.

## Sources

- [Wikipedia · Elevator Action](https://en.wikipedia.org/wiki/Elevator_Action)
- [XP Arcade · Elevator Action](https://retroxp.beehiiv.com/p/xp-arcade-elevator-action)
- [StrategyWiki · Elevator Action](https://strategywiki.org/wiki/Elevator_Action/Walkthrough)
  — itself behind Cloudflare, quotes taken from search results
- [retroarcadia · My Life With… Elevator Action](https://retroarcadia.blog/2023/03/22/my-life-with-elevator-action-in-the-arcade-and-beyond/)
