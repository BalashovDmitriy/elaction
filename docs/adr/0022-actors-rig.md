# ADR-0022 · Actors: rig from Blender, animation in code

- **Status:** changed. Decisions 1–3 are replaced by [ADR-0032](0032-actor-models.md):
  a Quaternius pack model with knees, the pack's clips together with code poses, the pack's
  proportions; height 1.68 m — [ADR-0026](0026-proportions.md), decision 2. Decision 4
  (outline) in force. `tools/palette.py` from decision 5 was removed in M22
  ([ADR-0030](0030-grading-and-quality.md), decision 8)
- **Date:** 2026-09-20

## Context

M16 is the second milestone of the pivot: instead of greybox boxes, Otto, the agent and the car at
the exit get models and animations. [ADR-0019](0019-3d-pivot.md) recorded that Blender stays in the
pipeline and "no longer renders sprites but exports models". How exactly is decided here.

### What the check found

- **Our set of poses is already complete.** According to The Cutting Room Floor, the falling agent
  in the original had noticeably more frames than remained in the final version; the freed space
  was spent on the jump and on being crushed by the cab. We have had all these poses since M7b:
  walk, crouch, jump, kick, shoot, two deaths and crushed, and for the agent — kneeling and prone.
  The milestone introduces no new poses.
- **The figure is already described by code.** `tools/render_actors.py` built an actor in Blender
  from boxes — legs, torso, arms, head, hat or pompadour, a pistol in the hand — and held a pose
  table as limb angles. This is a ready parametric rig, and the milestone's question is not "how to
  model" but "where this rig lives and who moves it".
- **The chibi proportions are deliberate** ([ADR-0011](0011-asset-pipeline.md), item 8):
  Taito's big head is the authors' decision, not a consequence of sixteen pixels.

## Decisions

### 1. Blender builds the rig and exports glTF; there are no animation clips in it

`tools/build_actors.py` — the successor of `render_actors.py` — assembles in Blender the same figure
from boxes, but instead of rendering it hangs it on an **armature**: bones for the hips, torso,
head, two arms and two legs. Each box is fully weighted to one bone — skinning without bends, the
boxes stay rigid. The figure is merged into one mesh and exported to `assets/models/<actor>.glb`
together with materials; the car at the exit — by the same script, without an armature.

Porting the figure straight into Godot as hinge nodes was considered — cheaper and without export.
Rejected for the sake of a skeleton: `Skeleton3D` with bones is the standard anchor for everything
that comes later, from a skinned model to animation retargeting, and the code that moves bones does
not change with such a replacement. Blender meanwhile stays a developer tool, not a build tool:
`.glb` files are versioned, as PNGs were versioned before ([ADR-0011](0011-asset-pipeline.md),
item 2).

### 2. Animation is procedural and lives in code

The pose table moves from Python to GDScript — [`FigurePoses`](../../src/systems/assets/figure_poses.gd):
per pose — leg and arm angles, torso tilt, whole-body tilt, hip drop.
[`FigureRig`](../../src/systems/assets/figure_rig.gd) — a node on top of the imported `.glb` — finds
bones by name and every frame drives them toward the pose angles with exponential smoothing; walking
is not three frames but a continuous cycle: legs and arms swing by a sine in antiphase, the body
rises slightly at mid-step.

The EPIC listed `AnimationTree`. It is deliberately not taken: our poses are data, not clips,
transitions between any two poses are the same, and the rule "which pose to show" already exists —
`ActorPose`, the same one that picked the sprite. An animation tree would duplicate it in the
editor, poses would have to be edited by hand, and tests would see only the result. The procedural
rig is checked without rendering — by bone angles.

The "animation smoothness" feedback is closed entirely by this decision: smoothing makes any
transition smooth, and the walk cycle makes the walk itself smooth.

### 3. Chibi proportions, same height

Otto — 1.26 m, agent — 1.17 m, exactly by the collisions; the head is a third of the height. The
head will not be smaller: in a three-floor frame an actor is a tenth of the screen height, and the
hat and pompadour remain the only thing by which friend is told from foe in the dark
([ADR-0011](0011-asset-pipeline.md), item 13).

Crouching and kneeling are not a different figure, as with sprites, but a skeleton pose: the hips
drop, the legs bend forward, the torso leans. The figure must fit into the crouch collision
(0.81 m), and this is checked by a test on the bone extents, not by eye.

### 4. The actor is lit by the scene; readability comes from an outline

From M16 the actor stops emitting light itself: materials come from the `.glb` as ordinary ones,
and the lamp casts shadow on the figure. The requirement of [ADR-0019](0019-3d-pivot.md),
decision 5, is not lifted by this — on a darkened floor the actor must be visible, because he does
not stop shooting. It is met by an **outline**: a second pass over the mesh (`material_overlay`) —
an inverted hull, front faces culled, unshaded, slightly wider than the body. It is visible in any
light because it does not obey light.

Rim light does not work for this, though it comes to mind first: in `StandardMaterial3D` it is a
term of the lighting, and on a floor without a lamp it goes out with everything else. The strength
and colour of the outline will be tuned by M17 together with the light; here it exists and holds
readability.

### 5. What goes away

The sprite pipeline is done with: `tools/render_actors.py`, `tools/render_env.py`, `assets/sprites/`
in full. The greybox `ActorBox` is replaced by `FigureRig`. `tools/palette.py` stays — it is the
source of colours for the new materials too. `requirements-assets.txt` stays too: Pillow, numpy and
soundfile are needed not by sprites but by the sound and icon generators (`render_audio.py`,
`render_icon.py`).

[ADR-0011](0011-asset-pipeline.md) is thereby superseded in the "render to sprites" part and stays
in the roles part: Blender for actors, code for everything else.

## What is not in the milestone

- **A skinned model with joints.** Boxes bound to bones are a rig without bends: the knee does not
  bend, the elbow does not bend. A model with bends will go onto the same skeleton when we get to
  it, and `FigureRig` will not notice.
- **Materials and lighting for the figure.** A rough suit, cloth versus skin — M17 together with all
  the lighting.
- **A second agent type.** A kneeling shooter in a helmet — the parked M16a.

## How we check

**Milestone DoD:** a still frame of the walk shows that it is a step, not a picture swap, and Otto
crouching is still below the agent's bullet.

- `test_figure_poses.gd` — without a scene: every `ActorPose` pose has an entry, the walk cycle
  swings the legs in antiphase, a blend of two poses at its ends matches them.
- `test_figure_rig.gd` — with a scene: the models load and carry all bones; the crouch pose puts the
  figure's extents below the agent's bullet; within one transition frame the bones move but do not
  arrive — this is exactly "not a picture swap".
- `test_proportions.gd` does not change: the collisions are the same.
