# ADR-0032 · M21: Otto and agent models from the Quaternius pack

- **Status:** accepted
- **Date:** 2026-09-24

## Context

Since M16 (ADR-0022) Otto and agents are figures made of boxes on seven bones:
hips, torso, head, arms and legs with one bone each. There are no knees or
elbows, so the crouch is a 76° torso tilt, and it reads as "bent over" rather
than "crouched" (M18c debt). The head is a third of the height, like a sprite
chibi.

The user's decision (ADR-0031): models come from the **Quaternius Ultimate Modular
Men Pack**, CC0 license, the Business Man character for Otto and for agents.

### What the check showed

- **Model.** Business Man — 4162 triangles, four meshes (legs, torso, feet,
  head) and eight color materials, no textures. Height 1.86 m, the head is about
  a fifth of the height.
- **Skeleton.** 62 bones: Root, Body, Hips, Abdomen, Torso, Chest, Neck, Head,
  shoulder, upper arm, forearm and hand with fingers, thigh, shin and foot.
  **Knees and elbows exist.** Rest is a T-pose, arms horizontal.
- **Clips.** 24 of them: Idle, Idle_Gun, Idle_Gun_Shoot, Gun_Shoot, Walk, Run,
  Death, Kick_Left/Right, Roll, HitRecieve and others. **There is no crouch,
  prone or jump** — and those are exactly the heights the ROM fixes: a bullet at
  1.13 m standing, 0.68 crouched, 0.23 prone (ADR-0027), and the poses are fitted
  to them.
- **Business Man has no hat.** Farmer has a brimmed hat, but with a red band and
  a wide brim — a cowboy silhouette.
- **There is no pistol in the pack** for any character: the "with gun" clips hold
  an empty hand.

## Decisions

### 1. Mixed animation: pack clips and poses in code

The user's decision. Where the ROM does not dictate heights, pack clips move;
where it does, our poses in code, now with knees and elbows:

| Pose | By |
|---|---|
| idle | clip Idle_Gun |
| walk | clip Walk, by walk phase |
| shoot | clip Idle_Gun_Shoot |
| dead_0, dead_1 | clip Death: middle and last frame |
| crouch, prone, jump, kick, crushed | code poses from `FigurePoses` |

Code poses are built **not from rest** but from the first frame of the stance:
in a T-pose the arms are horizontal, and "arm at −4° forward" from it means
nothing. A bone rotates around the figure's side axis taken in the bone's own
space — so the pose table does not care about the roll of the pack's bones or
their axes.

**Own sampling instead of AnimationTree.** The rig reads a clip directly —
`Animation.rotation_track_interpolate` at the needed moment — and a pose of
either nature becomes the same thing: a set of bone rotations. A transition
between poses is spherical interpolation per bone, as the angle smoothing has
been since M16. This is simpler than joining `AnimationTree` with code poses,
and two things the tests rely on stay valid: `snap()` sets a pose immediately,
and the bounds are computed from skinned vertices.

### 2. The agent's hat — our own fedora

The user's decision. Built in `build_actors.py` and attached to the head bone: a
crown with a pinch and a narrow brim in the agent's hat color. A gangster
silhouette, like the agents in the original. Other heads from the pack are not
used.

### 3. Otto — in the previous palette, without a hat

The user's decision. The model is shared; the difference is color and head: Otto
has a cream suit and dark hair, an agent has a dark-blue suit, a fedora and
glasses. On a dark floor the hat silhouette tells an agent apart even without
color.

### 4. Agents get dark glasses

The user's decision. A thin plate with two lenses on the head bone, over the
pack's eyes.

### 5. We build the pistol ourselves

There is no pistol in the pack, so `build_actors.py` builds it from primitives and
attaches it to the right hand — as it was with the M16 figure.

### 6. Pipeline: the pack source in the repository, build via Blender

- The source `business_man.glb` (1.5 MB, CC0) lies in `assets/source/quaternius/`
  with the license. `assets/source/` has a `.gdignore`: Godot does not import the
  source; the game has only the built models.
- `tools/build_actors.py` opens the source in Blender, scales the height to
  `Proportions.BODY` (1.68 m), recolors materials with the actor palette,
  adds the fedora, glasses and pistol, keeps the four needed clips and writes
  `otto.glb` and `agent.glb`.
- Bone names are the pack's. The rig looks them up by name and fails with an
  error if a bone is missing — as since M16.
- Deferred from M20: `car.glb` with no reader and its build go away together with
  the old figure.

### 7. The car at the exit — from the Cars Pack, a different one in each building

The user's decision, made during the milestone. Quaternius has a Cars Pack (CC0):
taxi, police car, SUV, two sports cars and two regular ones. Five go into the draw
— **except the taxi and the police car**: a spy driving away in a patrol car is
odd. Which car and what color is a draw by the building salt, but **the first
building gets the red sports car**, as in 1983. The length of any car is scaled to
`Proportions.CAR_LENGTH` so that the exit and the garage opening do not shift.
`CarModel` from primitives goes away.

### 8. Proportions — the pack's

The head is about a fifth of the height instead of a third. The height is the
same, 1.68 m, and equals the collision (ADR-0026, decision 8).

## Consequences

- The crouch finally reads as "squatting": the hips go down, the knees bend,
  rather than the torso lying on the knees.
- Lively walking and death via clips — without manual work.
- The model is two hundred times heavier than the old box one (about 3000
  vertices versus a hundred), and grounding is computed from skinned vertices.
  So for grounding the rig takes a thinned set of vertices and computes it only
  when a code pose or a transition is running; clips are grounded by the pack
  itself.
- Vertex-based pose tests stay: crouch under a standing bullet, an agent on one
  knee under a standing shot, a prone agent under a crouched shot.
