# ADR-0044 · M24h: street with traffic, cab, escalator, doors, FPS

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0038](0038-building-start-and-end.md) (exit),
  [ADR-0027](0027-rom-combat.md) (cab crush),
  [ADR-0043](0043-animation-and-look.md) (escalator, cut by the cab),
  [ADR-0005](0005-doors-and-documents.md) (doors)

## Context

The user's request during M24g — traffic at the exit — and his remarks on the
results of M24g (2026-09-29). There were ten remarks, and the milestone is split:
M24h — mechanics and movement, M24i — look ([ADR-0045](0045-takedowns-helicopter-dressing.md)).

### What the check against the ROM showed

Notes — [`arcade-rom.md`](../reference/arcade-rom.md), part 5.

- **Doors.** Only the player is let in, only into a red door and only while the
  document has not been taken (@3BDA–3C25). The ADR-0005 question "does the
  original let one into a regular door" is closed: it does not.
- **Walking in the cab.** The ROM does not check whether the cab is moving: Otto
  always walks left-right in it. The cab is 21 px, Otto 8 px.
- **Exiting on the move.** One can jump from a moving cab onto a floor if its floor
  is higher than the floor of the level by no more than 18 px of 48 (~0.4 floor);
  one can also jump into a moving one the same way.
- **Crush.** Touching from the side never kills: the cab pushes Otto to the edge
  of the shaft. It crushes only someone who is entirely in the shaft under it and
  to whose head the cab floor has descended, or someone on the cab roof who hits
  the top of the shaft with his head. 300 points for an agent — only if Otto is
  riding in that same cab.
- **Empty shaft.** In the ROM Otto holds on at the edge for half a second, and any
  fall into the shaft kills. Ours, since M24a, kills on a fall of more than a
  floor — this stays.
- **Exit.** The original has no traffic: Otto's car drives right, turns around and
  leaves past the left edge. Traffic is a divergence at the user's request.

## Decisions

All decisions are the user's.

1. **The street — two lanes.** The near one goes one way, Otto merges into it; the
   far one goes the opposite way. Cars are Cars Pack models with headlights and
   brake lights, speed and gaps drawn from the building seed.
2. **Otto waits for a gap.** The car pulls out to the curb, lets the traffic pass
   and merges into a gap; then it drives with the traffic until it leaves the
   frame.
3. **Doors — only red ones, while the document has not been taken.** A regular
   door and a collected red one do not let Otto in; there is no more cover in a
   door, the bot learns to live without it.
4. **One can walk in the cab, including on the move**, from wall to wall.
5. **Exiting and boarding on the move — as in the ROM:** while the floor difference
   is less than 0.4 floor, Otto jumps out onto the floor or into the cab.
6. **Touching a cab does not kill.** Only a cab under whose floor Otto stands
   entirely and which has descended to his head crushes, or the top of the shaft —
   one standing on the roof. One clipped by the edge is pushed to the edge of the
   shaft.
7. **Points for a crush — as in the ROM:** only for the cab Otto is riding in.
8. **Falling into a shaft — as is** (M24a): a fall of more than a floor kills.
9. **The cab cut does not stretch the texture:** the cut-off part does not deform
   the UV mapping of the remaining one.
10. **The escalator — into depth.** The flight goes behind the play plane, toward
    the back wall; the floor slab in the play plane is whole, and one walks past
    the escalator on the floor. Otto steps onto the landing with a step into depth,
    like into a red door. The building layout does not change because of this: the
    escalator's place is the same, and the hole in the slab is only in the back
    strip of the corridor and only where the flight passes through the slab. The
    model is the same one of ours, redrawn: the flight is thicker and clad, the
    steps denser, a glass balustrade with a handrail on both sides.

    The angle is 45°, not 30° as in the answer option: 30° was already tried in
    M24g, in the frame the flight came out too shallow, and the user himself
    corrected it to 45° (ADR-0043, decision 15). The escalator looked steep not
    because of the angle but because it was thin.
11. **FPS on the bottom floors — measure first** per floor (`light_bench --whole`),
    then fix. If corpses are the drag, a settled body freezes: it stops being
    physical and becomes a static model, the look is the same, it lies until the
    end of the building. Bodies must not disappear.

## What the FPS measurement showed

`light_bench --floors` and the new frame breakdown `--probe` ("Ultra", 1920×1080,
RTX 5060 Ti). At the bottom of the building the GPU was 19 ms versus 12–13 at the
top, and the cause is not corpses but the light and the indicator boards:

- **Lamp shadows — 10 ms of 18.** The podium is one and a half frames wide: up to
  three lamps per floor, and all lamps of the floors in the frame cast shadows,
  including beyond the frame edge. Most expensive is the fill shadow — cubic, six
  passes over the scene: 7.7 ms. Light now also goes out beyond the frame edge in X
  (the frame strip plus the fill range), the cone shadow only within 2.5 m of the
  frame, and fill shadows are cast by no more than four lamps closest to the middle
  of the frame — as many as there are in the frame at the top. Bottom of the
  building: 19 → 15 ms.
- **Shaft indicator boards — up to 10 ms of the physics step, in spikes.** All cabs
  of a building move in step (one pause, one speed), and on every floor passed the
  indicator boards of all shafts rebuilt their text at once. Indicator boards are
  now redrawn only on floors in the frame; the others catch up when the floor
  enters the frame. Physics: median 7 → 3.3 ms, peaks 13 → 6.
- **Corpses.** Freezing is done as decided; physics does not grow on frozen bodies.
  Found along the way: a body that fell out of the world fell forever and was
  counted by physics — now it disappears below the building.

## Consequences

- The bot loses cover in doors: combat tests on all seeds are re-recorded.
- `ShaftHazards` gets the "entirely under the cab floor" rule, tests — touching by
  the edge.
- The escalator in depth changes boarding and the bot's path on the landing, but
  not the route graph: the places in the layout are the same.
