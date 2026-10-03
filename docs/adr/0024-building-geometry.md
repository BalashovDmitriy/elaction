# ADR-0024 · Building geometry: slot grid, threshold silhouette, overlapping shafts

- **Status:** accepted; decision 6 changed by [ADR-0025](0025-shafts-escalators-and-riders.md)
  (decision 1: up to two pairs, in every building where there is room), decisions 7 and 8
  refined there too. The slot step 2.1 → 1.8 m and building width 38.4 → 33.6 m from
  decisions 1–2, the cap on shafts per level in decision 3 — [ADR-0026](0026-proportions.md),
  decision 3
- **Date:** 2026-09-21

## Context

M18 is the building geometry milestone. Before it the building was assembled like this: nine slots
across, a silhouette of equal steps, shafts of equal length end to end, an escalator at every
junction. Light, materials and actors are ready by this point ([ADR-0023](0023-light-and-readability.md),
[ADR-0022](0022-actors-rig.md)) — what remains to be redone is the building itself.

### What the check showed

[Elevator World](https://elevatorworld.com/article/elevator-action/) analysed the original's
building as a real one. The shafts there are unequal and **overlapping**:

> 1–5, 1–6, 1–7, 1–7, 1–7, 7–11, 7–13, 10–12, 13–15, 15–17, 19–30 with the roof.

If you count how many shafts serve a floor, a rule emerges that we do not have at all:

| Original's floors | Our floors | Shafts |
|---|---|---|
| 1–7 | 23–29 | 3–5 |
| 8–15 | 14–22 | 1–3 |
| 16–17, 19–30 | 0–13 | 1 |
| 18 | 12 | **zero** |

The seventh is a sky lobby: five shafts meet on it. The upper third of the building is one shaft
for twelve floors, and the descent there has no alternative.

**Escalators are at the top, not the bottom.** According to one source (not double-checked): on
floors 17–20 there is an escalator both on the left and on the right, on 16 — only on the right.
That is, escalators fill exactly the band where there are no shafts or they do not overlap. Below
the sixteenth the transfer goes by **overlap**: 7–13 and 10–12 share floors 10–12, 13–15 and 15–17
share the fifteenth.

The milestone plan in `EPIC.md` promised the opposite — "two escalators at band junctions at the
bottom". The check turned the milestone around: at the bottom there are not escalators but many
shafts down to the ground; escalators are the upper band.

Other things from the check: one shaft has a double-deck cab, the cab doors open on two sides, the
original does not scroll horizontally — the building is exactly the width of the screen.

### What the code showed

- **The reachability graph already handles overlap.** `BuildingRoute._links` connects all floors of
  a shaft with each other, so overlapping shafts just give more edges. The EPIC's fear that "unequal
  and overlapping ones drag the whole reachability graph along" was not confirmed: the work is not
  in the graph but in `_lay_shafts`.
- **Not a single floor fits in the frame.** The frame is 19.2 m (`SideCamera`: half-height 5.4 m at
  16∶9), the narrowest floor is 21.6 m, the widest 38.4. The promise "the upper floors fit
  entirely" is not met for any of them.
- **The escalator is no longer a `Line2D`.** In 3D it is two belt boxes
  (`Escalator._lay_belt`); the wording in the EPIC is left over from the 2D plan. What is actually
  missing is the balustrade, the steps, the framing of the opening.

## Decisions

### 1. A finer slot grid: seventeen slots at a 2.1 m step

There were nine slots at a 4.2 m step. Now there are seventeen at 2.1 — the building width
(38.4 m) and the margin from the walls (2.4 m) do not change, only the granularity does.

A finer grid was chosen over two other ways of fitting the top floor into the frame. Narrowing the
top to three slots leaves exactly a shaft, a door and a lamp on the floor, and the escalator, which
according to the check lives precisely at the top, has nowhere to go. Widening the frame makes the
actors smaller, and all the tuning of light and materials in M17 was done for the current scale.

The 2.1 m step holds everything that occupies a slot: a 0.84 m door leaf slides by its own width
(1.68 m), a 1.2 m shaft, a 1.92 m exit.

**The escalator takes two slots** — its own and the next one in the direction of descent. The
opening goes 2.28 m from the axis and the lower pad 2.88 m, and this does not fit into one grid
step. It did not fit before either, but one slot was taken, and a door could stand on the pad; now
both slots are taken, on both floors.

### 2. The silhouette is set by a threshold: a narrow tower on a wide podium

Equal-height steps go away. Two widths remain with a threshold between them — `wide_from`, the
twentieth floor by default:

| | Slots | Width | 19.2 m frame |
|---|---|---|---|
| Roof … floor 19 | 7 | 17.4 m | fits with 1.8 m to spare |
| Floor 20 … 29 | 17 | 38.4 m | twice the frame width |

This is what the player asked for: the top is visible in full, the bottom ten are wider than the
screen. The original does not scroll horizontally at all, so the divergence is deliberate and
recorded here as a choice.

**Lamps per floor are counted by width, not by the number of slots.** The M17 rule "one lamp per
three slots" ([ADR-0023](0023-light-and-readability.md), decision 2) on the finer grid gives two
lamps at the top instead of one: there are more slots, but the floor is the same width. The spacing
between fixtures is a metric property, and it must be counted by width. It is counted as a
fraction: a floor across the full building width gets `lamps_per_floor`, the narrow top gets one.
Not in metres: an absolute spacing between lamps would not survive a building of other dimensions,
and the tests assemble such buildings. The M17 numbers are kept — one at the top, three at the
bottom.

### 3. Shafts overlap, and the number of paths grows toward the bottom

End-to-end bands go away. The layout runs top to bottom as a sweep: at each level it is known how
many shafts should serve it; those that have used up their `shaft_span` close, the missing ones
open.

Overlap arises by itself and comes out unequal: shafts opened on different floors close on
different ones. Shafts opened at the very bottom are cut off by the bottom floor — and all reach the
ground at once, like 1–5, 1–6 and three 1–7 in the original.

How many shafts serve a level:

- the roof and floors down to `single_shaft_until` (11 by default) — **one**; this is the upper
  third of the original, its 19–30 shaft;
- below — grows from two to `shafts_max` (**five** by default, as in the original) toward the bottom
  floor.

The bottom floor is then two-thirds occupied: five shafts, two doors, three lamps and the exit —
eleven slots of seventeen. Six remain for the M19 dressing.

### 4. Escalators — a band at the threshold, plus a guarantee at a break

Two rules, and the second backs up the first.

**The band.** Escalators live where the descent has no alternative — in the lower part of the
single-shaft zone, right at the silhouette threshold. Architecturally this reads: the tower's shaft
ends above the podium, and an escalator leads down. This is the original's sky lobby.

**The guarantee.** Wherever neighbouring shafts do not overlap, the generator must place an
escalator — otherwise the band below is unreachable. One rule for the whole height, and the
traversability test stays the same.

**Two escalators per floor where they fit, otherwise one.** The original has two each (left and
right) on 17–20 and one on 16. Our band falls on the narrow part of seven slots, where two
escalators eat four of them: with two shafts, a door and a lamp that is nine slots out of seven.
Degenerating to one is a consequence of the stepped silhouette, which the original does not have.

### 5. The interior wall is solid, but traversability is checked after it

A floor is divided in two by a floor-to-ceiling wall. Neither people nor bullets pass through it; an
agent behind the wall does not shoot. Crossing is possible only via another floor — by elevator or
escalator.

The wall stands **on the boundary between slots, not on a slot**: even a metre thick, it is narrower
than the grid step, and there is no reason to take a whole slot for it.

It must cut the floor only for walking, not for the slab. Today floor pieces are counted with one
count — by openings (`BuildingPlan.spans_between`), and the slab geometry is taken from it too. There
become two counts: **the slab is cut by openings, traversability by openings and walls.** They must
not diverge, so both stay in `BuildingPlan`, side by side.

**A wall that locks the player in is removed.** The generator places walls, computes reachability
and removes those that made a document or the exit unreachable. Checking in advance more cheaply is
not possible: reachability depends on all walls at once, not on each separately.

**The wall keeps a clearance of half a grid step** from openings, escalator pads, doors and the
exit. It is almost a metre thick (see below), and placed right against an opening it leaves no room
to stand; at an escalator this broke twice — with the upper pad and with the landing pad a floor
below — and the reachability graph lost a connection.

**Thickness — almost a metre, not the thickness of the outer wall.** In the milestone's first frames
a 0.48 m wall was indistinguishable from a 0.45 m pilaster: "you cannot pass here" read as
decoration. Arcade readability matters more than plausibility ([ADR-0019](0019-3d-pivot.md)), and it
costs no slots — the wall stands on the boundary between slots.

### 6. The double-deck cab is a rigid pair, rare and only with a live alternative

Two decks are fastened together and ride together, serving two floors at once. Otto enters either;
an agent may ride in the other. This is a real double-deck, not two independent cabs in one shaft:
an independent second cab is a moving boundary of the shaft, and the reachability graph would stop
being static.

`ElevatorMotion` does not change — it is one movement and two bodies. What changes are the bounds
passed to it: the pair is taller than a single cab by a floor height, and the travel range is
shortened at the bottom, otherwise the lower deck would go below the shaft bottom.

**It occurs rarely.** In the original there is one such shaft per building, and it is a curiosity,
not the norm. Rules:

- no more than one double-deck shaft per building;
- not in every building — about one in three, by seed;
- only in a shaft that has a parallel neighbour on all of its floors.

The last condition matters more than the first two. The pair takes one more floor and travels a
shortened range; were such a shaft the only one on its floors, the descent could get stuck. We put
it only where there is something to use instead — that is, in the podium, where there are several
shafts. In the original the double-deck cab stood there too, in the busy lower shafts.

One in three is a chosen number, not measured and not confirmed by the original.

### 7. A light column stands in the shaft

A debt from M12: in 2D the light column in the shaft was the only thing showing the way in a
darkened building. The greybox has none, and the shaft is held only by the cab indicators.

The shaft's source is not a floor lamp: it does not go out from a shot and does not take part in the
darkness zones ([ADR-0023](0023-light-and-readability.md), decision 2). Darkness decides whether
agents see Otto; the shaft must always read, otherwise a darkened building stops being traversable
by eye.

The frame budget is the same: 16.6 ms, 2.0 currently used.

### 8. The escalator is built as a structure

The two belt boxes are replaced by a balustrade, steps, upper and lower pads and a framing of the
opening. The steps are relief, not animation: the M17 light falls on geometry, and that is what the
pivot was undertaken for ([ADR-0019](0019-3d-pivot.md)).

### 9. The bot finds its way over the building graph rather than descending greedily

Until M18 the building guaranteed a greedy descent: shafts went end to end, an escalator stood at
every junction, and "ride down the nearest shaft" always worked. Overlap cancels that rule. Now there
are up to five shafts per floor, the first may end on that very floor, the escalator goes both ways,
and a solid wall divides the floor in two.

A property surfaced separately that did not exist before: **a floor piece from which there is no way
down**. The shaft has ended, there is only an escalator opening nearby — and to descend you have to
ride back up first. The building is still traversable: the links are two-way, and the reachability
graph knows it. Forcing the generator not to produce this turned out to cost more than it was worth —
extending shafts broke the set number of paths per floor, and a mandatory escalator ate slots for
lamps and doors.

**A shaft divides a floor, and the halves connect through a standing cab.** The opening cuts the
floor into pieces, and crossing from piece to piece is possible only while the cab covers the
opening with itself — as in the original. Before overlap this almost never occurred: there was one
shaft per floor, and there was no reason to get around it. Now it is a full-fledged move of the
graph, and the bot uses it: it waits for the cab and walks straight through.

So the path is found by the bot, not guaranteed by the generator. `BuildingRoute` returns a labelled
graph — floor pieces and the transitions between them with what to use — and the first move toward
the goal. The graph is computed once per building, the decision is made every frame: a walker misses
the cab, fights and falls, and a remembered route would be stale by the next frame.

This is not only about the bot. The bot is our only check of the building as a whole
([`docs/testing.md`](../testing.md)), and it must be able to do what the player can. A player who has
ridden into a dead end will ride back too.

### 10. The milestone splits into M18a and M18b

Seven things at once, three of which change the layout. If traversability breaks, finding the cause
among seven changes costs more than among three.

- **M18a — layout:** slot grid, threshold silhouette, overlapping shafts, escalators as a band,
  interior walls. Everything that touches the reachability graph — in one piece and under one bot run.
- **M18b — geometry and look:** escalator as a structure, light column in the shaft, double-deck cab.

Both halves end with a playable build — the pivot rule ([ADR-0019](0019-3d-pivot.md)).

## What is not in the milestone

- **Unequal shafts by the original's literal layout.** We take the rule ("the lower, the more paths",
  overlap, five shafts at the bottom), not the list 1–5, 1–6, 1–7. Our building is generated, and it
  cannot be set by a list.
- **Cab doors on two sides.** The check names them, but our cab has no doors at all: Otto enters
  from the side.
- **Steps that move.** Relief — yes, belt animation — no.
- **Floor dressing.** Furniture, pipes, signs — M19.
- **Growth of the number of shafts from building to building.** The number of paths is a property of
  the building, not of difficulty; difficulty grows by agent anger ([ADR-0016](0016-combat-balance.md)).

## How we check

- On any seed, levels above the threshold fit in the frame entirely, those below do not.
- The number of shafts serving a floor does not decrease from top to bottom and reaches five.
- Neighbouring shafts either overlap or their junction is closed by an escalator.
- A wall locks neither a document nor the exit: on hundreds of seeds reachability is intact.
- A double-deck shaft, if it came up, has a parallel neighbour on all its floors, and its travel range
  keeps both decks inside the shaft.
- The bot completes any building on three lives — the same test, a new layout and a new way of
  finding the path.
- The frame budget with light columns in the shafts stays under 16.6 ms.
