# ADR-0019 · Moving to a 3D scene

- **Status:** accepted
- **Date:** 2026-09-19

## Context

A reference arrived: a side cross-section of a building, shot in 3D. A polished floor with
reflections, volumetric light, glass partitions, neon signs, depth of field. The question was
direct — will we get close to this, and what does it cost.

We will get close, but not in 2D. The reflections, volumetric light and materials in the reference
are a 3D render with an orthographic camera. Godot 4 can do everything visible in the frame. The
issue is not the engine but that our scene is made of sprites, and that one of geometry.

### What the trial showed

Before deciding, a trial was assembled ([`tools/look3d.gd`](../../tools/look3d.gd)):
three floors of our own geometry — numbers taken from [`BuildingRules`](../../src/levels/building_rules.gd) —
a side ortho camera, PBR materials, SSR, SSAO, volumetric fog, glow, ACES.

- **The engine is not the bottleneck.** A frame with reflections, fog and two dozen
  shadow-casting sources costs **1.8 ms against a budget of 16.6**. A nine-fold margin.
- **A side ortho camera does not see the floor.** This is the main finding, and it cost three
  almost black frames. The camera looks strictly horizontally, so the top face of the slab is a
  zero-thickness strip. A lamp shining straight down lights exactly what is not in the frame.
  Floor reflections — the technique 3D was undertaken for — **do not work from the side in pure
  form**.
- **Light needs geometry.** A smooth box gives an even fill and reads as a blurry blob. Half the
  frame was pulled out not by the sources but by pilasters, slab edges and a skirting panel: an
  edge is contrast.
- **Readability breaks first.** In the frame with the lamps out, the silhouettes of floors, cabs
  and actors hold, but **the door disappears completely**. The door is the goal of the game.

## Decisions

### 1. We move to 3D nodes rather than putting a 3D render under 2D physics

Both paths were considered.

**Keep 2D physics and run a 3D scene alongside for the picture.** Keeps the node layer and the
physics tests untouched. Rejected: the bridge between the two worlds would have to be maintained
forever, and depth for shadows and reflections would have to be invented anyway — that is, a second
world would arise by itself, only implicitly.

**Move to 3D nodes, locking movement to the XY plane.** Chosen. We go to 3D for the light, so the
light must live in the same world as the geometry. The Z coordinate of game bodies is fixed: the
game stays flat, only the scene is three-dimensional.

### 2. The rule core does not move at all

`src/` has 42 scripts, 21 touch 2D nodes. The other half is rules:
`OttoStateMachine`, `ElevatorMotion`, `ShaftHazards`, `BuildingPlan`,
`BuildingRoute`, `EnemyBrain`, `DocumentRoute` — all on `RefCounted` and `Resource`,
without a scene and without physics. They survive the render change without a single edit, and
together with them most of the 315 tests survive.

Hence the rule for all milestones of the pivot: **if a new mechanic ended up in a node, it is
written wrong.** A node translates a decision into a coordinate and dispatches events; the decision
is made by a class without a node.

### 3. The scale is metric: 100 units of the former world = 1 metre

A 360 floor becomes 3.6 m, a 171 door — 1.71 m, a 126 Otto — 1.26 m. The numbers of
[ADR-0018](0018-native-fullhd.md) are not recomputed anew but divided by a hundred: the proportions
are already chosen and checked by `test_proportions.gd`.

The metre is chosen because things that cannot be set in pixels depend on it: light attenuation,
fog density, material roughness, depth of field.

### 4. Every milestone ends with a playable build

The biggest risk of the pivot is to spend six to nine milestones without a game. It is cured by the
order of work: the first milestone gives not a picture but a **playable 3D greybox** — boxes
instead of assets, but Otto walks, cabs ride, agents shoot, the bot completes the building. Beauty
is laid on top, milestone by milestone.

The project has gone this way once already — M1 greybox, M7 assets — and it worked then. A
milestone that aims straight at the look gives a pretty unplayable mock-up and no way to understand
what broke.

