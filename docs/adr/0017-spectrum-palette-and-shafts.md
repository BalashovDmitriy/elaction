# ADR-0017 · Spectrum palette, visible shaft and roof with a rope

- **Status:** accepted; item 1 superseded — the round palette is applied to materials and light
  ([ADR-0019](0019-3d-pivot.md), decision 7; [ADR-0029](0029-city-weather-dressing.md),
  decision 5); items 2–6 in force
- **Date:** 2026-09-19

## Context

M12 was conceived as a "round palette" on top of our look: [ADR-0015](0015-round-palette-and-roof.md),
item 1, took from the Spectrum version **level structure, but not look**. The request changed —
follow the port in the palette too, rework the shafts ("you can hardly see them") and the roof.

### What the port's frame shows

A real in-game frame from the World of Spectrum archive was analysed. The colours were read from
it, not described by eye: it is exactly the Spectrum attribute palette, eight colours in two
brightnesses.

| What is in the frame | Colour |
|---|---|
| Outside the building | `#000000` |
| Floor interiors | `#00FFFF` |
| Brickwork on the sides | `#FF0000`, white mortar |
| Doors | `#FFFF00`, outline `#0000FF` |
| Floor slabs | `#FFFFFF` with a black dashed line |
| Shaft | `#0000FF` full height, yellow crossbars at floors |
| Cab | `#CECECE` |
| Sprites | `#0000FF` |
| HUD | `#FFFF00`, `ROUND` counter |

The main observation is not about colour. **The shaft in the port is the most noticeable element
of the frame:** it runs as a solid band through the whole building, and one can see at once how
far the elevator goes. Ours is a hole in the slab with a light column, and it is barely present in
the frame. The descent through the building is the game, and its main tool does not read.

### What the arcade says

> The basic building layout never changes, though colors change with new levels.

> Then your character will slide down the line to the roof.

The colour change by round and the rope descent are confirmed by the arcade directly; the counter
is called `ROUND` both in the arcade and in the port.

## Decisions

### 1. Their colours, our light

The colour language is taken from the Spectrum, at full strength: turquoise floor interiors, red
brickwork on the sides, yellow doors, a blue shaft, white slabs. It is still drawn by our engine —
with normals, highlights and the lighting from M6.

This **supersedes the palette rule of [ADR-0011](0011-asset-pipeline.md), item 6** ("the building
is muted, the picture is made by light"). It was written for a grey-blue building where colour was
a background for light. Now it is the reverse: the colour is recognizable by itself, and the light
falls on it as relief and highlight. [ADR-0002](0002-visual-target.md) stays in force — the look is
still HD pixel art with dynamic lighting; only the palette changes.

The flat attribute look **is not taken**: it would supersede M6 and M7 entirely — decision 1 of
[ADR-0015](0015-round-palette-and-roof.md) stays in this part.

### 2. Round palette: a cycling set, both colour pairs

Colours move from level constants into a palette that `BuildingRules.for_building()` picks by round
number. The set is finite and cycles, like the rounds in the original.

The palette sets **both** pairs — the tone of a lit floor and that of a darkened one. The reason is
the same as in ADR-0015, item 3: a darkened floor differs from a lit one by hue, not brightness,
because in the dark agents keep shooting. A freely wandering colour will sooner or later produce a
round where a darkened floor does not read, and it will be the player who finds it — so the gap
between the pairs is checked by a test on every palette of the set.

### 3. The shaft is drawn as a structure, not a fill

A solid full-height band, as in the port, **is not taken**: behind our shaft one can see the floor,
the windows and the city, and a fill would kill the depth for which parallax and lighting were
made.

Instead the shaft gets what it lacks now — a body:

- **guide rails** along both edges of the opening, running through the whole height of the shaft;
- **door leaves** on every floor the shaft serves: they show where the elevator stops and where it
  just passes by;
- **the light column** stays — it was the only thing that gave the shaft away.

The colour of the rails and leaves is set by the round palette, and it contrasts with the floor:
the shaft must read first, not last.

### 4. The machine-room superstructure and the rope descent

A machine room stands above the top shaft — as in the port: its own roof, brick sides, a cab
inside. Otto starts the building by sliding down a rope onto the roof: this is an intro shot, not a
mechanic — the rope does not stay in the game and cannot be climbed.

### 5. The round counter is called ROUND

In the HUD and in the translations "building" becomes `ROUND` / "round" (in both languages) — as
in the port and the arcade.

### 6. What tests check

- on every palette of the set, the gap between a lit and a darkened floor is not below a threshold;
- the palette is picked by round number and cycles;
- every shaft has guide rails over its whole height and door leaves on all its floors;
- the superstructure stands above the top shaft and does not cover Otto's spawn point;
- the rope descent ends with Otto standing on the roof and controllable.

## What is not in the milestone

- **The flat Spectrum look** — decision 1.
- **Recolouring the actors.** In the port Otto and the agents are equally blue; ours have a light
  suit versus a dark one — this is how friend and foe are told apart on a darkened floor
  ([ADR-0011](0011-asset-pipeline.md), item 6), and changing it to the port's colour means losing
  readability for the sake of resemblance.
- **Changing the palette within one building** — the palette is picked per round.
- **Brickwork across the whole side wall.** Our building's sides go off frame, and the brickwork is
  visible only on the silhouette steps; a fully Spectrum-style side would require giving up the
  steps (ADR-0015, item 5).

## Sources

- [World of Spectrum · in-game shot](https://worldofspectrum.net/pub/sinclair/screens/in-game/e/ElevatorAction.gif)
- [Spectrum Computing · Elevator Action](https://spectrumcomputing.co.uk/entry/1594/ZX-Spectrum/Elevator_Action)
- [arcade-history · Elevator Action](https://www.arcade-history.com/game/747/elevator-action) — rope descent, round bonus
- [XP Arcade · Elevator Action](https://retroxp.beehiiv.com/p/xp-arcade-elevator-action) — colour change by round
