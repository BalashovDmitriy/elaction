# ADR-0026 · M18c: proportions after the original

- **Status:** accepted; the shot and stance heights from decision 2 are replaced by ROM numbers
  ([ADR-0027](0027-rom-combat.md), decision 3), the "known hole" of decision 5 exists in the original
  too and is removed from the debt list (same ADR, "What the check showed"); head proportions are the
  pack's ([ADR-0032](0032-actor-models.md), decision 8)
- **Date:** 2026-09-23

## Context

The elevator cab turned out to be half the height of the original's — the player noticed it, and in
M18b it was stretched over the full floor clearance (end of M18b, commit `a0edc4e`). The same check
showed that **all** building objects are too small, not just the cab, and in [EPIC.md](../EPIC.md)
milestone M18c is recorded as a choice: grow the contents or shrink the floor.

The check the plan was written from was done on a single frame and was not saved. Before the
milestone it was redone from scratch, by pixels.

### What the check showed

Two native MAME snapshots (256×224, unfiltered: `elevator` — floors 19–16, `elevatorb` — floors
30–27 with the roof) and a 1:1 sprite sheet of the arcade version. Each size was taken by counting
same-colour runs, not by eye. Fractions are of the floor clearance: 40 px for the original, 3.0 m
for us.

| | Original | Ours before the milestone |
|---|---|---|
| Floor step | 48 px | 3.6 m |
| Slab | 8 px — 20% | 0.6 m — 20% |
| Clearance | 40 px | 3.0 m |
| Cab | full floor together with slabs | full floor (M18b) |
| Otto above the floor | 22–23 px — 56% | 1.26 m — 42% |
| Otto width | 10 px — 25% | 0.54 m — 18% |
| Agent | same height, 22–23 px; narrower — 9 px | 1.17 m — 39%, **shorter than Otto** |
| Crouch to stance | 15–16 of 24 — ~65% | 0.81 of 1.26 — 64% |
| Door | 28×16 px — 70% × 40% | 1.71×0.84 m — 57% × 28% |
| Door top to ceiling | 12 px — 30% | 1.29 m — 43% |
| Shaft and cab width | 24 px — 60% | 1.2 m — 40% |
| Slot step on a floor | 24 px — 60%: door 16 and gap 8; shaft exactly a slot | 2.1 m — 70% |
| Lamp | 8×7 px, hangs from the ceiling, bottom at 33 px — 82% | centre at 1.8 m — 60% |
| Escalator | entry–exit ~32 px across by 48 up (~56°), belt ~63° | 2.88 m by 3.6 (~51°), belt ~61° |
| Floors in the frame | 176 px of building field — **3.67** | 3.0 |
| Frame width | 256 px — 6.4 clearances | 19.2 m — 6.4 clearances |

The earlier check was wrong in four places: the slab is 8 px, not 7; the clearance is 40, not 41;
**the agent is as tall as Otto**, not taller; there are 3.67 floors in the frame, not 4.7 — 4.7 is
the whole screen including the HUD and the brick strip.

Along the way, what the agent can do was rechecked. StrategyWiki: *"they walk around and
attempt to fire at Otto. They also have the capability to crouch and fire at
Otto's knees. They will wait for elevators to reach them, and they will hop on
and ride them"*; arcade-history adds that in later buildings they lie down.
**The agent has no jump in the original** — only Otto jumps. We do not have one either: `EnemyBrain`
has no such state, the agent's pose set has no jump. The agent is in the air only when falling — the
cab left from under him or pushed him from below.

### What follows from this

- **Our floor is right; what stands in it is wrong.** The slab, the cab and the frame width in
  clearances match the original to a percent; everything standing on the floor diverges — and in one
  direction, by 1.33 times.
- **Both paths from the EPIC give the same picture.** Growing the contents by 1.33 with a 3.6 m floor
  or shrinking the floor to 2.7 m with the former actors — the screen comes out the same: Otto takes
  12.7% of the frame height versus 13% in the original. The path is decided not by the look but by
  which numbers in the code have to be touched.
- **The 16:9 frame is wider than the original's field** (1.78 versus 1.45). Matching both height and
  width is impossible: 3.67 floors in height give 7.8 clearances in width instead of 6.4.

