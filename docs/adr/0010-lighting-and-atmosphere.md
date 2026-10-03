# ADR-0010 · Lighting and atmosphere

- **Status:** accepted; the 2D-light implementation is superseded by [ADR-0019](0019-3d-pivot.md),
  decision 7, the rules stay in force. Items 3 and 5 are changed by
  [ADR-0023](0023-light-and-readability.md): there are several lamps per floor and darkness
  comes in zones (decision 2), whether an agent sees Otto is decided by Otto's zone
  (decision 8). Item 10 — the city as 3D blocks,
  [ADR-0029](0029-city-weather-dressing.md), decision 1
- **Date:** 2026-09-12

## Context

M6 is the milestone for which Godot was chosen in [ADR-0001](0001-tech-stack.md), and HD pixel
art with dynamic lighting in [ADR-0002](0002-visual-target.md). Before it the game looks like
grey boxes, and that was deliberate: mechanics matter more than the picture.

The original has no dynamic lighting at all — it is 1983, flat colours. So there is almost
nothing to check here: the target is set not by the original but by ADR-0002. Still, the check
before the milestone found two rule divergences, and they are below, in items 6 and 7.

## Decisions

### 1. The light budget is not a constraint. Measured, not guessed

The debt "Godot's ceiling on 2D sources is unverified" had hung since M0. Closed by measurement
(`tools/light_bench.gd`), 1280×720 window, RTX 5060 Ti:

| Sources | Shadows | Bloom | ms/frame |
|---|---|---|---|
| 0 | no | no | 0.34 |
| 12 | yes | no | 0.42 |
| 48 | yes | no | 0.49 |
| 24 | yes | yes | 0.59 |

The frame budget at 60 FPS is 16.6 ms. Even 48 sources with shadows and post-processing eat
4 % of it. A twenty-five-fold margin.

The numbers were re-measured after code review: in the first version of the bench all sources of
the small measurement piled onto one floor over one occluder, that is, it measured something
that does not happen in the game. The conclusion did not change — only the numbers did.

Two consequences follow. First: **the "no more than ~12 sources" limit recorded in the epic
stays, but as an artistic constraint rather than a technical one** — more than a dozen light
spots in the frame turn into mush before they turn into an FPS drop. Second: the measurement was
made on a fast graphics card, and the absolute numbers do not transfer to the target hardware;
what transfers is the conclusion that light here is cheaper than anything else in the frame.

**What the measurement does not cover.** The bench scene is light — a dozen rectangles. In Godot
a source redraws the canvas items that fall into it, so the cost grows as
"sources × items under them". The real building is denser. So the milestone DoD is measured
again, on the assembled building with real lighting.

### 2. Light falls on grey boxes. Normal maps move to M7

The epic lists for M6 "normal maps and specular on sprites via `CanvasTexture`", but there is
not a single sprite in the project: everything is drawn with `ColorRect`. Textures come in M7.

So the milestone is split where it stands: **M6 — all the lighting** (ambient, sources,
occluders, post-processing, background), **M7 — materials** that this light will fall on.
The order is this way because lighting is tuned once and survives replacing a box with a sprite,
while the reverse order would force tuning the light twice.

### 3. A floor is lit because a lamp is on there

The key decision of the milestone, from which everything else follows.

`CanvasModulate` sets the overall tone of the building — and that is the tone of a **darkened**
floor. A floor is made bright not by the absence of darkness but by its own light source. Shoot
the lamp down — the source goes out, and the floor falls to the overall tone.

This way darkness stops being a semi-transparent band on top of the picture (the placeholder
from [ADR-0007](0007-lamps-and-darkness.md), item 6) and becomes what it is in the game: a floor
without light.

**A floor has two sources, not one.** There is one lamp per floor, its spot has a radius the
height of a floor, and a floor is 1280 px wide. One spot cannot light it, and a "lit floor"
would be lit only under the lamp. Therefore:

- **floor fill** — a wide soft source across the full width of the floor, even light, shadows
  off. This is "the light is on on the floor";
- **lamp spot** — a small bright source right under the lamp, shadows on. This looks good and
  shows where the light comes from.

Both go out at once, because the building has one lamp per floor and one circuit.

### 4. A darkened floor stays readable

Of two extremes — "atmospheric, but enemies cannot be seen" and "everything is visible, but not
scary" — readability is chosen. A darkened floor is noticeably darker and colder in tone, but
the silhouettes of Otto and agents on it are always distinguishable.

The reason is not aesthetics but the rules: in the dark agents **keep shooting**, only their
range drops ([ADR-0007](0007-lamps-and-darkness.md), item 4). A floor where the enemy cannot be
seen but shoots is death for reasons outside the player's control. Darkness must stay a tactic,
not a lottery.

