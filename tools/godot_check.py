#!/usr/bin/env python3
"""Checking the project with the Godot engine.

Godot can do what gdlint and gdformat cannot: import resources, link
scenes to scripts and catch real parse errors. The script runs
`godot --headless --import`, then `--check-only` on every .gd.

Godot often exits with code 0 even when scripts have errors, so the output
is additionally scanned for error markers.

Scripts are parsed in batches: an engine process loads a batch of scripts
(`tools/check_scripts.gd`), and batches run at once, as many as there are CPU threads.
Loading compiles a script with everything it depends on, the same as
`--check-only`; with one run per script, in sequence, two hundred and fifty
engine starts took two and a half minutes at 10–15 % CPU (M24j). The import
is a single one and comes before them: parsing reads already imported resources.

Run:
    python tools/godot_check.py              # full check
    python tools/godot_check.py --no-scripts # resource import only
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

SCRIPT_DIRS = ("src", "tests", "tools")

ERROR_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"SCRIPT ERROR", re.IGNORECASE),
    re.compile(r"Parse Error", re.IGNORECASE),
    re.compile(r"Failed to load script", re.IGNORECASE),
    re.compile(r"Failed loading resource", re.IGNORECASE),
    re.compile(r"Cannot open file", re.IGNORECASE),
    re.compile(r"Invalid call", re.IGNORECASE),
)


def find_errors(output: str) -> list[str]:
    """Returns output lines that look like errors."""
    return [
        line.strip()
        for line in output.splitlines()
        if any(pattern.search(line) for pattern in ERROR_PATTERNS)
    ]


def import_resources(godot: str) -> tuple[int, str]:
    """Imports resources. On a clean checkout, in two passes.

    `project.godot` loads `res://assets/i18n/*.translation` at engine startup,
    and these files are produced by the same import, from `assets/i18n/ui.csv`. The files
    are generated and in `.gitignore` (as the standard Godot.gitignore prescribes),
    so on a fresh clone the first pass always complains that they are missing,
    although by the end of the pass they are already in place.

    A real resource breakage does not go away on the second pass either, so
    the repeat hides nothing: we judge by it.
    """
    code, output = run(godot, ["--headless", "--import"])
    if not find_errors(output):
        return code, output

    print("  ..   first import had errors — repeating on the ready resources")
    return run(godot, ["--headless", "--import"])


def gd_scripts() -> list[Path]:
    scripts: list[Path] = []
    for directory in SCRIPT_DIRS:
        scripts.extend(sorted((PROJECT_ROOT / directory).rglob("*.gd")))
    return scripts


# How many batches per CPU thread: batches are uneven, one drags half the project's
# dependencies along and another does not, and small ones share the tail more evenly.
CHUNKS_PER_THREAD = 2

CHECKER = "res://tools/check_scripts.gd"


def check_scripts(godot: str) -> bool:
    """Parses all scripts in batches; prints the failed ones and the total."""
    scripts = [f"res://{path.relative_to(PROJECT_ROOT).as_posix()}" for path in gd_scripts()]
    count = max(1, min(len(scripts), (os.cpu_count() or 1) * CHUNKS_PER_THREAD))
    piles = [scripts[index::count] for index in range(count)]

    def check(pile: list[str]) -> tuple[list[str], int, str]:
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as listing:
            listing.write(chr(10).join(pile))
        try:
            code, output = run(
                godot, ["--headless", "-s", CHECKER, "--", listing.name], echo=False
            )
        finally:
            os.unlink(listing.name)
        return pile, code, output

    ok = True
    checked = 0
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        for pile, code, output in pool.map(check, piles):
            passed = {
                line.split(" ", 2)[2].strip()
                for line in output.splitlines()
                if line.startswith("CHECK OK ")
            }
            checked += len(passed)
            missing = [path for path in pile if path not in passed]
            errors = find_errors(output)
            if code == 0 and not missing and not errors:
                continue
            ok = False
            for path in missing:
                print(f"  FAIL parse {path.removeprefix('res://')}")
            if not missing:
                print(f"  FAIL parse of a batch of {len(pile)} scripts (exit code {code})")
            for line in errors[:20]:
                print(f"       {line}")
    if ok:
        print(f"  OK   parsed {checked} scripts")
    return ok


def report(step: str, code: int, output: str) -> bool:
    """Prints a step result. Returns True if the step succeeded."""
    errors = find_errors(output)
    if code == 0 and not errors:
        print(f"  OK   {step}")
        return True

    print(f"  FAIL {step} (exit code {code})")
    for line in errors[:20]:
        print(f"       {line}")
    if not errors and output.strip():
        for line in output.strip().splitlines()[-10:]:
            print(f"       {line}")
    return False


def main(argv: list[str]) -> int:
    use_utf8_output()
    godot = require_godot()
    print(f"Godot: {godot}")
    ok = True

    code, output = import_resources(godot)
    ok &= report("resource import (--import)", code, output)

    if "--no-scripts" not in argv:
        ok &= check_scripts(godot)

    print("Check passed." if ok else "Check failed.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
