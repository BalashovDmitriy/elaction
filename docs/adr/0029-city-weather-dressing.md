# ADR-0029 · M19: city, weather, dressing and roof

- **Status:** accepted; the dressing of decision 3 is pack models from a catalogue instead of boxes,
  the indicator board above the shafts is live ([ADR-0033](0033-dressing-from-packs.md),
  decisions 3 and 7); the palette of decision 5 enters the walls more strongly than 18%
  ([ADR-0031](0031-scene-detail.md), decision 5) and is applied to textures (ADR-0033,
  decision 5)
- **Date:** 2026-09-23

## Context

After M18 the building plays by the original's rules, but in the frame it is a diagram of a building:
behind the tower and above the roof there is black emptiness (half the screen in the roof frame), a
floor is a bare wall with doors, the roof is a flat deck, and rounds differ only by overall tone.
The M19 DoD is "the frame shows it is a building at night in a city".

### What the check showed

- **The arcade has no furniture, no weather, no city.** A floor is doors, lamps and shafts, outside
  the building a grey field. Everything the milestone adds is ours, and it has one rule: do not
  hinder readability (ADR-0019, ADR-0023).
- **The original's roof** (MAME frame, `tools/compare_original.py`): above the thirtieth floor, on
  both sides of the shaft, stepped slopes, the shaft rising above them. Ours is a flat deck and a
  machine room.
- **The look reference** (`docs/reference/3d-look-reference.jpg`): objects stand at the back wall of
  the corridor — a planter, a display case, a neon sign — indicator boards above the elevators, the
  floor number on the wall. They do not touch gameplay.
- **The camera is orthographic** (ADR-0023, decision 1). With it, layers at different depths shift
  equally: a city placed in the same world behind the building gives no parallax.

## Decisions

### 1. The city — generated 3D blocks in a perspective view of its own

The user's decision: blocks, not drawn layers. Houses are boxes with emissive windows, without light
sources: the frame does not get more expensive against the lamp budget. Three or four rows in depth,
the far ones darker and deeper in the fog. The layout is by the building seed.

The ortho camera gives no parallax, so the city lives in **its own world** (`SubViewport` with
`World3D`) under a **perspective camera** that follows the main one and stands 30 m from the play
plane: the play plane is seen at the same scale, the near row of houses (60 m behind it) three times
smaller, the far row (220 m) eight times smaller, and as the camera moves they shift the slower the
farther away they are. The image is laid under the main frame as its background
(`Environment.BG_CANVAS`): wherever there is no building — behind the tower, above the roof — the city
is visible. This way the depth is real, and the rule "a floor is a band of the frame" of the main
camera is not touched. The city view is rendered at a reduced resolution: it is in fog and not sharp
by design.

### 2. Weather — by the building seed: rain, fog or a clear night

The user's decision. One weather per building, picked by the seed, so rounds differ not only in
colour.

- **Clear** — clean air, the city is visible farther.
- **Fog** — denser air between blocks, the far rows melt away.
- **Rain** — particles in the city view and drops above the roof, the fog slightly denser.

There is no weather inside the building: the corridor is dry. Particles — within the frame budget,
measured with `tools/light_bench.gd`.

### 3. Floor dressing — decoration only

The user's decision. Objects stand at the back wall of the corridor, behind the play plane: without
bodies, bullets and people pass by them, they do not serve as cover — as in the original, where there
is nothing on a floor. The set: planters, vending machines, water coolers, benches, cabinets, signs;
pipes under the ceiling; floor indicator boards above the shafts. The board's digits are cold, not
red: a red light at sign height is the mark of a door with a document.

It is laid out by its own class from the building plan (`BuildingDressing`) and the seed, without a
scene — so it is checked by tests. An object **does not occupy** the place of a door, lamp, shaft,
escalator or exit, nor stand next to a wall: the door and the shaft must read, and a lamp must have
somewhere to fall. Objects have muted tones; only what glows in real life glows (a sign, a vending
machine panel, an indicator board), and an actor's silhouette is held by his outline (ADR-0022,
decision 4) — so even a tall vending machine behind Otto does not hide him.

### 4. The roof — a silhouette behind the play

The user's decision. Stepped slopes on the sides of the shaft are decoration behind the play plane;
the roof's outer walls serve as parapets at the edges, they already exist. Otto walks on the flat
deck, as now: the path, the bot and the traversability checks do not change, and the frame reads as
the top of a building.

### 5. The round palette — through materials and light

The technique of ADR-0017 returns not as a fill colour but through materials: the back wall takes the
floor tone of the round palette, the outer walls the brickwork (18%), the roof slopes the brickwork at
8%: the roof is background. Lamp light is not tinted by the palette: the palette's light is almost
white in all rounds, and 18% only made the lamps lighter (M19 code review). Rounds differ in hue, not
in brightness: readability holds in all of them.

### 6. A dark floor is noticeably darker than a lit one

The M18e frames showed: in the dim tower a dark floor differs from a lit one only weakly. The back wall
of a map-dark floor (ADR-0028, decision 4) is at 0.45 of a lit one; the readability lights stay.

## What is not in the milestone

- Rain reflections on the facade glass and wet asphalt — M20, grading.
- Movement in the city (cars, blinking signs) — not in this milestone.

## How we check

- `BuildingDressing` on any seed: no object stands in the place of a door, lamp, shaft, escalator or
  exit, or right next to a wall; the objects have no bodies.
- The city and weather repeat by seed; different seeds give different weathers.
- The light source budget in the frame does not grow — the city's windows have no sources.
- Frame: `light_bench` no more than a third worse than M18c; the milestone frames and the comparison
  with the original.
