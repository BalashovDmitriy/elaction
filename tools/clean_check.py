#!/usr/bin/env python3
"""Runs the checks on a clean copy — the way CI sees them.

CI clones the repository afresh, and there is nothing there that is not in git: no
`.godot` folder with the import cache, no generated `*.translation`, no local
settings. So checks that are green on the work machine may fail on a clean checkout —
this is exactly what happened in M8b: the engine loaded translations that do not yet exist
on a fresh clone, because the import itself produces them.

The script checks out the revision into a temporary working copy (`git worktree`) and runs
`godot_check.py` and `run_tests.py` there. Uncommitted changes do not get into it —
that is the point: what is checked is what goes to CI, not what lies on disk.

The run is long: importing resources from scratch takes minutes. So it is not in the hooks,
but is run by hand before a PR.

Run:
    python tools/clean_check.py              # HEAD
    python tools/clean_check.py origin/main  # any revision git understands
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from godot_bin import PROJECT_ROOT, use_utf8_output

CHECKS = ("tools/godot_check.py", "tools/run_tests.py")


def git(*args: str) -> subprocess.CompletedProcess[str]:
    """Runs git in the project folder."""
    return subprocess.run(
        ["git", "-C", str(PROJECT_ROOT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def warn_if_dirty() -> None:
    """Warns that uncommitted changes do not get into the run."""
    changed = git("status", "--porcelain").stdout.strip()
    if changed:
        count = len(changed.splitlines())
        print(
            f"Warning: {count} file(s) with uncommitted changes — "
            "they are not part of the run.",
            flush=True,
        )


def run_checks(worktree: Path) -> bool:
    """Runs the checks in a clean copy. True if all passed."""
    ok = True
    for check in CHECKS:
        print(f"\n== {check} on a clean copy ==", flush=True)
        completed = subprocess.run(
            [sys.executable, str(worktree / check)],
            cwd=worktree,
            check=False,
        )
        ok &= completed.returncode == 0
    return ok


def remove_worktree(worktree: Path) -> None:
    """Removes the temporary copy without failing the run because of a busy file."""
    if git("worktree", "remove", "--force", str(worktree)).returncode == 0:
        return
    shutil.rmtree(worktree, ignore_errors=True)
    git("worktree", "prune")


def main(argv: list[str]) -> int:
    use_utf8_output()
    revision = argv[0] if argv else "HEAD"

    resolved = git("rev-parse", "--short", revision)
    if resolved.returncode != 0:
        print(f"Cannot resolve revision '{revision}': {resolved.stderr.strip()}")
        return 2

    warn_if_dirty()
    worktree = Path(tempfile.mkdtemp(prefix="elaction-clean-"))
    # mkdtemp has already created the folder, and git worktree add requires it not to exist.
    worktree.rmdir()

    added = git("worktree", "add", "--detach", str(worktree), revision)
    if added.returncode != 0:
        print(f"Failed to create a clean copy: {added.stderr.strip()}")
        return 2

    print(f"Clean copy of {revision} ({resolved.stdout.strip()}) in {worktree}", flush=True)
    try:
        ok = run_checks(worktree)
    finally:
        remove_worktree(worktree)

    print("\nEverything passed on the clean copy." if ok else "\nChecks failed on the clean copy.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
