# ADR-0021 · 3D greybox: play plane, room depth and order of the move

- **Status:** accepted; the 2D cleanup from decision 6 was done not in M20 but in M22
  ([ADR-0030](0030-grading-and-quality.md), decision 8). The window check that
  "How we check" postponed did not come back: there are no windows in the building walls, the city
  behind it is a separate scene
- **Date:** 2026-09-20

## Context

M15 is the first milestone of the pivot. [ADR-0019](0019-3d-pivot.md) decided that we move to 3D
nodes, lock Z for game bodies and do not touch the rule core. It also left undecided what shows up
at the very first attempt to assemble the building from meshes.

The trial [`tools/look3d.gd`](../../tools/look3d.gd) placed game things **in different planes**:
the door at the back wall of the room (`-DEPTH + 0.45`, room depth 7 m), the elevator shaft by the
camera (`-1.0`). In 2D they all lie in one plane, and the difference was not visible. With Z locked
this is impossible: Otto cannot reach a door seven metres away without moving into the depth, and
ADR-0019 directly forbids moving into the depth.

A count of what is to be touched:

| | files |
|---|---|
| Touch 2D nodes: `src/` | 19 |
| Touch 2D nodes: `tests/` | 9 |
| `Vector2` as plane math, do not touch nodes | 12 |

## Decisions

### 1. There is one play plane, depth lives behind it

Everything the player interacts with stands in **one plane Z = 0**: Otto, agents, bullets, the cab,
doors, lamps, documents, escalators. Nothing gameplay-related shifts along Z by even a centimetre —
otherwise "reached it or not" stops being a property of the rules and becomes a property of mesh
placement.

Depth comes not from spreading game objects apart but from the structure of the room:

- **The corridor** in the play plane, shallow (about 2 m). Everything happens in it.
- **The back wall of the corridor** carries doors, windows and shaft doors. A door is an opening in
  this wall, and its threshold lies exactly in the play plane.
- **The room volume behind the wall**, up to 7 m, as in the trial. It is visible through the
  openings of open doors and through windows, and it is what gives depth, fog and the far plane.

Rejected: putting the game at the back wall and the room in front of it. Fog and defocus would work
at full strength, but everything standing in front would block Otto, and
[ADR-0019](0019-3d-pivot.md), decision 5, puts readability above cinema.

### 2. `Vector2` stays in the rule layer

The game is flat, and the plane coordinate is a `Vector2`. This is not a legacy of the 2D engine,
and there is no reason to change it to `Vector3` in the rules: `BuildingPlan`, `BuildingRoute`,
`BuildingRules`, `EnemyBrain`, `DocumentRoute`, `VisibleFloors` and their tests move without a
single line changed.

The conversion is done by the node layer, in one place — [`WorldSpace`](../../src/systems/world_space.gd).
If such a conversion was needed inside a rule class, the rule has crept into the presentation — and
that is a mistake, not a necessity.

**Y is flipped in the conversion, and this is no trifle.** In the rules Y grows downward:
`floor_surface` increases with the floor number, floor zero is the top one. That is how it was in
2D, and it must not be touched. In the scene Y grows upward, as in the rest of Godot: that is where
`Vector3.UP` of `CharacterBody3D` points, and that is where directional light shines from.

Flipping the sign in each node locally is the cheapest way to lose a milestone: a sign error does
not crash but quietly puts a floor upside down. That is why `WorldSpace` holds both sides of the
conversion and is covered by a test without a scene.

### 3. We convert in place, the rollback point is `main`

The 2D level does not stay alongside behind a flag. The branch `feat/m15-3d-greybox` rewrites the
node layer in place, and for the whole milestone there is no playable build on the branch.

The requirement of [ADR-0019](0019-3d-pivot.md), decision 4 — "the 2D build must keep building
until 3D has passed the bot" — is met by `main`: M14 is there, it builds and plays. The branch is
merged only after the DoD, that is, when the bot has completed the building in 3D.

Rejected: running both scenes behind a launch flag. There is always something to play and compare,
but the cost is half of `src/` in two copies and a double set of scene tests for the whole
milestone; and there is something to compare with anyway, `main` is at hand.

