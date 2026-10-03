# EPIC-1 · elaction — an Elevator Action remake

| | |
|---|---|
| **Status** | In progress, the current milestone is in [STATUS.md](STATUS.md) |
| **Started** | 2026-09-11 |
| **Stack** | Godot 4.7.2, typed GDScript |
| **Repository** | https://github.com/BalashovDmitriy/elaction |
| **Decisions** | ADR-0001…0034 in [`adr/`](adr/); summary table in [STATUS.md](STATUS.md#accepted-decisions) |

## 1. Goal

Release a finished arcade game for PC that:

1. reproduces the mechanics of Elevator Action (Taito, 1983) **with no gameplay changes**;
2. looks modern — through a 3D scene with a side-on orthographic camera, dynamic lighting,
   PBR materials and post-processing ([ADR-0019](adr/0019-3d-pivot.md)), not through
   reinventing the design: the game stays flat;
3. passes automated checks on every commit.

The project formula: **1983 mechanics, 2026 picture.**

## 2. Epic Definition of Done

- [x] Full game loop: entry from the roof → collect all documents → exit to the car → next building
- [x] 30 floors, elevators, escalators, doors, enemy agents, shooting, kick
- [x] Lamps that can be shot out, and darkening
- [x] Lives, score, high score table, Game Over screen
- [x] Main menu, settings, gamepad support
- [ ] Windows and Linux builds are built in CI on a tag — the workflow exists since M9,
      the first tag has not been set yet
- [x] Green CI; game logic is covered by tests (rendering is not)

## 3. Scope

**Not part of the epic:** multiplayer, mobile platforms, consoles, a level editor for
players, an online high score table, 3D gameplay (the scene is 3D, the game is flat —
[ADR-0019](adr/0019-3d-pivot.md)), story cutscenes.

The online leaderboard is moved to the optional M24 — it is the only reason a backend and
docker compose might appear in the project (see [ADR-0003](adr/0003-no-docker.md)).

## 4. The original's mechanics — the source of truth

Implemented as in the arcade original. Disputed details are checked against the ROM code
and runs in MAME, not from memory: disassembler notes are in
[`reference/arcade-rom.md`](reference/arcade-rom.md).

| Mechanic | Essence | Milestone |
|---|---|---|
| Otto | Agent 17. Walks, crouches, jumps, shoots, kicks | M1, M18d |
| Building | 30 floors and a roof, descent from top to bottom, exit at the bottom to the car | M5a, M18a, M18e |
| Elevators | Cab in a shaft; the player controls it from inside; without the player it moves on its own; on the cab roof you ride without control; crushes to death | M2, M18b |
| Escalators | Boarding by a press on the landing, automatic transfer between floors | M2 |
| Doors | Regular — agents come out of them; red — they hold documents; you can hide inside for up to five seconds | M3, M14 |
| Documents | 500 points each, 5–10 per building depending on skill; exiting without all of them returns you to the topmost uncollected door | M3, M18e |
| Enemies | Agents come out of doors, walk and shoot standing, crouching and lying down; their bodies do no harm | M4a, M18d |
| Lighting | Lamps can be shot out and fall on heads; the zone goes dark; dark floors 11–15 | M4b, M17, M18e |
| Level end | Exit at the bottom to the car | M5b |

The ROM check closed the former disputed points — the number of red doors, the score table,
the exit bonus, agent release, darkness ([ADR-0027](adr/0027-rom-combat.md),
[ADR-0028](adr/0028-building-by-the-map.md)). Deliberate deviations are recorded
in these ADRs.

## 5. Roadmap

Each milestone is a separate branch and PR. A milestone is closed when its DoD is met and CI
is green. Detailed results of completed milestones are in [`milestones.md`](milestones.md).

M0–M22b are done and all merged into `main` (the last is M22b, PR #43, together with
the documentation check and its debt); the 3D pivot is finished. Also done:
**M23** — sound (PR #44), **M24a** (PR #45), **M24b** (PR #47), **M24c** (PR #48),
**M24d** (PR #49), **M24e** (PR #50), **M24f** (PR #51, #52) and **M24g** — animation
and look (PR #53). **M24h** is done — the street with traffic and mechanics fixes from the
M24g remarks. Done: **M24i** — takedowns, helicopter and dressing (PR #57), **M24j** — time
of day and the new city (PR #58), **M24k** — time of day for everything else and
the cinematic opening (PR #59). Done: **closing open questions and debt**
([ADR-0053](adr/0053-open-questions-and-debt.md), PR #60) and **M24l** — snow
(PR #62); done: **M24m** — the residential complex (PR #63) and **M24n** — building kind character (PR #64); **M24o** — special floors, cab and music (PR #65); **M24p** — the building exterior by kind (PR #66); next is **M25** — the online leaderboard (optional).

### M0 · Foundation

Repository, engine, tooling, process.

- [x] Git repository, public, SSH
- [x] Godot 4.7.2, `project.godot`, basic render settings and the input map
- [x] Folder structure and conventions (`docs/conventions.md`)
- [x] `gdformat` + `gdlint` + pre-commit (on commit) and the engine check (on push)
- [x] CI on GitHub Actions: lint + project import
- [x] Minimal runnable scene `src/main.tscn`
- [x] GUT 9.6.1 test framework, first tests, running in CI
- [x] Close [ADR-0002](adr/0002-visual-target.md): the visual target (superseded by
      [ADR-0019](adr/0019-3d-pivot.md))

**DoD:** `tools/check.ps1` passes locally, CI is green, the project runs. ✅

### M1 · Otto walks — a vertical slice

The first thing you can play. Graphics are grey boxes.

- [x] `CharacterBody2D` and a state machine: idle / walk / crouch / jump / fall / dead
- [x] Gravity, collisions, the floor, walls at the level edges
- [x] Camera: follows the player, clamped to the level bounds
- [x] Grey-box level of one floor with platforms for jumping
- [x] Input: keyboard and gamepad
- [x] State machine tests (14 of them)
- [x] Taking milestone screenshots (`tools/capture.py M1`)

**DoD:** Otto runs, crouches and jumps along one floor; tests are green. ✅

The state machine is moved out of the node into the `OttoStateMachine` class: it takes an
input snapshot and facts about the body, returns a state — and is tested without a scene or
physics.

### M2 · Elevators and escalators — the core of the game

Decisions — [ADR-0004](adr/0004-elevator-mechanics.md).

- [x] The shaft is described by level data: bounds and stop floors (in a `Resource` — in M5a)
- [x] Cab: `AnimatableBody2D`, moving up and down, stopping at floors
- [x] Entering the cab and controlling it from inside, stepping out onto a floor when the floors line up
- [x] Autonomous cab movement when Otto is not in it: floor to floor with a pause
- [x] Riding on the cab roof, without controlling it (platform carries the player)
- [x] Open shaft opening: can be run across and jumped over, falling into an empty shaft kills
- [x] Lethal crushing of the player by the cab (agents — since M18d)
- [x] Escalators: boarding by pressing "up/down" on the landing, transfer between floors
- [x] Contextual input: "down" is a crouch on the floor and lowering the cab in the shaft
- [x] Checking for headroom when standing up from a crouch (M1 debt)
- [x] Tests: platform carry, boarding and stepping off, crushing, falling into the shaft

**DoD:** you can descend from the top floor to the bottom one using an elevator and an escalator. ✅

### M3 · Doors and documents

Decisions — [ADR-0005](adr/0005-doors-and-documents.md).

- [x] A door as a scene: closed / opening / open, a mat in front of the entrance
- [x] Entering from the mat by pressing "up"; inside, Otto hides for up to five seconds,
      with an early exit by pressing sideways
- [x] Red doors: a document on first entry, +500 points, the door stops being red
- [x] Regular doors: scene and states; agents from them — in M4a
- [x] `GameState` autoload: score and collected documents, connected via signals
- [x] Document counter and score in the HUD
- [x] The building exit is always open, but without all documents it moves you to the
      topmost floor with an uncollected red door — the original has no exit lock
- [x] Tests: collecting a document, score, choosing the door to move to, the real-exit condition

**DoD:** in a three-floor test building you can collect all documents and exit; an attempt
to exit early returns you to the uncollected door. ✅

### M4a · Combat and enemies

M4 is split in two; the numbering of the other milestones does not shift. Decisions and the
check — [ADR-0006](adr/0006-combat-and-enemies.md).

- [x] Otto's shooting: standing, crouching, mid-jump; no more than three bullets on screen at once
- [x] Jump kick
- [x] Bullets as separate entities: flight height, hits
- [x] Dodging: crouch under a high bullet, jump over a low one
- [x] Enemy agent: comes out of a regular door, walks along the floor, shoots along the line
- [x] Three lives; only a shot takes a life — colliding with an enemy is harmless
- [x] Player death, respawn, Game Over
- [x] Points for enemies: 100 for a shot, 150 for a kick
- [x] Tests: hits, dodging, the life counter, agent behaviour

**DoD:** a floor with enemies can be fought through; out of lives — Game Over. ✅

### M4b · Lamps and darkness

Decisions — [ADR-0007](adr/0007-lamps-and-darkness.md).

- [x] A lamp as a scene: can be shot out, falls, kills an agent beneath it (300 points)
- [x] A falling lamp does not touch Otto: the sources speak only of agents
- [x] A downed lamp darkens its floor for good — a deviation from the original, where the
      whole building goes dark for a short while ([ADR-0006](adr/0006-combat-and-enemies.md),
      item 7); since M17 — its zone
- [x] Until M6, darkness is shown as a darkening rectangle over the floor
- [x] In darkness, agents' shooting range drops (since M17 — the range at which an
      agent notices Otto)
- [x] Bonus for a kill in the dark (amount corrected in M6)
- [x] Otto's invulnerability on the escalator — M2 debt
- [x] Tests: floor lighting, points in the dark, agent range in the dark

**DoD:** lamps go out, enemies behave differently on a dark floor. ✅

### M5a · Building

M5 is split in two, like M4. Decisions — [ADR-0008](adr/0008-building-generation.md).

- [x] The building is described by rules, not a list of floors: how many shafts, doors, lamps
- [x] Layout by seed: in the original, buildings differ by the placement of red doors
- [x] Assembling 30 floors from this description
- [x] The shaft and the escalator move into data — M2 debt
- [x] The escalator landing is decoupled from the belt: boarding without a jerk, the belt
      does not cut through the slab (M2 code review debt)
- [x] FPS measurement on the full building: 60 holds, streaming was not needed
- [x] Tests: layout rules, repeatability by seed

**DoD:** a 30-floor building is assembled from data and can be played top to bottom, 60 FPS. ✅

### M5b · Game loop

Decisions — [ADR-0009](adr/0009-game-loop-and-alarm.md).

- [x] Exit with the documents collected → bonus → next building
- [x] Building bonus: 1000 × number. In the ROM it does not grow past the tenth building
      ([`arcade-rom.md`](reference/arcade-rom.md)) — we have no cap, a deviation
- [x] Difficulty grows through agents: they shoot more often, see farther, replace each other faster
- [x] Alarm on a per-building timer: agents get angrier, the cab responds with a delay.
      Death does not clear the alarm, only a building change resets it
- [x] Pause on Esc with a hint: resume, restart, quit
- [x] Tests: alarm, bonus and building number, delayed cab response

**DoD:** the game plays from the first building to the second without crashes. ✅

### M6 · Lighting and atmosphere — the graphics layer

Decisions — [ADR-0010](adr/0010-lighting-and-atmosphere.md). The 2D lighting
implementation left with the pivot, the rules stayed ([ADR-0019](adr/0019-3d-pivot.md), decision 7).

- [x] Measuring the lighting budget — M0 debt
- [x] `CanvasModulate` sets the tone of a darkened floor; the floor's own lamp makes it bright
- [x] Two sources per floor: a full-width fill and a spot under the lamp
- [x] `LightOccluder2D` on the slabs: light does not leak between floors
- [x] Light from the elevator shaft, muzzle flashes
- [x] Per-frame source culling: only visible floors are lit
- [x] Post-processing: bloom and vignette
- [x] Parallax city background, laid out from the building seed
- [x] Bonus for a kill in the dark: +50 instead of doubling — a fix from the check
- [x] Tests: visible floor culling, the budget on the assembled building, background by seed, points

**DoD:** a dark floor with a firefight holds 60 FPS, measured on the assembled building. ✅

### M7a · Art pipeline and environment

M7 is split in two. Decisions — [ADR-0011](adr/0011-asset-pipeline.md). The milestone's
sprite pipeline left with the pivot (M16, [ADR-0019](adr/0019-3d-pivot.md), decision 8);
`tools/blender_bin.py` remained.

- [x] `tools/blender_bin.py`: Blender 5.2.1 is looked up like Godot — `$BLENDER_BIN` → PATH → winget
- [x] The pipeline runs end to end on one asset: render → import preset →
      `CanvasTexture` → the M6 lighting falls on it
- [x] `tools/palette.py` — the palette in one place (removed in M22 with the 2D cleanup)
- [x] Environment generator `tools/render_env.py`: diffuse, normal, specular from one geometry
- [x] Building tileset, slabs, back wall, windows
- [x] Doors (red and regular), elevator cab, escalator, lamp, exit
- [x] The city behind the windows gets textures, the M6 layout rules stay
- [x] Godot import presets are committed to the repository
- [x] Tests: every asset a scene requests exists, splits into frames and has a normal map

**DoD:** no grey boxes left in the frame except Otto and the agents; 60 FPS holds
on the assembled building. ✅

### M7b · Actors

Decisions — [ADR-0011](adr/0011-asset-pipeline.md), items 12–14. Actor sprites
were replaced by skinned models in M16.

- [x] `tools/render_actors.py`: a low-poly model and an orthographic render in Blender 5.2.1
- [x] Otto: idle, a three-frame walk, crouch, jump, fall, kick, shot
- [x] Death in two poses and a separate crushed pose — as in the final arcade
- [x] Agent: a hat versus Otto's pompadour — the silhouette reads in the dark
- [x] Normal and specular maps from a second render pass (from depth, not the normal pass)
- [x] Bullets and hit flashes
- [x] The red car at the exit: drives off, and only then is the next building assembled
- [x] Not one collision from M1–M5 changed — a test checks this

**DoD:** all grey-box placeholders are replaced with final assets. ✅

### M8a · Sound

M8 is split in two: sound depends on nothing, while the menu depends on the font, language
and volumes. Decisions — [ADR-0012](adr/0012-sound-and-interface.md).

- [x] `tools/render_audio.py`: synthesis into `assets/audio/` — an effect built from an
      attack, a body and a room tail; frequent sounds in WAV, long ones and music in OGG
- [x] SFX for all game events: steps, shot, hit, kick, lamp, elevator,
      escalator, door, document, death, exit
- [x] Our own theme and a separate alarm motif
- [x] Master / Music / SFX buses and an overall mix
- [x] Tests: every game event has a sound, and no file is lost

**DoD:** a session sounds from the first step to Game Over, and nothing is silent without reason. ✅

### M8b · Interface

Decisions — [ADR-0012](adr/0012-sound-and-interface.md), items 8–11.

- [x] Pixellari (OFL) with Cyrillic in `assets/fonts/` together with the license text
- [x] Two languages: `ru` and `en`, by system locale, with a switch in the settings
- [x] HUD instead of the debug overlay: score, lives, documents, floor, alarm —
      modern, in the corners, without the arcade line at the top
- [x] Main menu: play, high scores, settings, controls, quit
- [x] Settings: three volumes, language, fullscreen; the controls screen
      only shows the bindings — rebinding is in the debt (STATUS)
- [x] Local high score table: ten rows with score and date, no initials
- [x] Extra life at 10,000 points — a fix from the check against the Taito manual
- [x] Tests: strings exist in both languages, high scores and settings survive
      a restart, the extra life for points is granted once

**DoD:** the game starts from the menu and returns to it. ✅

### M9 · Release

Decisions — [ADR-0013](adr/0013-release-and-versioning.md). Pages on itch.io and Steam
are not in the epic — only GitHub Releases (same place, item 1).

- [x] `export_presets.cfg`: Windows and Linux, resources embedded in the executable,
      without `tests/`, `tools/` and `addons/`
- [x] `icon.ico` is drawn by a generator from the same geometry as `icon.svg`
- [x] `tools/version.py`: the version is changed with one command and written
      into both `project.godot` and the presets; the tag is checked against it
- [x] The version is visible outside git too: a log line at startup and the main menu corner
- [x] `release.yml`: tag `v*` → version check → build on ubuntu and windows →
      archives in GitHub Releases, notes from `CHANGELOG.md`
- [x] `tools/smoke.py`: the built binary runs headless, prints a marker
      and writes not a single `SCRIPT ERROR`
- [x] `CHANGELOG.md` following Keep a Changelog
- [x] Tests: the version is semver and matches the presets, both presets are in place,
      `tests/` and `tools/` do not leak into the export

**DoD:** an archive downloaded from Releases runs and plays. The first tag has not been
set yet — the run of the Windows archive on a clean machine is postponed to it.

### M10 · Building architecture

Decisions — [ADR-0014](adr/0014-building-architecture.md). The milestone was opened after
M9: a bot run of a real building showed that the built archive was unplayable.

- [x] The roof is a separate level with index −1, with sky above it; all levels have the
      same clearance, Otto and his jump fit in the frame
- [x] The roof has no doors, lamps or agents; the top shaft reaches it
- [x] Floor zero becomes a regular floor: it gets a ceiling, a back wall and a lamp
- [x] A stepped silhouette: 5 → 7 → 9 places (since M18a — by threshold)
- [x] The floor bounds are known to slabs, walls, windows, lighting and the reachability graph
- [x] Agents are released by `VisibleFloors`, not all 55 at once in `_ready()`
- [x] Fewer doors at the top than at the bottom
- [x] Returning to the game — with a breather and away from the one who killed you
- [x] Tests: a bot run of the real building, roof clearance, an empty roof,
      profile monotonicity, the shaft stands on an accessible spot on all its floors,
      Otto survives the start with agents

**DoD:** the bot clears a real thirty-floor building, and with agents enabled the
player survives the start doing nothing. ✅ Combat balance is moved to M11.

### M11 · Combat balance

Decisions — [ADR-0016](adr/0016-combat-balance.md). The bot used to measure combat in M10
could not dodge, so the milestone started with a measurement, not with tuning numbers.
Combat numbers since M18d are taken from the ROM.

- [x] Check the difficulty growth axes against the original
- [x] Growth along the original's axes: fire rate and bullet speed, range is frozen
- [x] Agents dodge: a knee against a high bullet, lying down against a low one
- [x] A wind-up before the first shot — without it the player had no move
- [x] Teach the bot to dodge — otherwise there is nothing to measure with
- [x] Move combat numbers into the building rules, as anger and door density were moved
- [x] A cap of eight live agents (since M18d, by the ROM — 3–4 per building)
- [x] The bot fights rather than walking past — and really shoots
- [x] Tests: the bot clears a real building with agents enabled

**DoD:** the bot clears a real thirty-floor building with agents without using up
three lives. ✅ Seeds 1–6, zero to two deaths per run.

### M12 · Spectrum-style visuals: round palette, shafts, roof

Decisions — [ADR-0017](adr/0017-spectrum-palette-and-shafts.md) on top of
[ADR-0015](adr/0015-round-palette-and-roof.md). The Spectrum colours were cancelled by
the pivot; the round palette as a technique stayed ([ADR-0019](adr/0019-3d-pivot.md),
decision 7).

- [x] The palette moves from level constants into the building rules and changes by round
- [x] The palette sets both colour pairs — of a lit floor and a darkened one
- [x] Environment assets are redrawn in the Spectrum colour language
- [x] The shaft gets a body: full-height guide rails and doors on its floors
- [x] A machine room superstructure on the roof, Otto descends to it on a rope
- [x] The round counter in the HUD is called ROUND
- [x] Tests: the gap between lit and darkened on every palette, the shaft is dressed
      on all seeds, the superstructure does not hinder Otto's appearance

**DoD:** consecutive buildings differ by eye, a darkened floor reads in each,
and the shaft is seen first in the frame, not last. ✅

### M13 · Native FullHD and quality textures

Decisions — [ADR-0018](adr/0018-native-fullhd.md). The world was drawn at 640×360 and
tripled to 1080p. A trial showed that resolution by itself gives nothing — the milestone
is about asset detail (details in [`milestones.md`](milestones.md)).
Detail through canvas scale was cancelled by the pivot ([ADR-0019](adr/0019-3d-pivot.md),
decision 7), the 1920×1080 viewport stayed.

- [x] ADR-0018 replacing the visual target [ADR-0002](adr/0002-visual-target.md)
- [x] 1920×1080 viewport, the world is scaled threefold: floor height, building width,
      actor height, speeds, jump
- [x] `render_env.py --scale` and `render_actors.py --scale` — a shared canvas scale
- [x] Environment assets redrawn with fine detail: masonry, panelled doors,
      slabs with an edge, a cab with panels, a lamp with a socket and a wire
- [x] Detail depends on scale rather than duplicating an asset
- [x] Actors re-rendered from Blender at a larger size
- [x] Fonts, HUD and menus recalculated for the new viewport
- [x] Proportions: Otto and agents larger, the door taller, the window smaller (ADR-0018, decision 5)
- [x] The limit of the shaft's travel is visible: stops and arrows in the cab (decision 6)
- [x] Tests: no geometry number remained at the old scale; every asset
      is three times larger than before; the bot clears the building; the frame is within the 16.6 ms budget

**DoD:** the game runs at 1920×1080 without stretching, and by eye it is more detailed, not
just larger. ✅

### M14 · The door really opens

Decisions — [ADR-0020](adr/0020-agent-doors.md). The last milestone on 2D, about behaviour,
not the picture: agents appeared over a closed door. A logic bug would have survived
the renderer change, so it was fixed before it.

- [x] The door cycle is a class without a node (`DoorCycle` on `RefCounted`):
      `closed → ajar → open → closed`, with timings and a release ban
- [x] The door does not hand out an agent until it is open, and closes behind him
- [x] The agent steps out of the doorway rather than appearing on the mat
- [x] The door moves smoothly for Otto too
- [x] Tests: the door does not release an agent before it opens; it closes behind
      the one who came out; the cycle is checked without a scene

**DoD:** not one agent appears over a closed door, and the door cycle is
checked by a test without a scene. ✅

### Pivot: from M15 the project moves to 3D

The decision and its cost — [ADR-0019](adr/0019-3d-pivot.md). The visual target became
a 3D scene with a side-on orthographic camera instead of a 2D frame of sprites. The game
logic does not change in a single rule; the node layer, the asset pipeline and lighting
change. The 2D build remains in history — the M14 merge, `d5774df`.

Three rules for all pivot milestones:

- **Each milestone ends with a playable build.** The first (M15) gave boxes,
  not beauty (ADR-0019, decision 4); before it `main` kept the 2D build.
- **Arcade readability matters more than cinematics.** A game object has no right
  to depend on the scene lighting (decision 5). A shot with the lamps out is taken
  in each milestone on a par with a lit one.
- **Mechanics do not live in a node.** If a new rule ended up in `_physics_process`,
  it is written wrong: a class without a scene makes the decision, the node executes it.

### M15 · 3D greybox: building, elevators, Otto

Decisions — [ADR-0021](adr/0021-3d-greybox.md). Moving the node layer; it is measured by
what plays, not by what is seen.

- [x] The scene is 3D: `Node3D`, `CharacterBody3D`, `AnimatableBody3D`,
      the Z coordinate of game bodies is locked
- [x] There is one play plane (Z = 0), depth lives behind the corridor's back wall
- [x] `Vector2` stays in the rules layer; conversion to `Vector3` is only in `WorldSpace`
- [x] One light source per floor — the lamp; the rule "a downed lamp darkens the floor" lives on
- [x] Metric scale: the numbers of `BuildingRules`, `ElevatorMotion` and `EnemyBrain`
      are divided by a hundred (ADR-0019, decision 3)
- [x] The building generator feeds meshes and collisions; `BuildingPlan` and `BuildingRoute` are untouched
- [x] Side-on orthographic camera: `CameraBounds`, `SideCamera`
- [x] Render settings revised: pixel snapping and nearest-neighbour
      filtering are cancelled together with ADR-0002
- [x] The core moved without logic changes; the one exception — the cab's arrival
      tolerance at a stop — is recorded in ADR-0021
- [x] Tests: all scene-less tests pass; scene tests are rewritten; the bot clears
      the building with agents on three lives

**DoD:** the bot clears a thirty-floor building in a 3D scene of grey boxes, and not
one rules test was changed along the way. ✅

### M16 · Actors: models and animations

Decisions — [ADR-0022](adr/0022-actors-rig.md).

- [x] `tools/build_actors.py`: Blender builds a figure from boxes on an armature
      and exports `assets/models/*.glb`; the car at the exit — with the same script
- [x] `FigurePoses` — a table of poses as limb angles; `FigureRig` drives the bones
      towards the pose with smoothing, walking is a continuous cycle; `ActorPose` picks the pose
- [x] The agent gets the same plus dodge stances (standing, kneeling, lying)
- [x] The actor is lit by the scene; readability on a darkened floor is held by an outline
- [x] The sprite pipeline is gone: `render_actors.py`, `render_env.py`,
      `assets/sprites/`, `ActorBox`
- [x] Tests: every pose has a table entry; the crouch is below an agent's bullet; bones
      do not overshoot within a transition frame; no pose goes below the floor

**DoD:** a freeze-frame of walking shows a step, and crouching Otto is below an agent's
bullet. ✅ The rig has no knees — crouching is a torso lean; a model with knees — M21.

### M16a · The cost of crouching — dropped

A parked milestone (2026-09-20): no agent could hit a crouching Otto, and a separate type
was planned — a kneeling shooter in a helmet. Dropped in M18d: by the ROM, a regular agent
can fire low, a lying-down bullet hits a crouching Otto too, only a jump saves you
([ADR-0027](adr/0027-rom-combat.md), decision 3; open question #7 is closed).

### M17 · Lighting, materials and readability

Decisions — [ADR-0023](adr/0023-light-and-readability.md).

- [x] The orthographic camera is tilted ten degrees from above: the floor is visible as a strip;
      the play plane and hits are untouched (decision 1)
- [x] Lamps per floor by width — one at the top, three at the bottom; a downed one darkens
      its zone (decision 2)
- [x] **New mechanic:** shadow decides whether an agent sees Otto — in a dark zone
      they notice him closer than 1.8 m, behind a door they do not see him at all (decision 8)
- [x] PBR materials: polished floor, rough concrete, metal of shafts, cabs and rails.
      No textures: M19 went with palette materials, details — with geometry in M20,
      wall textures — since M21b
- [x] Sources with soft shadows: the lamp has a downward cone and a weak fill. There is no
      cold source at the windows: the M19 city glows by emission
- [x] Volumetric fog and a hint of glow
- [x] Floor reflections — SSR; contact shadows — SSAO
- [x] Edges for the light to catch on: slab ends, skirting, pilasters
      (`BuildingRibs`)
- [x] The lamp hangs on a pendant; no swinging — a downed one falls at once (ADR-0007)
- [x] Readability through indicator lights: the door board, cab indicators, the exit sign;
      the light fixture and the bullet glow on their own, actors are outlined
- [x] Tests: `tools/light_bench.gd` — 1.2 ms GPU; `test_readability`,
      `test_darkness`

**DoD:** the light is soft and volumetric, and on a dark floor the player sees what they are shooting at. ✅

### M18 · Building geometry

Decisions — [ADR-0024](adr/0024-building-geometry.md). The check against
[Elevator World](https://elevatorworld.com/article/elevator-action/) gave the rule
**the lower, the more paths**: shafts are unequal and overlap, escalators are where
there is no overlap. The milestone is split: first the reachability graph, then the look,
then proportions, combat and the building by the ROM.

#### M18a · Layout

- [x] A finer grid of places: 17 places instead of 9 (pitch since M18c — 1.8 m)
- [x] A threshold silhouette: down to the twentieth floor a narrow tower that fits in the
      frame; from the twentieth — a wide podium
- [x] Shafts overlap: from one at the top to five at the bottom
- [x] Escalators as a strip at the threshold plus a guarantee at a break
- [x] An inner wall splits the floor in two; a wall that cuts off a document or the exit
      is removed
- [x] Tests: the tower fits in the frame, the podium does not; the number of shafts does not
      decrease downward; every junction is an overlap or an escalator; the bot clears any building

**DoD:** from the twentieth floor down there is a choice of path, and any building is passable. ✅

#### M18b · Geometry, look and riders

Decisions — [ADR-0025](adr/0025-shafts-escalators-and-riders.md).

- [x] The escalator as a structure: balustrade, steps, landings, opening frame;
      a low side on the camera side
- [x] The light column in the shaft is a real source, it does not go out from a shot
- [x] A two-storey cab: a rigid pair, up to two per building, only in a shaft that
      has another path on every floor
- [x] `BuildingRules.MIN_SHAFT_FLOORS` 3 → 4
- [x] Agents ride in cabs but do not control them — as in the original
- [x] `_moves` and `_links` in `BuildingRoute` are merged into one graph count
- [x] A combat run on seed 1 is reproducible — the last cause was closed in M18d
- [x] Parallel check runs: `run_tests.py` over six processes, 139 s versus
      755 ([`testing.md`](testing.md)). A CI job matrix is in the debt (STATUS)
- [x] Tests: travel keeps both tiers in the shaft; the share of seeds with a pair; a shaft's
      travel is no shorter than four floors; the frame budget with light columns

**DoD:** below the twentieth floor there is a choice in the frame, the escalator looks like
an escalator, and in a cab you can meet someone other than Otto. ✅

#### M18c · Proportions from the original

Decisions — [ADR-0026](adr/0026-proportions.md). Our floor is right, but everything that
stands on the floor was 1.33 times too small. Shares are of the floor clearance (40 px in
the original, 3.0 m here):

| | Original | Before the milestone | After |
|---|---|---|---|
| Otto | 56% × 25% | 42% × 18% | 1.68 × 0.72 m |
| Agent | 56%, as tall as Otto | 39%, shorter than Otto | 1.68 m |
| Door | 70% × 40% | 57% × 28% | 2.1 × 1.2 m |
| Shaft and cab | 60% | 40% | 1.8 m |
| Place pitch | 60% | 70% | 1.8 m |
| Floors in frame | 3.67 | 3.0 | 3.67 |

- [x] Grow the contents, leave the floor alone
- [x] Otto and the agent are 1.68 m, the same height; models rebuilt
- [x] Numbers tied to height: shots, kneeling and lying, crouch, kick, bot tolerances
- [x] Door 2.1×1.2, the leaf swings into the room
- [x] Shaft and cab 1.8, cab width from the rules; shafts do not stand side by side
- [x] Place pitch 1.8, building 33.6 m
- [x] The lamp under the ceiling, can be shot down from a cab
- [x] The escalator steeper, into its two places
- [x] The car sized to Otto's height; exit opening 1.68
- [x] The camera shows 3.67 floors
- [x] Sizes — in one `Proportions` table in original pixels (decision 8)
- [x] A floor number on every floor (decision 9)
- [x] Re-measuring the bot run and the frame budget: 2.25 ms GPU
- [x] Tests: shares against the original's table, floor footprints do not overlap each other,
      the leaf in the opening, the cab fills the shaft width

**DoD:** the shares of all building objects to the floor clearance match the original,
and deliberate deviations are recorded as numbers. ✅

#### M18d · Combat by the ROM rules

Decisions — [ADR-0027](adr/0027-rom-combat.md); disassembler notes —
[`reference/arcade-rom.md`](reference/arcade-rom.md). The original's logic rate is
14.8 ticks/s.

- [x] `Arcade` — the ROM formulas in one table
- [x] Difficulty: skill + time in the building, four times faster after the alarm, cap 15;
      each agent has its own anger
- [x] 3–4 agents per building, coming out of a random blue door on Otto's floor and adjacent ones
- [x] Agent shot: wind-up, pause, one bullet in flight, standing, crouching and lying; ROM
      bullet heights
- [x] Dodging by the ROM: high bullet — crouch, low — lie down
- [x] ROM speeds: walking 2.2 for both, bullets 8.9 and 6.7–8.9, cab 2.2
- [x] ROM jump: +1.88 m, 0.95 s, direction does not change in the air
- [x] Otto's shots wake agents for 6 s
- [x] The cab crushes agents — 300 points
- [x] Alarm at 277 s
- [x] Four difficulty levels in the settings — DIP 0–3
- [x] The bot jumps over a low bullet; the death rate is measured at each level
- [x] Tests: `Arcade` against ROM numbers, the "bullet — stance" order, agent limits,
      cab crush

**DoD:** combat follows the original's rules, and difficulty is expressed by the bot's
death rate at each level. ✅

#### M18e · The building by the original's map

Decisions — [ADR-0028](adr/0028-building-by-the-map.md). Generation stays but
takes its rules from the original's map.

- [x] `Arcade`: ROM floor by share of height, floor doors (`table_280E`), dark floors,
      red door quotas
- [x] Doors per floor by the ROM per screen width; one per floor is mandatory
- [x] Red doors 5 → 10 by skill, in ROM bands
- [x] ROM dark floors 11–15 — without lamps, dark from the building start; they do have doors
- [x] ROM lower floors 1–7 — the lamps stay (deviation recorded)
- [x] Session salt: the building seed from the number and the salt, zero in tests and for the bot
- [x] Door telegraph at the end of a shift (M14 debt)
- [x] Re-measuring the bot on the new door density, all difficulty levels
- [x] Tests: on any seed and skill — doors by the ROM, documents by quota and reachable,
      dark floors without lamps, the salt changes the building

**DoD:** a floor is no emptier than the original, and a building cannot be memorised from
session to session. ✅

### M19 · Dressing and background

Decisions — [ADR-0029](adr/0029-city-weather-dressing.md). The arcade has none of this;
there is one rule — do not get in the way of readability.

- [x] City: blocks by generation, windows by emission, three to four rows of depth, in its
      own perspective view as the frame background
- [x] Round weather by seed: rain, fog or a clear night; dry in the corridor
- [x] Floor dressing — decor by the back wall, not on occupied places
- [x] A floor indicator board above the shafts
- [x] The roof as in the original: stepped slopes and parapets as a silhouette behind the play plane
- [x] Round palette via materials ([ADR-0017](adr/0017-spectrum-palette-and-shafts.md)
      as to the technique, not the colours)
- [x] A dark floor is noticeably darker than a lit one
- [x] Tests: dressing not on occupied places and without bodies, city and weather by seed,
      the source budget does not grow

**DoD:** the frame shows a building at night in a city, not a diagram of a building. ✅

### M20 · Scene detail

Decisions — [ADR-0031](adr/0031-scene-detail.md). M19 shots: the roof, the elevator and
the floors are boxes without detail, while the frame costs 2.3 ms of 16.6. Everything new
is without bodies; no more than two new light sources (the roof neon).

- [x] The elevator as in the reference: the cab is open at the front, with walls, a light,
      a handrail and a panel; in the shaft guide rails, ropes and a counterweight; on the
      floors portals with open doors
- [x] Roof: equipment (tank, air conditioners, pipes, ladder); a parapet with a drip edge,
      a cornice, ribbed slopes; a mast with a blinking light; a neon sign. Since M21b
      the equipment is pack models, the neon moved to the facade corner
- [x] Floors: door casings, panels and handles, lamps with shades, a carpet
      runner and a tile seam, wall panel joints. The ceiling is untouched — the camera
      does not see it
- [x] The exit floor is a garage without doors or dressing (in the ROM the car is in the
      basement, floor zero has no doors); the car is a sedan with headlights and brake
      lights (since M21 — from the Cars Pack)
- [x] Sparks from a bullet into a lamp, blood from a bullet into an agent and into Otto
      (can be turned off in the settings)
- [x] The round palette is noticeable by eye: rounds 1–4 differ without a caption, shots
      of the rounds side by side
- [x] City: windows in a grid, unlit ones as dark glass
- [x] Tests: details without bodies, roof layout on any seed, the exit floor without doors,
      the source budget

**DoD:** the roof reads as a skyscraper roof, the elevator as an elevator, the floor as an office. ✅

### M21 · Models of Otto, the agents and the car

Decisions — [ADR-0032](adr/0032-actor-models.md). Quaternius Ultimate Modular Men
(CC0), Business Man for Otto and for the agents; the car — Cars Pack (CC0).

- [x] Pipeline: the pack source in `assets/source/`, `build_actors.py` fixes height,
      palette, clips; a fedora and glasses for the agent, a pistol for both
- [x] Mixed animation: pack clips (stance, walk, shot, death) and poses
      in code with knees and elbows (crouch, lying, jump, kick, crushed)
- [x] Squatting crouch and lying down at ROM heights (M18c debt)
- [x] Grounding by the extreme bone vertices — the model is two hundred times heavier
- [x] The car at the exit from the Cars Pack: five models without taxi and police, eight
      paints, a draw by the building number and seed, the first building gets a red
      sports car; length — `Proportions.CAR_LENGTH`
- [x] A pose shot tool `tools/actor_shot.tscn`
- [x] The bullet is a tracer with a tail and a muzzle flash instead of a box (a user
      remark during the milestone)
- [x] No elevator chime on the floors (the user's decision: "as if someone is ringing a
      doorbell")
- [x] Tests of poses by vertices and bounds, clips and bones in the models, the car draw

**DoD:** Otto and the agents are people in suits, not boxes, the stances hold the ROM
bullet heights, the car at the exit is a real car. ✅

### M21b · Floors, roof and elevator from pack models

Decisions — [ADR-0033](adr/0033-dressing-from-packs.md). User remarks:
"nothing but incomprehensible squares on the floors", "everything natural, as in real life".

- [x] Building kind and name — a draw per building: a hotel or an office tower
- [x] A model catalogue `PropCatalog`, pack models in `assets/models/props/`,
      `CREDITS.md` with the author and license of every model and texture
- [x] Floor dressing: on the walls between doors sconces, paintings, clocks, boards,
      room numbers; furniture on the floor on every second free place
- [x] Walls — textures by building kind with the round tone as a multiplier
- [x] The shaft is steel: bolted sheets, concrete, braces, a chrome portal
- [x] By the portal a cab floor indicator with an arrow and ▲▼ buttons (display only)
- [x] A vertical neon sign on the facade corner; the neon leaves the roof
- [x] Roof from models: tank, air conditioners, antennas, a dish, ventilation, panels,
      an exit; the surface with a texture
- [x] Tests: every model has a line in CREDITS, models without bodies that fit in
      depth, layout on any seed, the indicator shows the cab's floor

**DoD:** a floor reads as a hotel or an office without a caption, at the elevator you can
see where the cab is, the roof is a skyscraper roof, the shaft is visible as a column
through the building. ✅

### M22 · Grading and polish

Decisions — [ADR-0030](adr/0030-grading-and-quality.md) and
[ADR-0034](adr/0034-ultra-and-auto-quality.md). The last milestone of the pivot. Part of
it was done back in the M20 branch and is finished here by shots of the detailed scene.

- [x] The tone is night noir: cold shadows, warm lamps, deeper black; game
      signs stay bright. Curves in code since M20, tuning — by shots
- [x] Depth of field — only on the city, the play plane is sharp (in the M20 branch)
- [x] A light vignette under the HUD, no grain
- [x] Banding on gradients is removed by dithering
- [x] Graphics quality: low, medium, high (in the M20 branch)
- [x] The "Ultra" level: volumetric lamp light, SSIL reflected light, high-resolution
      shadows. Godot 4.7 has no real RT — only low-level Vulkan
      RT in `RenderingDevice`; it becomes an option when it lands in the main branch
- [x] Anti-aliasing by level: FXAA, MSAA ×2, MSAA ×2, MSAA ×4. TAA was dropped based on
      shots — it blurred the actors' outline
- [x] The level at first launch — by a frame measurement
- [x] The city is not drawn when the building covers the frame — M19 debt (in the M20 branch)
- [x] A more modern and better-looking HUD (a user remark during the milestone)
- [x] Resolution in the settings (a user question): window mode — windowed, borderless,
      fullscreen at native resolution; the window size from those the monitor
      supports, up to 4K; 3D render scale (FSR) for weak cards at 4K
- [x] A more detailed city behind the building (a user remark): roof silhouettes,
      blinking antenna lights, neon and billboards on distant buildings, the glow of streets
- [x] Richer weather (a user remark): in rain — lightning with a reflection in
      the city's glass and a flash in the corridor; in fog — drifting bands of haze;
      on a clear night — stars and the moon
- [x] Frame budget on the full building, at every quality level
- [x] 2D cleanup: the remains of the sprite palette (ADR-0019, decision 8)
- [x] Tests: a quality level enables what it promises and does not change the rules

**DoD:** the frame can be put next to the reference and the difference discussed in terms
of craft, not capabilities. ✅

### Documentation after the pivot

The user's decision (2026-09-24). After M22 — a check of all documentation: every
`.md` in the project, including the README, sentence by sentence and claim by claim. The
pivot went through milestones M15–M22, and the documents were written during each: what is
outdated, what contradicts the code, what was promised and not done. Branch `docs/sweep`,
the plan is in [STATUS.md](STATUS.md).

- [x] README, CLAUDE.md, CHANGELOG, CREDITS, `conventions.md`, `testing.md`,
      `reference/arcade-rom.md`
- [x] STATUS and EPIC; the debt — cleanup
- [x] ADR 0001–0034: a status line where a decision is superseded or changed,
      with a link to the replacing ADR
- [x] `milestones.md` — milestone by milestone against git
- [x] Checking claims against the code: names of classes, files, numbers, commands
- [x] Debt found by the check — branch `fix/sweep-debt`: licenses in the archive,
      type checking by the engine, the bonus and agent departure by the ROM, the CI matrix

### M22b · Menu

Decisions — [ADR-0035](adr/0035-menu.md). A user remark after M22: the game
looks modern, but the menu does not.

- [x] Behind the main menu — the night city with its own camera, weather by draw; on
      pause and at the end of a session — the game, blurred and darkened
- [x] The title is a neon sign "ELACTION", one letter blinks
- [x] One font — Exo 2: menu, the facade sign, plaques, indicator boards; Pixellari
      leaves the project
- [x] A column on the left, items are HUD-style plates; the plate style is shared with the HUD
- [x] "‹ value ›" switches instead of drop-down lists; high scores as a grid
- [x] Page transitions and selection highlight with animation
- [x] Hover, select and back sounds — by synthesis
- [x] Tests: every page builds and holds gamepad focus, the background
      builds without a building, the project has no references to Pixellari

**DoD:** the menu can be put next to a game frame, and they look like one game. ✅

### M23 · Soundtrack

Decisions — [ADR-0036](adr/0036-sound-from-libraries.md). The user's decision
(2026-09-24): the sound "now seems very primitive" next to the picture. Sounds and
music since M8a were synthesised by code (`tools/render_audio.py`).

- [x] Check against the original, questions, ADR-0036
- [x] Candidates by ear: a page with a player, two to four CC0/CC-BY files per slot
      with the author and license; the user chooses
- [x] Noir jazz tracks: building, alarm, menu, end of session; jingles —
      document, life, bonus, death, end of session
- [x] Effects for the same events as now: steps on carpet and concrete, shot,
      hit, kick, doors, cab, escalator, lamps, deaths, car,
      menu sounds
- [x] Ambience: street and rain — at full strength on the roof, at the exit and in the menu,
      muffled on the floors (the `Ambience` bus, a filter); shaft hum; thunder after
      lightning with a delay by the strike's distance
- [x] Music: the alarm fades in, behind a red door and on pause it is more muffled, a jingle
      ducks the track
- [x] Synthesis removed: `render_audio.py`, `audio_dsp.py`; authors in `CREDITS.md`
      and `assets/audio/credits.json`, a test for the authorship of every file

### M24a · Bugs, rain, fast bullets

Decisions — [ADR-0037](adr/0037-polish-bugs-and-combat.md). User remarks
after M23 (2026-09-25).

- [x] A cab that has arrived at a floor does not get stuck together with Otto
- [x] The top and bottom of the shaft do not flicker
- [x] Rain from scratch: drops die on the roof, splashes, puddles, a wet roof, layers in the city
- [x] The background does not crawl in bands when the camera moves
- [x] Bullets three times faster for both sides; the agent's wind-up and aiming beam; a new look
- [x] Agent corpses stay until the end of the building
- [x] A fall of more than one floor kills everywhere
- [x] 5–10 documents in a building by draw
- [x] The controls screen from pause; the building number in the HUD

### M24b · Building: helicopter, doors, garage, exit

Decisions — [ADR-0038](adr/0038-building-start-and-end.md). Merged into `main` (PR #47).

- [x] Check against the ROM, questions, ADR-0038
- [x] A helicopter in every building: flies in, lowers a rope, Otto slides down, the
      helicopter leaves; skippable with a key
- [x] Red door: closes behind Otto, 70 ROM ticks inside (4.73 s), no way out
      earlier, the document on exit; muffled through the door; agents sometimes wait at the door
- [x] Basement: one shaft down, no escalators; the garage — columns, a ceiling with
      pipes and lamps, other cars, a gate and a ramp; Otto's car at the gate on the left
- [x] Exit: walk up — get in — headlights — drive out through the gate; the bonus on top, a fade
- [x] Without all documents the elevator does not go to the basement

### M24c · Animation and keys

Decisions — [ADR-0039](adr/0039-animation-and-controls.md). Merged into `main` (PR #48).

- [x] Check, questions, ADR-0039
- [x] UAL clips on the pack skeleton: retargeting in `build_actors.py`, a jump in three
      phases, landing, crouch, stance, walk, shot, death
- [x] Transitions between poses by time, not by a single exponential; turning with the body
- [x] Short turn and landing pauses in the rules; a combat test at the threshold
- [x] Agents on the same clips
- [x] Rebinding: one key and one button per action, a swap when
      taken, reset, the scheme in `settings.cfg`
- [x] Shader warm-up: Shader Baker in the export, the first display of rare effects
      (flash, smoke, sparks, blood, lightning) invisibly on entering the building

### M24d · Takedowns instead of the kick

Decisions — [ADR-0040](adr/0040-takedowns.md). Merged into `main` (PR #49).

- [x] Research: the original, Elevator Action Returns, takedowns in other games,
      free animations; questions, ADR-0040
- [x] A jump without a kick: the UAL flight clip, the kick zone and kick points are gone
- [x] A point-blank shot is a takedown; from behind — a chokehold or a neck snap (300),
      from the front — a series of punches or a pistol-whip (200), +100 in the dark and on 11–15
- [x] Jumping on from above — automatic, on landing on an agent (300)
- [x] World slow-down for the duration of the scene, Otto is vulnerable
- [x] UAL 2 clips, a paired-scene director, rules with tests, the bot does takedowns

### M24e · Demo mode

Decisions — [ADR-0041](adr/0041-demo-mode.md). Merged into `main` (PR #50).

- [x] Check against the ROM, questions, ADR-0041
- [x] The bot moves from `tests/` to `src/`
- [x] 45 s of inactivity in the main menu — demo; any press — back to the menu
- [x] About 30 s, three points in rotation: roof, middle, bottom; death ends the demo
- [x] Sound as in the game, no caption; high scores and the quality measurement are untouched

### M24f · Bugs, settings, Game Over

Decisions — [ADR-0042](adr/0042-bugs-and-settings.md). User remarks
after M24e (2026-09-28).

- [x] Check, questions, ADR-0042 and ADR-0043
- [x] A corpse is a physics body: it rides on the cab floor, falls into the shaft, does not
      pass through slabs; the cab obeys with corpses inside
- [x] Jumping on is simpler: landing overlapping an agent is a takedown
- [x] FPS at the bottom on "Ultra": a measurement by floors, cheaper shadows
- [x] The fullscreen resolution sets the 3D resolution; the cursor is hidden in game
- [x] The last death: slow-down, zoom-in, "GAME OVER", the menu not right away
- [x] The outline is removed; the red door gets its own light
- [x] A "Credits" page in the menu

### M24g · Animation and look

Decisions — [ADR-0043](adr/0043-animation-and-look.md).

- [x] Rope: a pose in code, landing by a clip
- [x] Escalator: Otto walks on the steps; the model from Blender
- [x] Red door: entering into the depth and coming out
- [x] Headlights light the way until the fade
- [x] City windows turn on and off
- [x] Dismemberment: a cab passing over a body with its floor cuts it at the cab's
      edge; the part under the floor disappears with splashes, a stain remains. Corpses,
      agents and Otto; together with the "Blood" flag (decisions 7–9)
- [x] Corpses pile onto each other with physics, with no height limit (decision 10)

### M24h · Street with traffic

The user's request during M24g: cars drive along the street at the exit, and Otto in
his car merges into the traffic and drives off. The cars are real models, not boxes.
Plus the user's remarks after M24g (2026-09-29) that concern
mechanics and flow; the look — in M24i. Decisions — [ADR-0044](adr/0044-street-and-cab.md).

- [x] A flow of cars along the exit street in two lanes: models, headlights and brake lights,
      speed and gaps by draw
- [x] Otto's car waits for a gap, merges into the traffic and drives off with it
- [x] **The escalator from scratch — into the depth.** The flight behind the play plane, at the
      back wall, gentle, about 30°; the floor slab in the play plane is solid, you walk past
      the escalator on the floor; onto the landing — a step into the depth. The model is
      redrawn: a thicker flight, more frequent steps, the handrails visible. Check on
      shots and with a test on all seeds
- [x] **FPS on the lower floors.** It drops — a big investigation is needed: measurement
      by floors (`light_bench --whole`), what grows towards the bottom of the building
      (corpses and ragdoll, lighting, shadows, dressing, city), then a fix. If it is corpses —
      a settled body freezes into a static model but does not disappear
- [x] **In a moving cab you can walk left and right** — as in the ROM. Stepping out and
      boarding on the move while the floor difference is less than 0.4 of a floor
- [x] **Accidentally touching a cab does not kill.** Only a cab under which Otto stands
      entirely crushes him — as in the ROM; one grazed by the edge is pushed out.
      Points for an agent — only for the cab Otto is riding in
- [x] **Dismemberment: the texture does not ride with the cab.** When the cab cuts a body,
      the model's texture stretches after the cab. The cut must not
      touch the texture
- [x] **Regular doors cannot be entered — only red ones,** until the document is taken.
      Checked against the ROM (@3BDA): the original does not let you into a regular door.
      The bot that hid in doors and the combat tests change

### M24i · Takedowns, helicopter, dressing

The second half of the M24g remarks — the look. Decisions —
[ADR-0045](adr/0045-takedowns-helicopter-dressing.md).

- [x] **More cinematic takedowns.** The M24d scenes look too simple:
      direction is needed. The camera stays at the side, but the zoom-in is livelier — a
      jolt and a roll on the hit; uneven slow-down with a freeze-frame on the hit; a flash
      sculpts the faces, the background darkens, the music drops out; the agent acts it
      out and falls as a ragdoll. Check by the shots of `tools/takedown_shot.tscn`. Done
      ([ADR-0050](adr/0050-takedown-direction.md))
- [x] **A more detailed helicopter.** In the M24g shots both the model and the lighting are
      poor. The model is the low-poly kazuma (CC0, 78 KB): a flat silhouette of a dozen
      faces, the main rotor is one thin line, skids made of sticks, no doors, no
      rivets, no tail rotor that would read. Lighting: the body is
      dark and holds on one rim, no lights on the sides, the belly and the cockpit
      are almost unlit — the helicopter reads as a silhouette. A more detailed model
      is needed — a free CC0/CC-BY one with details added on top in Blender, and if there
      is no worthy one — our own; a rotor with blur when spinning, and lighting that
      sculpts volume: city lights on the metal, cockpit illumination, a searchlight below.
      Done with our own model by a script ([ADR-0049](adr/0049-own-helicopter.md))
- [x] **Richer hotel and office interiors.** In the M24g shots the dressing is poor: on a
      floor doors, wallpaper, a painting and a side table with a lamp. More detail is
      needed, and all of it as models, not flat textures and boxes: hall and
      corridor furniture, plants, light fixtures, rugs, signs, small things by the walls.
      Each item has its own light and shadow within the frame budget; it does not get in
      the way of movement and combat; it varies by floor and building by draw. The office
      has its own set: a water cooler, a copier, shelving, armchairs. Authors — in
      `CREDITS.md`. Done, and the corridors are set apart by kind: doors, light fixtures,
      floor, sconces, plaques ([ADR-0048](adr/0048-hotel-and-office-apart.md))
- [x] **Getting into the car from scratch** (user remarks, 2026-09-30).
      Currently a spot glows at the waist of Otto as he gets in: the interior dome light
      stands outside the body, 30 cm towards the camera, at a height of one metre
      (`exit_car.gd`, `Dome`), and burns out the white suit. The door does not read as
      open: a separate panel swings out, while the model's body stays solid with a
      painted door, and no interior is visible; the inner side of the panel is a black
      spot. Needed: the dome light under the roof inside the cabin (the user's decision);
      the body cut along the door opening during boarding; in the opening — an interior
      from models: seats, dashboard, steering wheel, trim, headliner; at the door — the
      inner trim. Done for all five cars of the draw, the interior by car type
      ([ADR-0046](adr/0046-car-cabin-indicator-traffic.md), decision 1)
- [x] **The right turn signal,** while Otto's car pulls up to the edge of the roadway,
      waits for a gap and pulls out into the lane (the user's request, 2026-09-30;
      ADR-0046, decision 2)
- [x] **Traffic situation by draw:** free, normal or dense; if there is a
      gap the car pulls out on the move, if not it waits (the user's request,
      2026-09-30; ADR-0046, decision 3)
- [x] **Behind an open door — a room, not darkness** (the user's request,
      2026-09-30): both behind the red one that Otto enters and behind the one an agent
      comes out of. While the leaf is open, the interior is visible in the opening: a hotel
      room or an office — by building kind, by a draw per door, in detail and
      as models: a bed, a nightstand, a lamp, a window with the city; a desk, a cabinet, an
      armchair. The room's own light, within the frame budget. Done
      ([ADR-0047](adr/0047-room-behind-the-door.md))

### M24j · Time of day and the new city

The user's requests (2026-09-30): add morning, day and evening to night, and snow to clear
weather, fog and rain. Sixteen round combinations by draw. Check and questions
— [ADR-0051](adr/0051-time-of-day.md). After the first daytime shots it was decided to
build the city behind the building from scratch (decisions 10–13), and the milestone split
into four.

- [x] Time of day by draw from the building seed, night 40 %, frozen within the building
- [x] Darkness and dark floors — only at night; thunderstorms — in the evening and at night
- [x] The building's air and the frame tone by time of day; the sun only outside
- [x] Shots of all combinations — `tools/m24j_shot.tscn`
- [x] The city from pack models with real materials, one for all times:
      Quaternius Downtown facades baked into an atlas (`tools/build_city.py`)
- [x] The sky as HDRI panoramas by time and weather, chosen by the user
      (`tools/build_sky.py`, [CitySky])
- [x] The new city's night is a state of the same city; the menu is night
- [ ] Shots and tests for all twelve combinations

### M24k · Time of day for everything else and the cinematic opening

- [x] The exit street and the ramp: lights as in real life, headlights in daytime only in
      bad weather; buildings with the pack facade at all times of day (the user's request)
- [x] The window of the room behind the door, the building sign, the helicopter, the lamp
      above the roof
- [x] Own music for morning, day and evening — tracks chosen by the user; street
      ambience by time
- [x] **Cinematic opening** (the user's request, 2026-10-01): the helicopter
      flies up, its door opens, Otto climbs out and descends on the rope,
      the helicopter flies away, the door closes by itself, the rope is retracted.
      Settled by questions on 2026-10-01:
      - a sliding door: while hovering it slides back with a clang, the cabin lights up
        in the opening; on departure it slides shut again;
      - the rope: after the door opens the coil is thrown out, it unwinds down to the roof,
        swaying in the rotor downwash; on departure the winch reels it into the
        cabin, then the door closes;
      - Otto looks out of the opening, sits on the sill, grabs the rope,
        slides off and quickly rides down on his hands, braking near the roof — and
        lands with a crouch;
      - the camera — a zoom-in without a change of angle, as with takedowns: closer on the
        door and the exit, it follows Otto down the rope, pulls back to the gameplay frame;
      - length: in the first building of a session the full one, 10–12 s; after that a short
        one, about 6 s: the helicopter is already hovering with the door open; skipping is
        as now;
      - behind the glazing — a pilot (a Quaternius pack model), he nods on departure;
      - departure: nose down, a bank, up and sideways accelerating past the frame edge, the
        rotor downwash drives dust across the roof, and since ADR-0053 rain too
- [x] Gaps in the sound found by an audit (the user's request, 2026-10-01):
      some twenty sounds chosen by the user ([ADR-0052](adr/0052-day-for-the-rest-and-arrival.md))
- [x] Shots and tests

### Open questions and debt after M24k

[ADR-0053](adr/0053-open-questions-and-debt.md). Check against the ROM, then questions
to the user in two blocks (2026-10-02).

- [x] The player's cab does not stop between floors — it travels to a floor, as in the ROM
- [x] Returning after death by the ROM, 1.5 s invulnerability — ours
- [x] Release no closer than 1.2 m to Otto (in the ROM right next to him); a crowd on a
      floor goes into the doors
- [x] The ROM's twentieth floor — not excluded: our door search does not lead behind a wall
- [x] The bot shoots down lamps from a cab; the shadow distance — by measurement
- [x] Debt: rotor downwash and rain, facade atlas margins, weather set by hand in
      the building rules, label mipmaps in the scene, indicator arrows as geometry
- [x] Dropped by decision: lamp swinging, darkness weakening with skill
- [x] Code review, `check.ps1`, README

### M24l · Snow

[ADR-0054](adr/0054-snow.md). Check: the arcade has no weather; questions asked
on 2026-10-02.

- [x] A fourth weather, a 25 % draw
- [x] Falling snow drifting with the wind, cover on the roof, cornices, equipment and street
      from the first frame, footprints of Otto and the agents, car ruts; its own sound and
      wind, the city in a snowfall
- [x] Flakes in clumps, precipitation dies on people, cars, the helicopter and the street,
      the rotor downwash scatters rain and snow (the user's requests, 2026-10-02)
- [x] Pedestrians at the exit in any weather: varied, walking, dressed for the weather,
      under umbrellas
- [x] A slippery roof in snow — measured by the bot on snowy seeds
- [x] Code review, `check.ps1`
- [ ] Shots and tests for the sixteen combinations

### M24m · The residential complex and its own agents for each building kind

[ADR-0055](adr/0055-residential.md). The user's request (2026-09-30). Check:
the arcade has one building and one kind of agent; the reference is Elevator Action
Returns, where each place has its own enemies. Questions asked on 2026-10-02.

- [x] Building kind — a three-way `Kind` instead of `is_hotel()`, an equal draw, the first is
      the EMPIRE hotel
- [x] An American 1980s apartment building: names and neon of its own colour
- [x] Corridor: apartment doors with a peephole, a number and a mat; linoleum or
      checkerboard, two-tone walls, ceiling lights; wear and graffiti, a blinking
      lamp; mailboxes, a stroller, radiators, trash, a fire extinguisher
- [x] Missing furniture from CC0 packs: a kitchen, a TV, a dining table,
      lobby dressing
- [x] An apartment behind a red door by draw: a kitchen, a living room with a flickering
      TV, a bedroom
- [x] Agents by building kind — a wardrobe in the game: hotel — a fedora, office — no
      hat, with a tie, residential — a raincoat and a cap or a hood; the mechanics are shared
- [x] Each of the three kinds has its own corridor ambience, sounds from behind the doors of
      the residential building, steps on linoleum — chosen by the user via the listening page
- [x] Shots and tests for all three kinds
- [x] Code review, `check.ps1`, README

### M24n · Building kind character

[ADR-0056](adr/0056-building-character.md). The user's request (2026-10-02):
"set the design of the three levels as far apart as possible". Check: in the arcade rounds
differ by colour, in Elevator Action Returns missions differ by colour, lighting and detail
density. The mechanics — by the ROM, unchanged. Questions — 2026-10-02.

- [x] Each kind has its own air within the noir: the warm amber of the hotel, the cold
      white-blue office, the dim sodium with green of the residential building; lamp colour
      by kind; the time of day on top
- [x] The round palette — each kind has its own set; darkness is equally dark,
      the gap to the light — by a test for every kind × round pair
- [x] Office: glass partitions, with an open space behind them on visible floors;
      the office door opens into it
- [x] Hotel: arched niches with lighting, framed mirrors, tall panels with
      mouldings
- [x] Residential building: risers, electrical panels and cables, windows onto the fire
      escape, bare brick, EXIT doors and a garbage chute hatch
- [x] Light fixtures by kind within the target's footprint: a chandelier, a box under a
      suspended ceiling, a bulb on a wire
- [x] Shots of the three kinds side by side, tests on any building
- [x] Code review, `check.ps1`, README

### M24o · Special floors, cab and music by kind

[ADR-0057](adr/0057-floors-cab-music-by-kind.md). Check: the arcade has one building,
floors differ only in their layout — the lower 1–7 have almost no doors, the dark
11–15 have no lamps; in Elevator Action Returns each mission has its own place and its own
music, the theme changes along the way. Questions — 2026-10-03.

- [x] Floor role by kind and ROM floor: public halls on 1–7, technical ones
      on 11–15, each floor of a band is different
- [x] A hall extending into the depth on a special floor: columns, glass or chain-link
      instead of the back wall; the rooms behind the doors stay in place
- [x] Halls: lobbies of three kinds, a restaurant and a canteen, a ballroom, a pool, a bar,
      a conference room, meeting rooms, a gym, a common room, storage cages,
      a laundry, a boiler room, ventilation, a server room, an archive, a kitchen, a
      warehouse, a workshop
- [x] Small touches on special floors: ambience by hall, steam, ripples, indicators, bottles
- [x] Furniture from the Kenney Furniture Kit with an entry in CREDITS
- [x] A cab and shaft of each kind: brass and a dial, stainless steel and digits,
      a freight cab with a gate following the ROM step-out window and floor lamps
- [x] Music: kind × time of day, a theme change from the middle of the building, its own alarm
- [x] Shots of the three kinds, tests on any building, the frame budget
- [x] Code review, `check.ps1`, README

### M24p · The building exterior by kind

[ADR-0058](adr/0058-exterior-by-kind.md). Split off from M24o (ADR-0057,
decision 1). Check: in the arcade the buildings are identical outside, in Returns each
mission has its own place and its own finale. Questions — 2026-10-03.

- [x] A tall crown by kind behind the play plane: art deco with a spire, a glass
      top with a mast, a water tank on supports; the helicopter flies around it, the intro
      shot redone
- [x] Parapet and cornice by kind
- [x] The podium setback ledge: a terrace, skylights, roofing felt with laundry
- [x] Tower end walls: rustication and flags, glass fins, a fire escape
- [x] Garage by kind: VALET and a stand, a barrier and Reserved, graffiti and a dumpster
- [x] The facade at the exit street: a canopy with a carpet, a glass lobby, a stoop
- [x] The barrier rises in front of Otto's car, a valet at the hotel exit
- [x] The car at the exit, in the garage and on the street — a draw by kind
- [x] Shots of the three kinds, tests on any building, the frame budget
- [x] Code review, `check.ps1`, README

### M24q · Animation, frame by frame

Requested by the user on 2026-10-03, after the whole-game review — a big one. Every
animation in the game is reviewed frame by frame, and what looks unnatural or skips a step
is finished. Look only: the rules of who can hit whom and when belong to M24r. Before the
code: a check against the original and questions, as for any milestone.

- [ ] Frame-by-frame pass over all animations: a series of frames for each one (tools in
      `tools/*_shot.gd`), a list of what is missing or looks wrong
- [ ] Otto leaving the helicopter: today it looks unnatural
- [ ] Agents coming out of doors: the door opens and the agent just appears — he should
      open it and step out
- [ ] Otto entering a door: he vanishes instead of going in and closing the door behind him
- [ ] Otto coming out of a door: the door opens and he is already there — he should open
      it himself and step out
- [ ] Takedowns: a careful frame-by-frame review of every scene, the missing frames added
- [ ] Deaths in unnatural poses: find out whether it is the death clip or the ragdoll
      physics (joint limits, the hand-over from clip to ragdoll), and fix whichever it is
- [ ] Shots: check that the bullet and the flash leave from the pistol's muzzle, for Otto
      and agents, in every stance (standing, crouching, kneeling, prone, on the move)
- [ ] Buildings flicker behind the main menu at night in fog — find the cause (fog against
      the city SubViewport, depth precision, LOD) and fix
- [ ] Shots of every animation, tests, code review, `check.ps1`, README

### M24r · Agent mechanics

Requested by the user on 2026-10-03. The agents' life in the building is reviewed as a
whole — release, pacing, who keeps a slot, when an agent can be hit — and everything tied
to it, not only the symptoms below. Today's rules live in `AgentSpawn`, `AgentCrowd`,
`AgentLifts`, `DoorWatch`, `GreyboxLevel._tend_agents`, `EnemyBrain` and ADR-0020,
ADR-0025, ADR-0027, ADR-0053, ADR-0059 (the calm after the return) and ADR-0060
(decision 6). Before the code: a check against the ROM for each rule, then questions.

- [ ] An agent is hittable as soon as he has stepped out into Otto's plane: today he is
      shielded for the whole 0.6 s `EMERGING` phase (ADR-0020), and bullets pass through an
      agent already standing on the floor. How long does the original shield an agent in a
      doorway? Tied to the door exit animation of M24q
- [ ] Agent release paced: standing on the top floor after the roof, agents come out one
      after another without a break — the stream needs a rhythm
- [ ] No empty building below: once the agent slots are filled up top and those agents stay
      alive, going down meets nobody — the whole building can be walked without agents.
      Agents left behind must give their slots to the floors where Otto is
- [ ] Review of the related rules: the slot count and the late agents, release distance and
      the calm after the return, agents following Otto by cab, the crowd leaving through
      doors, the keep margin, difficulty over time — each checked against the ROM and against
      the two symptoms above
- [ ] Tests on any building: agents keep meeting Otto all the way down at a steady rhythm;
      the bot runs measured again; code review, `check.ps1`, README

### M24s · Settings by the monitor

Requested by the user on 2026-10-03.

- [ ] The frame limit list shows only what the monitor supports: limits up to its refresh
      rate (`DisplayServer.screen_get_refresh_rate`), not a fixed 60–240 list. Today
      `DisplayModes.FRAME_LIMITS` is fixed, because Godot 4.7 cannot enumerate screen modes
- [ ] The same for resolutions (today they are already cut to what fits on the screen)
- [ ] Auto-detection on first launch: the monitor's own resolution and refresh rate as the
      defaults, the way quality is measured today; a change of monitor is noticed
- [ ] Tests, code review, `check.ps1`, README

### M25 · Online leaderboard (optional)

The only part where a backend and docker compose will appear
([ADR-0003](adr/0003-no-docker.md); there it is still numbered M10 — the number changed
every time work on the visuals and on remarks turned up).

- [ ] API, DB, docker compose
- [ ] An in-game client, minimal protection against score cheating
- [ ] Deployment

## 6. Cross-cutting requirements

| Requirement | How we check |
|---|---|
| Typed GDScript everywhere | `gdlint` and review |
| Uniform formatting | `gdformat --check` in pre-commit and CI |
| Logic is covered by tests | GUT, run in CI; locally — in shards (`tools/run_tests.py`) |
| Any generated building works | Tests on all seeds, the bot clears the building — [`testing.md`](testing.md) |
| Frame within the 16.6 ms budget | `tools/light_bench.gd` in every visual milestone; across the whole building — `--whole`, since M22 |
| No import or parse errors | `tools/godot_check.py` on pre-push and in CI |
| The gamepad works on a par with the keyboard | A manual check at the end of each milestone |
| Russian and English interface | Test: every string exists in both languages (since M8b) |
| Screenshots and comparison with the original | `tools/capture.py <milestone>`, `tools/compare_original.py <milestone>` |
| Code review of the changes after each milestone | `/code-review xhigh --fix` before opening the PR |

### Milestone screenshots

After each milestone we take shots for analysis and comparison with previous milestones and
with the original:

```powershell
python tools/capture.py M20
python tools/compare_original.py M20
```

The game starts with the argument `--capture=<milestone>`, the `Screenshotter` autoload walks
the milestone's route, saves one shot per step and exits. Shots go into
`screens/<milestone>/`, the comparison — into `screens/<milestone>/compare_original.jpg`. The
`screens/` folder is not versioned. A shot is taken manually with the **F12** key.

### Code review

Before opening a milestone PR, the changes go through a high-thoroughness code review
with fixes applied automatically:

```
/code-review xhigh --fix
```

After the fixes, `tools/check.ps1` and the tests are run again. The review result is briefly
recorded in the PR description.

## 7. Workflow

- **Starting a milestone:** check the mechanics against the original, clarifying questions,
  the answers go into an ADR, then update EPIC and STATUS. Only then code.
- **Branches:** `feat/m20-detail`, `fix/elevator-crush`, `chore/ci-cache`. No direct pushes to `main`.
- **Commits:** Conventional Commits — `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- **Before a commit:** hooks run by themselves. Manually — `tools/check.ps1`.
- **Before a push:** the engine check and the tests run in addition.
- **At the end of a milestone:** screenshots and comparison with the original, `/code-review xhigh --fix`,
  re-running the checks, tests strengthened at the building level, README brought up to date.
- **PR:** one PR per milestone or per large task within a milestone, merge only with green CI.
- **Decisions:** everything that affects the architecture is recorded as an ADR in `docs/adr/`.

## 8. Open questions

There are no open questions. The last ones — 4, 8 and 9: the player's cab, returning to the
game, release at a door, the shadow distance and the twentieth floor — were closed by the
check against the ROM and a bot measurement ([ADR-0053](adr/0053-open-questions-and-debt.md)).

Closed earlier: 1 — the visual target ([ADR-0019](adr/0019-3d-pivot.md)); 2 —
the art pipeline (models from Blender, [ADR-0022](adr/0022-actors-rig.md)); 3 — the platform,
only GitHub Releases ([ADR-0013](adr/0013-release-and-versioning.md)); 6 — checking
the mechanics and combat numbers against the ROM ([ADR-0027](adr/0027-rom-combat.md),
[ADR-0028](adr/0028-building-by-the-map.md)); 5 — animation frames (dropped together
with the sprites); 7 — the cost of crouching, the low shot by the ROM
([ADR-0027](adr/0027-rom-combat.md), decision 3).
