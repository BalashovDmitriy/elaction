# ADR-0028 · M18e: the building by the original's map

- **Status:** accepted
- **Date:** 2026-09-23

## Context

The M18d check found the full map of the original's building (StrategyWiki, matches NES and ZX) and
the disassembly of the arcade ROM ([ADR-0027](0027-rom-combat.md)). The map showed that our floors are
emptier: in the M18c frame comparison we have 1–2 doors, the original up to seven. Building generation
stays — the user's decision at the M18d check; from the map we take rules, not the layout itself.

The check before M18e read in the ROM what was not in the M18d notes: where the lamps hang and which
floors are dark. Addresses are in [`reference/arcade-rom.md`](../reference/arcade-rom.md), the
"Building" section.

### What the check showed

ROM floors are counted **from the bottom**: the first is the bottom one, the thirtieth the top,
zero is the basement with the car.

| ROM floors | Doors (`table_280E`) | Lamps (`$81DA`) | Which ones they are for us |
|---|---|---|---|
| 1–6 | 2, at the edges | none | 24–29, wide |
| 7 | none | none | 23 |
| 8–10 | 6, 6, 4 | 2 | 20–22 |
| **11–15** | 4, 5, 6, 7, 5 | **none — dark** | 15–19 |
| 16–18 | 5, 4, 6 | 2 | 12–14 |
| 19–30 | 4 | 2 (1 on the 20th) | 0–11, tower |

- **The dark floors are 11–15.** There are no lamps there at all (`init_building_2700` zeroes their
  masks, `@2719`), and a kill is worth as much as in the dark, 150 and 200 instead of 100 and 150
  (`@56A1`). They do have doors, and these are the densest floors of the building. The EPIC entry
  "without lamps and doors" was a mistake.
- **Red doors 5 → 10 by skill**, and each band of floors has its own quota by skill up to eight
  (`@27D2`, tables `@282D`–`@2874`):

  | ROM floors | Skill 0 1 2 3 4 5 6 7 8 |
  |---|---|
  | 1–6 | 0 1 2 2 2 2 3 4 5 |
  | 8 | 0 0 0 1 1 1 1 1 1 |
  | 9–11 | 2 2 2 1 1 2 1 1 1 |
  | 12–14 | 1 at any |
  | 15–17 | 1 at any |
  | 18–20 | 1 at any |
  | 21–25 | 0 0 0 1 1 1 1 1 0 |
  | 26–30 | 0 0 0 0 1 1 1 0 0 |

  In total 5, 6, 7, 8, 9, 10, 10, 10, 10. In the first building the top ten floors have no
  documents — a fast descent; with skill the bottom and top fill up. No more than one red door per
  floor, the floor within the band is random.
- **The original's building is a screen wide**, 256 px — 19.2 m. Our podium is twice the frame width
  (ADR-0024), the tower fits in the frame.

## Decisions

### 1. ROM floor — by fraction of height

Our index goes from the top, the ROM's from the bottom: ROM floor `f` is our `floors − f`. For a
building of a different height, and tests assemble such buildings, the ROM number is taken by
fraction of height and rounded: the map's rules stretch rather than break off.

The rule lives in `Arcade` next to the ROM tables: `Arcade.rom_floor`.

### 2. Doors — by ROM per screen width

The user's decision. The number of doors on a floor is from `table_280E`, multiplied by the floor
width in the original's screens (19.2 m), rounded, at least one. The tower gets the ROM number as
is — 4 and 4–7 — the wide bottom twice as many: the bottom floors 2 → 4, floors 8–10 up to 12. The
density in the frame is as in the original.

As many are placed as fit: shafts, escalators and the exit still come first. Doors stop being
mandatory in the slot count (`BuildingPlan._room_left`): one door is mandatory on a floor for which
the ROM gives doors at all, and the rest take whatever is left. Otherwise the layout, protecting seven
doors, would find no room for an escalator.

Where there is not enough room, it shows in the frame. In the tower's escalator band (ROM floors
20–23) two escalators take four slots out of seven, and together with the shaft and the lamp one
remains for doors. In the tower with three shafts (ROM 11–18) — four doors instead of five to seven.
The other floors get the map's number in full.

There are no more agents: their limit is 3–4 per building (ADR-0027). Doors give more places an agent
can come out of, and it is harder to memorize where he will come out.

The seventh ROM floor gets no doors, as in the original.

