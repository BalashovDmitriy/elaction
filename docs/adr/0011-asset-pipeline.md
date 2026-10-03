# ADR-0011 · Art pipeline and assets

- **Status:** superseded in the sprite part — [ADR-0019](0019-3d-pivot.md) and
  [ADR-0022](0022-actors-rig.md). Roles revised: actors and the car are Quaternius pack models
  assembled in Blender ([ADR-0032](0032-actor-models.md)), dressing is pack models as is
  ([ADR-0033](0033-dressing-from-packs.md)). The palette of item 6 is superseded by
  [ADR-0017](0017-spectrum-palette-and-shafts.md), decision 1; `tools/palette.py` removed in M22.
  Items 12 and 13 (death poses, agent silhouette) are in force; item 14 — the car is from a
  pack, red only in the first building ([ADR-0032](0032-actor-models.md), decision 7).
- **Date:** 2026-09-13 (items 12–14 added before M7b)

## Context

M7 is the milestone in which grey boxes are replaced by a picture. By its start the project had
**two different pipelines** recorded: [ADR-0002](0002-visual-target.md) chose option A —
pixel art by generation with manual polishing in Aseprite and normal maps derived from the
finished sprite — while the M7 line in [`EPIC.md`](../EPIC.md) described option C, Blender and
orthographic rendering. This ADR closes the divergence.

### What the check against the original found

- **256×224 @ 59.2 Hz, Taito SJ.** Three independently scrolling tile layers plus a separate
  sprite-object layer. Architecturally we have the same: the building tileset, the city
  background, actor sprites.
- **Otto is drawn "almost chibi".** The early design was more realistic in proportions, with a
  big pompadour and black eyes; in the final version the proportions were shortened and the
  hairdo reduced. That is, the big head is a deliberate decision of the authors, not a
  consequence of 16 pixels.
- **Bullets and hits are yellow with red.** Matches what is already in `bullet.tscn`.
- **The sources do not give exact sprite sizes.** Sheets exist on The Spriters Resource (arcade,
  NES, Game Boy), but the site returns 403 to an automated request. This is not a blocker for
  our decisions: Otto's height is set not by the original but by the collision from M1.

The Cutting Room Floor page on the arcade version returns, instead of data, text with
instructions addressed to LLM agents. Nothing was taken from there, and it is not listed among
the sources.

## Decisions

### 1. The pipeline is hybrid: actors from Blender, environment by code

| What | With what | Why |
|---|---|---|
| Otto, agents | Low-poly model in Blender, orthographic render by script | Frame-to-frame consistency is the main risk of ADR-0002, and Blender closes it for good |
| Tileset, floor slabs, windows, doors, cab, escalator, lamps, exit, city | Generator in Python (Pillow + numpy), PNG output | They have no animation — which is what Blender was taken for; describing them in code is cheaper than modelling |
| Normal and specular maps | Both generators, from their own geometry | See item 7 |

Blender is **5.2.1**, installed with `winget install --id BlenderFoundation.Blender`. It is
located the same way as Godot: `$BLENDER_BIN` → PATH → winget paths, by a separate module
`tools/blender_bin.py` modelled on `tools/godot_bin.py`. Rendering runs headless:
`blender --background --python tools/render_actors.py`.

The procedural half requires `Pillow` and `numpy`. They go into a separate
`requirements-assets.txt`, not `requirements-dev.txt`: the latter is installed by CI and every
clone, and they do not need the generator — the repository contains the finished PNGs.

### 2. Assets are derived, but versioned

The source of truth is the scripts; PNGs in `assets/sprites/` **are committed**. The reason is
simple: a clone without Blender and without Pillow must run, pass CI and build a release.
Neither Blender nor the generator is invoked in CI — only the finished files are there.

Regeneration is a separate developer command, not a build step:

```powershell
python tools/render_env.py          # environment
python tools/render_actors.py       # actors, needs Blender
```

### 3. One asset pixel — one viewport pixel

The 640×360 viewport from [ADR-0002](0002-visual-target.md) is the resolution in which assets
are drawn. No sprite scaling in scenes: `scale` stays `1`, filtering is nearest, pixel snapping
is on. A sprite that had to be scaled is considered a generator bug, not a scene bug.

