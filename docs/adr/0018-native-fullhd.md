# ADR-0018 · Native FullHD and asset detail

- **Status:** superseded in the 2D part — [ADR-0019](0019-3d-pivot.md), decision 7:
  "an asset pixel is a world unit" and detail by canvas scale (decisions 1–3)
  went away together with sprites; the 1920×1080 viewport stayed. The proportions of decision 5
  were revised after the original — [ADR-0026](0026-proportions.md)
- **Date:** 2026-09-19

## Context

The world is drawn at 640×360 and tripled to 1080p ([ADR-0002](0002-visual-target.md)).
Playing the game by hand produced two complaints at once: not a single floor fits in the frame —
the narrowest one is 720 px with a 640 px frame — and the picture "looks kind of crappy".

### What the trial showed

Before touching three dozen assets, a trial was made: render them three times larger and see what
it gives. The result was not the one expected.

- **The environment gains nothing.** Assets are described by rectangles in world units: brick,
  mortar joint, panel. Multiplying by three makes each rectangle three times thicker — the picture
  comes out pixel for pixel the same. Resolution by itself does not buy a single detail.
- **Actors gain for free.** They come as a render from Blender, and on a three-times-denser frame
  they get a real penumbra on the face and a fold on the suit. It is a render setting, the model
  is the same.
- **A redrawn asset gains immediately.** In the trial the brickwork got varied brick tones, a
  bevel and chips; the door got a frame profile, two panels, a handle with a highlight and a
  threshold. The difference to the eye is bigger than from any resolution.

The conclusion that defined the milestone's scope: **resolution is the pretext, the work is
textures.**

## Decisions

### 1. The world becomes three times larger, not three times finer

The viewport is 1920×1080, and all world quantities are multiplied by three: floor height,
building width, actor height, speeds, jump, gravity. One asset pixel stays one world unit, as it
was, so the frame shows exactly what it did before — only three times denser.

The reverse move was also considered: keep the world as is, draw assets three times larger and
show them at ⅓ scale. Rejected: then every node that gets a texture must know about the scale —
and there are dozens of them in the project, from `TiledRect` to `NinePatchRect` and `Line2D`.
Forget one, and the asset sticks out three times larger than its place. With a stretched world
nobody knows about scale: the numbers are just different, and they are guarded by the same set of
tests as before.

Speeds and accelerations grow by the same factor: with tripled coordinates and tripled gravity the
jump trajectory is the same and the flight time does not change.

### 2. Detail is chosen by canvas scale, not by a second asset set

The environment generator knows its `scale` (`tools/render_env.py --scale`, removed in M16)
and on a large canvas draws what does not exist at world-unit size: tone variation, bevel, a joint
with depth, a chip, a lamp socket. The asset stays one, described in world units; fine detail is a
branch inside it, not a separate file.

This way the set will survive the next resolution change too: 4K will require editing one number
and new detail branches, not a second set of images.

### 3. What this supersedes

[ADR-0002](0002-visual-target.md) in the part "base viewport 640×360, 3× scale to 1080p" no longer
applies: the viewport is 1920×1080, there is no scale. The rest of ADR-0002 — HD pixel art with
dynamic lighting — is in force, and it is precisely for it that detail grows: light falls on the
normal, and the normal is computed from the height map, which on a large canvas has something to
describe.

[ADR-0011](0011-asset-pipeline.md) is in force entirely: the environment is still drawn by code,
the actors by Blender. Only the density changes.

### 4. There is no check against the original here, and that is fine

Neither the arcade nor the Spectrum port gives a 1920×1080 model: the first is 256×224, the second
256×192. There is nothing to align with, and the milestone is measured not by resemblance but by
its own DoD — by what is visible in a still frame.

### 5. Proportions: the man bigger, the door taller, the window smaller

Playing by hand produced the complaint: "a little man, little doors and absurdly huge windows".
That was so: Otto took 84 units with a floor clearance of 300, the door was only a fifth taller
than him, and the window was twice as wide as the door.

Actors grow one and a half times (rendering goes at scale 4.5 versus 3 for the environment: an
asset pixel is a world unit, and a denser render makes Otto bigger in the world itself), the door
from 102 to 171, the window shrinks from 216×120 to 150×100.

This is not only looks. Otto became bigger as a target, and it showed immediately: the agent's
bullet went 90 units above the floor and started hitting him in the head while he fell into a
shaft opening or stood in a cab that had stopped below the floor. The agent's line of fire is
raised to 105 — it must hit someone standing, pass over someone crouching and pass over someone
standing below floor level. The test `test_proportions.gd` holds this.

### 6. The shaft limit is shown in the frame

Also from playing by hand: "on some elevators the controls did not work — the cab would not obey
commands and stood still, and as soon as you stepped off, it drove away".

Checking all cabs of the building showed the mechanic is sound: it was the end of the shaft's
band. Shafts do not go all the way through ([ADR-0008](0008-building-generation.md)); a cab at the
edge hears the command but has nowhere to go, and when empty it immediately drives away on its
schedule. The player read the game's structure as a breakage — so the fault is not the mechanic but
the fact that the limit is shown by nothing.

We show it in two ways: a **buffer stop** in the shaft at the top and bottom of the band — visible
from outside, and **arrows in the cab** that go out when there is no way in that direction —
visible from inside, where the cab itself hides the buffer stop.

## What is not in the milestone

- **4K and arbitrary scale.** The generators can do any `--scale`, but one set is drawn and
  committed — three times larger than before.
- **New assets.** Existing ones are redrawn; floor dressing and city layers are M17.
- **Anti-aliasing and filtering.** A pixel stays a pixel: nearest-neighbour filter, as before.

## Sources

- Scale and detail trial: `tools/render_env.py --scale`,
  `tools/render_actors.py --scale` (both removed in M16); result —
  [`milestones.md`](../milestones.md), M13, "What the trial showed". The list "What playing by
  hand found" was in `STATUS.md` before this milestone (commit `f009aa3`)
