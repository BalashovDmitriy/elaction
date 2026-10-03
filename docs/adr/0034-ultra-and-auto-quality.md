# ADR-0034 · M22: the "Ultra" level, antialiasing and choosing the level by measurement

- **Status:** accepted
- **Date:** 2026-09-24
- **Extends:** [ADR-0030](0030-grading-and-quality.md), decision 5

## Context

ADR-0030 introduced three quality levels. The user asked about ray tracing;
Godot 4.7 does not have it — only low-level Vulkan RT in `RenderingDevice`
(STATUS, debt). Decided: a top level "Ultra" using engine means. Along with it —
antialiasing: staircase edges are visible on slab edges and thin shaft ropes,
and the game has no antialiasing setting.

Before M22 the default level is high for everyone, whatever the graphics card.

## Decisions

### 1. "Ultra" — the fourth level

The user's decision. On top of "High":

- **Volumetric lamp light** — a halo in the corridor air: lamp sources, shaft
  columns and the neon glow give three times more light to the volumetric fog
  (`light_volumetric_fog_energy`), the fog grid is twice as fine. The fog is not
  made denser: in a trial with 1.5× density the haze lay over Otto, and the
  outline lost contrast.
- **Indirect light (SSIL)** — lamp light bounces off the floor and walls.
  Screen-space, so the building cutaway does not break it.
- **High-resolution shadows** — the shadow atlas is twice as large, the penumbra
  softer.

SDFGI is not used: in the building cutaway light would leak through walls, and a
dark floor — a game rule — would stop reading as dark.

### 2. Antialiasing — inside the levels

The user's decision. There is no separate settings item:

| | Low | Medium | High | Ultra |
|---|---|---|---|---|
| Antialiasing | FXAA | MSAA ×2 | MSAA ×2 | MSAA ×4 |

TAA was in "Ultra" and was removed based on frames: it blurs the thin light outline
of the actors (ADR-0022, decision 4), which carries readability on a dark floor,
and Otto on "Ultra" came out softer than on "High".

### 3. The level on first launch — by measurement

The user's decision. While no level is chosen, the game on first launch measures
the frame and takes the highest level that keeps the median GPU frame with a
margin (no longer than 12 ms of 16.6). It measures not behind the main menu —
there is no building behind it, the level is unloaded — but during the intro of
the first building: Otto rides a rope up to the roof, there is almost no gameplay
in those seconds, and the frame is one of the busiest. It starts with "Ultra",
after a level change skips the shader compilation frames and steps down; the
measurement lasts no longer than 8 seconds (`QualityProbe`).

The chosen level is written to the settings; after that only the player changes
it. A level saved before M22 counts as chosen by the player.

### 4. Tone — finishing the noir

The user's decision. The ADR-0030 curves (decision 1) are tuned against frames of
the hotel, office, roof and a dark floor; game indicator lights stay bright.

## Consequences

- `Graphics.Quality` gets `ULTRA`; all per-level tables grow by a column,
  and a test holds that each level turns on what it promises and does not change
  the rules.
- The settings have four levels; the "Ultra" string is in both languages.
