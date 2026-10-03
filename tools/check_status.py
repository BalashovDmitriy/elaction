#!/usr/bin/env python3
"""Prevents committing game changes without updating the development status.

`docs/STATUS.md` is the entry point for a new session: the current milestone, what
works, what is next. If it lags behind the code, the next session starts with
archaeology. So a commit touching `src/`, `tests/` or `project.godot` must update the
status too.

Changes only to documentation, tooling or CI do not require the check.

Run: as a pre-commit hook, or manually `python tools/check_status.py`.
"""

from __future__ import annotations

import subprocess
import sys

from godot_bin import PROJECT_ROOT, use_utf8_output

STATUS_FILE = "docs/STATUS.md"

# Paths whose change means "development has progressed".
WATCHED_PREFIXES = ("src/", "tests/")
WATCHED_FILES = ("project.godot",)

# Vendored code lives inside tracked folders but is not our progress.
IGNORED_PREFIXES = ("addons/",)


def staged_files() -> list[str]:
    completed = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMRD"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=PROJECT_ROOT,
        check=True,
    )
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def is_watched(path: str) -> bool:
    if path.startswith(IGNORED_PREFIXES):
        return False
    return path.startswith(WATCHED_PREFIXES) or path in WATCHED_FILES


def main() -> int:
    use_utf8_output()

    staged = staged_files()
    watched = sorted(path for path in staged if is_watched(path))
    if not watched:
        return 0

    if STATUS_FILE in staged:
        return 0

    print(f"Коммит меняет игру, но не обновляет {STATUS_FILE}:")
    for path in watched[:10]:
        print(f"  {path}")
    if len(watched) > 10:
        print(f"  ... и ещё {len(watched) - 10}")
    print()
    print(f"Опишите в {STATUS_FILE}, что изменилось и что следующее, затем:")
    print(f"  git add {STATUS_FILE}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
