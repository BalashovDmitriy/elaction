# How the project is checked

Three levels of checking, from cheap to expensive. All three run in the common run
`python tools/run_tests.py`, which is also what runs on push and in CI.

**The repeat on push is skipped.** After a green run, `tools/check.ps1` records a
fingerprint of the working copy — a tree hash of all files, committed or
not — and the push hook skips the engine parse and the tests if not a single file
has changed since then (`tools/check_stamp.py`). If even one file has changed, the hook
runs everything, as before. The check is not bypassed, it is just not repeated: three
minutes of the same suite on the same tree added nothing.

## 1. Rules without a scene

State machines, building layout, death rules, score. They are pulled out into separate
classes (`OttoStateMachine`, `ElevatorMotion`, `DoorVisit`, `EnemyBrain`, `BuildingPlan`
and others) that know nothing about nodes or physics.

This is the bulk of the tests and the first place a check for a new mechanic goes.
The convention is simple: **a new mechanic arrives together with a test**.

## 2. Building properties over many seeds

The building is a pure function of the seed, so the check is not "this level works"
but "any building that gets generated works". These tests run generation on
dozens of seeds and guard invariants:

- every floor is served by a shaft, the bands do not overlap;
- every band junction has an escalator;
- an escalator opening does not lie between an elevator and its landing;
- all documents and the exit are reachable from the start point;
- nothing stands in the same place as something else.

Three M5a bugs — the opening between an elevator and its landing, the exit at the respawn
point and a silently vanishing document — did not show on every seed. On seed 1 they were
not visible.

## 3. Assembly and playthrough

The most expensive level: the building is assembled for real, with physics.

- **Assembly smoke test** — the level is built for several seeds, a few physics frames
  are stepped: it does not crash, Otto stands on the floor, the cabs are on their floors.
  It catches a mismatch between the layout and the code that places it.
- **Bot** — drives Otto through the building and checks that the building is actually
  completable: documents are collected, the exit triggers. It has three buildings: a small
  one on five seeds (cheap, and catches degenerate layouts), a real thirty-floor one and
  a real one **with agents** — the last one is the DoD of milestone M11, i.e. a check of
  combat balance, not geometry.

**The bot is driven by state, not by time.** Not "hold right for 3.5 seconds", but
"hold right until you get there". Timing-based tests broke in this project four times
in a row — in the capture scenarios — and each time silently captured something other
than what they promised.

## 4. The measuring tool itself

The bot is code too, and a bug in it looks like a conclusion about the game.

In M11 it did not fire a single shot during the whole milestone: Otto reads shooting and
jumping on the press edge, and the bot released and pressed the action in the same
frame — the engine sees no such edge. Walking and crouching are held, so they worked,
while one-off actions vanished entirely. Four rows of measurements in a row described a
game in which Otto can only crouch, and combat numbers almost got changed based on them.

Hence the rule: **a measuring tool must have its own test, and it must check the
result, not the intent.** `test_bot_fights.gd` does not look at whether the bot pressed
"fire" — it requires that the agent in the line of fire dies.

There was an indirect sign in the measurements themselves: zero agents killed in every
row of the table. A number that no change moves is not a result but a broken
pipeline.

**In tests the bot steers half as often as a player.** GUT's `wait_physics_frames(1)`
waits not one frame but two: inside it is `_elapsed_frames > _wait_physics_frames`.
So for every bot decision the world advances two physics frames, and the bot overshoots
any tolerance smaller than the distance covered in two frames.

Milestone M13 tripped over exactly this: an elevator cab is snapped to a floor only if
it is closer than `settle_distance`, and that stayed at the old scale — 12 units versus
36 per two frames. The cab froze 24 units below the floor, Otto ended up inside the
slab and stopped moving. In a manual run (`tools/playthrough.gd`, one frame per decision)
everything passed; in the tests it got stuck dead.

Hence the rule: **tolerances in the world must not be smaller than the distance covered
in two frames under `Engine.time_scale`**. A bot run is not only a completability check
but also the coarsest control loop the game will ever face.

The step length is confirmed by measurement and pinned by a test
(`test_a_tick_is_two_physics_frames`): it is defined by the behaviour of someone else's
code and may silently change with a GUT update. It must be counted by the engine,
`Engine.get_physics_frames()`, not by your own `physics_frame` handler: handlers run in
connection order, GUT's awaiter is connected earlier and wakes the coroutine right inside
the emission, so your own counter undercounts by one frame.

