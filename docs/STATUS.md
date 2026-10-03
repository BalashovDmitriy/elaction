# Development status

Updated in every commit that touches `src/`, `tests/` or `project.godot`.
The `status-updated` hook checks this.

| | |
|---|---|
| **Updated** | 2026-10-03 |
| **Current milestone** | none — next in the plan is M24q, animation frame by frame; then M24r, agent mechanics, difficulty and the alarm; M24s, settings by the monitor; then M25 (optional) |
| **Branch** | `fix/signal-flashes` — the plan of M24q–M24s, the death horn and the turn signal flashes removed |
| **State** | The whole-game review sweep is merged (PR #69, [ADR-0060](adr/0060-review-sweep.md)). The comic horn over Otto's death and the turn signal's amber flashes on the asphalt are removed at the user's request. Awaiting PR |
| **Rollback point** | `main` holds the 3D build since M19; 2D remains in history, `d5774df` |

## Where we are now

**M0–M6** are done: foundation, movement, elevators and escalators, doors and documents,
combat and lamps, generated building, game loop, lighting and atmosphere. All of it is in `main`.

A full session is playable: Otto descends from the roof of a thirty-floor building, collects
documents from red doors — five to ten of them — fights off agents, leaves through the exit
and enters the next building, where the agents are angrier. Dawdle, and the siren goes off.
A floor zone is lit while its lamp above burns; a lamp shot down puts it out for good.

**M7 is done in full**: the game is built from assets. The environment is drawn by a Python
generator, the actors and the car are rendered from a low-poly model in Blender; everything
has a normal map and specular, and the light from M6 falls on the relief. No coloured boxes
are left in the frame.

**M8a** is done: the game has sound — footsteps, shots, elevator, doors, lamps, deaths, the
building theme and the alarm motif.

**M8b** is done: the game starts from the menu and returns to it. Menu, HUD, settings,
high scores and two languages are in place.

**M9** is done: Windows and Linux builds, versions, tags and the release workflow.
No tag has been set yet.

**M10** is done: the roof as a separate level, a stepped silhouette, agent release
near the player.

**M11** is done: combat is balanced. Difficulty grows along the original's axes, agents
dodge bullets, no more than eight live agents in a building, combat numbers are in the
building rules. The bot clears a building with agents on three lives, and a test checks this.

**M12** is done: visuals after the ZX Spectrum version — round palette, a visible
shaft, a machine room on the roof and the descent by rope.

**M13** is done: native FullHD and quality textures — the world is three times larger,
assets are redrawn with detail, proportions are re-marked, the shaft limit is visible in the frame.

M12 and M13 are merged into `main` (PR #24).

**M14** is done — the last 2D milestone: the agent's door really opens.
The door leaf moves in its own class, a 0.7 s telegraph, an agent in the doorway is not a
target. Merged into `main` (PR #25).

**M15** is done — the first pivot milestone: the node layer moved to 3D, a building of grey
boxes, the bot clears thirty floors with agents. Merged into `main` (PR #26);
the 2D build remains in history — the M14 merge, `d5774df`.

**M16** is done — actors on a skeleton: a rig from Blender, animation in code, an outline
instead of a glow. Merged into `main` (PR #27).

**M17** is done — light: camera tilt, lamp zones, air and edges, readability indicator
lights. A new mechanic — darkness decides whether agents see Otto. Merged
into `main` (PR #28).

**M18a** is done — building layout: a fine grid of slots, a silhouette by threshold,
intersecting shafts, escalators in a band and interior walls. A path through the building is
found by the bot, not guaranteed by the generator. Merged into `main` (PR #30).

**M18b** is done — look and movement: the escalator as a structure, light in the shaft, a
two-floor cab and agents who ride cabs for the first time. Merged into `main` (PR #31).

**M18c** is done — proportions after the original: everything standing on the floor in
fractions of the 1983 floor, sizes in one table, floor numbers. Merged into `main` (PR #32).

**M18d** is done — combat by the ROM rules: an arcade disassembly turned up, and
difficulty, release, shooting, dodging and speeds are taken from its code. Merged
into `main` (PR #33).

**M18e** is done — the building by the original's map: doors, red doors and dark
floors by the ROM tables, the session salt. Merged into `main` (PR #35).

**M19** is done — filling and background: a night city in its own
perspective view, round weather, floor dressing, the roof after the original.
Merged into `main` (PR #36).

**M20** is done — scene detail: elevator, roof, floors, city, blood and sparks.
Merged into `main` (PR #37).

**M21** is done — people and cars from Quaternius packs, a tracer bullet. Merged into
`main` (PR #38).

**M21b** is done — the world from pack models: a hotel or an office with a neon sign,
floors with furniture and textures, a steel shaft with a cab indicator board, a roof with
equipment. Merged into `main` (PR #39).

**M22** is done — grading and polish, the last pivot milestone: the "Ultra" level
and level selection by measurement, a noir tone, a neon-noir HUD, window modes up to 4K,
a more detailed city and weather. Merged into `main` (PR #40).

Done: the **documentation audit** — every `.md` against the code and history — and
**the debt it found**. Then **M22b** — menus on a live scene: the night city
behind the main menu, the blurred game behind the pause, a neon title sign, a single font,
Exo 2, across the whole game. All three are merged into `main` in one PR #43.

**M23** is done — sound from free libraries: Kevin MacLeod noir jazz, effects
and ambience from Kenney and freesound, a mix by location. Merged into `main` (PR #44).

**M24a** is done — bugs, rain and fast bullets: boarding the cab level with the floor,
rain hitting the roof, an even ambience, bullets three times faster with an aiming beam,
corpses until the end of the building, falling more than a floor, 5–10 documents. Merged
into `main` (PR #45), the FPS counter test for CI was fixed right after (PR #46).

**M24b** is done — the start and end of a building: a helicopter drops Otto onto the roof,
the red door by ROM, a basement garage with one shaft down, the exit through a car onto a
night street. Merged into `main` (PR #47).

**M24c** is done — animation and keys: movement with Universal Animation
Library clips, a jump in phases, timed transitions, turn and landing pauses,
key rebinding, shader warm-up. Merged into `main` (PR #48).

**M24d** is done — takedowns instead of the jump kick: a jump without a kick, a point-blank
shot — a random scene, a jump onto an agent from above, the world slows down, the camera
pushes in. Merged into `main` (PR #49).

**M24e** is done — demo mode: 45 s of inactivity in the main menu, the bot plays,
three locations in rotation, any key press — back to the menu. Merged into `main` (PR #50).

**M24f** is done — bugs, settings, Game Over: the corpse as a physics body, cheaper lamp
shadows, 3D resolution in fullscreen, the last death in slow motion, a camera light
instead of the outline, a sconce at the red door, the "Credits" page. Merged into
`main` (PR #51, #52).

**M24g** is done — animation and look: corpses are a ragdoll on Jolt and pile on top of
each other, the cab cuts those under it, Otto hangs on the rope, walks on the
escalator and enters the red door into the depth, the bullet comes from the muzzle, the
escalator as a model at the floor's edge, headlights light the way, city windows go out and
light up, a run log. Merged into `main` (PR #53).

**M24h** is done — street and cab: traffic at the exit, and Otto's car
merges into a gap; the escalator in the depth, the floor in front of it whole; in a moving
cab one walks and steps out on the move; crush and doors by ROM; at the bottom of the
building the frame is back within the budget. Merged into `main` (PR #56).

**M24i** is done — boarding the car redone, a turn signal, traffic situation
at the exit, a room behind the door, different hotel and office corridors, our own
helicopter and takedown direction. Merged into `main` (PR #57).

**M24j** is done — time of day and a new city: morning, day and evening towards night,
drawn per building; darkness only at night; the city from pack models, the sky from
HDRI panoramas. Merged into `main` (PR #58).

**M24k** is done — time of day for the rest and a cinematic start:
the exit street, the room behind the door, the sign, music and ambience by time of day;
a helicopter with a door, a coil of rope and a pilot; two dozen sounds that were
missing. Merged into `main` (PR #59).

Done: **closing open questions and debt** (ADR-0053): cab,
respawn, release and crowd by ROM, the bot shoots down lamps. Merged into `main` (PR #60).

**M24l** is done — snow: a fourth weather, snow cover and footprints, pedestrians at the
exit, a slippery roof. Merged into `main` (PR #62).

**M24m** is done — the residential building as the third kind and agents of their own for
each kind. Merged into `main` (PR #63).

**M24n** is done — the character of the building kind: its own air and light per kind,
round palettes by kind, the back wall by layout, light fixtures. Merged into `main`
(PR #64).

**M24o** is done — special floors as halls, a cab and shaft of the kind's own style, music
by kind, chosen by ear. Merged into `main` (PR #65).

**M24p** is done — the building exterior by kind: a crown above the roof, end walls and the
setback ledge, the garage, the street entrance and the car by kind. Merged into `main` (PR #66).

## What works

- `OttoStateMachine` — states idle / walk / crouch / jump / fall / ride / indoors /
  dead. Moved out of the node into its own class: it takes an input snapshot and facts about
  the body and returns a state. So it is tested without a scene or physics — 14 tests.
- `Otto` (`CharacterBody3D`) — gravity, discrete arcade movement, a collision shape change
  when crouching; Z is locked. The figure is a pack model on a skeleton, the crouch
  fits under an agent's bullet, and this is checked by vertices. The camera is `SideCamera`
  on top of the `CameraBounds` rule: building bounds and smoothing; since M17 it is tilted
  ten degrees from above, and the floor is visible as a strip (ADR-0023). The frame holds
  3.67 floors, as in the original (ADR-0026, decision 4).
- `GreyboxLevel` (`Node3D`) — the building is assembled at runtime from `BuildingPlan` by
  builders: the shell (`BuildingShell`), the edges (`BuildingRibs`), the shafts
  (`BuildingShafts`), the surroundings (`BuildingScenery`). The rules plane is translated
  into the scene through `WorldSpace`. Above the building is the roof as a separate level
  (`BuildingRules.ROOF`); Otto slides down to it by rope, and the descent starts from it.
- Input: keyboard (arrows/WASD, space/Z, X/J, Esc) and gamepad (D-pad, stick,
  A, X, Start). Keys are read by `physical_keycode` — works on any keyboard layout.
- `ElevatorMotion` — cab movement in its own class: control from inside, autonomous
  travel from floor to floor with a pause, shaft bounds, alignment with the floor. 19 tests
  without a scene or physics.
- `ElevatorCar` — a cab on `AnimatableBody3D` with `sync_to_physics`. It carries whoever
  stands on its roof and crushes whoever ends up under its floor.
- `Escalator` — landings at the top and bottom, boarding by a key press, a ride without
  control.
- `ShaftHazards` — the rules of death in the shaft separate from physics, with tests.
- Context input: in a cab "up/down" drive it, crouch is off; left-right
  Otto walks in it, also on the move, and steps out onto a floor while it is close (ADR-0044).
- `Door` and `DoorVisit` — the red door closes behind Otto, inside exactly 70 ROM ticks
  (4.73 s), no leaving earlier; the 500-point document is given on the way out. Through the
  door the corridor sounds muffled, agents sometimes wait at the door (`DoorWatch`). Without
  all documents the shaft to the basement is closed by a slab (`BasementLock`).
- Arrival — a helicopter in every building (`Helicopter`, `RoofArrival`); exit — Otto
  gets into the car at the garage gate himself (`Garage`, `ExitBoarding`), the bonus over
  the scene, the building change under a fade (`FadeCurtain`).
- `Gun` and `Bullet` — a pistol with three bullets on screen, a jump kick. One bullet
  class for both shooters.
- `Enemy` and `EnemyBrain` — agents come out of doors, roam the floor, shoot
  standing, crouching or lying down and dodge Otto's bullets: they crouch under a high one
  and lie down under a low one. Otto in shadow is noticed only closer than 1.8 m, behind a
  door and behind a wall he is not seen at all. Each agent has his own anger, and it grows
  over time; it sets the wind-up, the pause, the shooting pose and the chance to dodge. They
  ride cabs as passengers, the cab crushes them with its floor — fully under it; one caught
  by the edge is pushed out; 300 points, only if Otto rides in that cab.
- **Combat numbers are in `Arcade`:** a table of the arcade ROM rules in the original's
  ticks — difficulty, anger, release, shooting, dodging, speeds (ADR-0027, decision 1).
  `BuildingRules` carries the building's skill, from which the table computes the rest, and
  manual caps for tests.
- **Three or four agents in a building at once, as in ROM:** they come out of a random door
  on Otto's floor, one floor above or below (`AgentSpawn`); the door right at Otto
  does not release closer than 1.2 m (in ROM — point-blank, ADR-0053), and an agent comes
  out only from an open leaf. From a crowd
  of three agents on a floor the extra ones leave through doors (ADR-0053). Randomness is
  seeded with the building seed.
- `Lamp`, `LampFall`, `FloorLighting` — one to three lamps per floor depending on width, none
  on the map's dark floors; a shot-down lamp falls, kills the agent under it (300 points) and
  puts out its zone for good — a zone is the nearest lamp's area, the neighbouring ones stay
  lit.
- `BuildingRules`, `BuildingPlan`, `BuildingRoute` — a building of 30 floors plus the roof
  is laid out by rules and seed: shafts **overlap**, and there are more of them the
  lower the floor — from one at the top to five at the bottom; escalators stand in a band at
  the threshold and at the overlap breaks. Doors, red doors and dark floors follow the ROM
  tables, five to ten documents depending on skill (ADR-0028). The seed is the building
  number with the session salt; in tests and for the bot the salt is zero. Traversability is
  checked by a test, and the path through the building by the same graph the bot walks
  (`BuildingRoute.walkable`).
- **Silhouette by threshold:** the top twenty floors are a narrow tower of 7 slots and 15.6 m,
  fits into the frame (23.5 m at 16:9) entirely; below it the podium spans all 17 slots and
  33.6 m, a frame and a half. There are also fewer doors at the top. Slots are numbered
  globally with a 1.8 m step, so a shaft stands in one column on all its floors
  (ADR-0014, ADR-0024, ADR-0026).
- **A floor can be split:** by a shaft opening and by a solid interior wall. One cannot walk
  or shoot through the wall, and an agent behind it does not see Otto; a shaft opening is
  crossed over a standing cab, as in the original.
- **Agents come out near the player:** a door releases its agent when its floor enters the
  band of visible floors and removes one that has gone far. The band is computed from the
  rules frame, not from the smoothed camera — otherwise release would depend on the frame
  rate.
- **Respawn follows ROM** (`RespawnSpot`, ADR-0053): no lower than the fifth
  ROM floor, at the floor's red door, and without one — at a point on the floor; live agents
  leave and come out again with delays. A second and a half of blinking invulnerability
  is ours, ROM has none.
- `GameState` and `Alarm` — three lives, respawn, Game Over, the exit bonus, the next
  building with angrier agents, the siren for slowness.
- Light: a lamp has a cone with a soft shadow and a weak fill, both go out with it;
  `Atmosphere` — the overall palette tone, reflections in the polished floor (SSR), SSAO,
  a hint of fog, glow above a threshold, ACES. Above the roof there is one light source, a
  bullet carries a flash. Only lamps and shaft light columns of visible floors are on
  (`VisibleFloors`). Behind the building is the city (`CityBackdrop`, `CityDetails`) —
  windows by emission, without light sources; weather by seed (`Weather`): a clear night,
  fog or rain with lightning (`Lightning`).
- Graphics quality (`Graphics`): four levels up to "Ultra", on first launch
  the level is chosen by a measurement (`QualityProbe`); window modes and render scale —
  `DisplayModes`; a vignette layer under the HUD (`Vignette`).
- Look: `GreyboxLook` — materials, indicator lights (door boards, cab indicators,
  the exit sign) and the actor outline; `BuildingRibs` — slab ends, baseboard,
  pilasters; `BuildingFinish` — textures of walls, shaft and roof. The building is a hotel or
  an office (`BuildingIdentity`) with a neon sign on the corner (`VerticalSign`), floors
  are furnished with pack models (`BuildingDressing`, `PropCatalog`), the car at the exit
  is different in every building (`ExitCar`). Actors are `FigureRig` on top of `.glb` from
  `tools/build_actors.py`: Quaternius pack models, pack clips and poses in code from
  `FigurePoses`, pose selection is `ActorPose` (ADR-0032).
- Sound (M23): music, jingles, effects and ambience from free libraries —
  Kevin MacLeod, Kenney, freesound; assembled by `tools/build_audio.py`, authors in
  `CREDITS.md`. Four building tracks, three alarm tracks — drawn per building; a footstep on
  concrete has five variants — drawn per step. Buses Master, Music, SFX and Ambience:
  the alarm fades in, behind a door and on pause the music is quieter, a jingle ducks the
  track; the ambience on the roof and at the exit is at full strength, on floors — rain
  behind glass and the corridor's silence; thunder follows lightning by distance; the shaft
  hum and neon are in their places.
- Interface: `Menu` with six pages, `Hud`, `GameSettings` and `Records` — menu,
  pause, settings, the high score table and the controls screen; two languages by system
  locale.
- Screenshots: `python tools/capture.py <milestone>` walks the milestone's route; F12 in
  game. Bot: `tools/playthrough.gd` with `--trace` prints where Otto is, what he pressed and
  where the cab is.

## Previous milestone — M24p · Building exterior by kind

Merged into `main` (PR #66).

Decisions — [ADR-0058](adr/0058-exterior-by-kind.md). Check against the original: in the
arcade the buildings look the same from outside, in Elevator Action Returns each mission has
its own place and its own ending.

Decided (questions 2026-10-03): the silhouette is look only, the layout follows ROM; a tall
crown for each kind behind the play plane, the helicopter flies around it, the intro
shot is redone; the podium's setback ledge and the tower's end walls by kind; the car is a
draw by kind from its own five models; the garage and the street facade by kind; the barrier
and the valet are animated, without affecting the game; no new sounds.

Done:
- the car at the exit and in the garage is a draw by kind (`CarModel.draw`): weights of
  models and paints, the residential building's paint is faded;
- the crown behind the play plane (`BuildingCrown`): art-deco steps with neon
  edges, a fan and a spire; a glass top with a cut and a mast; a tank on
  legs above a brick hut; the water tower left the roof equipment;
- the parapet cornice by kind: stone, aluminium, terracotta;
- the tower's end walls and the podium's setback ledge (`BuildingFlanks`): rustication and
  flags, a terrace with umbrellas and a string of lights; louvres and a glass edge, a plaza
  with skylights; a fire escape, roofing felt, pipes, satellite dishes and laundry.
- the garage by kind (`GarageDressing`): concrete tone and paint stripe, VALET
  signs and a VALET PARKING sign at the hotel, RESERVED and a barrier behind the gate at the
  office — it rises together with the gate, graffiti, a bin and bicycles at the residential;
- the street entrance (`StreetFront`): a canopy with bulbs, a carpet and a valet in
  livery at the stand; a glass vestibule with a revolving door; a stoop, railings and
  bins.
- tests: `test_exterior_by_kind` (car weights, the crown behind the plane, end walls
  outside the walls, the barrier with the gate, the valet at the hotel), the helicopter flies
  around the crown and the rope is in the frame on all three kinds (`test_roof_arrival`); the
  `capture.py M24P` route in the office, `light_bench --kind`, `intro_shot --building`.
- exit tests run over the three kinds; the valet's livery is per surface
  (a shared `material_override` on a skinned model crashed the renderer).
- code review (`/code-review xhigh --fix`): the barrier across the car's lane, the bin
  and bicycles in front of the far wall, graffiti in front of the paint stripe, the cornice
  overhang by kind for rain and snow, flags and louvres do not cover the sign,
  the stoop railings face the right way, the valet freezes off-frame, the mast's beacon
  blinks, hangers on the VALET sign; the intro shot does not fit the spire and the mast —
  recorded in ADR-0058.

The milestone is closed: results are in [milestones.md](milestones.md). `check.ps1` is green,
932 tests.

## Previous milestone — M24o · Special floors, cab and music

Merged into `main` (PR #65). Halls on ROM floors 1–7 and 11–15, a cab and indicator board
of the kind's own style with a freight elevator gate, music and hall ambience chosen by ear
([ADR-0057](adr/0057-floors-cab-music-by-kind.md)); results are in
[milestones.md](milestones.md).

## What's next

- **M24q — animation, frame by frame** (user's request, 2026-10-03): every animation
  reviewed frame by frame and finished — Otto leaving the helicopter, agents opening doors
  and stepping out instead of appearing, Otto opening and closing doors himself, the missing
  frames of takedowns, deaths in unnatural poses (clip or ragdoll), shots that should leave
  from the pistol's muzzle; also buildings flickering behind the menu in night fog. A big
  milestone. Plan in [EPIC.md](EPIC.md).
- **M24r — agent mechanics, difficulty, the alarm** (user's request, 2026-10-03): the agents' life reviewed as
  a whole against the ROM — hittable as soon as they step out, released at a rhythm, agents
  left upstairs not keeping the building below empty, and every related rule; difficulty
  levels that are actually felt; a countdown to the alarm on screen.
- **M24s — settings by the monitor** (user's request, 2026-10-03): frame limits and
  resolutions only those the monitor supports, detected on first launch.
- **M25 — online leaderboard** (optional).

In the credits the author is listed as "Idea & development" instead of "Game creator",
followed by the original: Elevator Action, Taito, 1983 (user request, 2026-09-29).

The plan is in [EPIC.md](EPIC.md).

## Move to 3D — complete

Decision — [ADR-0019](adr/0019-3d-pivot.md): a 3D scene with a side-on orthographic camera
instead of a 2D sprite frame, the game logic unchanged. The pivot ran through milestones
M15–M22 and is finished; the 2D build remains in history (`d5774df`). The pivot rules —
every milestone is playable, arcade readability matters more than cinematic look, mechanics
do not live in a node — and the `tools/look3d.gd` probe it all started with are recorded in
the same ADR.

## Accepted decisions

| | |
|---|---|
| [ADR-0001](adr/0001-tech-stack.md) | Godot 4.7 and typed GDScript, no C# |
| [ADR-0002](adr/0002-visual-target.md) | HD pixel art with dynamic lighting; superseded by ADR-0019 |
| [ADR-0003](adr/0003-no-docker.md) | Docker is not used; appropriate at most for a leaderboard backend |
| [ADR-0004](adr/0004-elevator-mechanics.md) | Elevator, shaft and escalator mechanics after the original |
| [ADR-0005](adr/0005-doors-and-documents.md) | Doors, documents and leaving the building |
| [ADR-0006](adr/0006-combat-and-enemies.md) | Combat, enemies and the split of milestone M4 |
| [ADR-0007](adr/0007-lamps-and-darkness.md) | Lamps, darkness and invulnerability on the escalator |
| [ADR-0008](adr/0008-building-generation.md) | Generated building, the M5 split, the alarm |
| [ADR-0009](adr/0009-game-loop-and-alarm.md) | Game loop, alarm and difficulty growth |
| [ADR-0010](adr/0010-lighting-and-atmosphere.md) | Light, darkness, the city outside the windows |
| [ADR-0011](adr/0011-asset-pipeline.md) | Art pipeline: Blender for actors, code for the environment, the M7 split; sprites superseded by ADR-0019 and ADR-0022 |
| [ADR-0012](adr/0012-sound-and-interface.md) | Synthesized sound, our own motif, a font with Cyrillic, the M8 split; synthesis and the motif superseded by ADR-0036 |
| [ADR-0013](adr/0013-release-and-versioning.md) | Release, versions and tags |
| [ADR-0014](adr/0014-building-architecture.md) | Roof, building silhouette and agent release |
| [ADR-0015](adr/0015-round-palette-and-roof.md) | Round palette and the roof after the Spectrum version |
| [ADR-0016](adr/0016-combat-balance.md) | Combat balance and agent dodging; the anger model replaced by ADR-0027 |
| [ADR-0017](adr/0017-spectrum-palette-and-shafts.md) | Spectrum palette, visible shaft and a roof with a rope |
| [ADR-0018](adr/0018-native-fullhd.md) | Native FullHD, asset detail, proportions and the shaft limit |
| [ADR-0019](adr/0019-3d-pivot.md) | Move to 3D nodes; supersedes ADR-0002 and half of ADR-0010 and ADR-0011 |
| [ADR-0020](adr/0020-agent-doors.md) | Agent door: telegraph, doorway and invulnerability |
| [ADR-0021](adr/0021-3d-greybox.md) | 3D greybox: play plane, room depth, order of the move |
| [ADR-0022](adr/0022-actors-rig.md) | Actors: a rig from Blender, animation in code, an outline instead of a glow |
| [ADR-0023](adr/0023-light-and-readability.md) | Light: camera tilt, lamp zones, edges, indicator lights; darkness decides visibility |
| [ADR-0024](adr/0024-building-geometry.md) | Building geometry: slot grid, silhouette by threshold, shaft overlap, walls, two-floor cab |
| [ADR-0025](adr/0025-shafts-escalators-and-riders.md) | M18b: escalator as a structure, shaft light, two-floor pair, agents in cabs |
| [ADR-0026](adr/0026-proportions.md) | M18c: proportions after the original — the contents grow, an agent as tall as Otto, 3.67 floors in the frame, a lamp from the cab |
| [ADR-0027](adr/0027-rom-combat.md) | M18d: combat by the ROM rules — difficulty, agent anger, 3–4 agents, low shot, speeds and jump, cab crush |
| [ADR-0028](adr/0028-building-by-the-map.md) | M18e: building by the map — ROM doors per screen width, red doors in bands by skill, dark floors 11–15, session salt |
| [ADR-0029](adr/0029-city-weather-dressing.md) | M19: the city in its own perspective view, weather by seed, dressing as decor, the roof as a silhouette, palette through materials |
| [ADR-0030](adr/0030-grading-and-quality.md) | M22: noir grading, the city out of focus, vignette, dithering, three quality levels, a budget across the whole building |
| [ADR-0031](adr/0031-scene-detail.md) | M20: detail — a modern elevator, a roof with equipment, an antenna and neon, floors, city windows as a grid |
| [ADR-0032](adr/0032-actor-models.md) | M21: Otto and agents from a Quaternius pack — pack clips and poses in code, the agent's fedora and glasses, a car from the Cars Pack |
| [ADR-0033](adr/0033-dressing-from-packs.md) | M21b: hotel or office by draw, a vertical sign, dressing and roof from pack models, wall textures, a steel shaft |
| [ADR-0034](adr/0034-ultra-and-auto-quality.md) | M22: the "Ultra" level, anti-aliasing within levels, the level on first launch by measurement, noir; amends ADR-0030 |
| [ADR-0035](adr/0035-menu.md) | M22b: menus on a live scene — the city behind the main menu, the blurred game behind the pause, a neon sign, a single font Exo 2 |
| [ADR-0037](adr/0037-polish-bugs-and-combat.md) | M24a: boarding the cab level with the floor, rain with collision, an even ambience, bullets three times faster with an aiming beam, corpses until the end of the building, falling more than a floor, 5–10 documents |
| [ADR-0038](adr/0038-building-start-and-end.md) | M24b: a helicopter in every building, the red door for 70 ticks without early exit, one shaft to the basement garage, without all documents the elevator does not go there, the exit through a car |
| [ADR-0039](adr/0039-animation-and-controls.md) | M24c: UAL clips, timed transitions, key rebinding, shader warm-up |
| [ADR-0040](adr/0040-takedowns.md) | M24d: takedowns instead of the jump kick, the world slows down for the scene |
| [ADR-0041](adr/0041-demo-mode.md) | M24e: demo mode — the bot after 45 s in the menu, three locations in rotation |
| [ADR-0042](adr/0042-bugs-and-settings.md) | M24f: the corpse as a physics body, cheaper shadows, 3D resolution in fullscreen, Game Over in slow motion, no outline, light at the red door |
| [ADR-0043](adr/0043-animation-and-look.md) | M24g: the rope pose, walking on the escalator and its model, entering the door into the depth, headlights, city windows |
| [ADR-0044](adr/0044-street-and-cab.md) | M24h: two lanes and a gap, red doors only, walking and stepping out on the move in the cab, crush as in ROM, the escalator into the depth, corpses freeze |
| [ADR-0045](adr/0045-takedowns-helicopter-dressing.md) | M24i: takedowns by direction without a camera angle change, a helicopter from a free model, hotel and office dressing |
| [ADR-0051](adr/0051-time-of-day.md) | M24j: time of day by draw, night 40 %, darkness only at night, thunderstorm in the evening and at night, the city from pack models and an HDRI sky |
| [ADR-0052](adr/0052-day-for-the-rest-and-arrival.md) | M24k: music and ambience by time of day, the street and the room in daytime, the sign goes out, a helicopter with a door and a pilot, gaps in the sound |
| [ADR-0053](adr/0053-open-questions-and-debt.md) | Open questions and debt after M24k: cab, respawn, release and crowd by ROM, the bot shoots down lamps |
| [ADR-0054](adr/0054-snow.md) | M24l: snow — a fourth weather, snow cover and footprints, precipitation stops at everything solid, pedestrians by weather, a slippery roof |
| [ADR-0055](adr/0055-residential.md) | M24m: an American 80s residential building as the third kind, a draw of three, an apartment behind the door, agents dressed by building kind |
| [ADR-0056](adr/0056-building-character.md) | M24n: each kind's own air and lamp colour within noir, the round palette by kind, the back wall by layout — the office's open space, the hotel's niches, the residential building's pipes and windows, light fixtures by kind |
| [ADR-0057](adr/0057-floors-cab-music-by-kind.md) | M24o: special floors by the ROM layout — halls in depth on 1–7, technical floors on 11–15; a cab and shaft of the kind's own style, a freight gate by the step-out window; music kind × time of day with a theme change and its own alarm |
| [ADR-0058](adr/0058-exterior-by-kind.md) | M24p: exterior by kind is look only — a crown above the roof, setback ledge and end walls, the garage and the street entrance, the car drawn by kind; the barrier and the valet are animated |
| [ADR-0059](adr/0059-deterministic-combat-run.md) | Deterministic combat run: bullets decide hits by a direct query instead of Jolt overlap events, the bot jumps onto prone agents, a 4 s calm after the return keeps near doors shut |
| [ADR-0060](adr/0060-review-sweep.md) | Whole-game review sweep: agents shoot where Otto is, no death in the frame a door or escalator takes him, the alarm stops in the exit car, agents kept by where they are, quality probe per level, saved files checked by type, zero is not a record, hall furniture by floor |
| [ADR-0036](adr/0036-sound-from-libraries.md) | M23: sound from CC0/CC-BY libraries, noir jazz, ambience by location, the music follows the game; synthesis goes away; supersedes items 1–2 of ADR-0012 |

Other: the base viewport is 1920×1080 (ADR-0018 superseded 640×360 from ADR-0002,
ADR-0019 superseded ADR-0002 itself); the `canvas_items` stretch serves only the HUD
and menus, 3D is drawn at window resolution with the render scale from the settings; crouching stops movement
(as in the original), jumping from a crouch is forbidden. **Coyote time and a jump buffer are not added:**
the question was deferred until the end of M2, and the project's formula is the 1983 mechanics, and the original
has neither.

## Open questions

There are no open questions.

Closed: 3 — the platform, GitHub Releases only
([ADR-0013](adr/0013-release-and-versioning.md), item 1); 5 — animation frames
(dropped together with the sprites); 6 — combat numbers, red doors, darkening and the alarm
by ROM ([ADR-0027](adr/0027-rom-combat.md),
[ADR-0028](adr/0028-building-by-the-map.md)); 7 — the low shot by ROM
([ADR-0027](adr/0027-rom-combat.md), decision 3); 4, 8 and 9 — cab,
respawn, release, shadow distance and the twentieth floor
([ADR-0053](adr/0053-open-questions-and-debt.md)).

## Debt and notes

There is no debt. Closed by [ADR-0053](adr/0053-open-questions-and-debt.md): the rotor
downwash and rain, the facade atlas margins, `Weather.forced`, mipmaps of in-scene labels,
the indicator board arrows; lamp swinging and weakening darkness were dropped by decision.

- **Determinism of the combat run** ([ADR-0059](adr/0059-deterministic-combat-run.md)):
  bullets decide hits by a direct query instead of Jolt's overlap events, the bot jumps onto
  prone agents instead of duelling them, and for 4 s after Otto's return doors near him stay
  shut. The pre-push hook had failed on the seed-3 combat run at random; now 2, 5, 3 deaths.

- **Whole-game review** ([ADR-0060](adr/0060-review-sweep.md)): seven areas, no crash,
  softlock or state leak; generation gives a winnable building for any seed. The fixes are
  in `fix/review-sweep`; bot deaths after them are 3, 5, 3. Splitting hall furniture by
  floor did not change the frame time on the test machine — it keeps the cost from growing.
  Left for later from the review of the fixes: a falling lamp loses its fill shadow while it
  still shines if the camera band changes mid-fall, and the knocked-off hat repeats
  `Ragdoll`'s resting logic without riding a moving cab — both small, both outside the sweep.

- **Ray tracing** — check with every engine update (user's
  question, 2026-09-24). Godot 4.7 has only low-level Vulkan RT in
  `RenderingDevice`, no ready-made RT shadows, reflections or GI; the NVIDIA fork is
  a separate engine build. The M22 "Ultra" is built with engine tools (SSIL,
  volumetric light, 8192 shadows; no SDFGI, ADR-0034), and RT as an option once it
  appears in the main branch.

## What came before

Results of completed milestones and code review findings are in [`milestones.md`](milestones.md).
Only what describes the project today is here: otherwise the file read
first in a new session drowns in history.
