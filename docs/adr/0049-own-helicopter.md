# ADR-0049 · M24i: our own helicopter

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0045](0045-takedowns-helicopter-dressing.md), decision 5,
  [ADR-0038](0038-building-start-and-end.md), decision 1 (the intro helicopter)

## Context

Decision 5 of ADR-0045: the helicopter — a more detailed free model, and if there is
no worthy one — our own model by script. The low-poly kazuma (CC0) in the M24g frames
read as a flat silhouette: a dozen faces, the rotor as one line, skids as sticks, no
doors, no tail rotor.

Check of candidates on poly.pizza (2026-09-30): the best is Helicopter,
jeremy (CC-BY), but it is one mesh in three colors, the rotor cannot be separated from
the body, there is no door. The rest are toy-like or military.

## Decisions

1. **Our own model, `tools/build_helicopter.py`.** A light helicopter lofted through
   cross-sections: a rounded nose, a cabin, a taper into the boom, a fin with a
   stabilizer, a cowling with an intake and exhaust, skids on cross tubes with steps.
   Glazing — the windshield and cabin windows with frames. The sliding door is
   pushed back, the opening is cut: the cabin is visible through it — seats, a
   bulkhead, the floor.
2. **Rotors — separate nodes** `MainRotor` and `TailRotor` with their origin on the
   axis: the game spins the main and tail rotors, the tail one faster. Under the
   blades — a blur disc: a semi-transparent circle with blades running over it.
3. **Model points — as empties:** lights, searchlight, cabin light and winch. The
   game puts its own lights and sources there rather than guessing the place from the
   bounds. The winch is on the rotor axis: the intro hangs the helicopter so that the
   rope falls above the landing spot.
4. **Recoloring by material name:** the body is dark metallic with a cold rim, the
   glass is dark with a reflection and a faint glow of instruments, the opening — with
   the warm cabin light. The light that sculpts the volume is as before: lights, cabin
   light and the searchlight from below while the helicopter hovers.

## Consequences

- `Helicopter` finds model parts by name, not by surface index.
- kazuma is removed from the credits: the model is no longer in the game.