Until the 3D build has passed the bot on three lives, **the 2D build in `main` stays buildable**:
it is the only thing that can be shown and played.

### 5. A game object does not depend on scene lighting

Straight from the trial. The door, document, lamp, agent and cab must read on a darkened floor:
their own emission, an outline or a highlight — but not relying on the room's light.

Checked in every milestone of the pivot: a frame with the lamps out is shot on par with a lit one
(`tools/look3d.gd --dark` and then `capture.py`), and every object the player interacts with is
visible in it.

This constraint matters more than cinematic quality: [ADR-0010](0010-lighting-and-atmosphere.md),
item 4, leaves agents shooting in the dark, and the player must see what he is shooting back at.

### 6. Camera tilt is an open question for the lighting milestone, but with a constraint

The floor is not visible because the camera is strictly from the side. It can be brought back by a
tilt of a few degrees — then reflections appear too. How much to tilt is decided by a trial in the
lighting milestone, not here.

The constraint is set now: **the binding "floor — horizontal band of the frame" and the bullet's
flight do not depend on the tilt.** A bullet flies in the XY plane, and the hit is computed in it
too; tilt is a property of the camera, not of the world.

### 7. What this supersedes

- **[ADR-0002](0002-visual-target.md) is superseded entirely.** HD pixel art with dynamic 2D
  lighting was the project's visual goal; the goal becomes a 3D scene. The render settings in
  `project.godot` tied to that decision (`snap_2d_transforms_to_pixel`, nearest-neighbour filter,
  `canvas_items` stretch) are revised in the first milestone of the pivot.
- **[ADR-0011](0011-asset-pipeline.md) changes by half.** Blender stays and becomes the whole
  pipeline: it no longer renders sprites but exports models. The Python environment generator
  (`tools/render_env.py`) goes entirely.
- **[ADR-0017](0017-spectrum-palette-and-shafts.md) is superseded in the palette part.**
  Spectrum colours do not live with a dark volumetric frame. The round palette as a technique —
  each building its own colour — stays: it comes from the original, and in 3D it is applied to
  materials and to the light temperature.
- **[ADR-0018](0018-native-fullhd.md) is superseded in the part "an asset pixel is a world
  unit".** The 1920×1080 resolution stays; detail stops being a function of canvas scale: it is
  set by geometry and material.
- **[ADR-0010](0010-lighting-and-atmosphere.md) changes by half.** The lighting implementation
  (`AreaLight`, `LightTextures`, `VisibleFloors`, `postprocess.tscn`) goes. All the rules stay: two
  sources per floor, a shot-down lamp darkens the floor permanently, in the dark an agent sees a
  shorter distance but does not stop shooting.

### 8. What is thrown out

`tools/render_env.py` and the whole set of environment sprites, `TiledRect`,
`BuildingBackdrop`, `Skyline`, `AreaLight`, `LightTextures`, `postprocess.tscn`,
`SpriteTextures`. That is about a third of `src/` and a larger chunk of `tools/`.

It is thrown out as it gets replaced, not up front: until the 3D build has passed the bot, the 2D
build must keep building (decision 4).

## What we do not do

- **We do not rewrite the logic.** This move does not change a single game rule. The mechanics
  stay the mechanics of 1983.
- **We do not make three-dimensional gameplay.** Movement is locked to the plane; depth is a
  property of the picture. Otto will not walk "into the depth".
- **We do not change the language.** Typed GDScript, [ADR-0001](0001-tech-stack.md) in force.
- **We do not take the cheap middle road.** It was on the table: keep 2D but draw the environment
  as a Blender render — about sixty percent of the impression for a third of the work. Rejected
  deliberately: floor reflections and volumetric light cannot be had this way, and they are what
  all of this is undertaken for.

## Sources

- Trial: [`tools/look3d.gd`](../../tools/look3d.gd), frames `screens/look3d/`
  (lit and with the lamps out), the frame timing in the run output
- Reference: [`docs/reference/3d-look-reference.jpg`](../reference/3d-look-reference.jpg).
  It sits under `.gdignore` so the engine does not import it and it does not end up in the build
  as a game resource
