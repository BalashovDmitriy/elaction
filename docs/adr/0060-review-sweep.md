# ADR-0060 · Whole-game review sweep

- **Status:** accepted
- **Date:** 2026-10-03
- **Amends:** [ADR-0007](0007-lamps-and-darkness.md) (invulnerability on the escalator),
  [ADR-0034](0034-ultra-and-auto-quality.md) (the quality probe)

## Context

After M24p the whole game was reviewed end to end: seven reviewers, one per area, each
finding traced in the code and the main ones checked again by the lead. No crash, softlock
or state leak between sessions turned up; building generation was shown to give a winnable
building for any seed. What turned up were rules that hold almost always, and the cases where
they do not.

One finding did not survive the fix: "under the tests' `time_scale = 4` Otto takes his own
falls for teleports". He does not — `_last_position` is written after his own move, so the
gap measures only moves made by someone else. Two tests now guard it.

## Decisions

Questions asked to the user on 2026-10-03.

1. **An agent shoots where Otto is.** During the wind-up an agent firing on the move no longer
   turns at a floor edge, towards his exit or towards a cab: a blocked path stops him. Before,
   the bullet left in whatever direction he faced at that moment, often away from Otto. He
   does not re-aim mid-wind-up either — an Otto who jumped over him is safe, as before.
2. **Neither kill nor be killed, from the first frame.** `Otto.kill` does nothing while a door
   or an escalator drives him: before, a bullet could land in the frame they took him, ahead of
   the deferred shape change, and the door later let the revived Otto out with a document.
   A door or an escalator drops a guest that died.
3. **A dead Otto leaves the player layer** — bullets fly through where he stood. Except inside
   a cab: there the cab must keep its passenger, otherwise it carried the body to another floor
   and Otto came back on the wrong one (measured: seed 3 went from 3 deaths to 12).
4. **A bullet outlives its shooter.** An agent removed while his bullet flies hands the hit
   over; the bullet still kills.
5. **The alarm clock stops in the exit car** (user's choice). Once Otto has boarded, the
   siren cannot go off over the bonus count. The intro of the first building still counts,
   and so does the difficulty time.
6. **Agents are kept by where they are.** An agent who followed Otto by cab is no longer
   removed by the floor of his door; one in the camera view is never removed. A removed agent
   stops at once, and a late signal from him frees nothing.
7. **The quality probe gives each level its own time** (4 s, 12 s in all); a shader-compile
   stall counts at most 0.1 s; when time runs out, it steps down by how far over the target
   the frame is, not by one level.
8. **Saved files are trusted only by type.** A setting, a key binding or a high score of the
   wrong type falls back to the default instead of stopping the game. A settings file without
   a resolution counts as old and is upgraded.
9. **Zero is not a record**, and an equal score goes below the one already in the table.
10. **Hall furniture is drawn by floor** (user's choice). Each hall floor has its own batch,
    and floors outside the visible span are hidden. On the test machine (RTX 5060 Ti, Ultra)
    the frame time did not change; draw calls went down on some floors and up on others. The
    win is that the cost no longer grows with the number of hall floors.
11. **Smaller fixes:** the jump pose and sound only after a jump (not when stepping off a
    rising cab); the slow-motion whoosh once per takedown, not on every unpause; the knocked-off
    hat settles and freezes like a corpse; the main menu subtitle follows the language; the
    settings are saved when the window is closed; the demo warms shaders up; leaving a paused
    building drops it before unpausing; a frozen building does not bring Otto back; a shot
    lamp hands its fill shadow on; the storm writes the ambient light only when it changes.

## Consequences

- Each behaviour fix has a test in the file of its system.
- The bot runs keep their gate of 6 deaths per seed; measured again after the sweep.
- Dead facade code from before the pack facades is gone, with two shaders.
- `GreyboxLevel.AgentPost` moved to its own file to keep the level under 1000 lines.
