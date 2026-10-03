# ADR-0001 · Godot 4.7 and typed GDScript

- **Status:** accepted; still in force after the move to 3D ([ADR-0019](0019-3d-pivot.md)),
  but argument 1 about 2D lighting no longer applies — the scene is three-dimensional
- **Date:** 2026-09-11

## Context

We need to pick a stack for the Elevator Action remake. Requirements: the mechanics repeat the
1983 original, the picture is modern. There is one developer, whose main experience is Python
and Django, with no game-dev experience. Target platform is PC.

Key observation: picture quality is determined not by the language but, in descending order,
by the art pipeline, by the engine's rendering capabilities, and only then by the language.
Dead Cells looks expensive not because of Haxe, but because its characters were modelled in 3D
and pre-rendered into sprites.

Second observation: the original's mechanics themselves suggest a visual technique. In Elevator
Action lamps get shot out and the floor sinks into darkness — that is, the game is built around
dynamic 2D lighting, not around polygon count.

## Options considered

| Option | Why not chosen |
|---|---|
| Unity 6 + C# | Higher ceiling for 2D, but a steeper entry, and the whole gain lies in an area the project will never reach |
| Unreal 5 | Paper2D is effectively abandoned; the real path is HD-2D, i.e. a full 3D project. Overkill |
| Bevy (Rust) | Version 0.18, breaking API changes every release, editor not ready |
| Python (pygame-ce, Arcade) | Familiar, but no editor, weak shader stack, performance ceiling. Good only for a prototype |
| GameMaker | Fast path to a result, but GML is a dead-end skill, lower ceiling for lighting |
| Own engine on C++/SDL or Rust/wgpu | Maximum control at the cost of months of infrastructure instead of the game |

## Decision

**Godot 4.7.2 + typed GDScript.**

Reasons:

1. **2D is a native subsystem**, not a layer on top of 3D. `PointLight2D`, `DirectionalLight2D`,
   `LightOccluder2D`, `CanvasModulate`, normal and specular maps via `CanvasTexture` —
   exactly what shoot-out lamps need.
2. **GDScript is syntactically close to Python** — indentation, `func`, `var`, type annotations.
   This removes the project's main risk: the developer learns game development, not a new
   language on top of it.
3. **Static typing is mandatory.** Typed GDScript is up to ~59% faster than untyped and catches
   errors at parse time; the difference from C# on game logic is unnoticeable.
4. **MIT, no royalties and no licensing risk.**
5. **Active release cycle:** 4.6 sped up 2D batching, 4.7 added HDR output.
6. **Lightweight editor** — about 100 MB, starts in seconds.

C# is not used in the project: it gives no gain on this task, but it breaks web export
and adds .NET to the build chain.

## Consequences

- All code is written with type annotations; `gdlint` checks this.
- Godot's ceiling on the number of simultaneous 2D light sources is lower than Unity URP's:
  the community cites a practical limit of about 15–16 sources per node, with a noticeable
  drop already at 5+ shadow-casting sources. Some of the complaints date back to Godot 3. We
  verify the limit with a prototype in M6 and plan for a lighting budget and floor streaming.
- Console builds, if ever needed, are possible only through the paid partner W4 Games. This
  is outside the scope of the epic.
- Python knowledge stays useful: all project tooling (`gdlint`, `gdformat`, `pre-commit`,
  `tools/godot_check.py`) is in Python.
