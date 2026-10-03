# ADR-0016 · Combat balance and agent dodging

- **Status:** accepted; items 1, 2, 5 and 6 replaced by ROM rules — building difficulty and agent
  anger, dodging by bullet, formulas in `Arcade`, 3–4 agents per building
  ([ADR-0027](0027-rom-combat.md), decisions 1–3); item 3 lifted — there are no sprites since
  [ADR-0022](0022-actors-rig.md). Item 8 in force, the death threshold since M18e is five
  ([ADR-0028](0028-building-by-the-map.md))
- **Date:** 2026-09-16

## Context

M10 fixed the geometry and agent release but left combat open: with agents enabled the bot got
stuck on the fifth floor and lost the duel again and again. The numbers were deliberately not
tweaked then — the bot cannot dodge, and crouching and jumping per
[ADR-0006](0006-combat-and-enemies.md), item 3, are exactly dodging. The milestone starts with a
measurement, not with changing numbers.

### What the check found

> …the enemy agents will begin to **shoot more frequently**, their **bullets will
> travel more quickly**, and they will begin to **take evasive action** to avoid being
> shot, either going down to a knee to avoid high bullets or dropping into a prone
> position to avoid bullets at a lower level, and they will sometimes shoot from this
> position as well.

Three axes of growth: rate of fire, bullet speed, agent dodging. **Shooting range is not among
them.**

### What we have

`Enemy.set_menace()` grows range and rate of fire:

```gdscript
_brain.fire_range = base * _menace
_brain.fire_cooldown = fire_cooldown / _menace
```

Bullet speed (180 px/s) does not grow at all, and agents do not dodge. That is, we grow the axis
the original does not have and do not grow two that it does.

This has already backfired. `MENACE_CAP` was introduced precisely because of range: "during the
alarm the shot range went up to 900 px with 1120 px of usable floor — an agent covered almost the
whole floor with fire, and the player was left no move" (comment on `MENACE_CAP` in
`building_rules.gd`). Growing range takes away from the player the very possibility of
approaching; growing bullet speed takes away only reaction time.

### Dodging already works for us — nobody uses it

The heights line up, and crouching and jumping already save Otto today:

| | collision | agent shot at −20 |
|---|---|---|
| Otto standing | −28…0 | hit |
| Otto crouching | −18…0 | passes above |
| Otto jumping | body raised | passes below |

So the bot's 324 deaths from M10 are not a verdict on the balance. They are a verdict on the bot.

## Decisions

### 1. Grow what the original grows

`agent_menace` stops touching range and starts touching bullet speed:

- **rate of fire** — the pause between shots is divided by anger (as before);
- **bullet speed** — multiplied by anger (new);
- **range** — frozen at its value (was: multiplied).

Range stays the rule "an agent shoots when you have come close", not a way to make a floor
impassable.

**The anger cap is kept,** although in the question it was called unnecessary — that was haste.
Without a cap the pause between shots tends to zero and the bullet to infinite speed; the cap is
still needed, it just limits the other two quantities now, and its value is chosen anew by
measurement.

### 2. Agents dodge: kneel against a high bullet, prone against a low one

Three stances instead of one:

| Stance | Collision | What gets through |
|---|---|---|
| Standing | 26 px | any shot |
| Kneeling | ~17 px | the low shot of a crouching Otto (−10) |
| Prone | ~8 px | only the kick |

Prone, an agent is invulnerable to both bullets — and this is not a hole but the intent. The jump
kick strikes with a −28…0 zone, that is, it reaches a prone agent, and in the original's score
table it is worth more than a shot (150 versus 100, ADR-0006, item 5). A prone agent is a reason
to come up and kick, not a reason to shoot into empty air.

Dodging is turned on by anger: in the first buildings agents only stand, further on they start
kneeling, further still — going prone. The threshold is set by the building rules.

### 3. Assets: kneeling is an already drawn pose, only one new one is needed

The agent does not get `crouch`, `jump` and `kick` rendered — "EnemyBrain cannot do that for
him". Now it can: `crouch` stops being excluded and serves as the "kneeling" pose. Only `prone`
is drawn anew.

