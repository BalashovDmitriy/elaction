# ADR-0027 · M18d: combat by ROM rules

- **Status:** accepted; the item "Dark floors — without lamps and doors" in "What is not in the
  milestone" is corrected by [ADR-0028](0028-building-by-the-map.md): there are no lamps there, but
  there are doors. A lagging agent leaving through a door (decision 3a) was taken from ROM in full
  after M22: an 80 px gap and only on ROM floors from the eighth (`Arcade.agent_leaves`).
  The ROM condition "except the twentieth" was not taken: on seed 2 it raised the cost of the
  building from one death to ten — open question 9 in STATUS. The "waits for the cab" exception
  stayed ours
- **Date:** 2026-09-23

## Context

Combat was assembled in M4a and M11 from retellings — StrategyWiki, the FAQ by War Doc, Hardcore
Gaming 101 — and finished by measurement ([ADR-0016](0016-combat-balance.md)): numbers were picked
until the bot completed the building. The check before M18d found a source more precise than all the
retellings — an annotated disassembly of the arcade ROM (by jotd, for porting to the Amiga). The
conclusions from it with addresses are in [`docs/reference/arcade-rom.md`](../reference/arcade-rom.md);
here — what is taken from it and how.

The original's logic rate is confirmed by the MAME driver: **14.8 ticks per second**, a tick is
67.6 ms. Below, all of the original's times are in ticks and seconds, distances in pixels and our
metres (a pixel is 0.075 m, `Proportions.PX`).

An independent check against arcade video at 60 frames/s matched the ROM to the pixel in the jump and
the height of the low bullet.

### What the check showed

| | Original (ROM) | Ours before the milestone |
|---|---|---|
| Agents in the building at once | 3; 4 when skill·4 + time ≥ 14 | 8 |
| Where one comes out | a random blue door on Otto's floor, above or below | the door nearest to Otto |
| Agents per floor | 1 for the first ~51 s, 2 up to ~3.4 min, then 3; 1 while Otto is not on the floor | unlimited |
| Door turnover | max(0, 80 − 6·difficulty) ticks: 5.4 s → 0 | 3.0 s ÷ anger |
| Difficulty | skill (DIP + buildings completed) + 1 every ~69 s in the building, after the alarm every ~17 s, cap 15 | anger from building and alarm |
| Agent anger | each has his own: on exit — difficulty, +1 every ~17 s, up to 15 | one for all |
| Wind-up before a shot | max(0, 10 − anger) ticks: 0.68 s → 0 | 0.35 s |
| Pause after a shot | max(0, 80 − 8·anger) ticks: 5.4 s → 0; one bullet in flight | 1.1 s ÷ anger |
| Shooting pose | by anger: standing 77% → crouching up to 52% → prone up to 73% | always standing |
| Bullet height | standing 15 px (1.13 m), crouching 9 (0.68), prone 3 (0.23) | agent 1.4, Otto 1.13 and 0.66 |
| Agent dodge | Otto's bullet within 20 px: high → crouch, low → lie down; chance by anger | 3.6 m range threshold, anger |
| Prone | height 5 px (0.38 m) | 0.53 |
| Agent bullet speed | min(8, skill/4 + 6) px/tick: 6.7–8.9 m/s, +1 during the alarm | 5.4 × anger |
| Otto's bullet | 8 px/tick — 8.9 m/s | 6.6 |
| Walking | Otto and agent the same, 2 px/tick — 2.2 m/s | 2.7 and 1.65 |
| Otto's jump | +25 px (1.88 m) by tick 6, 14 ticks (0.95 s), forward 2 px/tick; direction does not change in the air | +2.4 m by physics, air control |
| Cab | 2 px/tick — 2.2 m/s | 1.8 |
| The cab crushes agents | yes, 300 points | no |
| Otto's shots "wake up" agents | Otto's bullet on screen → 90 ticks of agent alarm: more come out, they shoot without looking | no |
| Alarm | 4096 ticks — 277 s | 300 s |

**Agents do not jump** — and here the ROM agrees with ADR-0026. A label that looks like an agent
jump is the mode of shooting from the cab roof; the "jump" frames in the sprites are the hop shared by
everyone when entering and leaving a cab.

**The "lamp from a jump under an opening" hole (ADR-0026, decision 5) exists in the original too.**
The bullet in a jump goes 12 px above the feet, and under an opening, where the ceiling does not stop
the head, it passes the lamp height. The hole cannot be closed by jump height, and it is not a
divergence from the original — the debt entry is removed.

## Decisions

### 1. Combat — by ROM rules, in one table

The user's decision: port the ROM rules rather than fit our numbers to them. The "one anger per
building" model (ADR-0016) goes away: it is replaced by the building's **difficulty**, growing both
between buildings and over time within a building, and **agent anger** — each has his own, on which
the wind-up, pause, shooting pose and dodge depend.

The formulas live in one table — `Arcade` (`src/systems/arcade.gd`), by the same technique as the
sizes in `Proportions` (ADR-0026, decision 8): in the original's ticks, and the table itself converts
them into seconds and metres. The rule's ROM address is next to the number, so it can be rechecked.

### 2. 3–4 agents in the building, random exit

- The cap is 3, and 4 when skill·4 + time in the building (in units of 256 ticks) ≥ 14.
- They come out of a random blue door on Otto's floor, a floor above or below; onto Otto's floor —
  with a chance of 4·difficulty out of 256 on top of the usual.
- No more than 1, 2 or 3 per floor — by time in the building; while Otto is not on the floor
  (in a cab, on an escalator, behind a door) — no more than 1.
- Door turnover — max(0, 80 − 6·difficulty) ticks.

