# ADR-0004 · Mechanics of elevators, shafts and escalators

- **Status:** accepted; cab speed taken from ROM — [ADR-0027](0027-rom-combat.md),
  decision 4
- **Date:** 2026-09-12

## Context

M2 is the elevator milestone, and it is the first to run into open question No. 4 of the epic:
disputed mechanics details must be checked against the original, not implemented from memory.

Before the milestone started, references on the 1983 arcade original were collected.
StrategyWiki — the most detailed source — is behind Cloudflare and unreachable both over HTTP
and via the MediaWiki API, so Wikipedia, Hardcore Gaming 101 and StrategyWiki quotes that
appeared in search results were used. Links are at the end of the document.

The check changed three assumptions the milestone was planned with, and added a mechanic that
was not in the epic at all.

## Decisions

### 1. The cab is controlled only from inside

While Otto is in the cab, "up" and "down" drive it. This is confirmed verbatim:

> While Otto is in an elevator, the player can push up or down to send him to a higher
> or lower floor.

### 2. Otto does not crouch inside the cab

"Down" in the shaft is taken by control, so crouching is unavailable there. This matches
the original: StrategyWiki — "While in the elevator, you can't squat".

Consequence for the code: the input snapshot is no longer unconditional. `move_down` means
crouch or lowering the cab depending on where Otto is. The ambiguity is resolved not by
`OttoInput` but by the side that knows the context.

### 3. No control on the cab roof

> He can ride on its roof but not control its motion or cross to the other side.

The roof is a passive ride: the cab moves by itself, Otto just rides on it. Walking across the
roof to the other side of the shaft is not possible.

### 4. Cabs without the player move by themselves

This item was not in the epic; it was added to M2. Without it neither riding on the roof by
the rules of item 3 nor crushing Otto standing in the shaft works.

> When you aren't in them and are waiting for them, elevators move painfully slowly,
> for they hit each floor and pause for about one to two seconds.

An autonomous cab stops **at floors** and pauses for about one to two seconds.
This differs from a cab under player control — see item 6.

### 5. The shaft opening is open, falling kills

The floor opening is a hole in the floor, not a closed-off wall. It is run across and jumped
over when the cab is above; when the cab is below, the rope gets in the way.

> He can jump across an empty shaft as long as the elevator is above him.

> If he is shot or crushed, or if he falls down an open shaft, the player loses one life.

Therefore death by falling into the shaft arrives already in M2, a milestone earlier than
planned. The terminal `DEAD` state in `OttoStateMachine` already exists for this; lives,
respawn and the Game Over screen stay in M4.

### 6. Under player control the cab stops anywhere

> **Revised by [ADR-0053](0053-open-questions-and-debt.md), decision 1:** the check against ROM
> (@5E1E) showed that the cab does not stop between floors. Released, it continues to the
> next floor in its direction; the toggle is removed.

Release the direction — the cab stops, even between floors. Stepping out onto a floor is
possible only when the cab floor is level with the building floor.

**This is the only decision the check did not confirm.** None of the available sources says
what happens when the joystick is released between floors; Wikipedia's wording "send him to a
higher or lower floor" rather hints at floor-to-floor movement, but that is reading between
the lines.

The behaviour is moved into an exported cab parameter, so that switching it after a check in
MAME costs one line, not a rewrite of the mechanic.

### 7. Crushing kills both the player and an enemy

Confirmed from both sides: Otto dies "between a descending/ascending elevator and the
floor/ceiling", enemies can be "squash[ed] with the elevator". Points for a crushed enemy are
awarded — but enemies appear in M4, so M2 implements only Otto's death.

### 8. The escalator is boarded by pressing, not by walking on

> Stand on the pads at the top or bottom of the escalator and press up or down.

That is, the escalator is not a moving platform that picks up a passer-by, but a pad from which
Otto sets off up or down on a press. This is the same context-dependent "up/down" as with
the cab.

Invulnerability during the ride ("you can neither kill nor be killed") belongs to combat and
is implemented in M4.

## What remains unchecked

| Question | How to close it |
|---|---|
| Whether the player's cab stops between floors (item 6) | Running the ROM in MAME |
| Cab speed and floor pause duration | MAME, frame-by-frame measurement |
| Exact width of the shaft opening — can it be run across or must it be jumped | MAME |

Until checked, these values live in exported parameters with defaults chosen by feel.

## Consequences

- **Input becomes context-dependent.** `move_down` is crouch on a floor and descent in the
  shaft. This is the first place in the project where one action means different things, and it
  will have to be taken into account when adding shooting in M4.
- **Death by falling arrives in M2.** The milestone stops being purely "about platforms".
- **The epic gets a new item** — autonomous cab movement.
- **Some shafts in the original are two cabs one above the other** with a gap between floors.
  This does not affect M2, but the data description of a shaft in M5 must allow it.

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Elevator Action — Hardcore Gaming 101](https://hg101.kontek.net/elevatoraction/elevatoraction.htm)
- [Elevator Action/Gameplay — StrategyWiki](https://strategywiki.org/wiki/Elevator_Action/Gameplay)
  (not directly reachable, quotes obtained from search results)
