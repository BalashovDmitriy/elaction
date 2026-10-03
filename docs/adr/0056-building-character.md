# ADR-0056 · M24n: the character of a building kind

- **Status:** accepted
- **Date:** 2026-10-02
- **Extends:** [ADR-0055](0055-residential.md) (three building kinds),
  [ADR-0030](0030-grading-and-quality.md) and [ADR-0034](0034-ultra-and-auto-quality.md)
  (grading — changes render settings per kind, hence a separate ADR),
  [ADR-0017](0017-spectrum-palette-and-shafts.md) (round palette)

## Context

After M24m there are three buildings, but a frame of the three kinds side by side
(`screens/M24n/three_kinds.jpg`) showed: they differ in finish — wallpaper, plaster,
checkerboard, door color — while what is visible at first glance is shared: the blue
night grading, the round palette over all walls, one lamp color and strength, one
frame structure. With 3.67 floors in the frame the texture barely reads. The user's
request (2026-10-02): "set the design of the three levels as far apart as possible".

**Check against the original.** In the 1983 arcade there is one building, rounds differ
only in color — the round palette. In Elevator Action Returns (1994) locations differ
above all in color and light — the missions have color names: Red After Image, Colors
of Night, Crimson Line, Vermilion Sun — and in the density of detail on a floor:
flickering light, fire, rain on glass, smoke. Old & New (GBA, 2002) complicates the
layout itself — that does not suit us: the layout follows the ROM.

**Code** (review before the milestone): grading assembles `Atmosphere.environment` when
a building loads — the noir curve, contrast, saturation, ambient from `palette.dark`;
the building kind is known there but not used. The lamp color is one constant
`Lamp.LIGHT_COLOR`. The camera does not see the underside of the ceiling (10° tilt):
only what hangs below the slab edge is visible. Behind the corridor back wall the floor
already extends 7 m — the slab bodies are 9 m deep.

## Decisions

Questions asked of the user on 2026-10-02.

1. **Each kind has its own world inside the shared noir.** The noir stays — vignette,
   contrast, the curve with cold shadows — but each kind has its own air table, like the
   time of day: curve, saturation, ambient, fog and lamp light color.
   - Hotel — warm amber noir: incandescent lamps, thick air.
   - Office — cold white-blue: even fluorescent light, few shadows.
   - Residential — dim sodium orange with the green of fluorescent tubes.
   Time of day is applied on top of the kind: in the day all three are lighter but stay
   themselves.
2. **The round palette — inside the kind's family.** Rounds still recolor the building,
   as in the arcade, but each kind has its own set of palettes in its range: a hotel will
   not take on an office's color.
3. **Darkness is equally dark.** A darkened zone is the same deep gloom in any kind: the
   game rule reads the same. The "light — darkness" gap is checked by a test for each
   kind × round pair.
4. **The corridor back wall — different in structure, not in texture.**
   - Office: between doors — glass partitions, behind them an open space through the
     slab depth: cubicle desks, monitors, cabinets, windows onto the city. The office
     door opens into this same open space — the office has no separate room behind the
     door. It is built only on floors in the frame and nearby (`VisibleFloors`), without
     shadows — within the frame budget at the bottom of the building.
   - Hotel: arched niches with lighting and vases, mirrors in gilded frames — a
     highlight, not a reflection — tall wooden panels with molding. The carpet runner
     stays.
   - Residential: riser pipes, electrical panels and cables in view, windows onto a fire
     escape with the city behind it, bare brick where the plaster has crumbled,
     decorative doors to the stairs (EXIT) and a garbage chute hatch — they do not open
     and do not look like agent doors.
5. **The "ceiling" is what hangs.** Only the strip below the slab edge is visible, so
   the kind reads by light fixtures and what is under the edge: a chandelier in the
   hotel, a fluorescent box under a strip of suspended ceiling in the office, a bare
   bulb on a wire and pipes in the residential building. The lamp is a target: the
   place, bounds and the glowing part in view do not change.
6. **Music by kind — in M24o** (the user's decision during the questions).

## Consequences

- `Atmosphere.environment` and `Lamp` get the building kind; the palette contrast test
  runs over all kinds and rounds.
- The office loses the room behind the door ([ADR-0047](0047-room-behind-the-door.md)) —
  it is replaced by the open space behind glass.
- The set behind the office glass is the first geometry built per visible floor rather
  than for the whole building at once.