### 5. Light is a picture, not a rule

There was a temptation: since there are real light spots, let an agent see Otto farther when
he stands in the light and worse when in shadow. Rejected on purpose.

- The original does not have it: there the whole building goes dark at once, and there is
  nowhere to hide in the shadows.
- The rules would have to be rewritten from "the floor is dark" to "the point is lit", that is,
  bring lighting logic into physics and `EnemyBrain`. Now darkness is one flag per floor, and
  it is tested without a scene; after such a change the most important tests would require a
  rendered frame.

`FloorLighting` stays the source of truth about where it is dark. The picture follows it,
not the other way round.

### 6. The bonus for a kill in the dark is +50, not doubling

[ADR-0007](0007-lamps-and-darkness.md), item 5, took doubling "as the simplest rule" and
honestly marked it unchecked. The check before M6 closed it:

> You score 100 points for shooting an agent, 150 for dropkicking them or shooting one
> in the dark — dropkicking an agent in the dark is 200 points — and 300 for defeating
> one via shot lamp.

That is, the bonus is flat, +50, and the same for both methods. Our base numbers
(100 / 150 / 300) match this table one to one, which is what makes the bonus from it credible.

This also fixes what we ourselves complained about in ADR-0007, item 3: with permanent darkness
doubling is a direct incentive to darken the floor and farm points on respawning agents. A flat
bonus gives no such incentive.

The bonus is not awarded for the lamp: the lamp darkens the floor as it falls and kills on the
way — at the moment of impact the floor is still lit.

### 7. Darkness in later buildings does not weaken yet

The check found a second thing:

> In later levels, it doesn't work as well or at all.

That is, in later buildings darkness helps less. [ADR-0007](0007-lamps-and-darkness.md),
item 4, anticipated this: "it will also be convenient to weaken in later buildings". Decided
**not to do it in M6**: it is a difficulty rule, not a picture, and its place is next to
`agent_menace` from [ADR-0009](0009-game-loop-and-alarm.md). Filed as debt.

### 8. Sources are turned off outside the frame

The building has 30 floors and two sources per floor — sixty. Two and a half floors fit in the
frame. Only those should be lit.

Selection goes by floor numbers, not by the camera rectangle: a floor's height is known, and the
number of the visible floor is a division. The result is a pure function, tested without a scene
and without a frame — the same technique as `OttoStateMachine` and `ElevatorMotion`.

The measurement in item 1 says sixty sources would hold anyway. The selection is needed
regardless: the cost grows as "sources × items under them", and by M7 the items will get
heavier.

### 9. Post-processing: glow and vignette, nothing more

- **Bloom** — `WorldEnvironment` with `BG_CANVAS` and a brightness threshold. Lamps and muzzle
  flashes glow, not the whole frame.
- **Vignette** — a shader on a full-screen layer on top of the game.

Colour correction and grain are not taken into the milestone: their place is after M7, when
real colours appear, and tuning the overall tone on grey boxes is pointless.

### 10. The city background is generated from the building seed

A parallax background is needed so that it is not empty behind the openings. There is no
artist until M7, so the city silhouette is laid out by code from the seed — by the same rules
as the building itself ([ADR-0008](0008-building-generation.md)). So the background is
reproducible and tested.

In M7 it will be replaced by a drawn one, and that will be the replacement of one node.

## What remains unchecked

| Question | How to close it |
|---|---|
| How much exactly darkness weakens in later buildings | MAME |
| Whether the dark bonus is awarded for a lamp kill | MAME |

## What remains not done

- **Darkness does not weaken in later buildings** (item 7) — debt.
- **Normal maps and specular** (item 2) — moved to M7.

## Consequences

- **`FloorLighting` stops being only a model and gets a picture.** The class still does not
  know about nodes, but the level now uses it not to lay a band but to turn sources off.
- **Per-frame source selection appears** — the first system that cares where the camera is.
  Until now the level did not know about the camera.
- **`DARKNESS_COLOR` and the darkening band are thrown out.** The placeholder from ADR-0007
  lived exactly as long as it promised.

## Sources

- [Elevator Action — StrategyWiki](https://strategywiki.org/wiki/Elevator_Action)
- [XP Arcade: Elevator Action](https://retroxp.beehiiv.com/p/xp-arcade-elevator-action)
- [Elevator Action — Retro Arcade](https://retroarcade.com/arcade/elevator-action/)
- [Elevator Action — arcade-history](https://www.arcade-history.com/game/747/elevator-action)
