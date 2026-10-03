# ADR-0036 · M23: sound from free libraries, noir jazz, ambience by place

- **Status:** accepted
- **Date:** 2026-09-25
- **Supersedes:** [ADR-0012](0012-sound-and-interface.md), items 1 and 2 and their amendment
  — synthesized sound and our own motif

## Context

After M22 and M22b the picture is modern, but the sound remained from M8a: 17
effects, the building theme and the alarm motif are synthesized by
`tools/render_audio.py` from waves and noise. The user's remark: the sound "now
seems very primitive".

What the check against the original showed:

- **The arcade music is one Yoshio Imamura theme** in several guises: the
  building theme and its own "Hurry Up" on alarm (@466E in jotd's disassembly).
  The arcade rip names eight more short jingles: building intro, entering a red
  door, document, life, bonus, death, death under a cab, game over.
- **The ROM distinguishes sounds more finely than we do:** Otto's and an agent's
  shot, a bullet into a wall, three deaths of Otto, a jump, the hook on the roof,
  escalator up and down. The full command list is in STATUS, section M23.
- **There is no ambience either in ours or in the arcade**, although since M19 and
  M22 the frame has the city, rain and lightning.

## Decisions

### 1. Sound — from free libraries, synthesis goes away entirely

The user's decision. Music, effects, jingles and menu sounds are taken as ready
files with a **CC0 or CC-BY** license; `tools/render_audio.py` and
`tools/audio_dsp.py` are removed. Authors are in `CREDITS.md` and in
`assets/audio/credits.json`, following the models
([ADR-0033](0033-dressing-from-packs.md)).

Licenses with strings attached — "royalty free" without the right to publish the
file, the Pixabay License, GDC bundles — are not used: the repository is public,
and a file in it is already distribution.

### 2. Character — spy noir jazz

The user's decision. Double bass, brushes, muted trumpet, vibraphone — matching
the spy plot and the M22 noir tone. The effects are chosen for the same character:
a muffled indoor gunshot rather than a laser, elevator machinery rather than a
beep.

### 3. A track for each screen

The user's decision. Building, alarm, menu and game over are separate tracks of
one character. One theme in different guises, like the arcade's, cannot be
assembled from libraries: different tracks have different themes. Jingles are
short files in the same idiom.

### 4. We do not add the original's sounds

The user's decision. The same events sound as now — with new sound. ROM
distinctions (agent shot, three deaths, jump, hook, door-entry and intro jingles)
are not in the milestone. New beyond the current set is only ambience and what is
already written in EPIC: footsteps on different floors, shaft hum, thunder.

### 5. Ambience — by place

The user's decision. On the roof, at the exit and in the menu — street and rain at
full strength; on floors — muffled, as if through glass, thunder breaks through.
Thunder follows lightning with a delay by the distance of the strike
(`Lightning`).

Ambience has its own bus `Ambience`, a child of `SFX`: the effects volume in the
settings controls it too, and the muffling on floors is a low-pass filter on that
bus, not a second set of files.

### 6. Music follows the game

The user's decision. The alarm comes in with a swell, not a cut; behind a red door
and on pause the music is muffled, as if through a wall — a filter on the `Music`
bus; a jingle ducks the track while it plays.

### 7. The choice — by the user's ear

The developer cannot check sound by ear. For each slot two to four candidates
with author and license are prepared on a local page with a player; the user
chooses, and the chosen ones are built into the game.

### 8. Variants and what did not fit

The choice is multiple (the user's decision): several tracks for one screen
alternate by a draw on the building seed, several variants of an effect — by a
draw on each playback (`AudioStreamRandomizer`). Files are `name.ogg`,
`name.2.ogg`, ….

For a bullet hitting a body no candidate fit. It has no sound of its own: a hit
always kills, and it is heard as the death. Rain behind glass and corridor
silence were found as recordings — those play on floors, not a filter over the
street ones.

## Not in the milestone

- ROM sounds beyond the current events — item 4.
- Music in tension layers: tracks split into stems are almost never found in free
  libraries.

## Consequences

- `assets/audio/` changes entirely; sound names in `Sounds` stay, so that the game
  code is not touched without need.
- The `Ambience` bus and filter effects on the `Music` and `Ambience` buses appear
  in `buses.tres`.
- The release archive carries `CREDITS.md` — CC-BY requires attribution.
- ADR-0012, items 1 and 2, are superseded; the status line is in its header.
