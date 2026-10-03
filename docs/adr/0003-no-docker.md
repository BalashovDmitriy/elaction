# ADR-0003 · Docker is not used in the project

- **Status:** accepted
- **Date:** 2026-09-11

## Context

Question: does the project need Docker and, in particular, a multi-container configuration.

## Decision

**Docker is not used locally. There is no multi-container configuration.**

Reasons:

1. **Godot is a desktop GPU application.** The editor needs a display and a graphics card.
   On Windows there is no GPU passthrough into a container, and running the editor through a
   container means fiddling with an X server for zero benefit.
2. **There is nothing to split into containers.** The project has no database, broker, backend
   or network layer. Docker compose solves the problem of orchestrating several services, and
   there is exactly one service here — the game itself.
3. **Reproducibility is solved more cheaply.** The engine version is pinned in `project.godot`
   and in the `GODOT_VERSION` variable in CI, tooling versions in `requirements-dev.txt`.
   This is enough for the environment to match between the developer and CI.

## Where containers are still appropriate

- **CI.** GitHub Actions is isolated by itself, so a separate image is not needed:
  the workflow downloads the Linux build of Godot of the required version and runs it headless.
  If the build becomes heavy in the future, an option is our own image with the engine and
  export templates, so as not to download them on every run.
- **M10, online leaderboard.** If it appears, the project will get a real backend
  with a database. That is where docker compose fits — and then it will describe the
  leaderboard services, not the game.

## Consequences

- The developer needs Godot and Python installed locally. The entry threshold is minimal;
  installation is described in the README.
- If a second person with a different OS joins the team, the environment will have to be
  described more precisely. That is exactly the moment to revisit the decision, not earlier.
