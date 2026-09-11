#!/usr/bin/env python3
"""Не даёт закоммитить изменения игры без обновления статуса разработки.

`docs/STATUS.md` — точка входа для новой сессии: текущая веха, что работает, что
дальше. Если он отстаёт от кода, следующая сессия начинается с археологии.
Поэтому коммит, трогающий `src/`, `tests/` или `project.godot`, обязан обновить
и статус.

Правки только в документации, тулинге или CI проверку не требуют.

Запуск: хуком pre-commit, либо вручную `python tools/check_status.py`.
"""

from __future__ import annotations

import subprocess
import sys

from godot_bin import PROJECT_ROOT, use_utf8_output

STATUS_FILE = "docs/STATUS.md"

# Пути, изменение которых означает «разработка продвинулась».
WATCHED_PREFIXES = ("src/", "tests/")
WATCHED_FILES = ("project.godot",)

# Вендоренный код живёт внутри отслеживаемых папок, но нашим прогрессом не является.
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