## Decisions

### 1. Grow the contents, leave the floor alone

The floor, slab, speeds and ranges stay in the same metres. Everything standing on the floor grows —
to the original's fractions.

Why not the reverse: shrinking the floor means scaling the whole world by 0.75 — and with it speeds
and ranges, otherwise the game becomes faster — the layout, the camera and
[ADR-0018](0018-native-fullhd.md). Growing the contents touches the numbers tied to the body: there
are fewer of them, and each is visible in one place. The time it takes to cross a floor and the
building does not change at all.

### 2. Otto and the agent — 1.68 m, the same height

56% of the clearance, as in the original. Otto grows by 4/3 — both in height and width
(0.54 → 0.72 m); the crouch stays at 64% of the stance (0.81 → 1.08 m).

**The agent is as tall as Otto** — that is how it was in 1983, and it is what `test_proportions.gd`
always asserted (with a 0.12 m tolerance that 1.17 versus 1.26 fit into). The agent's collision is
the same width as Otto's: in the original he is 1 px narrower, but that is a difference of
silhouette, not of target, and it is not taken in this milestone.

Together with height, the numbers that depend on height move:

| | Was | Now | Why |
|---|---|---|---|
| Otto's shot standing | 0.9 | 1.12 | original's frame: the bullet 15 px above the floor |
| Otto's shot crouching | 0.45 | 0.66 | above the hat brim of a prone agent |
| Agent's shot | 1.05 | 1.4 | × 4/3: hits a standing one, passes over a crouching one (1.08) |
| Agent kneeling | 0.76 | 1.0 | the agent's crouch in the original is 14 px above the floor |
| Agent prone | 0.36 | 0.52 | the same share of his stance, 31% |
| Kick, zone width | 0.9 | 1.2 | × 4/3 |

The "shot — dodge" pairs keep their order: kneeling (1.0) is below Otto's high bullet (1.12) and
above the low one (0.66); prone (0.52) is below the low one.

The low bullet does not grow by a clean 4/3 (0.6): the agent's model grew to Otto's height, and the
hat brim of a prone agent rose to 0.66 m — the figure cannot lie lower than its diameter. The crouch
pose is tilted more steeply, 76° instead of 70°: at 70° a kneeling agent's hat stood at 1.16 and cut
the high bullet. At 76° it is at 1.04, and a crouching Otto is 0.97 m, ~62% of height versus ~64% in
the original. The order is guarded by a test, and so is the margin in centimetres.

Otto's high bullet does not grow by 4/3 but is taken from the frame: in the original it goes at 15 px
out of 22–23, at chest level, and slightly above a crouching agent — exactly as ours after the
milestone. The extra 8 cm the scale would give would be needed only to reach a lamp from a jump, and
the original does not do that (decision 5).

### 3. Door 2.1×1.2, shaft and cab 1.8, slot step 1.8

The door is 70% × 40% of the clearance, its top comes 0.9 m from the ceiling, as in the original.
The shaft and cab are 60%, exactly one slot, as in the original.

**Slot step 2.1 → 1.8.** In the original the floor grid is 24 px, door 16 and gap 8, the shaft exactly
one step. There are still seventeen slots, the narrow top seven; the building width is derived from
the step: 38.4 → 33.6 m. The margin from the wall (2.4 m) is not touched.

**Shafts do not go into neighbouring slots.** A shaft is exactly a step, and two neighbouring ones
would close up with no floor between them: stepping out of a cab would be possible only into the
neighbouring one. Hence also the cap on the number of shafts per level — a third of its slots,
rounded up: each shaft with its neighbours eats no more than three slots, and that many always fit,
however the earlier-opened ones lie. For the narrow tower this gives three shafts instead of the four
the M18a rule promised it below the twelfth floor; for the podium six, the cap of five is not
touched.

A 1.8 step with a 1.2 door leaves the leaf 0.6 m of sideways travel — less than its width. Sliding
along the wall by its full width, as since M14, an open door would overlap the neighbouring slot — a
shaft or another door. A pocket in the wall does not help: the back wall is a 0.1 m panel, and a
leaf slid behind it is visible in the opening of the neighbouring door. So **the leaf swings on
hinges into the room**: its footprint on the floor is the opening itself and nothing more, and the
room behind the wall is 7 m deep. A hinged model was promised back in M14.

