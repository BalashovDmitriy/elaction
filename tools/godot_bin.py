#!/usr/bin/env python3
"""Finding and running the Godot executable.

A shared module for scripts in `tools/`: godot_check.py, run_tests.py, capture.py.

Search order: $GODOT_BIN -> PATH -> standard winget install paths.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import time
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Return code for "Godot did not finish within the timeout", as in the timeout(1) utility.
TIMEOUT_EXIT_CODE = 124

# On Windows the regular build does not write to the parent console: _console is needed.
_BINARY_NAMES = ["godot_console", "godot"] if sys.platform == "win32" else ["godot"]


def find_godot() -> str | None:
    """Returns the path to the Godot executable, or None if it is not found."""
    from_env = os.environ.get("GODOT_BIN")
    if from_env and Path(from_env).exists():
        return from_env

    for name in _BINARY_NAMES:
        found = shutil.which(name)
        if found:
            return found

    winget_links = Path.home() / "AppData/Local/Microsoft/WinGet/Links"
    for name in _BINARY_NAMES:
        candidate = winget_links / f"{name}.exe"
        if candidate.exists():
            return str(candidate)

    packages = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    for pattern in ("GodotEngine*/Godot*_win64_console.exe", "GodotEngine*/Godot*_win64.exe"):
        for candidate in sorted(packages.glob(pattern)):
            return str(candidate)

    return None


def require_godot() -> str:
    """Like find_godot, but prints a hint and exits the process if Godot is missing."""
    godot = find_godot()
    if godot is None:
        print("Godot not found. Install it or set GODOT_BIN=<path to godot>.")
        print("Windows: winget install --id GodotEngine.GodotEngine")
        raise SystemExit(127)
    return godot


def as_text(value: str | bytes | None) -> str:
    """Output of a process killed by timeout: it can be str, bytes and None at once.

    On POSIX TimeoutExpired carries what managed to be read, as bytes, and a stream
    nobody wrote to stays None. They cannot be concatenated directly.
    """
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def run(
    godot: str,
    args: list[str],
    timeout: int = 600,
    echo: bool = True,
    stop_on: tuple[str, ...] = (),
    env: dict[str, str] | None = None,
) -> tuple[int, str]:
    """Runs Godot in the project folder and returns (return code, combined output).

    **Output goes out line by line while the process runs.** The test suite runs for
    more than ten minutes, and the bot prints "looped" long before the last line:
    a silent run made you wait for the end where everything is clear by the third minute.

    [stop_on] is a watchdog: on seeing any of these lines in the output, the run is
    stopped immediately. There is nothing to wait for after it, and the waiting takes
    minutes.

    A hung Godot (for example, a modal error window) is stopped by timeout and
    returned as an ordinary failure with code TIMEOUT_EXIT_CODE, not as a traceback.
    """
    started = time.monotonic()
    process = subprocess.Popen(
        [godot, "--path", str(PROJECT_ROOT), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        # Shards need their own environment: Godot derives `user://` from APPDATA/HOME,
        # and without this two processes write to the same high-score file.
        env=env,
    )

    lines: list[str] = []
    assert process.stdout is not None
    for line in process.stdout:
        lines.append(line)
        if echo:
            # flush on every line: without it the pipe buffers the output itself, and the whole
            # point of streaming is lost.
            print(line, end="", flush=True)
        if any(mark in line for mark in stop_on):
            return _cut_short(process, lines, f"Run killed by the watchdog: {line.strip()}")
        if time.monotonic() - started > timeout:
            return _cut_short(process, lines, f"Godot did not respond within {timeout} s and was killed.")

    process.stdout.close()
    left = max(timeout - (time.monotonic() - started), 1.0)
    try:
        return process.wait(timeout=left), "".join(lines)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        return TIMEOUT_EXIT_CODE, "".join(lines) + f"\nGodot did not respond within {timeout} s and was killed."


def _cut_short(process: subprocess.Popen, lines: list[str], why: str) -> tuple[int, str]:
    """Stops the process and returns what it managed to say."""
    process.kill()
    if process.stdout is not None:
        process.stdout.close()
    process.wait()
    print(why, flush=True)
    return TIMEOUT_EXIT_CODE, "".join(lines) + "\n" + why


def use_utf8_output() -> None:
    """Output in UTF-8 regardless of the Windows console code page."""
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
