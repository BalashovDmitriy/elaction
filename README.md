# elaction

A remake of the arcade game **Elevator Action** (Taito, 1983) in Godot 4.

Mechanics as in the original: agent Otto descends from the roof of a thirty-storey
building, collects documents behind red doors, rides elevators, shoots back at enemy
agents and escapes by car. The lamps on a floor can be shot out, and the floor goes
dark.

**The project has moved to 3D** ([ADR-0019](docs/adr/0019-3d-pivot.md)): the scene is
three-dimensional, the camera is orthographic and looks from the side, Otto's movement is
locked to a plane. The move ran through milestones M15–M22: first playability in grey
boxes, then actors, lighting, the building layout from the original, the city, pack models
and grading. The last 2D build remains in git history — the M14 merge, `d5774df`.

| | |
|---|---|
| Engine | Godot 4.7.2 |
| Language | GDScript with static typing |
| Platforms | Windows, Linux |
| Status | Milestones up to M24p are complete: the game is assembled in full — three building kinds with their own halls, cabs, music and exterior. Next — M24q: every animation reviewed frame by frame and finished; M24r: agent mechanics, difficulty and the alarm; M24s: settings by the monitor; then M25: online leaderboard (optional). |

## Download and play

There have been no releases yet: the first tag has not been set, and until then the game
is built from source — see "Running" below. When a tag appears, ready builds will be on
the [releases page](https://github.com/BalashovDmitriy/elaction/releases):
`elaction-vX.Y.Z-windows.zip` and `elaction-vX.Y.Z-linux.zip`. Inside is an `elaction`
folder: the executable and the licenses. Resources are embedded in the file itself,
nothing else is needed next to it, and there is nothing to install.
Godot is needed only by those who build the game from source.

On first launch Windows shows a SmartScreen warning: the build is not signed
("More info" → "Run anyway"). A certificate costs money, and the project has no
publisher — [ADR-0013](docs/adr/0013-release-and-versioning.md).

What changed between versions is in [CHANGELOG.md](CHANGELOG.md).

## What already works

The game rules live separately from the scene nodes and moved to 3D without changes;
during the move they grew — combat and the building map are now taken from the arcade ROM.
The world is built from pack models and textures, the lighting is real: lamp cones with
soft shadows, reflections in the polished floor, a hint of fog. Actors are human models on
a skeleton; on a darkened floor the doors, the cab and the exit keep their own indicator
lights, the red door its own sconce, and the actors a faint camera light that shines only
on them.

- Otto walks, crouches and jumps; he does not stand up from a crouch where there is no
  room.
- Elevator: the cab obeys from inside, an empty one runs on its own, on the roof they ride
  without control. Released between floors, the cab carries on to the next floor in its
  direction, as in the arcade. Otto can walk inside the cab while it moves, and step off
  onto a floor while it is close, as in the original. One can fall to death into an open
  shaft opening; a descending cab crushes anyone standing fully under it, and pushes
  someone caught by its edge to the edge of the shaft. Points for a crushed agent — only
  if he was caught by the cab Otto rides in.
- Escalators: boarding from the landing with a press, during the ride Otto is invulnerable
  and walks along the steps.
- Doors: only a red door can be entered, while its document has not been taken — as in
  the original. Documents behind red doors are worth 500 points each — on exit; Otto turns
  to the door and goes deep into the doorway, the door leaf closes behind him, he stays
  inside exactly 4.7 s, the corridor is heard muffled from there, and an agent who lost him
  sometimes waits at the door — and shoots as soon as Otto can be hit again. Until the
  documents are collected, the shaft to the basement is closed by a steel hatch; the last
  document opens it.
- An agent does not appear out of nowhere: the door opens fully and only then releases
  him, and he steps out of the doorway. While he is in the doorway, a bullet passes
  through — this is not armour but the absence of a target, and the door leaf shows that
  someone is about to come out. The leaf closes as soon as the doorway is free; an emptied
  red door becomes an ordinary one and starts releasing agents too.
- Combat: a pistol limited to three bullets on screen and point-blank takedowns; enemy
  agents come out of doors along the way down and shoot. There is no kick as in 1983:
  point-blank to an agent the shot becomes a short scene — from behind a chokehold or a
  neck snap, from the front a series of punches or a pistol-grip blow — and Otto, falling
  onto an agent from above, jumps on him by himself. The scene is staged: a quick approach,
  a freeze-frame on the hit and a ramp back; on the hit the camera shoves and tilts, a
  flash sculpts the faces, the music drops away, the background darkens and loses colour
  for the scene. The agent manages to reach for his gun or glance back, his hat flies off
  on the hit, and he falls as a body, thrown away from Otto. Otto is vulnerable; a takedown
  is worth 200–300 points against 100 for a shot. Three lives, Game Over, and after a
  death — return by the arcade rules: at the floor's red door or at its point, while the
  agents leave and come out again; for the first second and a half Otto is invulnerable.
- **Combat follows the rules of the arcade ROM.** An annotated disassembly of the original
  turned up, and the combat numbers are taken from the code rather than from retellings:
  speeds, pauses, wind-up, poses, release. Notes with addresses are in
  `docs/reference/arcade-rom.md`.
- There are three agents in the building at once, later four; they come out of a random
  blue door on Otto's floor, a floor above or below. They do not chase Otto — they wander
  and shoot while looking at him; Otto's shots put them on alert.
- Agents shoot standing, kneeling and lying down. A high bullet passes over a crouching
  Otto, a kneeling bullet passes over a lying one, and a lying agent hits a crouching Otto
  too: only a jump saves from it. They dodge the same way: from a high bullet — onto a knee,
  from a low one — lying down.
- Difficulty grows from building to building and over time within a building; each agent
  has his own anger — it sets the wind-up before a shot, the pause after and the
  chance to dodge. Settings have four difficulty levels, like the cabinet's switch.
- The cab crushes agents — 300 points; the alarm turns on after 277 s, as in the ROM, and no longer once Otto is in the exit car.
- Lamps: one to three per floor across its width, hanging right under the ceiling. As in
  the original, a lamp can be shot down only from the cab, riding between floors: from the
  floor a bullet does not reach it, neither standing nor jumping. A downed lamp falls,
  kills the agent under it and darkens its zone for good. Agents notice Otto in a dark
  zone only point-blank, lose him behind a door and wander the floor blind; killing an
  agent in the dark is worth 50 points more.
- The 30-floor building is generated, but by the rules of the original's map: the doors on
  a floor follow the arcade ROM table (four on the tower, up to seven in the middle, twice
  as many on the wide lower part), red doors range from five in the first building to ten,
  and they lie in bands, as in the original: in the first building the top is empty.
  Floors 11–15 are dark — there are no lamps, agents see Otto only point-blank, and kills
  are worth more. Each session salts the layout, and buildings differ from session to
  session. Above the building is the roof, where the descent starts; the elevator reaches
  it, there are no doors or agents on it.
- **The lower, the more paths**, as in the original. The upper third is served by one
  shaft, and the descent there has no alternative; lower down the shafts overlap — one can
  change from one to another without looking for an escalator — and five of them converge
  on the bottom floor.
- Escalators stand in a band where the tower's shaft ends, and at every gap the shafts did
  not cover. In the original they are also in the upper third, not at the bottom.
  They stand at the edge of the floor and descend to it at 45°: the top landing is reached
  on foot, the opening runs from it toward the wall. Several in a row — in a zigzag.
- An open shaft cuts a floor: one can cross from one side of it to the other only while
  a standing cab covers the opening. A cab that has left tears the floor in two, and the
  way has to be found through neighbouring floors.
- A floor may be split in two by a solid wall: one cannot walk or shoot through it, and an
  agent behind it does not see Otto. It can be bypassed only through another floor.
- The round palette is a building rule, and the set cycles, like the colours in the
  original. The round's tone lies on the materials — as a multiplier on the wall texture,
  on the brickwork and the shaft: the pattern stays, the colour comes from the round.
  A darkened floor is dark, not black: in the dark agents keep shooting, and the player
  must see what to shoot back at.
- The shaft is visible in full: guide rails along its whole height and doors on every floor
  it serves. The band has stops at the top and bottom, and the cab has arrows: they go out
  when there is no way in that direction, and the shaft's limit no longer reads as a
  breakdown. The shaft has its own cold light: it does not go out from a shot and does not
  take part in the darkness zones — a darkened building must stay passable by eye.
- No more than two shafts in a building carry a **double-deck cab** — a rigid pair of decks
  one floor apart, as in the original. Either deck can be entered; it carries only between
  the floors that either of the two reaches, and is placed only where it does not lock the
  descent.
- The escalator stands deep inside, at the back wall: the floor in front of it is solid,
  people walk past, and Otto steps onto the landing by stepping inward. It is built from a
  model made by its own script in Blender: ribbed steps with a yellow edge, a clad truss,
  glass balustrades with a handrail on both sides, newels, landings with a comb plate. The
  span has its own light: there is little room on a floor, and the escalator almost always
  stands away from the lamps.
- **Agents ride elevators.** They do not call the cab — nobody has that — but enter one
  that already stands level with their floor and ride as passengers: only Otto controls the
  cab's travel. An agent lost a floor above now comes down by cab.
- **Proportions as in 1983.** Sizes are checked pixel by pixel against an arcade frame and
  set by one table in arcade frame pixels: Otto and the agents are the same height,
  slightly more than half the floor's clearance, a door is 70% of the clearance, the cab
  spans the full floor, the shaft is exactly one door step. As in the original, the frame
  shows 3.67 floors.
- On every floor at the right wall there is a glowing sign with the number, as in the
  original: the top floor is 30, the basement garage is "P". It is readable on a darkened
  floor too.
- A round starts with a helicopter — its own model: transparent glazing with a pilot in a
  helmet, a sliding door, skids, a tail fin, main and tail rotors with motion blur when
  spinning. In the first building of a session — the full scene: the helicopter flies in,
  slides the door open, Otto looks out of the doorway and sits on the sill, a coil of rope
  drops and swings in the rotor downwash, Otto slides onto the rope, goes down hand over
  hand, brakes at the roof and lands in a crouch; the camera zooms in and follows him.
  Then the winch reels in the rope, the door slides shut, the pilot nods, and the
  helicopter leaves banking. In the following buildings — shorter: the helicopter is
  already hovering with the door open. The scene can be skipped with a jump, a shot or
  pause. Above the top shaft is the machine room.
- The silhouette is set by a threshold: up to the twentieth floor a narrow tower that fits
  in the frame entirely, from the twentieth — a podium twice the screen's width, which has
  to be walked.
- Game loop: collect the documents, get out — a bonus and the next building, where agents
  are angrier. Dawdle — the siren, and it cannot be removed until the end of the building.
- Lighting: a zone is lit while a lamp hangs over it — a cone downward with a soft shadow
  and a faint fill around. Shot down — the zone drops to the building's overall tone
  forever. The camera looks slightly from above, and reflections show in the polished
  floor; slab ends, the skirting and pilasters give the light edges. A shot carries a
  flash.
- Actors: people from the Quaternius pack (CC0) — Otto in a light suit, agents in dark
  suits, fedoras and dark glasses, everyone with a pistol in hand. Idle, walk, shot, death,
  hit reaction and landing are clips from the Universal Animation Library (Quaternius,
  CC0), retargeted to the pack's skeleton, and the punches and knockback for takedowns come
  from its second part; squatting crouch, lying, grab, chokehold and neck snap are poses in
  code. The transition between poses is short and ends on time; a turn is a rotation of
  the body, and while the body turns, the actor stands. After a jump — a short recovery.
  On a darkened floor the figure is picked out by a faint cold camera light — only the
  figure, not the floor.
- The building ends in an underground garage: Otto walks up to his car at the gate by
  himself and gets in through the open door — every car's body is cut along the opening,
  inside is an interior made for that car, a dome light glows under the roof; the
  headlights come on, the roller gate rises, and the car drives up a smooth ramp onto the
  street. There, traffic runs in two lanes, and the road situation is different in each
  building: on a free street Otto's car, with the right indicator on, pulls into the lane
  without stopping; in dense traffic it stops at the kerb and waits for a gap; the frame
  follows it, and the headlights' light lies on the road until the fade-out. The bonus is
  counted on top of the scene, then a fade-out and the next building. In the first
  building — a red coupe, as in 1983; after that the model and colour come from the
  building's draw (Cars Pack, CC0).
- A bullet is a thin tracer, three times faster than the arcade one; at the muzzle a flash
  and a puff of smoke, on the wall sparks, dust and a mark. Before a shot the agent raises
  his pistol, and a red aiming beam runs from the muzzle at the height of the coming
  bullet; the arm points the barrel exactly where the bullet will come from. The killed —
  agents and Otto — fall as jointed bodies from the bullet's impact, at the body part it
  hit, and lie until the end of the building: they pile on each other, ride on the cab
  floor, fall into the shaft. A cab passing with its floor slices what is under it, with
  spray and a blood stain, and a body lying across the sill of a cab that has started
  moving tears along its wall; with blood turned off the body simply disappears.
  Physics — Jolt.
- Takedown from above — land on an agent or right next to him, from a jump or from the
  floor above. The last life goes out in slow motion: the camera zooms in on Otto, and only
  then — the end of the session, whose menu items cannot be pressed for the first second
  and a half.
- The street at the exit — buildings from Quaternius Downtown facades with shop windows,
  awnings and fire escapes: by day in the sun, neon and street lamp off, at night windows,
  neon and street lamp lit. There are more cars by day than at night, by day headlights are
  on only in bad weather. Pedestrians walk along the sidewalk — men and women from the
  Quaternius townsfolk packs, all different and dressed for the weather: on a clear day
  lightly, in cool weather and fog in jackets, in rain in raincoats and with an umbrella in
  hand, in snow in coats, hats and scarves.
- Snow: flakes in clumps drifting with the wind, cover on the roof, window sills,
  equipment, sidewalk, awnings and cars, footprints of Otto and agents on the roof and
  tyre tracks on the road, the city in a snowfall. A snowy roof is slippery: on stopping
  and turning the feet slip. Its own sound — blizzard, crunching steps, tyres on slush.
- Rain by light: drops are visible where the light of a lamp, a shaft or neon falls on
  them, they end on the roof, equipment, people, cars and the helicopter, break into
  splashes, rings spread over puddles; a water haze hangs over the roof. The helicopter's
  rotor downwash scatters rain and snow, and in snow raises snow dust off the roof. The city
  behind — with floors, curtained windows and signs, and it moves smoothly with the camera.
- There are five to ten documents in a building, by draw. Anyone who falls more than a
  floor — onto the floor, a cab roof or the bottom of the shaft — is killed.
- Sound: Kevin MacLeod's music is different for each building kind — swing and lounge for
  the hotel, cold synth noir and elevator music for the office, blues and funk for the
  residential building; its own set for night, morning, day and evening and its own alarm
  per kind, the track comes from the building's draw, from the middle of the building down
  the theme changes; the menu and the end of a session have their own tracks; the alarm
  comes in with a siren and a swell, behind a red door and on pause the music is muffled.
  Effects and ambience — Kenney and freesound (CC0, CC-BY): Otto's and agents' steps on
  carpet, stone and metal, jump and landing, an agent's shot with its own sound at his
  position, bullet ricochet off wall and metal, a body hitting the ground, cab crush, the
  cab starting and stopping, the hum of the cab and the shaft, the helicopter door and the
  winch, a car door and the indicator, passing cars and horns, the neon sign crackling,
  bonus and high score, the clang of the freight elevator's gate; halls have their own
  ambience — splashing of the pool, hum of the server room and the boiler room, laundry
  drums, the chatter of the restaurant and the bar; on the roof and at the exit the street
  of its time of day and the rain, on floors rain behind the glass, thunder after
  lightning. In the slow motion of a takedown and of the last death, world sounds go lower
  in pitch.
- Demo mode, as on the cabinet: the main menu, left for 45 seconds without input, gives
  way to a game driven by a bot — about 30 seconds from the roof with the helicopter, from
  the middle or from the bottom of the building, in turn. The bot shoots back, dodges
  bullets and takes agents down point-blank. Any key, gamepad button or mouse button
  returns to the menu; the demo does not record high scores, and a score of zero is no record.
- Interface: main menu, pause, settings (three volumes, language, difficulty, graphics
  quality, window mode, resolution, frame limit, vertical sync, blood, frame counter),
  high-score table, controls screen with key rebinding and the credits page. The mouse
  cursor is visible only in menus. The first building of a session opens from black: under
  it the shaders of rare effects warm up once, and the first shot does not stutter the
  frame. Behind the main menu is a living night city, the game's title glows as a neon
  sign; on pause, behind the menu, is the frozen game out of focus. Items are neon plates,
  values scroll left-right, transitions are animated and have sound. Two languages —
  Russian and English, by the system locale. HUD — neon plates in the colour of the
  building's sign: score, document folders, lives as silhouettes, the building's name and
  the floor where Otto is, the round and the alarm. All text is in the Exo 2 font.
- An extra life at 10,000 points — the threshold from the Taito manual.
- Time of day is each building's own: morning, day, evening or night, night more often
  than the others. Darkness happens only at night: by day a downed lamp falls, but the
  floor stays lit, and there are no dark floors. Morning, day and evening have their own
  music and their own street ambience: in the morning birds, by day a dense hum; the
  building's neon sign is off in the morning and by day, in the room behind a door the sun
  shines through the window by day.
- Behind the building is the city: brick, stone and glass buildings with facades from
  Quaternius Downtown modules, in several rows in depth, the far ones shift slower than the
  near ones. The sun, and at night the moon, give the facades volume, the glass reflects
  the sky — a Poly Haven photo panorama matching the time and weather. In the evening and
  at night windows glow — going out and lighting up as in a living city — neon signs,
  blinking lights on the roofs and the glow of the streets. Round weather — clear, fog with
  drifting bands, rain or snow; in the evening and at night with a thunderstorm: a flash
  lights up the city's glass and brightens the corridor for an instant. The dressing is
  decor and takes no part in combat.
  The roof rises to the shaft in steps, as in the original.
- The building is a hotel, an office tower or a residential building, by draw: a vertical
  neon sign on the corner of the facade (EMPIRE HOTEL, KRONOS, LENOX APTS…), and their
  corridors differ. The hotel has wallpaper, a carpet runner, wooden panelled doors,
  sconces on marble pilasters, "Do not disturb" on the handles and newspapers at the
  doorstep; the office has plaster, carpet tiles, doors with frosted glass, department
  signs, fluorescent light boxes; the residential building has checkerboard tiles, peeling
  paint and glazed brick, steel apartment doors with a peephole and a doormat, saucer
  ceiling lights, graffiti and stains on the walls, flickering lamps, mailboxes, strollers
  and radiators, and from behind the doors one occasionally hears a TV, a dog or neighbours
  arguing. Along the walls is furniture from packs (sofas, benches, dressers with lamps,
  clocks, water coolers, filing cabinets, copiers, visitor chairs, plants), on the walls —
  paintings, boards, clocks. Behind an open door is a hotel room, an office or an
  apartment: a bed with a nightstand and curtains, a desk with a chair, a kitchen with a
  stove and a fridge, or a living room with a sofa and a TV flickering in the dark; a
  window onto the city, its own light.
- Each kind has its own world: the hotel — warm amber noir with chandeliers, wooden panels,
  lit niches and mirrors; the office — cold white-blue, the corridor wall is glass, and
  behind it an open space with cubicles and glowing monitors is visible; the residential
  building — dim sodium light, pipes and panels on the walls, windows onto the fire escape,
  bare brick, bare bulbs. The round palette varies within its kind's range, darkness is
  equally dark everywhere.
- The building's lower and dark floors are special: behind columns, glass or mesh instead
  of the corridor wall is a hall of full depth. The hotel has a lobby with a reception
  desk, a restaurant, a ballroom with a grand piano, a pool, a bar, a kitchen, a laundry
  and a boiler room; the office has a lobby with turnstiles, a canteen, a gym, meeting
  rooms, server rooms with blinking racks and an archive; the residential building has
  mailboxes, storage cages, a common room with ping-pong, a workshop and a boiler room.
- Outside the building is also of its kind: above the roof is a crown — a stepped art deco
  one with a spire and neon on the hotel, a glass top with a slanted cut and a mast on the
  office, a wooden water tank on legs on the residential building. From the tower's floors
  its end walls and setback ledge are visible: the hotel has flags and a terrace with
  umbrellas and a string of lights, the office has louvres and skylights, the residential
  building has a fire escape and laundry on the roof. In the garage — VALET signs,
  RESERVED spots with a barrier or graffiti and a dumpster; on the street at the exit — a
  canopy with a carpet and a valet, a glass vestibule or a stoop; the car at the exit
  matches the building's taste.
- The elevator of its kind: in the hotel brass, wood and a dial with a needle above the
  door; in the office stainless steel and digits; in the residential building a freight cab
  with a folding gate — it is closed while moving and folds open when one can step out of
  the cab.
- Agents are dressed for the building: in the hotel in fedoras, in the office in business
  suits with a tie, in the residential building in jackets and caps. The mechanics are the
  same for all.
- The shaft is a steel column through the building: bolted sheet, braces, a chrome portal.
  Above the portal an indicator board shows the floor where the cab is now and the travel
  arrow, next to it the call buttons — the one in the direction the cab is travelling
  toward the floor is lit.
- On the roof — a water tower, a dish, air conditioners, a solar panel, a roof exit, an
  antenna with a blinking light.
- The elevator as in the reference: a cab with walls, a light and a control panel, ropes
  and a counterweight that moves the opposite way. Panelled doors with handles, pendant
  lamps, a carpet runner along the corridor. The bottom floor is an underground garage:
  columns, pipes and lights under the ceiling, other people's cars in the spots. Rounds
  differ in the colour of the floors. A bullet knocks sparks out of a lamp, and a hit on a
  person draws blood (it can be turned off in the settings).
- Graphics: four quality levels — from low for weak machines to "Ultra" with bounced light
  and lamp halos in the air; anti-aliasing at every level. On first launch the level is
  chosen automatically, by a frame measurement at each level in turn. The frame's tone is specific to each time
  of day; at night — noir: cold shadows, warm lamps.
- Any monitor resolution up to 4K: window, borderless window or fullscreen at native
  resolution. In fullscreen and borderless the chosen resolution is the scene resolution:
  below native — less is rendered and upscaled by FSR, while the interface stays sharp.
  The world is metric: a floor is 3.6 m, Otto 1.68.
  The depth of the frame is the room behind the corridor's back wall, seen through the
  doorways; everything gameplay-related stands in one plane, and "reached or not" is
  decided by the rules, not by mesh placement.

## Roadmap

The whole work plan is in [`docs/EPIC.md`](docs/EPIC.md). Architectural decisions and
their reasons are in [`docs/adr/`](docs/adr/).

## Running

### What to install

- [Godot 4.7.2](https://godotengine.org/download) — on Windows it is easier via winget:

  ```powershell
  winget install --id GodotEngine.GodotEngine
  ```

- Python 3.12 or newer — for linters and hooks.

Playing, passing the checks and building a release need only these two: models, textures,
sound and the icon are in the repository ready-made ([ADR-0022](docs/adr/0022-actors-rig.md)).
Below is what is needed only to **rebuild** them:

- [Blender 5.2.1](https://www.blender.org/download/) — actor models:

  ```powershell
  winget install --id BlenderFoundation.Blender
  ```

- Pillow, numpy and soundfile — the sound build and the icon generator; Pillow is also
  needed by the texture build `tools/build_textures.py` and by
  `tools/compare_original.py`, which compares a milestone shot with the original:

  ```powershell
  .venv/Scripts/pip install -r requirements-assets.txt
  ```

### Environment setup

```powershell
python -m venv .venv
.venv/Scripts/pip install -r requirements-dev.txt
.venv/Scripts/pre-commit install
.venv/Scripts/pre-commit install --hook-type pre-push
```

### Run the game

```powershell
godot --path .
```

### Open in the editor

```powershell
godot -e --path .
```

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Move | Arrows | D-pad, left stick |
| Crouch | Down | D-pad or stick down |
| Jump | Space | A |
| Shoot, point-blank — takedown | X | X |
| Pause | Esc | Start |
| Screenshot | F12 | — |

Move, jump and shoot are rebound in the "Controls" menu: one key and one gamepad button per
action, a key already in use swaps places, there is a reset to defaults. Pause, screenshot
and the stick are fixed.

In menus items are selected with the arrows or the D-pad, **Enter** or **A** — select;
values in the settings scroll left-right. **Esc** or **B** go back a page.

Pause opens a menu: continue, restart, settings, exit to main menu.
**Esc** from there also returns to the game.

"Up" and "down" depend on the place: in an elevator cab they drive it, on an escalator
landing they start the ride, on the mat at a door "up" leads inside. On a floor "down" is
an ordinary crouch.

## Checks

Hooks run by themselves: `gdformat` and `gdlint` on commit, project import by the engine
and tests on push. A full manual run:

```powershell
tools/check.ps1
```

CI runs the same set of checks on every push to `main` and every pull request.

Separately:

```powershell
python tools/run_tests.py     # GUT tests
python tools/godot_check.py   # import and script parsing
python tools/capture.py M22  # milestone screenshots into screens/M22/
python tools/compare_original.py M22  # milestone shot next to the original
python tools/clean_check.py   # import and tests on a clean copy — as on a fresh clone
```

`clean_check.py` checks out HEAD into a temporary working copy and runs
`godot_check.py` and `run_tests.py` there. It catches what is invisible on the working
machine: files that are not in git but lie on disk from earlier runs. The run is long, so
it is not in the hooks — run it before a PR.

A single test file is run separately — that way an iteration takes seconds rather than the
two-plus minutes of the full suite:

```powershell
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_elevator_motion.gd -gexit
```

Sound is built from free libraries, models from Quaternius packs (sources —
`assets/source/quaternius/`, CC0):

```powershell
python tools/build_audio.py        # sounds and music from libraries → assets/audio/
python tools/build_actors.py       # Otto, agent and cars from packs → assets/models/
python tools/build_textures.py     # wall, shaft and roof textures → assets/textures/
python tools/blender_bin.py        # check that Blender is found
godot --headless --script res://tools/dump_model.gd -- res://assets/models/otto.glb  # what Godot imported
```

Motion clips come from the Universal Animation Library (Quaternius, CC0): idle, walk,
shot, death, hit reaction, landing. `build_actors.py` retargets them to the pack's skeleton
and puts every frame on the floor. The repository holds a trimmed source
`assets/source/quaternius/ual_clips.glb`; to rebuild it from the downloaded archive —
`python tools/build_actors.py ual <AnimationLibrary_Godot_Standard.glb>`. The other poses
are a table in `FigurePoses`, and `FigureRig` drives the bones to them and to the clip
frames right in the game. Editing a pose in code means changing a number, not opening an
editor. `godot --path . res://tools/actor_shot.tscn` shoots all poses of Otto and the
agent side by side, with the ROM bullet lines, and
`godot --path . res://tools/takedown_shot.tscn` shoots each takedown scene as a contact
sheet, with the real director, slow motion and camera zoom.
`godot --path . res://tools/demo_shot.tscn` shoots the demo from each of the three points.
`godot --path . res://tools/car_shot.tscn` — all cars of the draw from the side, with the
door open and close up, `godot --path . res://tools/room_shot.tscn` — the rooms behind the
door, and `python tools/build_helicopter.py` builds the helicopter in Blender.

The dressing is pack models in `assets/models/props/`, as they came; height, turn toward
the camera and where an item stands are decided by the `PropCatalog` catalogue. A new model
is a line in the catalogue, in `assets/models/props/credits.json` and in `CREDITS.md`,
otherwise the test will not let it through.
`godot --path . res://tools/props_shot.tscn` shoots the whole catalogue side by side, with
captions (`-- --raw` — as the models came from the packs).

Shots by state, not by delay — tools that wait for the right moment and capture exactly
what the caption promises:

```powershell
godot --path . res://tools/ui_shot.tscn -- --folder=M8b --locale=en   # menu screens
godot --path . res://tools/combat_shot.tscn           # agent stances under fire
godot --path . res://tools/dark_shot.tscn             # floor lit, zone darkened, floor darkened
godot --path . res://tools/layout_shot.tscn           # tower, podium, escalator band, wall
godot --path . res://tools/geometry_shot.tscn         # escalator, shaft on a darkened floor, pair
godot --path . res://tools/look3d.tscn                # the 3D look test the pivot started with
```

The frame cost is measured separately — on a real building with agents, by GPU time,
not by frame rate:

```powershell
godot --path . res://tools/light_bench.tscn           # wide floor: three lamps and agents
godot --path . res://tools/light_bench.tscn -- --whole  # the whole building at every quality level
godot --path . res://tools/flicker_shot.tscn          # flicker map: what changes from frame to frame
```

The building is assembled from a seed, so it is checked on three levels at once: rules
without a scene, layout properties over dozens of seeds, and the assembled building that a
bot plays through — with agents too. Why this way and why the bot is driven by state rather
than by a stopwatch — in [`docs/testing.md`](docs/testing.md).

The bot finds its path through the building graph rather than descending greedily: with
overlapping shafts "ride the nearest one down" runs into a dead end, and getting out of it
takes going back and up. The route as the bot sees it is printed by `dump_plan` — that
trace is what is used to find where the descent gets stuck.

Combat balance is measured by the same bot, but manually and in detail: it prints where it
died, who stood nearby and how many agents it took down. With `--trace` it prints every
few frames where it stands, what it pressed and where the nearest cab is — this is how M15
found a cab that touched the roof for one frame and left.

```powershell
godot --headless --script res://tools/playthrough.gd -- --seeds=1,2,3 --agents
godot --headless --script res://tools/playthrough.gd -- --agents --at-once=12
godot --headless --script res://tools/playthrough.gd -- --seeds=1 --trace --budget=3000
godot --headless --script res://tools/playthrough.gd -- --seeds=3 --agents --log=logs/run_{seed}.jsonl
python tools/run_log.py logs/run_3.jsonl             # summary: deaths, causes, shooters
```

The run log (`--log=`) writes each event as a JSON line — deaths with cause and shooter,
hits, agent release, rides, bot decisions; the playthrough test with agents writes it by
itself to `logs/playthrough_seed<N>.jsonl`. Analysis without reruns —
`tools/run_log.py` (see `docs/testing.md`).

## Building a release

CI builds a release on a `v*` tag: it checks the tag against the project version, builds
Windows on a windows runner and Linux on ubuntu, runs the unpacked Linux archive (the
Windows build does not write to the console and is checked by hand) and uploads the
archives to Releases with notes from `CHANGELOG.md`. Decisions are in
[ADR-0013](docs/adr/0013-release-and-versioning.md).

The version lives in one place — `config/version` in `project.godot` — and is edited only
by a script: it also writes it into the export presets, where an empty version breaks the
Windows build.

```powershell
python tools/version.py                 # print the version
python tools/version.py --set 0.9.0     # set it everywhere
python tools/version.py --check v0.9.0  # check the tag against the version
```

The same can be built by hand — for example, to check the build before a tag. It needs
export templates of the same version as the engine (in the editor: "Project" →
"Manage Export Templates").

```powershell
python tools/export.py windows    # build/windows/elaction.exe
python tools/package.py windows   # dist/elaction-v0.9.0-windows.zip
python tools/smoke.py build/linux/elaction.x86_64   # run of the built build
python tools/render_icon.py       # redraw icon.ico
```

## Structure and style

Described in [`docs/conventions.md`](docs/conventions.md).

## License

The project code is MIT. Elevator Action is a trademark of Taito Corporation; the project
is not affiliated with the rights holder, the original game's assets are not used.

Models and textures by other authors are CC0 and CC-BY 3.0; who and what is in
[`CREDITS.md`](CREDITS.md).
