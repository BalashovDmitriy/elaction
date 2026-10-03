# Project conventions

## Repository structure

```
elaction/
├─ project.godot          engine settings
├─ icon.svg               project icon
├─ src/                   all game code and scenes
│  ├─ main.tscn|gd        entry point
│  ├─ actors/             Otto, enemies, bullets — everything that lives and moves
│  ├─ systems/            elevators, doors, lighting, score — mechanics
│  ├─ levels/             floors, buildings, test scenes
│  ├─ ui/                 HUD, menus, screens
│  └─ autoload/           singletons (game state, sound, screenshots)
├─ assets/                sprites, sound, fonts
├─ tests/                 GUT tests
├─ tools/                 developer scripts (Python, PowerShell)
├─ docs/                  epic, ADRs, notes
└─ .github/workflows/     CI
```

A scene and its script sit side by side and share a name: `src/actors/otto/otto.tscn` and
`src/actors/otto/otto.gd`.

## Naming

| What | Style | Example |
|---|---|---|
| Scene and script files | `snake_case` | `elevator_car.gd` |
| Classes (`class_name`) | `PascalCase` | `ElevatorCar` |
| Nodes in a scene | `PascalCase` | `FloorShape` |
| Functions and variables | `snake_case` | `set_response_delay()` |
| Private members | leading underscore | `_aligned_floor` |
| Constants | `SCREAMING_SNAKE_CASE` | `SLAB_THICKNESS` |
| Signals | `snake_case`, past tense | `document_taken` |
| Folders | `snake_case`; sections in the plural, inside them by entity or topic | `actors/`, `systems/`; `otto/`, `lighting/` |

## GDScript

- **Types are mandatory.** Arguments, return values, class fields — everything is annotated.
  Type inference via `:=` is allowed where the type is obvious from the right-hand side.
- **Order in a file** (checked by `gdlint`): `@tool` → `class_name` → `extends` →
  `##` documentation → signals → enums → constants → static fields → `@export` →
  public fields → private fields → `@onready` → functions. The order is set in `.gdlintrc`.
- **Indentation is tabs**, line length is 100 characters. `gdformat` takes care of this,
  nothing needs to be aligned by hand.
- **Documentation** of classes and public methods is written as `##` comments; they end up
  in the editor's built-in help.
- **Nodes are obtained via `%UniqueName`** or `@onready var x: Type = $Path`, not by strings
  at the call site.
- **No `get_node()` in `_process`** — cache references in `@onready`.
- **A new `class_name` is not visible to the engine until the project is reimported:** a
  scene that refers to it silently returns `null`. The fix is
  `python tools/godot_check.py` — it imports the project.

## Scenes

- One scene, one responsibility. An enemy is not assembled inside a floor scene.
- Interaction between unrelated systems goes through signals, including signals of the
  `GameState` autoload in `src/autoload/`, not through `get_parent().get_parent()`.
  There is no separate event bus.
- A scene's public interface is its `@export` fields and signals.

## Tests

- The framework is GUT, tests live in `tests/`, a file is named `test_<what_is_tested>.gd`.
- We test game logic: state machines, score, transition conditions, elevator–platform
  interaction. Rendering and animations are not tested.
- A new mechanic arrives together with a test.

## Git

- **Branches:** `feat/m2-elevators`, `fix/elevator-crush`, `chore/ci-cache`, `docs/epic-update`.
  No direct pushes to `main`.
- **Commits:** Conventional Commits.

  ```
  feat(elevator): control the cab from a floor

  The cab responds to move_up and move_down when Otto is inside.
  The stop is aligned to the nearest floor.
  ```

- **Pre-commit checks** are run by hooks automatically. A full manual run is
  `tools/check.ps1` (Windows) or `tools/check.sh`.
- **PRs** are merged only with green CI.

## Finishing a milestone

A milestone is not considered closed until all five are done:

1. **Screenshots** — `python tools/capture.py <milestone>`. Shots go into
   `screens/<milestone>/` and serve as material for comparing milestones and analysing
   picture problems. The folder is not committed. A single shot at any moment is the
   **F12** key. Then `python tools/compare_original.py <milestone>` — the shot next to the
   original, `screens/<milestone>/compare_original.jpg`.

   Lighting, combat and menus are not captured by this script: a dark floor and an agent's
   stance happen not on schedule but from a shot-down lamp and a flying bullet, and the
   script does not press menu buttons. They are captured by state with
   `tools/dark_shot.tscn`, `tools/combat_shot.tscn`, `tools/ui_shot.tscn` and other
   `tools/*_shot.tscn`.
2. **Code review** — `/code-review xhigh --fix`. High thoroughness, the problems found are
   applied to the working copy right away.
3. **Re-running the checks** after the review fixes — `tools/check.ps1`.
4. **Tests strengthened** — not only for the milestone's mechanics but also for the whole
   building, on many seeds ([testing.md](testing.md)).
5. **`README.md` is up to date** — status, controls, the list of what works. It is the only
   document read from outside the project, and it goes stale first.

Only after that is a PR opened.

## What to run

| Task | Command |
|---|---|
| Open the project | `godot --path .` or `godot -e` |
| Run the game | `godot --path .` |
| All checks | `tools/check.ps1` |
| Format only | `.venv/Scripts/gdformat src tests tools` |
| Lint only | `.venv/Scripts/gdlint src tests tools` |
| Engine check | `python tools/godot_check.py` |
| Tests | `python tools/run_tests.py` |
| Milestone screenshots | `python tools/capture.py M1` |
| Run all hooks | `.venv/Scripts/pre-commit run --all-files` |
