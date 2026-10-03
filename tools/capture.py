#!/usr/bin/env python3
"""Game screenshots for analysis after a playable milestone.

Launches the game with the argument `--capture=<milestone>`. The Screenshotter autoload
runs a short milestone script (each has its own, see AUTO_PLANS), saves
a frame per step and closes the game.

Shots go to `screens/<milestone>/<time>_<step>.jpg`.

Important: real rendering, not headless — a screen is needed. Not run in CI.

Run:
    python tools/capture.py M1
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

SCREENS_ROOT = PROJECT_ROOT / "screens"
TIMEOUT_SECONDS = 180


def existing_shots(folder: Path) -> set[Path]:
    return set(folder.glob("*.jpg")) if folder.is_dir() else set()


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Capture game screens for an epic milestone.")
    parser.add_argument("milestone", help="Milestone name, e.g. M1")
    args = parser.parse_args()

    godot = require_godot()
    folder = SCREENS_ROOT / args.milestone
    before = existing_shots(folder)

    code, output = run(
        godot, ["--", f"--capture={args.milestone}"], timeout=TIMEOUT_SECONDS
    )

    new_shots = sorted(existing_shots(folder) - before)
    for shot in new_shots:
        print(f"  {shot.relative_to(PROJECT_ROOT).as_posix()}")

    # The game closes itself after the script: any other exit code is a crash
    # in the middle of the run, and then the set of shots is incomplete, even if something
    # was captured.
    if code != 0:
        print(f"The game exited with code {code}, the set of shots is incomplete. Game output:")
        print(output.strip()[-2000:])
        return 1

    if not new_shots:
        print("No shots appeared. Game output:")
        print(output.strip()[-2000:])
        return 1

    print(f"Shots taken: {len(new_shots)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
