# ADR-0023 · Light: camera tilt, lamp zones, edges and indicator lights

- **Status:** accepted; the number of lamps from decision 2 is computed by floor width, not by slots
  ([ADR-0024](0024-building-geometry.md), decision 2); the fill shadow from decision 3 is only at the
  high quality level and above, below it the fill is shorter
  ([ADR-0030](0030-grading-and-quality.md), decision 5); the lamp hangs under the ceiling, not at
  1.8 m ([ADR-0026](0026-proportions.md), decision 5)
- **Date:** 2026-09-20

## Context

M17 is the lighting milestone for which the pivot was undertaken ([ADR-0019](0019-3d-pivot.md)).
The reference is a side cross-section of a building at night: a polished dark floor with
reflections, a row of ceiling fixtures casting cones downward, warm light inside against cold
outside, red indicators by the elevator, a neon sign. And the floor in it **is visible** — the
camera looks slightly from above.

What was already decided and stays: a game object does not depend on scene lighting
([ADR-0019](0019-3d-pivot.md), decision 5); a bullet flies in the XY plane regardless of the camera
(same, decision 6); in the dark an agent sees a shorter distance but does not stop shooting
([ADR-0007](0007-lamps-and-darkness.md)); actors in the dark are held by the outline
([ADR-0022](0022-actors-rig.md), decision 4).

The trial `tools/look3d.gd` gave numbers for fog, glow, SSAO and tone mapping, and two findings: a
strictly side camera does not see the floor, and a smooth box under light reads as a blob — the
frame was pulled out by edges.

## Decisions

### 1. The ortho camera tilts ten degrees from above

Strictly from the side, the top face of the slab is a zero-thickness strip, and floor reflections —
the technique the pivot was undertaken for — will never happen. A ten-degree tilt opens the floor
as a strip a third of a metre wide: reflections and lamp light fall into it, and floors stay
parallel bands of the frame.

The constraint of decision 6 of [ADR-0019](0019-3d-pivot.md) is in force: tilt is a property of the
camera, not of the world. The play plane, hits and the band of visible floors are computed as they
were; the camera merely stands above the target by `distance × tan(tilt)` so that its axis crosses
the play plane at the right point, and sees slightly more vertically — by `1/cos(tilt)`.

Perspective is rejected: floors stop being equal bands, the top and bottom of the frame are at
different scales, and the rule "a floor is a band of the frame" with the selection of visible floors
would have to be recomputed.

### 2. There are several lamps on a floor, and darkness comes in zones

As in the reference: a row of fixtures along the ceiling, one for every three slots of the floor —
one lamp at the narrow top, two in the middle, three at the bottom (`BuildingRules.lamps_on`). The
layout puts them not in random free slots but in the middles of equal zones of the floor: **the
lamp's zone is the unit of darkness.**

A shot-down lamp darkens **its zone**, not the floor: an agent in that zone sees a shorter distance
and is worth more, an agent under a neighbouring lamp is not. The zone is the nearest lamp
horizontally; the boundaries lie midway between neighbours. The rule lives in
[`FloorLighting`](../../src/systems/lighting/floor_lighting.gd), still without a scene, and is
checked by the same technique.

This is the second step away from the original, and it is recorded as a choice. In 1983 a
shot-down lamp darkened the whole building for a few seconds; [ADR-0007](0007-lamps-and-darkness.md)
made darkness per floor and permanent — for the tactic "darken the floor and get through". Zones
make the same tactic more precise: you have to darken where you stand, not anywhere on the floor —
and they are the only thing consistent with several lamps per floor. One lamp on a thirty-metre
floor does not read against the reference at all.

The option "several lamps that go out all at once" is rejected: it makes the very first shot at any
lamp a floor switch and devalues the rest.

### 3. A lamp has two sources, and both go with it

A downward cone — a warm `SpotLight3D` with a soft shadow — gives a spot on the floor and shadow
edges, as in the reference. One cone leaves blackness between lamps even when the lamps are lit, so
next to it there is a weak wide fill — `OmniLight3D`. Both are children of the lamp: shot down —
both go out, and "the zone is lit" means exactly "the lamp is hanging". Only lamps of visible floors
are lit, as before.

**Both need a shadow.** The fill was intended without a shadow — it is weak, and a shadow on the
second source of each lamp costs money. But its radius (7 m) is greater than the floor height
(3 m), and shadowless light went through the slabs: in the frame of a darkened floor, its floor was
lit by the lamps of the floor below, and darkness stopped being darkness. The radius cannot be cut —
it is needed to reach the edges of the zone. The shadow on the fill cost 0.8 ms per frame
(1.2 → 2.0 with a 16.6 budget), and that is cheaper than darkness one can see through.

There is no separate cold fill from windows: windows and the city come in M19, and then the cold
light from outside will have a source. For now the temperature is split by warm lamps against the
cold overall tone of the round palette.

### 4. Edges — the minimum for light to catch on

The trial showed: half the frame was pulled out by pilasters and slab edges, not by sources.
The milestone includes three edges, and only those: the **slab edge** — a light strip along the
front edge of the slab; the **skirting** — along the bottom of the back wall; **pilasters** —
between door openings and at the walls. All of this is boxes without bodies, like the room walls.
The silhouette, shafts and dressing remain M18 and M19.

