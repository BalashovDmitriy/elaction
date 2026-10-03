# ADR-0012 · Sound and interface

- **Status:** accepted; item 3 ("one third-party file") is lifted — pack models and textures
  ([ADR-0032](0032-actor-models.md), [ADR-0033](0033-dressing-from-packs.md)), the HUD
  is set in the Exo 2 font (OFL) since M22, the menu and the scene since M22b
  ([ADR-0035](0035-menu.md)), Pixellari removed. The difficulty setting, which is not in
  the milestone, appeared in [ADR-0027](0027-rom-combat.md), decision 8. Items 1 and 2 —
  synthesized sound and our own theme — are superseded by [ADR-0036](0036-sound-from-libraries.md)
- **Date:** 2026-09-13 (items 1 and 2 rewritten the same day, after listening)

## Context

M8 is the last milestone before release: sound, HUD, menu, high scores. All of this exists in
the project exactly as much as was needed for debugging: the HUD is a debug overlay in the
system font, there is no menu at all, and not a single sound.

### What the check against the original found

- **The original's sound is pure PSG.** Four AY-3-8910 chips and a separate Z80 for sound:
  three voices per chip, square wave, noise and envelopes. No samples, and in 1983 there was
  nowhere for them to come from.
- **The theme was written by Yoshio Imamura** — tense, simple, with "trembling" notes that fit
  cautious progress through the building well.
- **Of the effects, the sources name shots and the elevator "ding".** There is no full list.
- **Taito's manual turned up** (Internet Archive) — the very one that returned 403 since M2.
  It is about servicing the cabinet, and it has no score table, no number of red doors and no
  alarm rules. But it has the DIP switches:

  | Setting | Values |
  |---|---|
  | Extra life | 10,000 / 15,000 / 20,000 / 25,000 points |
  | Lives per game | 3–6 |
  | Difficulty | VERY EASY / EASY / DIFFICULT / EXPERT |

  The three lives we chose in M4a turned out to be the minimum from this list — that is,
  guessed correctly. But we have no extra life for points at all.

## Decisions

### 1. Sound is synthesized by code, like the graphics

`tools/render_audio.py` writes WAV into `assets/audio/`; the files are committed, like PNGs
([ADR-0011](0011-asset-pipeline.md), item 2). The reasons are the same:

- **Determinism.** Same script — same file, and the change "make the shot drier" is a change of
  a number in code, not a search for a new sample.
- **Not a single third-party file.** Library samples bring licences and inconsistency with them:
  sounds from different places do not get along, and the mix has to be pulled together with an
  equalizer.
- **This is exactly what the original could do.** Square, noise and envelope — the whole
  vocabulary of the AY-3-8910, and also the whole vocabulary of the generator.

Runtime synthesis via `AudioStreamGenerator` is rejected: sound would become code on the hot
path, and debugging it is harder than a file you can just listen to.

### 2. Our own theme, in the PSG idiom

The original's theme belongs to Taito and cannot be copied. We write our own: three voices —
melody, bass and noise percussion — a short loop, tense and simple, like the original's. A
separate motif for the alarm: our siren has worked since M5b
([ADR-0009](0009-game-loop-and-alarm.md)), and it has had nothing to sound with so far.

### Amendment of items 1 and 2 · 2026-09-13, after listening

The first version was made literally by these two items: square, noise, sixteen volume levels,
22 kHz mono. It sounded accordingly — like a 1983 chip, and by ear it turned out unusable.

**The mistake was in the reasoning, not the execution.** The project formula is
"1983 mechanics, 2026 picture" ([`EPIC.md`](../EPIC.md)), and sound belongs to the same side as
the picture: in M6 and M7 we did not reproduce the arcade's flat colours but made lighting and
normal maps. Sound should have been treated the same way from the start, and imitating the chip
was a tribute to the original where nobody asked for one.

**What changes:**

| Was | Now |
|---|---|
| 22,050 Hz, mono | 44,100 Hz, stereo |
| Square, noise, 16-level envelope | Alias-free oscillators, resonant filters, convolution reverb, compression, limiter |
| An effect is one or two voices | An effect is attack, body and room tail, as modern games build them |
| Melody on three PSG voices | Dark synthwave: bass, arpeggio with a moving cutoff, pad, drums |
| Everything in WAV | Short and frequent in WAV, long and music in OGG |

**What does not change:** synthesis, not samples (item 1 stays in force in this part), our own
theme instead of Taito's, three buses and the milestone split. The synthesis tools moved into a
separate module `tools/audio_dsp.py`; the sounds themselves stayed in `render_audio.py`.

