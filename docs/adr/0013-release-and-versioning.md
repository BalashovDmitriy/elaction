# ADR-0013 · Release: builds, versions and tags

- **Status:** accepted; in item 7 the archive was extended after M22: the licences of all fonts
  (the HUD uses Exo 2 since M22) and `CREDITS.md` — models under CC-BY 3.0 require naming the
  authors wherever they are distributed
- **Date:** 2026-09-14

## Context

M9 is the last mandatory milestone. The game plays in full: building, combat, lighting, sound,
menu and high scores. Only one thing is missing — a way to get it. Right now, to play, one has
to install Godot and clone the repository.

The milestones before this one were checked against the 1983 original. Here there is nothing to
check: the cabinet had no archives, no versions, no download page. So this time the check went
through the tools, and it found three things that change the milestone's scope.

### What the check of the tools found

- **Command-line export requires a re-imported project.** Without a ready `.godot` folder the
  export either hangs or builds stale resources — both silently ([godot#69511], [godot#95287]).
  We already have `tools/godot_check.py`, which imports the project; in the build it goes first.
- **The icon and metadata are written into the `.exe` by `rcedit`, not Godot.** Without it the
  Windows build silently ships with the engine's default icon ([godot-ci#21]).
  On Linux `rcedit` also needs wine.
- **An empty version breaks the Windows export.** Since 4.2 `rcedit` fails if
  `application/file_version` is empty ([godot#83379]). That is, the version is not decoration
  but a required field, and it must be in two places at once: in `project.godot` and in the
  export preset.

## Decisions

### 1. The platform is GitHub Releases only

Closes open question No. 3. itch.io and Steam are not in this milestone: each has its own page,
its own requirements for screenshots and description, and both are about audience, not the
build. First an archive that downloads and runs; a storefront, if needed, on top of the finished
archives.

Consequence: the itch.io page item leaves the scope of M9 in `docs/EPIC.md`.

### 2. Versions stay at `0.x`

The first tag is `v0.9.0`, then `v0.10.0`, `v0.11.0`. The major one does not mean "the game
works" — it means "everything planned is done", and the backlog still has key remapping, demo
mode and possibly an online leaderboard (M10). Until then the game is honestly called 0.x.

The format is semver: `MAJOR.MINOR.PATCH`. A milestone bumps MINOR, a fix to a released version
bumps PATCH.

### 3. The single source of the version is `config/version` in `project.godot`

The version is needed in four places: in `project.godot`, in two fields of the Windows preset
(`file_version` and `product_version`), in the archive name and in the tag. Once they drift
apart, they drift apart forever, so:

- the version is changed with one command `python tools/version.py --set 0.9.0`, which sets it
  both in `project.godot` and in `export_presets.cfg`;
- the match is checked by a test, not by eye;
- the release workflow first compares the tag with `config/version` and fails before the build
  if they differ. Tag `v0.9.0` requires version `0.9.0`, no exceptions.

The player sees the version too: it is printed to the log at startup and shown in the corner of
the main menu. Without it a "it doesn't work for me" report has nothing to be correlated with.

### 4. Two builds on their own runners

Linux is built on `ubuntu-latest`, Windows on `windows-latest`. A matrix of two jobs instead of
one with wine: `rcedit` runs natively on its own OS, the icon and metadata go into the `.exe`
without a layer in between, and the build happens where it will be run. Wine, `rcedit` and
their paths in editor settings are three extra moving parts, and they break silently: the build
passes, there is no icon.

We do not build macOS: there is nowhere to test the build, and without signing and notarization
Gatekeeper will not let it run anyway.

### 5. Export after import, always

The order of build steps is strict: `tools/godot_check.py` (resource import and script parsing)
→ `--export-release`. This is a direct consequence of [godot#69511]: without import the export
builds what is no longer in the sources.

Here also belongs a lesson CI gave right at the boundary of M8b and M9. `project.godot` loads
`res://assets/i18n/*.translation` at engine startup, and these files are produced by the import
itself from `ui.csv`; the files are generated and listed in `.gitignore`, so on a fresh clone
the first import complains they are missing. On the working machine they were already there,
and the check stayed silent. Hence two rules of the milestone: the import survives the first
pass (`godot_check.py` repeats it and judges by the second), and before a PR
`tools/clean_check.py` is run — the same checks on a clean copy via `git worktree`. The release
build runs on a fresh runner, that is, exactly under the conditions where this shows up.

### 6. The built artifact is checked by a run, not by the fact of building

Export returns 0 even when it has built something broken. So after the build the Linux archive
is unpacked and run headless: the game must print a startup marker, live a given number of
frames and not write a single `SCRIPT ERROR`. If this fails, the release is not published.

The exit code alone is not enough: a process that crashed on the first frame also exits with
zero. Hence the marker is mandatory.

The Windows archive is checked by hand — that is the "run on a clean machine" from the DoD.

### 7. One executable in the archive

`binary_format/embed_pck=true`: resources are embedded in the executable, and there is no `.pck`
next to it that could be lost when unpacking. The archive contains the executable, `LICENSE` and
the font licence (OFL requires shipping it with the product).

Archive names: `elaction-v0.9.0-windows.zip`, `elaction-v0.9.0-linux.zip`.
Inside is a single `elaction` folder, not a folder named after the archive: `unzip` on Linux
without a folder would scatter the files over the current directory, and a same-named one would
give `elaction-v0.9.0-windows\elaction-v0.9.0-windows\elaction.exe` — Windows Explorer already
creates a folder named after the archive. The version and platform stay outside, in the file
name.

### 8. `export_presets.cfg` is edited by hand and lives in the repository

Normally this file is written by the editor, and written whole — all platform options,
including the defaults. We keep only what deliberately differs from the defaults:
`create_preset()` in the engine first fills the preset with default values and only then applies
the file, so a missing key means "same as everyone".

This way the file reads as a decision, not a dump. The cost: opening export in the editor makes
Godot rewrite it in full, and such a change has to be reverted.

`tests/`, `tools/` and `addons/` are excluded from export — the player does not need them, and
`addons/gut` also drags editor code along.

### 9. The icon is drawn by code, like the other assets

`tools/render_icon.py` builds `icon.ico` from the same geometry as `icon.svg` and puts into it
all the sizes Windows asks for (16–256). The reason is the same as in
[ADR-0011](0011-asset-pipeline.md): an asset drawn by a script is reproduced and edited, not
stored as a found file.

### 10. `CHANGELOG.md` is the source of release notes

Release notes are taken from the changelog section for this tag, not written by hand on the
web. The format is Keep a Changelog. `docs/milestones.md` stays what it was: the internal
history of milestones with all review findings; the changelog is the same for someone who has
just downloaded the game.

## What is not in the milestone

- **itch.io and Steam** — item 1.
- **Key remapping.** Postponed from M8b to here ([ADR-0012](0012-sound-and-interface.md),
  item 10) and postponed again: the milestone's DoD is "the downloaded archive runs and plays",
  and remapping drags in the gamepad, conflict resolution and saving the scheme. It is a separate
  milestone after release, not an add-on to the build.
- **Signing and notarization.** A certificate costs money, and SmartScreen will warn about an
  unknown publisher anyway — that is normal for an indie without a publisher.
- **Auto-updates.** A 60-megabyte game downloaded once every six months does not need an
  updater.
- **macOS** — item 4.

## Consequences

- The repository gets `export_presets.cfg`, `icon.ico`, `CHANGELOG.md` and a second workflow —
  `release.yml`.
- CI gains an export-template cache: the `.tpz` weighs hundreds of megabytes, and there is no
  reason to download it for every tag.
- The version stops being a free field: it is edited by `tools/version.py`, and a test makes
  sure the places do not drift apart.
- The first thing the game prints to the log at startup appears — the version line.

## Sources

- [Command-line export does not re-import the project — godot#69511][godot#69511]
- [Headless export without `.godot` hangs — godot#95287][godot#95287]
- [`rcedit` fails without FileVersion — godot#83379][godot#83379]
- [Windows builds without rcedit ship without an icon — godot-ci#21][godot-ci#21]
- [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/)

[godot#69511]: https://github.com/godotengine/godot/issues/69511
[godot#95287]: https://github.com/godotengine/godot/issues/95287
[godot#83379]: https://github.com/godotengine/godot/issues/83379
[godot-ci#21]: https://github.com/abarichello/godot-ci/issues/21
