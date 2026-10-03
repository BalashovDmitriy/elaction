# ADR-0007 · Lamps, darkness and invulnerability on the escalator

- **Status:** accepted; item 3 changed — the lamp's zone goes dark, not the floor
  ([ADR-0023](0023-light-and-readability.md), decision 2); item 4 — visibility is decided by
  Otto's shadow, not the agent's (same ADR, decision 8); item 5 — a +50 bonus, not doubling
  ([ADR-0010](0010-lighting-and-atmosphere.md), item 6); the placeholder of item 6 was removed
  in M6 (same ADR, item 3)
- **Date:** 2026-09-12

## Context

M4b is the second half of the split milestone M4 (see [ADR-0006](0006-combat-and-enemies.md)).
The mechanics check was done together with combat, so this records decisions rather than the
search for sources; the links are there and at the end.

Along the way the milestone closes a debt filed back in M2: it was written then that the
escalator question would have to be decided "if in M4 an enemy shoots at the rider". Enemies
have appeared.

## Decisions

### 1. A lamp is knocked down by a shot, falls and kills the agent under it

> If you hit a lamp, you will cause the lamp to fall, killing any agent that might be
> standing beneath it.

300 points — the most expensive way to kill in the original, more than a shot (100) and a
kick (150).

### 2. A falling lamp does not touch Otto

No source says a lamp can kill the player — everywhere it is only about agents. So the lamp
stays a pure player weapon, and shooting upward is not risky. If a check in MAME shows
otherwise, one zone will have to change.

### 3. The floor goes dark permanently

The decision was made in [ADR-0006](0006-combat-and-enemies.md), item 7, and is only
implemented here. As a reminder, this is a **deliberate departure from the original**: there
the lamps are on one circuit, the whole building goes dark, and for about five seconds.

**A consequence the original does not have.** A darkened floor becomes a permanent advantage
rather than a window of opportunity. Together with the bonus for dark kills (item 5) and agents
respawning from doors, this gives a point farm: darken the floor and stand there shooting.
Time pressure will come only with the alarm in M5 — until then the farm is unlimited.

### 4. In the dark, agents' shooting range drops

The sources describe the effect softly:

> It makes it harder for the enemies to find, see, and react to you. However, the effect
> isn't absolute — certain enemies won't be able to see you, thus it reduces the amount
> of fire hailing in your direction.

That is, not blindness but a lower density of fire. The closest to this is a drop in range:
an agent notices Otto only up close, and until then just walks. This is one number in
`EnemyBrain`, and it will also be convenient to weaken in later buildings, where, according to
the sources, darkness helps less.

### 5. Double points for a kill in the dark

The original has a bonus ("you'll also get extra points for any kills you make in the
dark"), but no source gives its size. Doubling is taken as the simplest rule; **not checked**.

### 6. Until M6, darkness is shown by a darkening rectangle

Real lighting — `CanvasModulate`, `PointLight2D` and occluders — arrives in M6. Until then a
darkened floor is covered with a semi-transparent dark band on top of everything. This is an
honest placeholder: visible immediately, done in a dozen lines and thrown away without regret
in M6.

### 7. Otto is invulnerable on the escalator

> While riding on an escalator, you can neither kill nor be killed.

The debt from M2 is closed per the original. The implementation is the same as for a door: for
the duration of the ride the collision shapes are turned off. Shooting from there is not
possible anyway — while Otto is being carried, input does not act.

He stays visible though, unlike with a door: behind a door Otto is gone, while on the escalator
he is in plain sight. Hence "intangible" and "invisible" are kept separate.

## What remains unchecked

| Question | How to close it |
|---|---|
| Size of the bonus for a kill in the dark | MAME |
| How much exactly agents' visibility drops | MAME |
| How many lamps per floor and where they hang | MAME |
| Whether a fallen lamp can kill Otto | MAME |

## Consequences

- **The floor gets state** it did not have before: until now a floor was just geometry. In M5,
  when floors become described by data, light will move there too.
- **The agent starts depending on where he stands.** So far it is one number, but it is the
  first case where enemy behaviour depends on a floor property.
- **Otto gets a third way to kill** after the bullet and the kick — and the most expensive one.

## Sources

- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Discussion on the Museum of the Game forum](https://forums.arcade-museum.com/threads/elevator-action-question.70396/)
- [Elevator Action/Walkthrough — StrategyWiki](https://strategywiki.org/wiki/Elevator_Action/Walkthrough)
  (not directly reachable, quotes obtained from search results)
