# ADR-0048 · M24i: hotel and office — different corridors

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0045](0045-takedowns-helicopter-dressing.md), decision 6
  (richer dressing), [ADR-0033](0033-dressing-from-packs.md) (building kind)

## Context

Decision 6 of ADR-0045 — richer hotel and office dressing, each with its own set.
In the frames at the start of M24i the floor was rather empty, and the user's remark
(2026-09-30) — the hotel and office interiors are too similar. That was the case: the
building kind changed wall textures, plaque metal, pipes and the furniture set, while
the doors, light fixtures, carpet runner and cornice were the same for both.

There are few furniture spots on a floor: between doors there are pilasters, and a
single addition to the catalog will not make a floor richer. Details that live next
to doors are needed.

## Decisions

1. **Look by kind — in one place, [BuildingStyle].** Everything the kind differs in,
   except the furniture set: floor, doors, light fixtures, sconces, plaques. The
   mechanics are the same — a lamp is shot out and a door opens the same way.
2. **Hotel:** a carpet runner, a molded cornice; a wooden paneled door leaf, a brass
   handle, a dark wooden frame; a sconce on every pilaster ([WallSconce]) with a warm
   spot on the wall; some rooms have a "Do not disturb" sign on the handle (22 %) and
   a newspaper or a tray at the threshold (12 %) — by door draw, not at a red door.
3. **Office:** carpet tile across the whole floor with a grid of seams, a narrow
   cornice; a gray door leaf with frosted glass, a steel handle, an aluminum frame, a
   cold sign above the door; the plaque shows the department and office number; the
   light fixture is a white fluorescent box on rods instead of a dome shade.
4. **Sconces without light sources.** There are hundreds of pilasters in a building:
   the spot on the wall is a transparent gradient, the shade glows by itself. There
   are no sconces on a dark floor: light there is off per the ROM rules, and a glowing
   sconce would argue with the darkness. With the lamp shot out the sconces stay lit:
   they are decor, and the zone darkness is decided by the lamp (the user's decision
   on code review).
5. **The office light fixture — in the shape of the lamp.** The lamp is a target: the
   box fits into its hitbox, the target is neither smaller nor larger than the dome
   shade.
6. **More furniture on the floor:** the share of spots with furniture is 70 % instead
   of 50 %. New poly.pizza models: a bench (hotel), a visitor chair and a floor lamp
   (office), a "Wet floor" sign (any building).

## Consequences

- The style test builds a building of each kind and checks what is visible: boxes and
  glass in the office, sconces in the hotel and their absence on dark floors.
- A third building kind — a residential complex — and its own agents for each kind:
  milestone M24k.
