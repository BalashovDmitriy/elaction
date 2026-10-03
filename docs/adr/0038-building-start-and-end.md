# ADR-0038 · M24b: helicopter, red door, garage, exit via the car

- **Status:** accepted
- **Date:** 2026-09-25
- **Extends:** [ADR-0005](0005-doors-and-documents.md) — the door and the exit;
  [ADR-0017](0017-spectrum-palette-and-shafts.md) — descent on a rope;
  [ADR-0031](0031-scene-detail.md), decision 4 — the garage on the bottom floor
- **Supersedes:** "one may leave a red door early" from ADR-0005; the time
  "up to five seconds" there as well

## Context

M24b is the second of three milestones based on the remarks after M23
([ADR-0037](0037-polish-bugs-and-combat.md)): it is unclear where Otto comes from
on the roof; the red door does not look like the original; the bottom floor is
not a garage; nobody gets into the car, Otto vanishes at the opening.

Check against the disassembly of the arcade ROM (jotd666/elevator_action,
`elevator_z80.asm`, addresses from there; notes — [`docs/reference/arcade-rom.md`](../reference/arcade-rom.md)):

- **Arrival** (`player_arriving_on_roof_anim_4d70`): a hook flies in from beyond
  the left edge of the frame, the rope goes diagonally, Otto slides down, jumps
  off, looks around and walks into the elevator to floor 30 by himself — about
  11 s without control. There is no source of the rope; a helicopter exists only
  in the ZX Spectrum version. The scene plays once per game (@3531, flag $824A):
  the following buildings start on floor 30, after a death Otto stands on his
  floor, at a red door if it is not collected there (@2FAA).
- **Red door** (@3BDA, `update_in_room_timer_3c3e`): entry — standing on the mat
  facing the door; the door closes behind Otto; inside exactly 70 ticks
  ($82ED = $46, @2A5B) — 4.73 s; one can leave earlier after 9 ticks by pushing
  away from the door; the document and 500 points are credited on exit; from the
  first step inside until fully out Otto is invulnerable. Agents do not approach
  the door.
- **Basement**: floor 0, no doors. Exactly one shaft of the five lowest goes down
  there, drawn per building ($802D, @273F); escalators do not. The car is always on
  the left.
- **Exit** (@09D3, @0BF2): as soon as Otto is in the basement, control is taken
  away — he walks to the car, jumps in, the car drives right, turns around and
  drives off to the left; the bonus is a line on top, about 6 s. If documents are
  not collected — sound $38, the frame scrolls up quickly, Otto stands at the
  missed door (@09B5–0A69).

## Decisions

### 1. A helicopter in every building

The user's decision — as in the ZX Spectrum version. A helicopter flies in from
the left above the roof, hovers, lowers a rope; Otto slides down it onto the roof
and lets go of the rope, the helicopter leaves right and up. Control starts at
landing. The scene plays in every building: our buildings differ, and arriving on
the roof of a new one is not a repeat. It can be skipped with a jump, a shot or
pause — Otto immediately stands on the roof.

After a death there is no helicopter: Otto returns to his floor, as now.

Model — Helicopter, kazuma, CC0 (poly.pizza). The main rotor is a separate
surface, spun in code.

### 2. The red door as in the original, but without early exit

- The door leaf closes behind Otto while he is inside and opens to let him out.
- Inside exactly 70 ROM ticks — 4.73 s. **No leaving earlier** — the user's
  decision; the 3–6 s draw from the plan is dropped: without early exit a constant
  time is fairer, and it matches the ROM.
- The document and 500 points — on exit, as in the ROM; from the step inside until
  exit Otto is invulnerable, as before.
- Muffled through the door: music and corridor sounds — footsteps, shots, doors —
  go through a filter.
- Agents who lost Otto on his floor sometimes approach the door and wait at it —
  the user's decision from the plan, the ROM does not have this. A draw per agent,
  no more than one at a door; he waits while Otto is inside.
- Entry stays on "up" on the mat: in 3D the mat is in front of the door, and
  "facing the door" reads worse in the side view.

### 3. Basement — an underground garage, one shaft down

- The bottom floor is served by **one** shaft — drawn from those that reach the
  floor above it, as in the ROM. The others end one floor higher. Escalators do
  not go down to the basement.
- Look: columns, a low ceiling with beams, pipes and fluorescent lamps, markings,
  other cars in their spots, a gate in the end wall, a ramp up behind it.
- Otto's car stands at the gate, always on the left, as in the ROM: the path from
  the shaft to it depends on which shaft was drawn.

### 4. Exit: walked up — got in — drove off

The user's decision. Otto walks to the car himself. At the driver's door with all
documents control is taken away: Otto gets in, the headlights come on, the car
drives out through the gate. The bonus counts up over the scene, then a fade and
the next building.

### 5. Without all documents the shaft to the basement is closed

The user's decision — simpler than in the ROM. The shaft section between the
floor above the basement and the basement is closed by a slab: it is visible, and
there is no way through it — not by cab, on foot, by jump or by falling. The cab
stops one floor higher. When the last document is collected the slab opens by
itself, and the cab goes down to the basement. The ROM return for documents — a
sound, the frame scrolling up, transfer to the door — is not there; the old
instant transfer goes away.

### 6. Refinements from the milestone frames

The scene frames (`tools/m24b_shot.tscn`) showed what tests do not:

- **The basement is "P".** The HUD on the bottom floor says "PARKING", shaft
  indicator boards and plaques say "P"; other floor numbers are as before.
- **The exit is in the frame.** At boarding the camera widens left past the
  building's end wall: the gate, the ramp and the street are visible, the car
  drives up the ramp rather than into the frame edge.
- **The bonus before the round change.** The bonus finishes counting on the
  plate, then a fade, and only under black the bonus goes into the score and the
  round number grows.
- **Boarding is visible.** Otto turns to the car and gets in through the open
  driver's door; the door is our own part on top of the pack model.
- **An agent does not shoot an invulnerable Otto.** One waiting at the door
  aims, but shoots when Otto can be hit again: otherwise the bullet passed
  through him.

## Not in the milestone

- Looking around on the roof and walking into the elevator by himself from the ROM
  scene: our roof is a separate level with equipment, the way to the shaft is
  already gameplay.
- The ROM rule for returning after death (floor no lower than the fifth, at an
  uncollected door) — open question 4 remains.
- Smooth animation and key rebinding — M24c.

## Consequences

- The bot finds a path to the one shaft into the basement: reachability is checked
  on any building with the same graph.
- Tests and frame routes waiting for landing wait for the end of the helicopter
  scene.
- The bot's time in a building grows by the scene and the exit; step budgets — per
  the run.