**Ragdoll under test speed-up (M24g).** `Engine.time_scale = 4` lengthens not only
the frame but also the physics step: on a four times longer step the corpse's joints
fly apart and the body falls through the floor. So the corpse tests, along with the
speed-up, raise `Engine.physics_ticks_per_second` to 240 — the step stays the
game's 1/60 s — and restore 60 in `after_all`. The other tests do not do this: corpses
there are decoration, and their flight does not affect the check. Jolt physics
computes in several threads, and the body comes to rest slightly differently from run
to run: corpse checks measure the essence ("the upper one's pelvis is above the lower
one's pelvis", "the centres of the parts are no farther than a radius from the wall"),
not the exact position, and let the body settle before measuring.

**The second rule, from M18a: the measuring tool and the test must drive Otto
the same way.** `tools/playthrough.gd` stepped one frame per decision, while the tests
stepped two. Both numbers were called "frames" but meant different things, and a budget
set from the tool's measurement meant half as much in the test. Seed 2 "did not
complete the building" in the test while completing it in the tool — and three commits
in a row explained this first by the route length on the graph, then by combat balance.

The M13 rule itself worked as promised. On the same milestone it found
a real bug: the bot waited for the cab 0.81 m from the shaft axis, its edge ended up
at 0.54 m, and the cab takes up 0.6 m. A cab rising from below caught it with its
roof and carried it up, and the roof cannot be controlled — the result was an endless
loop. The tolerance again turned out smaller than the size, and it was precisely the
coarse loop that caught it.

**The third rule, from M18b: the building's progress is counted in physics steps, not
frames.** The bot run on seed 1 did not reproduce — the test gave four deaths one time
and five another, with the same number of steps — and the explanation was sought in
combat. The cause was in the loop: the agent release at doors and Otto's return timer
lived in `_process`, i.e. ran on wall-clock time, while the bot drives Otto in physics
steps. On a fast machine more agents came out of the doors during the same bot step
than on a slow one, and the same building ended up with different difficulty.

Hence the rule: **everything that affects the outcome of a session comes from
`_physics_process` and from `SceneTreeTimer` counting in physics.** `_process` keeps the
picture — for us that is, for example, turning off lamps and light shafts off-screen,
the camera, the weather and the HUD. The sign of a violation is simple:
the result of a run changes from launch to launch, while nobody touched the game's
numbers.

There is almost never just one culprit. After the first fix seed 1 still gave
four deaths one time and three another — **with the same number of steps**, i.e. along
the same route. The same path and a different death count mean that what changed was
not navigation but combat; what remained was the siren, which `GameState` ticked
in `_process`. Agent anger and cab delay depend on it, so the building came out
sometimes meaner, sometimes kinder. **Search by symptom:** steps diverged — navigation
diverged; steps matched, deaths diverged — combat diverged.

The second M11 bug was found not by a check but by **the capture tool**: `combat_shot.gd`
waited for the "lying" pose, and instead the agent died again and again. It turned out
that an agent who dodged straightens up while the bullet is still inside its bounds, and
catches it with its chest ([ADR-0016](adr/0016-combat-balance.md)). A tool that waits for
a state is also a check that the state happens at all.

## The run goes in shards

`python tools/run_tests.py` spreads the tests over Godot processes — one per core,
but no more than six: on the switch to shards the suite went **139 s versus 755**
(now, at 60 files and 66 units, about 170 s). The design rests on
one measurement, not a guess — it was made by `tools/test_times.py --by-test` (since M24j
the measurement is `python tools/run_tests.py --batch-cost 0`, see below):

| Unit | Was, s |
|---|---|
| `test_bot_survives_the_real_building_with_agents` | 328 |
| `test_bot_finishes_the_real_building` | 188 |
| `test_bot_finishes_every_building` | 60 |
| `test_building_architecture.gd` | 54 |
| the other 46 files | 1.4–36, ~190 in total |

Everything else follows from this:

- **Splitting by files is useless.** One test method weighed 40% of the suite, and a shard
  cannot split a file: six shards gave 574 s versus 755. So both
  expensive tests are cut **by seed** into separate tests, and the run's floor dropped
  from 328 s to ~120. As a bonus, a failed seed is now visible by the test name.
- **A unit of work is a file or one test in it.** GUT accepts
  `-gunit_test_name`, so a file can be split without touching its contents;
  the price is a separate process for each such piece.
- **An empty `-gconfig=` is mandatory.** Otherwise `-gdir` is taken from `.gutconfig.json`,
  the whole `res://tests` is added to the shard's list, and every process runs the whole
  suite — six of them take the same eleven minutes.
- **Each shard gets its own `user://` folder.** `test_records` and `test_interface` write
  to it, and Godot has no flag for it — it is derived from `APPDATA`/`HOME`, and the run
  substitutes those itself.
- **The distribution is greedy, by measured numbers** (`KNOWN_SLOW`). If they drift,
  the run survives, the shards just become uneven; remeasuring is cheaper than guessing.

## Frames without a real clock (M24j)

Six shards loaded the CPU at 5–30 %, while the suite took six minutes: a test with a
scene waits for physics frames, and the engine hands them out by the real clock — 60 per
second, with the process sleeping in between. `Engine.time_scale = 4` lengthened the step
but did not make frames more frequent. With **`--fixed-fps 60`** a frame is exactly
1/60 s of game time, and the clock does not hold it back: a bot seed went **9 s versus
97**, the whole suite **about a minute versus 374 s**, with the same game — the physics
step and all its numbers are the same.

Hence the rule: **time in game code and in tests is measured in frames, not by the
clock.** "Real time" on top of world slow-down is `delta / Engine.time_scale`, not
`Time.get_ticks_msec()`: under `--fixed-fps` the clock and frames diverge, and an effect
timed by the clock would fade out after hundreds of frames or not start at all. The
camera shake and the takedown flash fell on this (moved to frames), and so did the
last-death test that waited by the clock (moved as well). The clock is only fine where
the second itself decides nothing: the alarm blinking in the HUD, swaying on the rope.

**Jobs go in a queue, not in a distribution made in advance.** There are as many
processes as CPU threads (`--jobs`, no more than 16), and a freed process takes the next
job — the heaviest of the remaining ones. A job is a split test, a known
heavy file or a batch of small files weighing up to `BATCH_COST`: an engine start costs
about two seconds, and a process per small file would eat more than its tests.
Weights are `KNOWN_SLOW`, measured with `python tools/run_tests.py --batch-cost 0
--slowest 120`, each file in its own process, under the same load as the run. The suite
is now bounded by the longest jobs — `test_car_corpses.gd` and the bot seeds, about 50 s
under full load; going further means only cutting them. `--real-time` runs on the real
clock, as before.

**In CI the suite runs as a matrix on three machines.** `run_tests.py --part K/N` splits
the units into N parts by a greedy distribution over `KNOWN_SLOW` and runs the K-th one,
and on the machine it again goes as a queue over its threads. Each machine does the
resource import itself: without `.godot/imported` the tests will not load a single scene.

**The other checks also use all threads.** `godot_check.py` parses
scripts in batches — an engine process loads a batch (`tools/check_scripts.gd`) — rather
than starting the engine per script: two hundred fifty starts in a row took two and a
half minutes, in batches eight seconds. Format and lint are `tools/gd_tools.py`,
in chunks and all at once: two seconds versus eleven. `check.ps1` as a whole takes about
a minute versus three and a half.

## A long run is watched as it goes

The suite takes about a minute, and one bot seed on the real building up to fifty
seconds under full load. There is no point waiting for the end to learn that
the bot got stuck in the third minute: it prints "bot is looping: N steps without
progress" right away, and then only
uses up the step budget.

So two rules:

- **Godot output is streamed.** `tools/godot_bin.run` passes lines out while the
  process is running instead of accumulating them until it ends. A run should be watched
  as it goes, roughly once a minute.
- **The watchdog stops the run on the first such line** (`STALLED_MARKERS`
  in `run_tests.py`). The run then counts as failed — the exit code is the same
  as for a timeout.

The watchdog does not replace the check: it saves minutes of waiting, but you still have
to figure out why the bot got stuck.

## What the tests do not check

Rendering, animations and "does it look good". For that there are the milestone
screenshots (`python tools/capture.py <milestone>`) — but they show, they do not check.
Everything that can be checked by a program is checked by a program.

## Run log

A failed bot run is investigated through the log, not by reruns with debug
printing (M24g: seed 3 cost ten reruns). `RunLog` writes each event as a line of JSON:
Otto's death with its cause (bullet, cab, fall), place, and who shot and from where,
hits, agent release and death, returns to play, rides, the bot's decision changes.

- The playthrough test with agents always writes it: `logs/playthrough_seed<N>.jsonl`.
- The run tool and the game write it on a flag: `--log=logs/run_{seed}.jsonl`
  (`{seed}` is the seed number) or the `ELACTION_LOG` environment variable.
- Analysis: `python tools/run_log.py FILE` — a summary (events, deaths by place and
  cause, where shots came from); `--deaths` — every death in full; filters
  `--kind`, `--floor`, `--from`/`--to` (seconds), `--around FRAME --span N`.

The `logs/` folder does not go into the repository.
