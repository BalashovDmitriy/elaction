#!/usr/bin/env python3
"""Fingerprint of the tree on which `check.ps1` passed in full.

The push hook ran the same set as `check.ps1` — engine parsing and all the GUT
tests, three minutes — even when `check.ps1` had just passed on the very same
code. What is cut here is the repetition, not the check:

- after a green run `check.ps1` writes the fingerprint (`--write`);
- the push hook runs the check via `--run`, and if the tree has not changed
  in any file since then, skips it with a message, otherwise runs it as before.

The fingerprint is a hash of the whole working copy tree: committed, modified and new,
without what `.gitignore` ignores. It does not depend on commits: a check
that passed before a commit is still valid after it, as long as the file contents are the
same. It lives in `.git/`, so it never gets into the repository.

Run:
    python tools/check_stamp.py --write
    python tools/check_stamp.py --run python tools/run_tests.py
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

from godot_bin import PROJECT_ROOT, use_utf8_output


def _git(*args: str, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        ["git", *args], cwd=PROJECT_ROOT, env=env, capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


def stamp_path() -> Path:
    return Path(_git("rev-parse", "--absolute-git-dir")) / "elaction-check-stamp"


def fingerprint() -> str:
    """Hash of the working copy tree, as if everything in it were committed.

    Built in a temporary index so as not to touch the real one: `git add -A`
    into it and `git write-tree`. The same content gives the same hash.
    """
    with tempfile.TemporaryDirectory() as folder:
        env = dict(os.environ)
        env["GIT_INDEX_FILE"] = str(Path(folder) / "index")
        _git("add", "-A", env=env)
        return _git("write-tree", env=env)


def write() -> int:
    stamp_path().write_text(fingerprint() + "\n", encoding="utf-8")
    return 0


def is_fresh() -> bool:
    path = stamp_path()
    return path.exists() and path.read_text(encoding="utf-8").strip() == fingerprint()


def run(command: list[str]) -> int:
    if is_fresh():
        print(f"Пропуск: {' '.join(command)} — это дерево уже проверено check.ps1.")
        return 0
    return subprocess.run(command, cwd=PROJECT_ROOT).returncode


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Отпечаток дерева, прошедшего check.ps1.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true", help="записать отпечаток текущего дерева")
    group.add_argument("--run", nargs=argparse.REMAINDER, help="команда, которую пропустить на проверенном дереве")
    args = parser.parse_args()
    if args.write:
        return write()
    if not args.run:
        parser.error("--run требует команду")
    return run(args.run)


if __name__ == "__main__":
    sys.exit(main())