### 3. The font is vendored, because of Cyrillic

The interface is bilingual (a cross-cutting requirement of the epic), and that means Latin plus
Cyrillic — about a hundred and thirty glyphs. Drawing them with a generator, like the other
assets, is half a milestone on letters alone.

We take an open pixel font with Cyrillic and a clear licence (CC0 or OFL) and put it in
`assets/fonts/` together with the licence text. The specific one is chosen in M8b — the
requirements: Cyrillic, integer point size, no anti-aliasing.

This is the first third-party file in the repository, and therefore it is the only one:
everything else is still drawn and synthesized by our own code.

### 4. Language by locale, with a switch

`ru` and `en`. The language is taken from the system locale, changed in the settings and
remembered. Strings live in one place, not in nodes: otherwise translation turns into walking
the scenes.

### 5. An extra life at 10,000 points

We take the minimum threshold from the manual. Until now points did not affect anything in the
game — there was nothing to spend them on, and the score remained decoration. Now it has a value.

The threshold does not repeat: one life for the first 10,000. Repeating every 10,000 is not
confirmed by the manual, and we already predicted infinite lives from farming agents in the dark
for ourselves once ([ADR-0010](0010-lighting-and-atmosphere.md), item 6).

### 6. The milestone splits: M8a — sound, M8b — interface

As M4, M5 and M7 were split.

- **M8a — sound.** The generator, effects for all game events, the theme and the alarm motif,
  buses and mix.
- **M8b — interface.** The font, two languages, a HUD instead of the debug overlay, the main
  menu, settings, the high-score table, the extra life for points.

The order is this way because sound depends on nothing, while the menu depends on the font, the
language and the volume settings that sound introduces.

### 7. Three buses: Master, Music, SFX

Volumes are in the settings, and they are the only thing the game writes to disk besides high
scores. Music has a separate bus precisely so that it can be turned down without turning off
the shots.

## Added before M8b · 2026-09-13

The interface questions are closed, and three answers change the work.

### 8. A modern HUD, not an arcade one

A top line with points, high score and life icons is the language of the cabinet. The game is a
remake: 1983 mechanics, a 2026 picture, and the interface is on the same side as the picture —
as is sound (the amendment of items 1 and 2 above).

So: only what is necessary, in the corners, semi-transparent. Points, lives, documents, floor
and alarm. The debug overlay with state, speed and FPS leaves the game — its place is behind a
key, not in the frame.

### 9. High scores without initials

Ten lines with score and date. Entering three letters with the arrows is a ritual of the arcade
hall, where a queue stands behind the cabinet; at home it turns into an extra screen between
death and the next game.

### 10. Key remapping is postponed

The settings will have a **controls screen**, but only a display one: which action is on which
key and which gamepad button, read from `InputMap`. Real remapping also means the gamepad,
conflict resolution and saving the scheme; that is half a milestone of work, and before release
it is more needed in M9. Filed as debt.

### 11. Font: Pixellari, OFL

Chosen by the only hard requirement — Cyrillic (ADR-0012, item 3). Verified: all 66 letters of
the Russian alphabet are present, Latin and digits too; of what is needed only the em dash is
missing, so it is not used in the interface. The file and the licence text lie side by side in
`assets/fonts/`.

## What is not in the milestone

- **Demo mode** (attract mode), which the cabinet runs between games. It requires a bot that
  plays by itself — we have one only in tests. Filed as debt.
- **Voice-over and speech.** The original has none, and the PSG has no voice for them.
- **Difficulty settings.** The cabinet's DIP switches are for the hall operator, not the player;
  our difficulty grows from building to building (ADR-0009).

## Consequences

- WAVs appear in `assets/audio/`, and the first third-party file in `assets/fonts/`.
- `requirements-assets.txt` gains the dependencies of the sound generator (numpy is already
  there).
- The first thing the game writes to disk appears: settings and the high-score table.
- The score affects the game for the first time — through the extra life.

## Sources

- [Arcade Game Manual: Elevator Action — Internet Archive](https://archive.org/details/ArcadeGameManualElevatoraction)
- [AY-3-8910 — Video Game Music Preservation Foundation](https://www.vgmpf.com/Wiki/index.php/AY-3-8910)
- [Elevator Action — Wikipedia](https://en.wikipedia.org/wiki/Elevator_Action)
- [Elevator Action "Theme" — Video Game Music Daily](https://vgmdaily.wordpress.com/2010/08/09/elevator-action-theme-yoshino-imamura/)