### 4. There is exactly as much light in the greybox as keeps the darkness rule alive

One source per floor, without SSR, volumetric fog, grading and depth of field — all of that is M17.
The reason is not beauty: the rule "a shot-down lamp darkens the floor permanently"
([ADR-0007](0007-lamps-and-darkness.md)) is covered by tests, and switching them off for the
milestone means losing the safety net exactly where the move is most likely to break something.

A darkened floor in the greybox differs from a lit one in the same way as in 2D — by tone, not
brightness ([ADR-0017](0017-spectrum-palette-and-shafts.md)): agents in the dark keep shooting.

### 5. Scene tests are rewritten along the way, not disabled in a block

Each system moves together with its test. Slower, but not a single day without a safety net — and
there is nothing else to catch the move breaking something: the rules did not change, so any
breakage will be in the node layer.

### 6. We throw out as things get replaced, not up front

`TiledRect`, `SpriteTextures`, `AreaLight`, `LightTextures`, `BuildingBackdrop`,
`Skyline`, `postprocess.tscn`, `tools/render_env.py` and the environment sprites go when they have
no readers left, and not a minute earlier. The order is from
[ADR-0019](0019-3d-pivot.md), decision 8; cleaning up what is left hanging — M20.

## What is not in the milestone

- **Models and animations.** Otto, agents and the car are boxes. Models in M16.
- **Materials and beautiful lighting.** One source per floor, the rest in M17.
- **Camera tilt.** The camera is strictly from the side, as in 2D. Tilt is an open question of the
  lighting milestone ([ADR-0019](0019-3d-pivot.md), decision 6), and there is nothing to tilt it
  for in the greybox: the floor is empty anyway.
- **Dressing and background.** The room volume behind the wall is empty. Filling it — M19.

## How we check

**Milestone DoD:** the bot completes the thirty-floor building in a 3D scene of grey boxes, and not
a single rule test was edited along the way.

The second condition is checked mechanically, by `git diff` over the rule layer. The classes split
into two groups, and the demands on them differ.

**The diff must be strictly empty** — these classes hold no lengths at all, everything comes from
outside: `building_plan.gd`, `building_route.gd`, `document_route.gd`,
`otto_state_machine.gd`, `shaft_hazards.gd`, `door_cycle.gd`, `door_visit.gd`,
`visible_floors.gd` and all their tests.

**The diff must be only a rescaling of constants** — these three hold default lengths:
`building_rules.gd` (building geometry and combat numbers),
`elevator_motion.gd` (`speed`, `settle_distance`, `FLOOR_EPSILON`),
`enemy_brain.gd` (`same_line`, `fire_range`, height in three stances). Division by a hundred is
[ADR-0019](0019-3d-pivot.md), decision 3: a change of unit, not a change of rule. Not a single
proportion or ratio between numbers changes, and exactly this is checked by `test_proportions.gd`,
which stays green without edits to its assertions. Nothing but dividing constants may appear in
these three files.

If the diff goes beyond these bounds — either the rule was written wrong or the move is being done
wrong, and it must be sorted out before the milestone closes.

**The milestone found one such case.** `ElevatorMotion._move_towards` counted arrival at a stop by
comparing the remainder with the frame step without a tolerance. In pixels the remainder and the
step matched to the bit, and the rule worked by luck; in metres, with stops in `float32`, the
remainder turned out a millionth larger than the step. The cab stopped a micron from the top stop —
"aligned" by `FLOOR_EPSILON` — but got no pause and turned around on the next frame. The bot on the
roof of the thirty-floor building waited for it a whole day of game time. The fix is a one-line
tolerance in the rule itself, covered by a test without a scene. This is exactly the outcome the
item was written for: the diff in `elevator_motion.gd` is larger than dividing constants, and here
it is said why.

The second thing that showed up was not in the rules but in their tests. `test_building_rules.gd`
and `test_building_silhouette.gd` set the floor height and slab, but took the sky, width and margin
from the rules' defaults. While the defaults were 480 and 3840, exact equalities held in any float;
at 4.8 and 38.4 they drifted on the last bit. The tests now set all lengths themselves — as
`test_elevator_motion.gd` did from the very beginning. The assertions are untouched.
