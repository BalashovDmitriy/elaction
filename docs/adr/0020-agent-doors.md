# ADR-0020 · Agent door: telegraph, doorway and invulnerability

- **Status:** accepted; decision 7 went away together with the 2D frames — in 3D the door leaf
  became a model, on hinges since M18c ([ADR-0026](0026-proportions.md), decision 3);
  decision 2 extended: the leaf moves at the end of a shift ([ADR-0028](0028-building-by-the-map.md),
  decision 7); red doors from decision 6 — 5–10 by skill level (ADR-0028, decision 3)
- **Date:** 2026-09-19

## Context

Playing the game by hand produced the complaint at the top of the list: agents appear **on top of
a closed door**, and the doors do not open at all. The leaf in the frame stays closed, and a man
materializes right on it.

That is exactly how the code works. `DoorVisit` knows the phases `CLOSED → OPENING → OPEN` and all
three assets are drawn, but this works only for Otto's visits. The level creates an agent as a
node straight on the mat: `_release_agent` sets `global_position = mat` and hands over a finished
enemy. The agent's brain has an `EMERGING` phase — for 0.6 s he does not walk or shoot — but for
those 0.6 s he just stands in front of a closed door.

This is a logic bug, not a picture bug: it will survive the move to 3D ([ADR-0019](0019-3d-pivot.md))
and reproduce there one to one. So we fix it before the pivot, while a working game is at hand for
comparison.

### What the check against the original showed

- **Agents come out of closed doors** — the sources say so directly. The mechanic matches.
- **They come out from the player's floor and neighbouring ones** — matches our release band.
- **Documents are behind red doors; once taken, the door stops being red.** Matches, but our
  emptied door never started releasing agents.
- **Whether the leaf opens before an agent comes out — the sources are silent.** Screenshots do
  not capture it. We decide ourselves; not confirmed by the check.
- **Found something we do not have:** by entering a red door Otto throws agents off his trail —
  they lose his exact position and know only the direction. Not taken into this milestone,
  recorded as debt.

## Decisions

### 1. The door cycle is a separate class without a node

`DoorCycle` on `RefCounted`: phases `CLOSED → OPENING → OPEN → CLOSING`, leaf travel as a fraction,
and not a single access to the scene. The door node asks it what to show and does it.

`DoorVisit` stays, but gives up the leaf: it is about the visit rules — whom to let in, when to let
out — not about where the door is now. Previously it pulled both with one timer.

The reason is not purity. In 3D the door node will be different, and the rules the same
([ADR-0019](0019-3d-pivot.md), decision 2): a milestone written this way moves for free.

### 2. A 0.7 s telegraph

The door opens fully, and only then an agent comes out of it. The player has time to see the leaf
and leave.

This makes the game softer, deliberately: the complaint was precisely about the suddenness. We
measure the cost — see decision 9.

The number is not confirmed by the check, nor is the fact of the telegraph itself.

### 3. The agent is invulnerable until he has left the doorway

Otherwise the telegraph turns into a shooting gallery: the player keeps the door in his sights and
picks off each one on the way out, and 0.7 s gives all the time in the world for that.

Invulnerability ends exactly when the agent has cleared the doorway and walked off along the
floor — that is, when he is already a full-fledged opponent.

### 4. The door closes right behind the one who came out

An open door in the frame means "someone is about to come out of there". One sign — one meaning.
If it is left open while the agent is alive, on a floor with agent turnover half the doors will
stand wide open and the sign will stop reading.

### 5. Otto in the doorway does not stop the door

Stand in front of an opening leaf — the agent will come out anyway. The door does not change its
mind.

The check "do not release if Otto is right next to it" ([ADR-0016](0016-combat-balance.md))
stays and works as before: it decides whether to **start** the cycle, not whether to interrupt one
already started.

### 6. An emptied red door becomes an ordinary one

The document taken — the door looks ordinary and behaves like an ordinary one, that is, starts
releasing agents. Previously it remained a permanent shelter.

The addition is small: five red doors per building versus fifty ordinary ones.

### 7. Smoothness — a cross-fade of three frames

We do not draw new leaf frames. `DoorCycle` gives the travel as a fraction, the node shows two
neighbouring frames and cross-fades the transparency between them.

It would be more honest to draw six more frames in the generator, and for 2D that would give a
better result. Not done deliberately: the whole asset set goes away with the pivot
([ADR-0019](0019-3d-pivot.md), decision 8), and there is no reason to spend a week drawing into it.
Real smoothness will come in M16 with model animation.

### 8. The agent's door makes the same sound

`DOOR_OPEN` and `DOOR_CLOSE`, a positional source. Sound is a second warning channel: you can hear
even what opened behind your back. No separate effect for an ambush.

### 9. The cost of the telegraph is measured by the bot, not by eye

Decisions 2 and 3 together weaken the ambush: the player always has time to leave, and an agent
cannot be killed on the way out. By how much is a question of numbers, and it is part of the
milestone DoD: the run `test_bot_survives_the_real_building_with_agents` on the same seeds before
and after, comparing deaths and kills.

If the danger of doors dropped to zero — we compensate, and with what exactly is decided from the
numbers, not in advance.

## What is not in the milestone

- **Walk and jump animation frames.** The feedback on actor smoothness is closed by a model with
  animation in M16, not by drawing more sprites.
- **Losing the trail behind a red door.** Found by the check, as debt.
- **Changes to the door layout.** Their number and places are set by `BuildingPlan`, and it is not
  touched.

## Sources

- [Video Game History Wiki](https://videogamehistory.fandom.com/wiki/Elevator_Action) —
  agents come out of closed doors
- [Just Games Retro](https://www.justgamesretro.com/nes/elevator-action) — doors of the player's
  floor and neighbouring ones, the red door after the document, losing the trail
- [The Cutting Room Floor](https://tcrf.net/Elevator_Action_(Arcade)) — animation frames in the
  original were counted one by one
