# ADR-0005 · Doors, documents and leaving the building

- **Status:** accepted; red doors — 5–10 by skill level, [ADR-0028](0028-building-by-the-map.md),
  decision 3
- **Date:** 2026-09-12

## Context

M3 is the milestone about red doors and documents. As before M2, the mechanics were checked
against the original before work started: in M2 the check changed three decisions out of four,
and redoing that work after the fact is more expensive.

StrategyWiki is still behind Cloudflare, so the sources are Wikipedia, Hardcore Gaming 101, the
NES version manual and StrategyWiki quotes from search results. Links are at the end. The NES
port differs from the arcade, so its manual is used only where another source confirms it.

The check confirmed most of the plan, changed one item of the milestone and added a mechanic
that was not in the epic.

## Decisions

### 1. A document behind a red door, 500 points

Confirmed by Wikipedia: "collecting secret documents (500 points per) whose locations
are marked by red doors". A collected door stops being red and from then on behaves
like an ordinary one.

Along the way the whole score table turned up — it will be needed in M4: shot 100, jump kick
150, lamp on the head 300, document 500, building bonus 1000 × its number.

### 2. Entry — from the mat and by pressing "up"

In the original a mat lies in front of the door: "To enter the red door, stand directly on a
white square in front of the door", and one must stand facing the door.

**We add an explicit "up" press.** This is a deliberate departure from the letter of the
original:

1. Otto's facing direction is not stored in the project yet — it will appear with animations
   in M7.
2. Entry by merely stopping would pull into the door anyone who stopped on the mat.
3. "Stand on the pad and press a direction" is already the project's established way of
   interacting: the cab and the escalator work this way too (ADR-0004, items 1 and 8).

### 3. A door is a room to hide in

This mechanic was not in the epic. Having entered, Otto stays inside **for up to five
seconds**, after which he is thrown out automatically; leaving earlier is possible by pressing
toward the door handle.

> Once you enter a red door, you can stay inside for up to five seconds, and after that,
> if you have not left the room, you will automatically exit.

This is cover from enemies, and in M4 it becomes part of combat. The door behaviour itself is
implemented right away: without it a door is not a door.

### 4. Ordinary doors are ambushes, but not in this milestone

> Enemy agents, armed and lying in wait behind the blue doors, will try to ambush you.

In M3 an ordinary door gets a scene and the states "closed / opening / open".
Releasing enemies from it is for M4.

### 5. The exit is not blocked — Otto is sent back up

**Here the milestone plan diverged from the original.** The epic said "block the final exit
until the documents are collected". In the original the exit is always open:

> If a red door is missed and the building is exited, you will be returned to the first
> missing red door… he will be transported to the highest floor that still has an
> unopened red door and must work his way back down.

And this is not so much a punishment as a technique: players deliberately go down to the exit
to get thrown to a door that is hard to reach otherwise.

Blocking the exit does not allow that kind of play, so the transfer is implemented.

### 6. Score and progress — in the `GameState` autoload

Points, collected documents, later lives and the floor number live in a single singleton with
signals. The HUD and doors connect through it rather than directly to each other — as
`docs/conventions.md` prescribes for interaction between unrelated systems.

### 7. Doors are described by level constants for now

Like the shaft and the escalator in M2. Moving all geometry to `Resource` remains a single task
of M5: doing it in the middle of the doors milestone would mix two unrelated pieces of work.

## What remains unchecked

| Question | How to close it |
|---|---|
| How many red doors per building | MAME. Hardcore Gaming 101 mentions five documents per level, other sources give no number |
| Whether cover lasts exactly five seconds | MAME, frame-by-frame measurement |
| Whether an ordinary door opens for the player or only for an enemy | Closed in M24h by ROM (@3BDA): only a red door with a document lets the player in — [ADR-0044](0044-street-and-cab.md) |

## Consequences

- **`GameState` is the first game-state singleton.** Until now there was one autoload, and it
  was a utility (`Screenshotter`). There is now a place where M4 will put lives, and M5 the
  transition between buildings.
- **Otto gets one more state that the world controls.** After `RIDE` from M2, being inside a
  door is added: player input does not act in it, and Otto himself is hidden.
- **The transfer to an uncollected door is the first mechanic that needs to know about the
  whole building**, not one floor. In M5, when floors start streaming, this place will have to
  be revisited.

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Elevator Action — Hardcore Gaming 101](https://hg101.kontek.net/elevatoraction/elevatoraction.htm)
- [NES version manual](http://www.world-of-nintendo.com/manuals/nes/elevator_action.shtml)
- [Elevator Action/Gameplay — StrategyWiki](https://strategywiki.org/wiki/Elevator_Action/Gameplay)
  (not directly reachable, quotes obtained from search results)