Shooting from kneeling and prone is not shown with a separate pose: the bullet has its own flash
(`Bullet.FLASH_*`), and it is visible. Breeding `crouch_shoot` and `prone_shoot` would double the
set for a frame that lasts 0.18 s.

### 4. The bot learns to dodge — otherwise there is nothing to measure balance with

The bot crouches under a high bullet and jumps over a low one. Without this the measurement
measures not the game but the bot: right now it stands under a shot and dies where a live player
crouches.

Dodging goes by bullets in flight, not by the shooter's pose: a bullet is a node with a position
and velocity, and "will I have time to crouch" is computed honestly from it.

### 5. Combat numbers move into the building rules

Range, pause, bullet speed and dodge thresholds are set by `BuildingRules`, as anger and door
density already are. Right now they are spread over the agent's own `@export`s, and they cannot
be tuned per building without touching the scene.

### 6. Live agents in the building — no more than a cap

`agents_at_once`, eight by default. The release band is nine floors, and at the bottom of the
building each has two doors: without a cap up to eighteen were alive, and the lower floors became
a shooting gallery with fire from all sides at once. Eight is roughly one per floor of the band
and three or four in the frame, that is, as many as are visible in the arcade original.

The cap is not only about difficulty. We already removed fifty bodies with physics and AI in M10
([ADR-0014](0014-building-architecture.md), item 5), and this is the same measure carried to the
end: a door still waits for its pause, and on top of that the level releases no more than one per
frame and picks the one whose door is closest to the player.

Measurement: without the cap the bot with the same numbers reaches floor 10–19 and loses three
lives; with the cap it completes the whole building.

### 7. DoD — the bot completes on three lives

The real building, agents on, three lives, no allowances. Goes into tests and CI.

The bot still plays worse than a human: it does not retreat, does not use doors and does not
think ahead. So this is a lower bar, not a measure of enjoyment — but a lower bar that repeats
and does not depend on mood.

**Replaced by item 8.** The run itself stayed; the measure changed.

### 8. The combat measure is the number of deaths, not "survived on three lives"

*Addendum of 2026-09-22, milestone M18a.*

The check of item 7 answered "yes" or "no", and the cliff between them fell exactly on the
interesting place. Measurement after M18a: **1, 1 and 3** deaths on three seeds. By the old
criterion this is "two fine, one failure", although between the second and third there is one
death. Where difficulty is drifting cannot be seen from such an answer at all.

Moreover, three lives were carried over to the bot without grounds: a live player retreats, hides
behind doors and thinks ahead, that is, spends lives differently. The number three is about the
player, not the bot.

**Decision:** in the run with combat the bot's lives are unlimited (`ENDLESS_LIVES`), the game
always reaches the end, and what is checked is **the number of deaths** against the threshold
`DEATHS_ALLOWED`. The numbers for each seed are printed to the run's output even when the test is
green: they show the direction.

The threshold is set with a margin — six: seed 1 did not repeat from run to run, and noise must
not be locked into a check. It is changed by measurement, like the other combat numbers, not by
fitting to a green test.

**What this gives further on.** The bot's death rate on the run is a ready difficulty scale:
difficulty levels can be built on it, set by a death threshold rather than by eye.

**What this does not cancel.** Traversability is still mandatory: the building must be completed
in full and with all documents. Unlimited lives removes the question "were there enough lives",
not the question "can the building be completed".

## Why the milestone's first measurements measured nothing

The bot did not fire once in the whole milestone. And did not jump once.

Otto reads the shot and the jump by the press edge (`is_action_just_pressed`), and the bot
released everything it held every frame and immediately pressed it again. A release and a press
in the same frame do not count as an edge: the action disappears entirely. Holding worked —
walking, crouching, "down" in the cab — but single presses did not.

So the measurement table on which the milestone stalled described a game in which Otto could only
crouch:

| What was measured | Lowest floor | Documents | Killed |
|---|---|---|---|
| M10, bot does not dodge | 0–3 of 29 | 0 of 5 | 0 |
| "Bot dodges" | 2–3 | 0 | 0 |
| "+ 0.35 s wind-up" | 6–12 | 1–2 | 0 |
| "+ firing does not block dodging" | 10–18 | 2–3 | 0 |

