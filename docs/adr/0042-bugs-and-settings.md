# ADR-0042 · M24f: bugs, settings, Game Over

- **Status:** accepted
- **Date:** 2026-09-28
- **Extends:** [ADR-0022](0022-actors-rig.md) (outline),
  [ADR-0034](0034-ultra-and-auto-quality.md) (resolution and "Ultra"),
  [ADR-0037](0037-polish-bugs-and-combat.md) (corpses),
  [ADR-0040](0040-takedowns.md) (pounce)

## Context

The user's remarks after M24e (2026-09-28) — fifteen items. They were split
into two milestones: M24f — bugs, settings and the last death; M24g —
animation and look (rope, escalator, door, headlights, city windows,
[ADR-0043](0043-animation-and-look.md)).

### What the check showed

The ROM disassembly ([`arcade-rom.md`](../reference/arcade-rom.md)) and code review:

- **Corpses.** In the ROM a killed agent falls and disappears; ours, since M24a,
  lies until the end of the building. A settled body went to sleep and moved into
  the cab node if a cab was under its *feet* — a ray from the feet, not from the
  middle of the body. A corpse lying with its torso on the platform rode with the
  cab through slabs; a cab passing by picked up a corpse from the platform edge.
- **Cab control with two corpses.** Per the code, corpses collide with nothing
  (layer 0) and do not enter cab zones; three tests — corpses in a cab, Otto
  boarding next to lying ones, takedowns in a cab — do not break control. The
  cause was not found; it goes away together with moving the corpse into the cab
  node, the tests stay as a guard.
- **FPS at the bottom on "Ultra".** A lamp has two shadowed sources: the cone and
  the fill. The fill is omnidirectional light, its cube shadow is six passes. At
  the bottom about fifteen lamps are lit versus five in the tower: ~105 shadow
  passes versus ~35, and each one gets all of the floor's dressing.
- **Resolution.** Godot 4.7 does not switch the monitor's video mode: fullscreen
  and borderless window are always at native resolution, and the "Resolution"
  item did nothing there, although it stayed active.
- **Game Over.** The menu appears on the same frame as the death; jump is space,
  and space presses "Restart": a player mashing jump restarted the game
  immediately.
- **Pounce.** It fired only if Otto fell from a support above the agent's floor —
  a jump on the same floor never fired it. In the ROM the jump kick kills on any
  body contact during the whole jump.

## Decisions

All decisions are the user's.

### 1. A corpse is a physical body

Not a ragdoll with bones: bodies on every bone of the pack skeleton fight with the
rig, which samples clips itself, and there are up to thirty corpses in a building.
Not a separate `RigidBody3D`: at the shaft ceiling it gets pushed through
geometry, and the bot run stops being reproducible. The agent body stays a
`CharacterBody3D`, but lying:

- the shape after the fall is a lying box along the body length, not a standing
  one;
- while the body touches a shaft column, it does not sleep: gravity and
  `move_and_slide` carry it on the cab floor as on a platform, and when the cab
  leaves the body falls into the shaft, onto the roof of a cab below or to the
  bottom;
- with its middle over a void the body does not hang by its edge on the slab but
  slides into the shaft;
- a body pinched between the cab roof and the top of the shaft disappears;
- outside shafts a settled body sleeps as before and costs the frame nothing.

A corpse no longer moves into the cab node.

### 2. FPS: cheaper shadows, same look

First a per-floor measurement (`light_bench`), then the fix. Shadows only for lamps
in the frame; the fill — without a shadow or dual-paraboloid; small dressing items
do not cast shadows. The goal is a steady frame across the whole building without
a visible difference in frames.

### 3. Resolution in fullscreen sets the 3D resolution

In fullscreen and borderless window the scene is drawn at the chosen resolution
and stretched to the screen, the interface stays sharp. "Render scale" is merged
with it into one: the fraction is the chosen resolution over the native one.

### 4. No cursor during play

During a game the cursor is hidden; in the menu and on pause it is visible.

### 5. The last death — slowdown and push-in

The world slows down, the camera pushes in on Otto, he falls with the death clip,
the frame fades, "GAME OVER" — and only after ~1.5 s does the menu accept presses.

### 6. Credits in the menu

A "Credits" page in the main menu — the list from `CREDITS.md`.

### 7. No outline for anyone

The M16 outline (ADR-0022) is removed from Otto, agents and corpses. In the dark
figures read by light.

### 8. A red door has its own light

Above an uncollected red door — its own sconce: a warm red spot on the wall and
floor, a glowing plaque; it stays lit even when the lamp is shot out, and goes out
when the document is taken.

### 9. Pounce — simpler

Otto landed — from a jump or a fall — with his body overlapping a living agent on
the same floor: this is a takedown from above. A support above the agent's floor
is no longer needed.

## Not in the milestone

Rope, escalator, door, headlights, city windows — M24g.
