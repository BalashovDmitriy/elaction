#!/usr/bin/env python3
"""Finding and running Blender to build actor models.

A companion module to `godot_bin.py`: the same search order, the same way of
complaining when the tool is missing. Only `build_actors.py` needs it (ADR-0022,
decision 1): everything else in the game is geometry in code and materials, Blender is
not needed for them.

Search order: $BLENDER_BIN -> PATH -> Program Files -> winget paths.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

# What is shared with finding Godot is not rewritten: the timeout return code, converting
# output to text and UTF-8 on output are the same for both tools, and separate copies of
# these three would drift from the original at the very first change.
from godot_bin import TIMEOUT_EXIT_CODE, as_text, use_utf8_output

# The version the pipeline was built and checked on (ADR-0011).
EXPECTED_VERSION = "5.2"


def _program_files_candidates() -> list[Path]:
    """Installed as an msi package: winget does not put blender.exe into its Links."""
    roots: list[Path] = []
    for variable in ("ProgramFiles", "ProgramFiles(x86)"):
        value = os.environ.get(variable)
        if value:
            roots.append(Path(value))
    if not roots:
        roots.append(Path("C:/Program Files"))

    found: list[Path] = []
    for root in roots:
        # The expected version first, then everything else by descending name:
        # so 5.2 wins over 4.x even if both are installed.
        blender_root = root / "Blender Foundation"
        preferred = blender_root / f"Blender {EXPECTED_VERSION}" / "blender.exe"
        if preferred.exists():
            found.append(preferred)
        for candidate in sorted(blender_root.glob("Blender */blender.exe"), reverse=True):
            if candidate != preferred:
                found.append(candidate)
    return found


def find_blender() -> str | None:
    """Returns the path to the Blender executable, or None if it is not found."""
    from_env = os.environ.get("BLENDER_BIN")
    if from_env and Path(from_env).exists():
        return from_env

    found = shutil.which("blender")
    if found:
        return found

    installed = _program_files_candidates()
    if installed:
        return str(installed[0])

    winget_links = Path.home() / "AppData/Local/Microsoft/WinGet/Links" / "blender.exe"
    if winget_links.exists():
        return str(winget_links)

    packages = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    from_packages = sorted(packages.glob("BlenderFoundation*/**/blender.exe"), reverse=True)
    if from_packages:
        return str(from_packages[0])

    return None


def require_blender() -> str:
    """Like find_blender, but prints a hint and exits the process if Blender is missing."""
    blender = find_blender()
    if blender is None:
        print("Blender not found. Install it or set BLENDER_BIN=<path to blender>.")
        print("Windows: winget install --id BlenderFoundation.Blender")
        raise SystemExit(127)
    return blender


def run_script(blender: str, script: Path, args: list[str] | None = None, timeout: int = 600) -> tuple[int, str]:
    """Runs a script in Blender without a window and returns (return code, output).

    Arguments after `--` go to the script: Blender parses the command line up to this
    separator itself.
    """
    command = [blender, "--background", "--factory-startup", "--python", str(script)]
    if args:
        command += ["--", *args]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        output = as_text(expired.stdout) + as_text(expired.stderr)
        return TIMEOUT_EXIT_CODE, f"{output}\nBlender did not respond within {timeout} s and was killed."
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def version_of(blender: str) -> str:
    """The first line of `blender --version`, for example "Blender 5.2.1 LTS"."""
    completed = subprocess.run(
        [blender, "--version"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    first = (completed.stdout or "").strip().splitlines()
    return first[0].strip() if first else ""


def main() -> int:
    """`python tools/blender_bin.py` prints the Blender found and its version."""
    use_utf8_output()
    blender = require_blender()
    print(blender)
    print(version_of(blender))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