Zero kills in every row was exactly the sign worth noticing: agents died only under lamps. Now
the test `test_bot_fights.gd` catches this — the bot must kill an agent standing in its line.

## How the milestone ended

Bot measurement on the real building, three lives, first building. The last row is seeds 1–6,
the others were taken on 1–3 while the milestone was not yet completable.

| What was done | Lowest floor | Documents | Killed | Deaths |
|---|---|---|---|---|
| After M10 | 0–3 of 29 | 0 of 5 | 0 | 3 |
| The bot really shoots | 10–19 | 1–4 | 6–52 | 3 |
| + duel instead of walking past | 10–19 | 2–4 | 6–52 | 3 |
| + cap on live agents | **29 of 29** | **5 of 5** | 7–19 | 0–2 |

**DoD reached.** The building is completed on three lives, and in the tests this is
`test_bot_survives_the_real_building_with_agents`.

What the bot learned to do in the milestone:

- **Fight instead of walking past.** An agent that can hit it, the bot meets by crouching and
  firing: crouching is both turning in place and dodging (the agent's bullet goes 20 px above the
  floor, a crouching Otto is 18 px), and a shot from a crouch reaches both a standing and a
  kneeling agent. Before, it walked through an agent standing in its line, and at three or four
  pixels the exchange was instant.
- **Not stand in a duel forever.** After two seconds the bot pushes through: an agent can also be
  out of reach, and doors send the next one every three seconds.
- **Shoot from the cab.** Crouching is not possible there (ADR-0004, item 2), so the only defence
  is to shoot first, and at a stop the bot turns toward anyone in its line.

### Dodging ended in death from the same bullet

This was found not by a test or a measurement but by shooting poses: an agent who dodged a shot
again and again turned up dead a fraction of a second later.

"Is it flying at me" was computed by side: the bullet is to the right and flying left — so it is
at me. As soon as it passed the middle of the body, the side changed, and the agent straightened
up — right under the bullet that was still inside his bounds. Dodging worked exactly until the
moment of impact.

Now what is computed is not the side but how far the bullet has left to go: it is dangerous until
it has passed behind the back by half the body width **and its whole length** — it passes the
middle tail first, and one half-width is not enough to clear the chest. The bullet states its
length itself (`Bullet.half_length`) rather than everyone who dodges it repeating it as a number.
The same was fixed for the bot — Otto would have been caught the same way, there was just nobody
to notice.

Numbers chosen by measurement and **not** confirmed by the original: a 0.35 s wind-up, dodge
thresholds 1.4 and 1.8, the distance closer than which a door does not release an agent — 96 px,
the live-agent cap — 8. All are marked for checking.

## What the milestone did not close

**Crouching has no cost.** The agent's bullet always goes 20 px above the floor — standing,
kneeling and prone alike — and a crouching Otto is lower. So nothing at all hits a crouching Otto:
not a single agent, nor any number of them at once. You cannot walk while crouching, and the only
thing that punishes sitting it out is the siren.

The original closes this: an agent "will sometimes shoot from this position as well", that is,
his shot from a knee goes low and reaches a crouching player. We have no low shot at all. This is
not a number change but a new mechanic with its own check, so it is not in this milestone — but
without it any combat balance rests on the player's word of honour.

## What is not in the milestone

- **Agents do not ride the elevator.** In the original they do; postponed since ADR-0006.
- **The original's "hurry-up" emergency mode** — for us the siren plays that role
  ([ADR-0009](0009-game-loop-and-alarm.md)); no separate difficulty step is introduced.
- **Darkness does not weaken in later buildings** — that is a lighting rule, not a combat one,
  and it sits next to ADR-0010.

## Sources

- [XP Arcade · Elevator Action](https://retroxp.beehiiv.com/p/xp-arcade-elevator-action)
- [Wikipedia · Elevator Action](https://en.wikipedia.org/wiki/Elevator_Action)