**Layout order: one door, lamps, walls, the remaining doors.** A wall does not stand right next to a
door — a door behind a wall cannot be entered — and when the extra doors were placed before the
walls, almost no walls were left: across 120 buildings 287 versus 507, in the tower 22 versus 156
(M18e code review). Now the walls go in earlier, the slots next to a wall get occupied, and the doors
take what is left: 474 walls, 168 in the tower; doors per building on average 114 versus 117. The
user's decision.

### 3. Red doors — by ROM bands

The user's decision. How many documents are in a band of floors — by the ROM table and the
building's skill up to eight; the floor is random within the band, where room was found on the
reachable part. A document that found no room anywhere in its band is placed on any floor of the
building without a document: not collecting all documents is impossible, so it cannot vanish. With
the default rules this did not happen on any test seed — the bands are respected, and this is
checked. The exit still does not open without all of them.

`BuildingRules.documents` goes away: the number of documents is now derived from skill. For tests and
runs a manual cap remains — by the same technique as `agents_at_once_cap`.

### 4. Dark floors — by our darkness rule

The user's decision. ROM floors 11–15 get no lamps and are entirely dark from the start of the
building. Darkness for us is not a picture but a rule (ADR-0023, decision 8; ADR-0027, decision 9):
an agent sees Otto in the dark closer than 1.8 m, a kill in the dark is worth 50 points more. On dark
floors it works by itself, and the score comes out as in the ROM: 150 for a shot, 200 for a kick.

The cost is recorded: these five floors come out easier than in the original, where darkness does
not affect agents. They are also the densest in doors, so they will not be empty.

`FloorLighting` learns about a dark floor from the level, as it learns about lamps: a floor without
lamps by the building rules is dark, a floor without lamps for lack of room is not. The roof is never
dark, the city lights it.

### 5. Bottom ROM floors 1–7 — with lamps

The user's decision. In the ROM there are no lamps there, but for us this is the wide bottom twice the
frame width, and light and darkness must play on it. The lamps stay as they are. The divergence is
recorded.

In the tower there is one lamp, not two as in the ROM: the lamp's zone is the unit of darkness, and in
a frame-wide tower one zone is ADR-0023, decision 2. Also a divergence.

### 6. Session salt

The building seed is `hash(building number, session salt)`; the salt is random at the start of a
session, one for layout and combat (ADR-0027, decision 2). In tests and in `tools/playthrough.gd` the
salt is zero, and the seed equals the building number, as before the milestone: the death scale and
green runs are not noisy.

### 7. The door telegraph — at the end of the shift

A debt of M14. The agent's leaf moves for 0.7 s (ADR-0020, decision 2), and before it started moving
after the turnover pause rather than at its end: agent density was cut by a third. Now an agent cell
counts as free when less than the leaf travel remains until the end of the shift — the agent comes out
where the ROM releases him. When there is no turnover at all (high difficulty), the telegraph stays:
it is a sign, not a pause.

## Measurement

The bot's death rate per building, `tools/playthrough.gd --agents --endless`, seeds 1–3:

| Skill | M18e | M18d |
|---|---|---|
| 0 — first building, easy level | 0, 1, 0 | 0, 0, 0 |
| 3 | 4, 7, 0 | 1, 3, 5 |
| 6 | 10, 36, 41 | 39, 33, 15 |
| 10 | 22, 11, 21 | 9, 19, 11 |

The measurement is after rearranging the walls (decision 2). The bot completes the building at any
skill except one seed at six: there it collected all documents, but 41 deaths did not fit into the
budget of 12000 steps. There are two and a half times more doors, and the first building got more
expensive: the combat test on seed 2 counted 4 deaths, and its threshold was raised from 3 to 5. The
scale is a measure of difficulty growth, not a number the game is fitted to (ADR-0027).

**The re-measurement found an old respawn bug.** One who died in a cab stands above the shaft opening,
in no floor piece, and the respawn picked from all spots of the floor — the farthest from the agents.
At skill 10 that spot turned out to be in a pocket behind an escalator opening with no way out: the
bot stood there for 6000 steps. Now the nearest piece with spots is taken — from it one boards the
cab. The bug had lived since M18a; the dense doors just dragged it out.

## How we check

- `Arcade` is compared with the ROM tables: the number of doors per floor, the red door quotas by
  skill and their total of 5–10, the dark floors.
- On any seed and skill: at least one door per floor where the ROM gives them, and no more than the
  ROM number per width; as many documents as the table says; all reachable; no lamps on dark floors,
  at least one on the others.
- A dark floor is dark in `FloorLighting` at any point, and a kill on it is worth more.
- Salt zero gives the same building as before the salt; different salts — different buildings.
- The bot completes the building at all difficulty levels with the new door density; the death rate
  is re-measured and recorded.
