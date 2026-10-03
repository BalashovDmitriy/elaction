#!/usr/bin/env python3
"""Run of a built binary: it must start, not just build.

Export returns 0 even when it has built something broken, so the build is checked by
running it ([ADR-0013](../docs/adr/0013-release-and-versioning.md), item 6).
We check three things at once:

1. **The startup marker.** The game prints `elaction <version> · <platform>` as the
   first line (`Release.banner`). A process that crashed on the first frame also exits
   with zero: without the marker it cannot be counted as "started".
2. **Not a single `SCRIPT ERROR`** or other breakage marker in the output.
3. **The binary survived to the end of the run**: either it exited by itself via
   `--quit-after`, or it was stopped by timeout after living the whole allotted time.
   Both outcomes are fine: what matters is that it did not die earlier.

    python tools/smoke.py build/linux/elaction.x86_64
    python tools/smoke.py build/linux/elaction.x86_64 --frames 600
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, as_text, use_utf8_output
from godot_check import find_errors
from version import read as project_version

# How many frames the game must live. 300 is five seconds at 60 FPS: the menu
# has time to build, the music to start and the autoloads to run.
DEFAULT_FRAMES: int = 300

# A time margin in case --quit-after does not work: frames still go on,
# and the time lived is a valid sign by itself.
TIMEOUT_SECONDS: int = 60


def marker() -> str:
    """The start of the startup line. The version is taken from project.godot, as everywhere."""
    return f"elaction {project_version()}"


def launch(binary: Path, frames: int) -> tuple[str, bool]:
    """Runs the binary. Returns the output and the "survived to the end of the run" flag."""
    command = [
        str(binary),
        "--headless",
        # There is no sound card on the runner, and without an explicit driver Godot looks for
        # one and complains: extra noise in the output that is easy to mistake for breakage.
        "--audio-driver",
        "Dummy",
        "--quit-after",
        str(frames),
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        # Streams of a killed process arrive in mixed forms, str, bytes or None,
        # so each is converted to a string separately (godot_bin.as_text).
        output = as_text(expired.stdout) + as_text(expired.stderr)
        # Stopped by timeout means it was alive all that time. This is success, not a failure.
        return output, True
    return (completed.stdout or "") + (completed.stderr or ""), completed.returncode == 0


def parse(argv: list[str]) -> tuple[list[str], int] | None:
    """Splits the arguments into paths and a frame count. None if parsing failed."""
    paths: list[str] = []
    frames = DEFAULT_FRAMES
    index = 0
    while index < len(argv):
        if argv[index] != "--frames":
            paths.append(argv[index])
            index += 1
            continue
        # Without an explicit check, "--frames" as the last argument crashes the script
        # with a traceback instead of a clear message.
        if index + 1 >= len(argv) or not argv[index + 1].isdigit():
            print("--frames needs a number of frames: python tools/smoke.py <build> --frames 600")
            return None
        frames = int(argv[index + 1])
        index += 2
    return paths, frames


def main(argv: list[str]) -> int:
    use_utf8_output()
    parsed = parse(argv)
    if parsed is None:
        return 2

    paths, frames = parsed
    if not paths:
        print("A path to the built build is needed: python tools/smoke.py build/linux/elaction.x86_64")
        return 2

    binary = Path(paths[0])
    if not binary.is_absolute():
        binary = PROJECT_ROOT / binary
    if not binary.exists():
        print(f"No such file: {binary}")
        return 2

    print(f"Run of {binary.name}: {frames} frames, marker '{marker()}'", flush=True)
    output, survived = launch(binary, frames)
    print(output.strip())

    errors = find_errors(output)
    started = marker() in output

    if not started:
        print(f"\nThe build did not print the startup line '{marker()}' — assuming it did not start.")
    if errors:
        print("\nThe output contains errors:")
        for line in errors[:20]:
            print(f"  {line}")
    if not survived:
        print("\nThe build exited with a non-zero code.")

    if started and survived and not errors:
        print("\nRun passed: the build started, ran and did not complain.")
        return 0

    print("\nRun failed.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