Our release rules stay on top: a door does not release right next to Otto (`AGENT_SAFE_RELEASE`),
the leaf is a telegraph (ADR-0020). The randomness comes from the building's own generator, seeded
with its seed. The session salt is in M18e, one for layout and combat: in tests and in
`tools/playthrough.gd` it is zero, otherwise the death scale would become noisy.

### 3. The shot: wind-up, pause and pose — by agent anger

- Wind-up max(0, 10 − anger) ticks, pause after the shot max(0, 80 − 8·anger).
- One agent bullet in flight.
- Shooting pose — by the anger table: standing, crouching, prone.
- **Bullet heights as in ROM:** standing 15 px, crouching 9, prone 3 — for both Otto and the agent.
  A high bullet passes over a crouching one, a bullet from a crouch over a prone one, a prone bullet
  hits both a standing and a crouching one: only a jump saves from it. Closes open question 7.
- Prone, the agent is 5 px tall (0.38 m), kneeling — 14 px, like a crouching Otto.
- A shot started with a wind-up is not fired if during the wind-up Otto hid behind a door or died:
  the invisible are not fired upon (ADR-0023, decision 8).

**The price of the ROM height.** Before M18d the agent's bullet went at five-sixths of height —
higher than needed, on purpose: that way it passed over Otto standing below floor level in a cab
stopped between floors, or in a shaft opening (ADR-0018, decision 5). At the ROM's 15 px there is
no such margin, and such an Otto gets hit. Taken as in the original.

### 3a. How the agent walks and when he shoots

- **The ROM has no fire range:** an agent shoots across the whole floor, and the original's floor is
  entirely on screen. Our building is wider than the screen, and the same meaning carries over as:
  an agent shoots while he is in the frame. The range in the dark (ADR-0023) stays.
- An agent shoots facing Otto; during the alarm — without looking: he turns around by himself.
- **The agent does not chase Otto on his floor** — he walks to random points of the floor, pauses and
  picks a new one. When Otto is on another floor, he goes to a cab — this has been so since M18b
  (ADR-0025, decision 6).
- An agent left two floors away from Otto and without a shaft in his direction **leaves through the
  nearest door** rather than wandering until the end of the building. One who has a shaft at hand
  waits for the cab: otherwise there would be no agent rides (ADR-0025) left at all.
- The kick counts in any phase of the jump, rising and falling.
- An agent in the cab and on its roof shoots by the same rules; one who boards a cab gets an alarm for
  90 ticks (@1AED).

### 4. Speeds and the jump — by ROM

- Walking for Otto and the agent — 2.2 m/s, the same.
- Otto's bullet — 8.9 m/s; the agent's — 6.7, 7.8 or 8.9 m/s by skill, +1 step during the alarm.
- Cab — 2.2 m/s.
- Otto's jump: feet +1.88 m by 0.4 s, the whole jump 0.95 s, sideways 2.2 m/s, the flight direction is
  set by the push-off and does not change in the air. A jump in place exists too.

### 5. Otto's shots wake up agents

Otto's bullet in the frame with difficulty above zero — 90 ticks (6 s) of agent alarm: release goes
by the full floor limit, and agents shoot without even turning around.

### 6. The cab crushes agents — 300 points

With the bottom from above, as with Otto: an agent who ends up under a descending cab dies. A debt of
M18b (ADR-0025). Passengers do not count — one standing on the cab floor rides in it, not under it.
Crushing with the roof against the ceiling, which the ROM also knows, is not taken in this milestone:
there is none for Otto now either, and they share one rule.

### 7. Alarm — 277 s

4096 of the original's ticks. After it, difficulty grows four times faster, the agent's bullet is one
step faster, the cab responds with a delay — as in ROM.

### 8. Difficulty level in the settings

Four levels — the cabinet's DIP switch 0–3: the starting skill, to which completed buildings are
added. Default 0. The bot measures the death rate on each.

### 9. Darkness stays ours

In the original a shot-down lamp darkens the whole building for 4.5 s, and darkness does not affect
agents at all. Ours: zones go dark permanently, and darkness decides whether an agent sees Otto
([ADR-0023](0023-light-and-readability.md), decision 8). The user's decision — keep ours: the light
and stealth of M17 rest on it. The divergence is recorded.

## Measurement

The bot's death rate per building, `tools/playthrough.gd --agents --endless`, seeds 1–3:

| Skill | Deaths |
|---|---|
| 0 — first building, easy level | 0, 0, 0 (and 0, 1, 0 on seeds 4–6) |
| 3 | 1, 3, 5 |
| 6 | 39, 33, 15 |
| 10 | 9, 19, 11 |

Before the milestone, skill 0 gave 5, 2 and 1. The peak at six is a property of the bot: agents there
are already fast but shoot standing, while at ten three shots out of four are prone, and the bot jumps
over a low bullet better than it wins a duel against a standing agent. A live player at six will die
less often than the bot; the scale is a measure that difficulty grows with skill, not a number the
game is fitted to.

## What is not in the milestone — M18e

The user's decision: the building as a separate milestone.

- Doors on a floor by the original's map: 4 in the tower, 4–7 in the middle, 2 at the bottom.
- Red doors 5, 6 … 10 by skill.
- The original's dark floors — without lamps and doors.
- Session salt in the layout: buildings differ from session to session.

## How we check

- `Arcade` is compared by a test with the ROM numbers: the formulas at extreme anger and difficulty
  give the values from the disassembly.
- The ROM order "bullet — stance" holds: high over a crouching one, from a crouch over a prone one,
  prone into a standing and crouching one, a jump escapes the low one from the first tick.
- Agents in the building — no more than the limit, on a floor — no more than the floor limit, at any
  seed and time.
- The cab crushes an agent and gives 300 points.
- The bot completes the building at all difficulty levels; the death rate of each level is measured
  and recorded — as a number, not "passed".
