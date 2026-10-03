# Changelog

Format — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions —
[semver](https://semver.org/). While the game is at `0.x`, 1.0 will mean
not "it works" but "everything planned is done"
([ADR-0013](docs/adr/0013-release-and-versioning.md), item 2).

GitHub release notes are taken from here: `python tools/changelog.py v0.9.0`.

There have been no releases yet: the `v0.9.0` tag has not been set. Its section describes
what is in `main`, and the date goes into the heading on the day of the tag; the links at
the bottom start working then too.

## [Unreleased]

## [0.9.0] — unreleased

The first public build. The game can be played through completely: from the roof to the car at the exit and on into the next building.

### Added

- **The game.** Otto descends from the roof of a thirty-floor building, collects documents
  behind red doors — five in the first building, then up to ten — fights off agents and
  drives away in a car. Then comes the next building, where the agents are meaner.
  Take too long and the siren goes on, and it cannot be turned off until the end of the
  building.
- **Buildings generated from the original's map.** Each building is laid out from a seed,
  while the doors, red doors and the dark floors 11–15 follow the arcade ROM tables. The
  lower you go, the more paths there are: shafts overlap, escalators stand in a row. Each
  session salts the layout. Traversability is checked by a bot that searches for a path
  through the building graph.
- **Elevators and escalators as in the original.** The cab obeys from inside, an empty one
  rides on its own; you can fall into an open shaft doorway, and die under a descending
  cab. There is a two-floor cab, agents ride as passengers. Otto is invulnerable on an
  escalator.
- **Combat by the ROM rules.** Agents' speeds, pauses, wind-up, shooting poses and dodges
  are taken from the arcade disassembly. Agents shoot standing, kneeling and lying down.
- **Light and darkness.** A zone is lit while the lamp above it is on; a shot-down lamp
  falls, can kill an agent below it and darkens its zone for good. In the dark agents see
  worse, and kills are worth more.
- **The picture.** A 3D scene with a side-on orthographic camera: people and cars from
  Quaternius packs, furniture, roof equipment and textures from CC0 and CC-BY packs
  ([CREDITS.md](CREDITS.md)). Real lighting — lamp cones with shadows, reflections in the
  floor; behind the windows a night city with the round's weather. Four quality levels;
  on first launch the level is chosen by measuring the frame time.
- **Sound.** 17 effects, the building theme and the alarm motif — synthesized in code,
  without a single third-party sample.
- **Interface.** Menu, pause, settings (three volumes, language, difficulty, graphics
  quality, window mode, resolution, render scale, blood), a ten-row high score table and a
  controls screen. Two languages — Russian and English, chosen by the system locale.
- **An extra life at 10,000 points** — the threshold from the Taito manual.
- **Windows and Linux builds** in GitHub Releases: a single executable with the resources
  inside it.

### Not there yet

- Key remapping: the controls screen shows the layout but does not change it.
- The demo mode that the arcade cabinet runs between sessions.
- Online high score tables.

[Unreleased]: https://github.com/BalashovDmitriy/elaction/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/BalashovDmitriy/elaction/releases/tag/v0.9.0