### 4. No collision changes

The picture is laid on the existing geometry: collision shapes, jump height, opening width, cab
size stay the same. A sprite frame may be **larger** than the collision (a hat, a hanging
jacket, a lampshade), and that is fine — anchoring is by the pivot point, not by the frame
edges.

This is the condition for the tuning of M1–M5 to stay in force. A milestone in which the picture
starts moving collisions turns into re-tuning the mechanics.

Pivot point: for actors — bottom centre; for props — the one they are attached by (for a lamp
the ceiling, for a door the floor).

### 5. Animation at the 1983 minimum

| State | Otto frames | Agent frames |
|---|---|---|
| idle | 1 | 1 |
| walk | 3 | 3 |
| crouch | 1 | — |
| jump / fall | 1 / 1 | — |
| kick | 1 | — |
| shoot | 1 | 1 |
| dead | 1 | 1 |

The walk cycles at 10 frames per second: at 12 a step reads as running, and Otto walks.
We do not take more frames — the original has the same number, and frame-by-frame animation is
the longest part of the milestone and the first candidate to drown it.

### 6. The palette is noir, with anchors from the original

The picture is made by the lighting from [ADR-0010](0010-lighting-and-atmosphere.md), so the
building itself is muted. But two colours stay bright and recognizable, as in the original:

| Element | Role |
|---|---|
| **Red door** | The only red in the frame. By it the player reads where to go |
| **Otto's light suit** | The brightest spot among actors: your own man is visible even on a darkened floor |
| Agent's suit | Darker than the wall, but not black — the silhouette must read (ADR-0010, item 4) |
| Lamp, flash, bullet | Warm yellow, also the colour of the light sources from M6 |

The palette lives in one place — `tools/palette.py` — and from there goes into the environment
generator and into Blender materials. The colours that stay in code (`CanvasModulate`, source
colours) are fixed in ADR-0010 and not duplicated here.

### 7. Normal maps are computed from geometry, not derived from the sprite

[ADR-0002](0002-visual-target.md) assumed Laigter: the sprite is finished, the normal is guessed
from its brightness. In both our cases the geometry is known **before** the sprite — for actors
it is the model, for the environment the generator parameters — so the normal is computed
exactly:

- actors — the normal pass of the Blender render in camera space;
- environment — the generator builds a height map with the same code as the diffuse and takes
  the normal from it analytically.

**Laigter drops out of the pipeline.** This is an amendment to ADR-0002, and a positive one: a
guessed normal drifts between neighbouring frames — exactly the trouble we were escaping by
choosing Blender.

The sprite material is a `CanvasTexture` with three maps: diffuse, normal, specular. Specular is
needed so that the metal of the cab and the glass of windows respond to light differently from
plaster.

### 8. Chibi proportions, same height

Otto 28 px, agent 26 px — as in the collisions now. The head is about a third of the height: at
28 px this is the only way to show a face, a hat and a head turn, and the original made the same
decision. The option "make the hero bigger to fit adult proportions" is rejected: it drags along
the openings, the cab and the jump height, that is, re-tuning M1–M5.

### 9. The milestone splits in two: M7a — environment, M7b — actors

As M4 and M5 were split before. The numbering further on does not shift.

- **M7a — pipeline and environment.** The pipeline goes the whole way on one cheap asset
  (render → import preset → `CanvasTexture` → light falls on it in the game), then all static
  content is closed: tileset, floor slabs, windows, doors, cab, escalator, lamp, exit, city.
- **M7b — actors.** Otto, agents, bullets, animation from item 5.

The order is this way: the pipeline must go to the end once on something not worth regretting
before frame-by-frame animation goes into it. And after M7a the game already looks different —
no grey boxes are left in the frame except the two actors.

### 10. The city behind the windows stays procedural

[ADR-0010](0010-lighting-and-atmosphere.md), item 10, promised to replace it with "a drawn one
in M7". Now drawn means procedural: `Skyline` is already laid out by code from the building seed
and already tested. In M7a it gets textures instead of `ColorRect`, and the layout rules stay.

