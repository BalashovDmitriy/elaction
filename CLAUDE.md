# elaction — project rules

A remake of the arcade game Elevator Action (Taito, 1983). Mechanics as in the original,
graphics modern: a 3D scene with a side-on orthographic camera and dynamic lighting
([ADR-0019](docs/adr/0019-3d-pivot.md)).

**Before doing anything, read [`docs/STATUS.md`](docs/STATUS.md)** — it has the current
milestone, what is done and what is next. The full plan is in [`docs/EPIC.md`](docs/EPIC.md),
the results of completed milestones are in [`docs/milestones.md`](docs/milestones.md).

## Stack

| | |
|---|---|
| Engine | Godot 4.7.2 (`winget install --id GodotEngine.GodotEngine`) |
| Language | GDScript, **static typing is mandatory** |
| Tests | GUT 9.6.1, vendored in `addons/gut` |
| Linters | gdtoolkit 4.5.0 (`gdlint`, `gdformat`) in `.venv` |
| Hooks | pre-commit 4.6.2, on commit and on push |

Docker is not used in the project and is not to be proposed — see
[ADR-0003](docs/adr/0003-no-docker.md).

## Commands

```powershell
tools/check.ps1                 # format, lint, engine and tests — same as CI
python tools/run_tests.py       # GUT tests
python tools/godot_check.py     # resource import and script parsing by the engine
python tools/capture.py M1      # milestone screenshots into screens/M1/
python tools/compare_original.py M1  # milestone shot next to the original
godot --path .                  # run the game
godot -e --path .               # open the editor
```

Godot is looked up in the order `$GODOT_BIN` → PATH → winget paths; on Windows
`godot_console.exe` is used, because the regular build does not write to the console.

## Hard rules

1. **Types everywhere.** Arguments, return values, fields, loop variables.
   Checked by the engine, not by `gdlint` (it has no rule for types): in `project.godot`
   an untyped declaration is a parse error, caught by `godot_check.py` and CI.
2. **No direct pushes to `main`.** One branch per milestone or task: `feat/m2-elevators`,
   `fix/elevator-crush`, `chore/ci-cache`. A PR is merged only with green CI.
   The `gh` CLI is not installed — the user opens and merges PRs on the web.
3. **Conventional Commits:** `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
4. **The status is updated in every commit that touches `src/`, `tests/` or
   `project.godot`.** The `status-updated` hook checks this; without an edit to
   `docs/STATUS.md` the commit does not pass.
5. **Checks are not bypassed.** No `--no-verify`. If a hook fails, fix the cause.
6. **Decisions are recorded as ADRs** in `docs/adr/` if they affect the architecture.
7. **Clarifying questions before every milestone.** First check the mechanics against the
   original, then ask about the disputed points, and only then write code. More in
   "Starting a milestone" below.
8. **Project documentation and code comments are written in English.** Conversation with
   the user stays in Russian.

## Starting a milestone

Before writing the milestone's code:

1. **Check the mechanics against the original** using the available sources and record
   the findings. On M2, M3 and M4 the check changed the milestone's scope each time — it
   is cheaper to learn this before implementation than to redo it.
2. **Ask clarifying questions** about the disputed points and wait for the answers. Ask
   about things where different answers lead to different work: milestone scope,
   deviations from the original, the choice between "as in 1983" and playability.
3. **Record the decisions as ADRs** in `docs/adr/` and update `docs/EPIC.md`
   and `docs/STATUS.md`.

## Finishing a milestone

A milestone is not closed until all five items are done:

1. `python tools/capture.py <milestone>` — screenshots into `screens/<milestone>/`. The
   folder is local and does not go into the repository. A single in-game shot is **F12**.
   Then `python tools/compare_original.py <milestone>` — the shot next to the original at
   the same height, `screens/<milestone>/compare_original.jpg`. Differences spotted by eye
   are written into the plan: into this milestone or a future one.
2. `/code-review xhigh --fix` — a high-thoroughness code review with fixes applied
   automatically.
3. `tools/check.ps1` again after the review fixes.
4. **Tests strengthened.** Each milestone must not only add tests for its own mechanics
   but also tighten the whole-level check: the building is generated, so the check is not
   "this level works" but "any building that gets generated works".
   More in [`docs/testing.md`](docs/testing.md).
5. **`README.md` is up to date.** It is the only document read from outside the project,
   and it goes stale first: status, controls, the list of what already works.
   Check it before every PR, not when it comes to mind.

Only then the PR.

## Structure

```
src/main.tscn   root scene: menu, HUD, building
src/actors/     Otto and agents
src/systems/    elevators, escalators, doors, combat and bullets, lighting, actor assets,
                camera, settings, graphics, high scores
src/levels/     building: layout, finishing, dressing, roof; city and weather
src/ui/         HUD, menus
src/autoload/   singletons: Screenshotter, Game (score and session), Sound
assets/         models, textures, sound, fonts, translations
tests/          GUT tests, test_*.gd files
tools/          Python developer scripts and GDScript tool scenes
docs/           STATUS.md, EPIC.md, milestones.md, conventions.md, testing.md,
                adr/, reference/
```

A scene and its script sit side by side and share a name: `otto.tscn` and `otto.gd`.
Detailed naming and style conventions are in [`docs/conventions.md`](docs/conventions.md).

## What not to do

- Do not change render settings in `project.godot` without an ADR — they are tied to the
  chosen look: currently [ADR-0030](docs/adr/0030-grading-and-quality.md) and
  [ADR-0034](docs/adr/0034-ultra-and-auto-quality.md). ADR-0002, which the rule referred
  to earlier, is superseded by [ADR-0019](docs/adr/0019-3d-pivot.md).
- Do not run the formatter and linter on `addons/`, it is vendored code.
- Do not commit `screens/`, `.venv/`, `.godot/`.
- Do not add C# — the decision is recorded in [ADR-0001](docs/adr/0001-tech-stack.md).