### 4. 3.67 floors in the frame, as in the original

The camera shows 13.2 m in height instead of 10.8 (half-height 5.4 → 6.6), 23.5 m in width — 7.8
clearances instead of 6.4. The vertical is the main axis of the game: as many floors as are visible,
that many cabs and agents above and below are visible.

The narrow top of the building (seven slots) still fits in the frame entirely, the podium (seventeen)
is still wider than the frame: 33.6 versus 23.5 m.

### 5. The lamp — under the ceiling

In the original the lamp is 8×7 px and hangs right from the ceiling: its bottom is 33 px above the
floor, 82% of the clearance. Ours had its centre at 1.8 m — 60%, and the lamp hung at head level.

**It is shot down from the cab — as in 1983.** Two independent sources say so directly:
*"shoot the light down on top of an enemy agent. You must do this
from the elevator"* (arcade-history, Tips) and *"they can be shot at while you are
riding between floors in an elevator"* (StrategyWiki). About shooting a lamp standing or in a jump —
not a word. This also follows from the geometry: the lamp is at 34–40 px, a standing shooter's bullet
at 15.

Before the milestone ours was shot down with a jump — it hung low, and a 2.4 m jump reached it with
room to spare. Now:

- the lamp is 0.6×0.45 m, top at the ceiling, bottom at 2.52 m — 84% of the clearance;
- standing, it cannot be reached: the bullet is at 1.12;
- in a jump neither: Otto hits the ceiling with his head when his feet have risen 1.32 m
  (3.0 − 1.68), and the bullet goes no higher than 2.47 — 5 cm below the lamp;
- from the cab — yes: a cab between floors carries the barrel through the lamp height.

Two percent versus the original's 82% is exactly those 5 cm on which "not from a jump" rests, and the
divergence is recorded as a number in the fractions test.

The jump itself does not change: 2.4 m by physics, it hits the ceiling earlier, as before the
milestone.

**A known hole.** "Not from a jump" rests on the ceiling, and there is not a ceiling everywhere: under
an escalator opening and at the bottom of a shaft while the cab is up, Otto in a jump hits nothing,
and the bullet on the way up passes the height of the floor's lamps — it will hit any in its line
(M18c code review). Honestly this is fixed by the jump height: ours is 2.4 m, the original's by
estimate 12–20 px, 0.9–1.5 m — and at 1.3 m the bullet reaches lamps from nowhere. But jump height is
a combat number (jumping over a bullet, the kick), and its place is in M18d.

### 6. The escalator is steeper and in its own two slots

Entry–exit 2.24 m by 3.6 — ~58° instead of 51° (the original's ~56°), belt ~66° (the original's
~63°). The passenger's clearance in the opening (`BEND_CLEARANCE`) grows with his width: 0.27 → 0.36 m
half-body, the 0.15 margin is kept. The escalator becomes steeper at the expense of the pad before the
opening: the opening steps back from it by 0.12 m instead of 0.48.

The number is held not by the angle but by the grid. The escalator takes two slots, and at a 1.8 m
step the lower pad with a passenger on it must end before 2.7 m — beyond is the neighbouring slot,
where a shaft may stand a floor below. The former 2.88 m put the pad right into its opening. The pad
at the end of the belt is shorter for the same reason: 0.42 instead of 0.66.

### 7. The car grows together with Otto, the exit opening does not

The car at the exit is what Otto gets into: 2.4 → 3.2 m, and the exit zone height 1.2 → 1.6. The exit
opening does not grow but narrows: 1.92 → 1.68. The cab of the neighbouring shaft starts 0.9 m from its
middle, and the former opening reached 6 cm past it — the floor extents test caught this.

### 8. Sizes — in one table in the original's pixels

The user's decision during the milestone (2026-09-23). Before it, metres lived where they were taken:
height — in the actor scene and in `tools/build_actors.py`, the door — in `Door`, the lamp — in its
scene, bullets — in exports, tolerances — in the bot. The milestone's first run failed on exactly
this: the agent's model grew, but the kneeling pose, which depends on height, stayed the same and cut
the bullet.

