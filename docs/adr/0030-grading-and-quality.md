# ADR-0030 · M22: grading, graphics quality and cleanup

- **Status:** accepted; decision 5 amended by [ADR-0034](0034-ultra-and-auto-quality.md):
  a fourth level "Ultra", antialiasing per level, the default level is chosen
  by a measurement on first launch rather than high
- **Date:** 2026-09-23

## Context

Written as M20; by the user's decision grading moved to M22, onto the detailed
scene ([ADR-0031](0031-scene-detail.md)). Tone, graphics quality, the city blur
and skipping the city behind a solid building were already done in the M20
branch and are in the code; in M22 they are tuned against frames.

The last milestone of the pivot (ADR-0019). The building, light, city and
dressing are in place; what remains is what is done on a finished scene: the
frame tone, dithering, the budget across the whole building and cleanup of what
is left from 2D. The milestone has no check against the original — this is the
craft of our frame, not 1983 mechanics.

The frame was measured only on three floors near the roof (`tools/light_bench.gd`)
and only on one graphics card — RTX 5060 Ti. Windows and Linux builds are
already released (ADR-0013), and the game has no quality setting.

## Decisions

### 1. Tone — night noir, as in the reference

The user's decision. Cold blue-teal shadows, warm lamp light, deeper black,
slightly less saturated walls. Done in the scene's environment
(`Atmosphere`): color correction with per-channel curves (shadow → light
gradient), contrast and saturation. Game signs — doors, red doors, readability
indicator lights, actor outlines — glow with emission and stay bright: the frame
tone does not dim them, and this is verified with frames on a dark floor.

### 2. Depth of field — only the city

The user's decision. The play plane and rooms behind doors are sharp:
readability matters more than cinema. The city background is blurred — the far
rows more — by its own camera (`CityBackdrop`); the main frame is untouched.

### 3. Light vignette, no grain

The user's decision. The frame edges are slightly darker — the eye goes to the
middle, where Otto is. The vignette is a canvas layer between the scene and the
HUD: it does not darken the interface. No grain: on dark floors it is noisy
exactly where the player is already peering.

### 4. Dithering — via a render setting

Banding on fog and sky gradients is removed by `use_debanding` in `project.godot`.
It is a render setting, so it is also noted in ADR-0002 (project rule).

### 5. Graphics quality — three levels in the settings

The user's decision. Low, medium and high:

| | Low | Medium | High |
|---|---|---|---|
| Floor reflections (SSR) | no | no | yes |
| Contact shadows (SSAO) | no | yes | yes |
| Volumetric fog | no | yes | yes |
| Lamp shadows | no | cone | cone and fill |
| Fill radius | one floor | one floor | 7 m |
| City | third resolution | half | half |
| Rain | quarter of drops | half | all |

Default is high. The level is stored in the settings and applied to the
current building immediately, not from the next one. Game rules do not depend
on the level: darkness is a rule (`FloorLighting`), not a picture, and on any
level an agent in the dark sees Otto the same way.

### 6. Budget — across the whole building

`light_bench` gets a run over all floors: the camera passes the building from
top to bottom, and the worst frame is recorded — on every quality level.

### 7. The city is not drawn when it is not visible

M19 debt. When the building covers the whole frame — at the wide bottom and on
the tower with no roof in the frame — the city view is not updated.

### 8. 2D cleanup

ADR-0019, decision 8: sprites and 2D systems went away over the milestones. The
leftovers — the sprite palette generator (`tools/palette.py`), palette fields
with no readers and outdated mentions of `CanvasItem.modulate` — are removed.
Comments "as it was in 2D" that explain conventions of the rules layer (y axis
down) stay: they are about the rules, not the rendering.

## How we verify

- Milestone frames on a lit and a dark floor, on the roof in every weather and
  on every quality level; comparison with the reference and with the original.
- Test: the quality level turns on and off what the table promises and does not
  change the rules — darkness and agent visibility are the same on all levels.
- The whole-building budget is recorded as a number on every level.
