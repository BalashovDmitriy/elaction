#!/usr/bin/env python3
"""Отпечаток дерева, на котором `check.ps1` прошёл целиком.

Хук на push гонял тот же набор, что `check.ps1`, — разбор движком и все тесты
GUT, три минуты, — даже когда `check.ps1` только что прошёл на том же самом
коде. Здесь это повторение отсекается, а не проверка:

- `check.ps1` после зелёного прогона записывает отпечаток (`--write`);
- хук на push запускает проверку через `--run`, и если дерево с тех пор не
  менялось ни в одном файле, пропускает её с сообщением, иначе гоняет как раньше.

Отпечаток — хеш дерева рабочей копии целиком: закоммиченное, изменённое и новое,
без того, что игнорирует `.gitignore`. Он не зависит от коммитов: проверка,
прошедшая до коммита, годится и после него, пока содержимое файлов то же.
Лежит в `.git/`, поэтому в репозиторий не попадает никогда.

Запуск:
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
    """Хеш дерева рабочей копии, как если бы всё в ней закоммитили.

    Собирается во временном индексе, чтобы не трогать настоящий: `git add -A`
    в него и `git write-tree`. Одинаковое содержимое даёт один и тот же хеш.
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
