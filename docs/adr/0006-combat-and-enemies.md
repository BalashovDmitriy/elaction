# ADR-0006 · Combat, enemies and splitting milestone M4

- **Status:** accepted; item 6 changed — agents dodge ([ADR-0016](0016-combat-balance.md)),
  ride in cabs ([ADR-0025](0025-shafts-escalators-and-riders.md)), walk and shoot
  by ROM rules ([ADR-0027](0027-rom-combat.md), decisions 3 and 3a); item 7 — the lamp's zone
  goes dark, not the floor ([ADR-0023](0023-light-and-readability.md), decision 2)
- **Date:** 2026-09-12

## Context

In the epic, M4 gathered shooting, the kick, enemies, bullets, lives, Game Over and
shoot-out lamps with darkening. That is twice as much as M2 and M3, each of which took a whole
milestone.

As before the two previous milestones, the mechanics were checked against the original before
work started. The sources are the same: Wikipedia, Hardcore Gaming 101, the Museum of the Game
forum, StrategyWiki quotes from search results (the site itself is behind Cloudflare). Links
are at the end.

The check confirmed part of the plan, clarified something important about damage and found a
mechanic that is not in the epic at all.

## Decisions

### 1. The milestone is split into M4a and M4b

- **M4a · Combat and enemies** — Otto's weapon, the kick, bullets, enemy agents, lives and
  Game Over.
- **M4b · Lamps and darkness** — shoot-out lamps, darkening, enemy behaviour in it.

The numbering of the other milestones does not shift: `M4a`/`M4b` instead of inserting a new
milestone between M4 and M5. Otherwise the numbers in already accepted ADRs would have to be
edited, and they are a record of the decision at the time it was made, not rewritten after the
fact.

### 2. No more than three of Otto's bullets on screen

> Agent 17 can vanquish the enemy spies by shooting them with his gun that can only fire
> up to three bullets at a time.

This is not a technical limitation but the basis of tactics: having fired three times, Otto is
unarmed until the bullets fly off. Shooting is available standing, crouching and in a jump.

### 3. Bullets are slow and have height

> Otto may jump over low enemy fire or duck to evade higher enemy bullets.

So a bullet is an entity with its own flight height, and crouching and jumping work as
evasion. A crouching shooter's shot goes low, a standing one's goes high.

### 4. Three lives, and only a shot takes them

> Players are given three "lives." The player loses a life if hit by enemy fire —
> physical contact with the enemies themselves will not affect him.

**Colliding with an enemy is harmless.** This changes enemy design: he is dangerous with his
weapon, not his body, and running through an agent is a legitimate technique, not a bug.

To the already implemented causes of death (falling into the shaft, cab crush, ADR-0004) a
bullet hit is added. Respawn after death is on the floor of death; the original's rules could
not be found, marked for checking.

### 5. Points

The original's table, found during the check:

| For what | Points |
|---|---|
| Shooting an enemy | 100 |
| Jump kick | 150 |
| Lamp on the head | 300 |
| Document | 500 |
| Building bonus | 1000 × number |

The NES version manual gives 100-150 for a shot and 150-200 for a kick — that is the port, so
the arcade values are taken. The original gives a bonus for kills in the dark; its size was
not found and belongs to M4b.

### 6. The enemy in M4a: door, walk, shot along the line

An agent comes out of an ordinary door, walks along his floor toward Otto and shoots when Otto
is on the same line as him. The state machine is a separate class, like Otto's, so it can be
tested without a scene.

Dodging bullets and riding the elevator exist in the original but are not done in M4a: an agent
who walks and shoots already gives playable combat, and the rest is easier to add once his
behaviour is visible in the game.

### 7. Lamps darken their floor permanently — a departure from the original

**This is the project's first deliberate divergence from the original, and it contradicts
item 1 of the epic's goal** ("reproduces the mechanics without changes to gameplay").

In the original the lamps are on one circuit: a shot-down lamp falls, kills an agent standing
under it — and the whole building goes black for about five seconds, after which the light
returns. That is, darkness there is a short window of opportunity, not a floor state.

The decision was made by the project owner after the divergence was shown: a lamp darkens its
floor and does not come back on. The mechanic is implemented in M4b, and if the decision is
revised after a check in MAME, that is what will have to change.

### 8. Timed alarm — in M5

The mechanic is in none of the epic's milestones:

> If he takes too long to clear a level, an alarm will sound; the enemy agents then
> become more aggressive, and the elevators will be slower to respond to the player's
> joystick movements.

This is a difficulty mechanic, not a combat one: it touches both the enemies and the elevator.
M5 already plans "increasing difficulty" — the item is filed there.

## What remains unchecked

| Question | Where it belongs |
|---|---|
| Respawn rules after death | M4a |
| Duration of darkness and bonus for kills in the dark | M4b |
| When the alarm triggers and how much the elevator slows | M5 |
| How many agents come out of a door and how often | M4a |

## Consequences

- **Otto gets a weapon and lives for the first time.** `GameState` from ADR-0005 takes lives,
  and `OttoStateMachine` takes weapon-related states.
- **The bullet is the first entity spawned by both Otto and an enemy.** The three-bullet limit
  applies only to Otto.
- **Harmless collision simplifies the enemy**: he needs no body-damage zone, only a weapon.

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Elevator Action — Hardcore Gaming 101](https://hg101.kontek.net/elevatoraction/elevatoraction.htm)
- [Discussion on the Museum of the Game forum](https://forums.arcade-museum.com/threads/elevator-action-question.70396/)
- [Elevator Action/Gameplay — StrategyWiki](https://strategywiki.org/wiki/Elevator_Action/Gameplay)
  (not directly reachable, quotes obtained from search results)
