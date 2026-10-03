# ADR-0041 · M24e: demo mode

- **Status:** accepted
- **Date:** 2026-09-26
- **Extends:** [ADR-0035](0035-menu.md) — the main menu on a live scene

## Context

Between games the cabinet plays the game by itself — that is how it lures players.
Ours, after M22b, has the main menu standing on the night city and waiting; the
user likes it, and the demo must not replace it (decision from M24c, ADR-0039,
"Not in the milestone").

### What the check showed

The ROM disassembly ([`arcade-rom.md`](../reference/arcade-rom.md)):

- **Cycle.** A title screen with the logo — about 12 s (`title_screen_loop_7171`:
  8 × 90 animation steps); no coin — demo; then the title screen again
  (@33D2–3415).
- **Who plays.** A recording of inputs, not a bot: three recordings
  (`recorded_inputs_7A63`, `7BD3`, `7DD3`) in rotation, counter `$8251` 0–2. Each
  has its own random seed (`fix_random_seed_for_demo_1175`), skill 2, zero lives.
- **Where from.** Each recording starts on its own floor: 28, 18 and 5 (`$802C` =
  `$1C`, `$12`, `$05`) — the top, middle and bottom of the building.
- **How long.** The recordings are 368 and 512 bytes, one input per logic tick
  (14.8 per second): about 25 and 35 s. The demo ends when the recording ends or
  Otto dies.
- **Sound.** There is none in the demo: "plays sound only if real game" (@3657).

## Decisions

All decisions are the user's.

### 1. The test bot plays

Not an input recording: a recording desyncs from any change to combat or the
building, while the bot has been passing buildings in tests since M5 and plays a
new game each time — including the M24d takedowns. The bot moves from `tests/` to
`src/`: tests do not go into the build.

### 2. Turns on after 45 s of idle in the main menu

The menu stays as it is and remains the main thing; the demo is a rare guest. Any
press in the menu resets the countdown. Only the main menu: on pause and in the
settings the demo does not turn on.

### 3. About 30 s, three points in rotation

As in the ROM: top — the roof with the helicopter, middle, bottom — the last
floors and the garage. The point is the next in rotation for each demo. The demo
ends by time or by Otto's death: lives, as in the ROM, are zero. The end is a fade
and the menu again with its countdown.

### 4. Sound — as in the game, no caption

The building sounds as in a game: building music, footsteps, shots. The HUD is as
in the game; there is no "demo" label.

### 5. Any press returns to the menu

A key, a gamepad button or a mouse click — the demo fades out, and the main menu
is on screen. The press does not pass into the game: the demo does not turn into
a game.

### 6. The demo does not write high scores and does not touch the game

The bot's points are its own, they do not go into the high-score table; the demo
does not run the settings or the quality measurement (`QualityProbe`).

### 7. The bot does takedowns

The user's request during the milestone: the bot uses takedowns and is smarter in
general. An agent who is not aiming the bot catches up to standing and presses
shoot at point-blank — at point-blank this is a takedown; an agent with his back to
the bot is stalked up to 5 m, one facing it — the bot rushes only closer than
2.2 m. One who is aiming it meets, as before, with a duel from a crouch, and it
evades the aiming beam.

### 8. Refinements from the milestone frames

- **Cabs near the start are held.** Cabs start from the top stop of their shaft
  and leave on schedule: from the roof during the helicopter intro, from the
  middle — while the bot was walking. The bot waited for a cab at the shaft for
  half the demo standing. Now, until the bot moves, cabs at the start level hold
  their stop and for 8 s after — `ElevatorMotion.hold`. The cab cannot be turned
  off for this time: a turned-off one does not see who boarded.
- **Middle and bottom start at a shaft** whose cab starts from this floor, within
  four floors of the ROM floor.
- **From the bottom, documents of the floors above are credited without points,**
  otherwise the demo score started at three and a half thousand.

## Not in the milestone

- A title screen with the logo between demos, as on the cabinet: the menu takes
  its place.
- High-score tables in the demo cycle.