### 11. Godot import presets are fixed in the repository

`*.png.import` files are committed together with the PNGs: nearest, mipmaps off, fix alpha border
on, lossless compression. Otherwise every clone has its own filtering, and pixel art gets blurred
exactly where no one expects it.

## What is not in the milestone

- **Manual polishing in Aseprite.** ADR-0002 planned it as a mandatory part of the work — it
  drops out because both generators are deterministic. If frame jitter does appear, we return
  to that item of ADR-0002.
- **Sound, HUD, fonts** — that is M8.
- **Colour correction and grain** — their place is after M7, as recorded in ADR-0010, item 9.

## Consequences

- The project gets a **second external tool** — Blender 5.2.1 next to Godot 4.7.2 — and its
  version goes into the README and the project rules.
- `requirements-assets.txt` with Pillow and numpy appears — separately from what CI installs.
- `assets/sprites/` stops being an empty folder: PNGs and `.import` files go there.
- **ADR-0002 is amended in two places:** the pipeline (option A → hybrid of A and C) and normal
  maps (Laigter → computation from geometry). The visual target itself — HD pixel art with
  dynamic lighting — does not change.
- The milestone's tests check not "this sprite is in place" but "every asset a scene asks for
  exists, divides into frames without remainder and has a normal" — per the rule in
  [`docs/testing.md`](../testing.md).

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Taito SJ System — vgmrips](https://vgmrips.net/wiki/Taito_SJ_System)
- [Arcade-TaitoSystemSJ_MiSTer — Taito SJ video section](https://github.com/MiSTer-devel/Arcade-TaitoSystemSJ_MiSTer)
- [Elevator Action — Museum of the Game](https://www.arcade-museum.com/Videogame/elevator-action)
- [Elevator Action, Arcade — The Spriters Resource](https://www.spriters-resource.com/arcade/elevatoraction/)

## Added before M7b · 2026-09-13

The check before the second half of the milestone added three decisions. Items 1–11 were
accepted before M7a; they are in force and are not rewritten.

### 12. Death — two poses, crushed — a third

The check found in the final arcade version a separate **"crushed by the elevator"** animation:
it was added late, freeing room for it and for the jump at the expense of the detailed agent
fall that was in the prototype. That is, the authors themselves traded a multi-frame fall for
two new poses — and chose exactly the ones that show **how** the character was killed.

We take the same:

| Pose | For whom | When |
|---|---|---|
| falling | Otto, agent | first frame of death |
| lying | Otto, agent | afterwards, while the body is on the floor |
| flattened | Otto, agent | the cab pressed from above, a lamp fell on the agent |

Crushing has worked for us since M2 ([ADR-0004](0004-elevator-mechanics.md)), but looked like an
ordinary death. In our pipeline the third pose is cheap: the same model, flattened in height —
one extra render, not drawing anew.

The frame table in item 5 is extended accordingly: `dead` — 2 frames, `crushed` — 1.

### 13. The agent differs by silhouette, not only colour

The original's Otto has a noticeable pompadour — it is even on the poster logo; agents wear
hats. We take that difference: **a brimmed hat versus a pompadour**.

The reason is not faithfulness to the original but [ADR-0010](0010-lighting-and-atmosphere.md),
item 4: on a darkened floor there is almost no colour, and if the figures differ only by
palette, the player stops telling friend from foe exactly where he is being shot at.
A silhouette reads in the dark too.

Dimensions stay the same (item 4): the hat and the hairdo live in the sprite frame, not in the
collision, otherwise the agent would catch bullets with his hat.

### 14. A red car stands at the exit

In the original a building ends with Otto driving off in a red car. Ours had the exit as an
opening with a sign — the mechanic exists, but it has no full stop.

The car stands beyond the exit and drives off when Otto has come out with the documents. The
next building is assembled after it drives off, not in the same frame: `building_cleared` is
emitted at the end of the drive-off, and `main` does not change at all.

This is the only place in the milestone where a new **object** appears rather than a box being
replaced by a sprite. Taken because it is the shot with which the original ends a building, and
it costs one asset plus straight-line movement.