Now sizes are set by `Proportions` (`src/systems/proportions.gd`) — in pixels of the original's frame,
a pixel being 0.075 m (a 3.6 m floor step over 48 px). Everything else derives them:

- **scenes do not store sizes:** Otto, the agent, the door and the lamp fit their shapes right after
  the scene is built, before entering the tree — tests that read shapes on a fresh instance see the
  same numbers as the game;
- **the building rules** take the floor, slab, slot step, shaft, kneeling and prone from the table;
  the escalator and the bot's clearances are derived from body and shaft width;
- **models** — `tools/build_actors.py` reads the height and car length from the same
  `proportions.gd`, it has no copy of the number of its own.

Percentages do not decide everything. The clearances the game rests on — the bullet above the knee,
the bullet from a jump under the lamp, the passenger's margin in the opening — are ratios, not sizes,
and tests still guard them. Speeds and ranges are balance numbers, and their place is in
`BuildingRules`. The table of the original's measurements in `test_proportions.gd` is its own,
separate from `Proportions`: otherwise the test would compare the table with itself.

### 9. A floor number on every floor

Comparing the milestone frame with the original's frame (`tools/compare_original.py`) showed something
that was in no measurement: in the original every floor has a red sign with a number by the right
wall — 12×7 px, a 5 px digit. We had no number anywhere, neither on the floor nor in the HUD; in the
plan it lay in M19 as a "building detail".

This is not dressing but a game summary: how much farther down and on which floor the document is.
So the sign is taken here (the user's decision, 2026-09-23), it glows by itself like the door
indicator boards (ADR-0023, decision 6) and reads on a darkened floor. Numbering as in the original:
the top floor is 30, the bottom 1, there is no sign on the roof.

It hangs not flush with the ceiling but a band lower: the camera looks 10° from above, and the slab
edge hides about 0.3 m below the ceiling at the back wall. In the first frame the sign went half under
it. The band is computed from the camera tilt and the sign's depth, not picked as a number.

## What is not in the milestone

- **Speeds and ranges.** The floor is the same, and the time to cross the building is the same; they
  are changed by balance — M18d.
- **A narrow agent in the collision.** 9 px versus 10 — in the model, not in the box.
- **Agents crushed by the cab** — M18d, as before.
- **Floor dressing and windows** — M19.
- **The original's door density.** There, two doors on each side of the shaft; ours have two for the
  whole narrow floor. Doors are where agents come from, and their number changes combat: taken in M18d
  together with balance (the user's decision).
- **A roof after the original** — slopes with edges on the sides of the shaft, walls up to the cornice.
  This is the look of the building against the sky: M19, next to the background.
- **The original's jump height** — M18d; the lamp under an opening also depends on it (decision 5,
  "A known hole").
- **A squatting crouch.** The rig's leg is one bone without a knee, and the hips are the skeleton
  root, so the figure can be lowered only by tilting the torso: at 76° the crouch reads as bent over,
  not squatting. A model with knees is needed — debt.

## How we check

- **Fractions of the clearance — by a test, with the original's table.** For each building object —
  the original's fraction in pixels and a tolerance. A divergence left deliberately is recorded there
  as a number rather than disappearing.
- The order "shot — dodge" and "agent's bullet — crouching Otto" holds under any building rules, not
  only under the defaults.
- An open door does not overlap the neighbouring slot — on any seed.
- The escalator carries the passenger through the opening with a 0.15 m margin — already exists,
  `test_escalator_carries_its_rider_through_the_gap`, with the new body width.
- The narrow top fits in the frame, the podium is wider than the frame — with the new camera.
- The bot completes the building on all seeds, the death scale is re-measured.
- The frame budget with 3.67 floors in the frame — under 16.6 ms.

## Sources

- MAME, snapshots `elevator.png` and `elevatorb.png`, 256×224:
  `adb.arcadeitalia.net/media/mame.current/ingames/`.
- A 1:1 sprite sheet of the arcade version: The Spriters Resource, Elevator Action (Arcade),
  asset 20689.
- Measurement: counting same-colour runs along the rows and columns of the native frame.