### 5. Materials: the floor polished, the rest rough

The floor is dark and smooth, for reflections: low roughness, a drop of metal. Walls and slabs are
rough concrete. The shaft is metal. These are PBR parameters on the same boxes; there are no
textures — they are the business of the M19 dressing.

### 6. Readability through diegetic indicator lights, not glowing boxes

A game object stops glowing as a whole: under beautiful light a glowing box-door looks alien, and
the greybox stays visible. Instead each one gets a small **light of its own**, like the indicators
in the reference:

| Object | Indicator light |
|---|---|
| Door | an indicator board above the leaf: red for a red door, warm for an ordinary one |
| Cab | two red indicators on the cab roof; arrows as before |
| Exit | a green sign above the opening |
| Lamp | the fixture itself — it is the source |
| Bullet | as before, it is light anyway |
| Actors | outline ([ADR-0022](0022-actors-rig.md), decision 4) |

Indicator lights are emission and do not obey scene light: the requirement of decision 5 of
[ADR-0019](0019-3d-pivot.md) is met by them on any floor, darkened ones included.

### 7. Atmosphere — with the trial's numbers, under budget

SSR, SSAO, volumetric fog at a hint of density, glow and ACES are taken from `look3d.gd` as is: they
are already tuned on our own geometry. They change only by measurement: `tools/light_bench.gd`
builds the real building with agents and measures the frame on the GPU. The 16.6 ms budget is the
limit, the number is written into STATUS.

**Light source brightness is an exception, and that is worth saying plainly.** The trial's numbers
belonged to its own light: six spots of 9 units each, tilted at the back wall. Ours is a cone
hanging at 1.8 m and shining down, and with the trial's numbers the first frame came out almost
black. Cone 9.0 at 6 m and 60°, fill 1.5 at 7 m and overall tone 0.55 were chosen by the frame —
the only numbers of the milestone whose source is "it looks right", not a measurement. The frames
they were chosen on are shot by `tools/dark_shot.gd`: the floor lit, a zone darkened, the floor
darkened entirely.

### 8. Whether an agent sees Otto is decided by Otto's shadow; a blind agent patrols

Until now darkness cut the range of an agent who himself stood in it
([ADR-0007](0007-lamps-and-darkness.md), decision 4). With zones this is reversed:
**from the shadow the lit one is visible; the lit one cannot see into the shadow.** An agent
notices Otto in a dark zone only closer than `agent_dark_fire_range` — 1.8 m, a third of the full
range, the M11 number on which the bot completes the building; a lit Otto he sees from full range,
wherever he himself stands. The agent's own shadow now affects only the price of his death
(ADR-0010, item 6).

Not seen — not a target. The brain gets "alive and visible" as one word and does not pursue an
invisible target: it goes where it was going, turns around at the edge of the floor and walks back.
This way the tactic "darken and stand in the shadow" works literally, not only as "does not shoot
from afar". The same word closes the M14 debt: Otto behind a door is invisible, and agents lose
him — in the original, entering a door meant throwing them off the trail.

Rejected: "both shadows — the worse range": simpler to explain but less honest, and checked in
exactly the same way. The number 1.8 is subject to bot measurement, like everything in the balance.

## What is not in the milestone

- **Windows, the city and cold light from outside** — M19.
- **Textures** — M19. Here materials set only roughness, metal and colour.
- **Lamp swinging after a shot.** A shot-down lamp falls immediately (ADR-0007), and it has no time
  to swing; the suspension — cord and socket — exists, swinging is not introduced.
- **Darkness fading in later buildings** — an open debt of ADR-0010, item 7.

## How we check

**Milestone DoD:** the light looks soft and volumetric, and at the same time on a dark floor the
player sees what he is shooting at.

- `test_side_camera.gd` — the axis of the tilted camera passes through the target in the play plane,
  the frame is taller by 1/cos vertically, the sound listener stays in the plane.
- `test_floor_lighting.gd` — zones without a scene: its own zone goes out, the neighbouring one stays
  lit, a floor without lamps never goes dark, a floor is dark when all its zones are out.
- `test_building_rules.gd`, `test_building_plan.gd` — lamps by floor width, spread along the floor,
  not sharing slots; the roof has none at all. In a degenerately cramped building every floor gets a
  lamp even when there is nothing left to share a slot with: a floor without a lamp is not lit and
  there is nothing to darken it with.
- `test_building_assembly.gd` — a shot-down lamp darkens a zone, not a floor; there are two fewer
  sources.
- `test_darkness.gd` — with a scene: a lit Otto is hit from full range; Otto in the shadow is not
  seen from afar, seen up close; an agent in the shadow sees a lit one; behind a door Otto is lost;
  a blind agent walks to the edge and turns around.
- `test_enemy_brain.gd` — an invisible target is not pursued or fired at.
- `test_readability.gd` — every door, cab, exit and lamp has an emissive element, actors have an
  outline. A structural check of what the frame with the lamps out must show.
- Frame budget — `tools/light_bench.gd`, manually, number in STATUS.
