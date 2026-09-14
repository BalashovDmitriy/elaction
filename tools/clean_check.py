#!/usr/bin/env python3
"""Прогон проверок на чистой копии — так, как их видит CI.

CI клонирует репозиторий заново, и там нет ничего, чего нет в гите: ни папки
`.godot` с кэшем импорта, ни сгенерированных `*.translation`, ни локальных
настроек. Поэтому проверки, зелёные на рабочей машине, на чистом чекауте могут
упасть — ровно это и случилось в M8b: движок грузил переводы, которых на свежем
клоне ещё нет, потому что их делает сам импорт.

Скрипт раскладывает ревизию во временную рабочую копию (`git worktree`) и гоняет
там `godot_check.py` и `run_tests.py`. Незакоммиченные правки в неё не попадают —
в этом и смысл: проверяется то, что уедет в CI, а не то, что лежит на диске.

Прогон долгий: импорт ресурсов с нуля занимает минуты. Поэтому он не в хуках,
а запускается руками перед PR.

Запуск:
    python tools/clean_check.py              # HEAD
    python tools/clean_check.py origin/main  # любая ревизия, понятная git
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
    """Запускает git в папке проекта."""
    return subprocess.run(
        ["git", "-C", str(PROJECT_ROOT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def warn_if_dirty() -> None:
    """Предупреждает, что незакоммиченное в прогон не попадёт."""
    changed = git("status", "--porcelain").stdout.strip()
    if changed:
        count = len(changed.splitlines())
        print(
            f"Внимание: {count} файл(ов) с незакоммиченными правками — "
            "в прогон они не идут.",
            flush=True,
        )


def run_checks(worktree: Path) -> bool:
    """Гоняет проверки в чистой копии. True, если все прошли."""
    ok = True
    for check in CHECKS:
        print(f"\n== {check} на чистой копии ==", flush=True)
        completed = subprocess.run(
            [sys.executable, str(worktree / check)],
            cwd=worktree,
            check=False,
        )
        ok &= completed.returncode == 0
    return ok


def remove_worktree(worktree: Path) -> None:
    """Убирает временную копию, не роняя прогон из-за занятого файла."""
    if git("worktree", "remove", "--force", str(worktree)).returncode == 0:
        return
    shutil.rmtree(worktree, ignore_errors=True)
    git("worktree", "prune")


def main(argv: list[str]) -> int:
    use_utf8_output()
    revision = argv[0] if argv else "HEAD"

    resolved = git("rev-parse", "--short", revision)
    if resolved.returncode != 0:
        print(f"Не понимаю ревизию «{revision}»: {resolved.stderr.strip()}")
        return 2

    warn_if_dirty()
    worktree = Path(tempfile.mkdtemp(prefix="elaction-clean-"))
    # mkdtemp уже создал папку, а git worktree add требует, чтобы её не было.
    worktree.rmdir()

    added = git("worktree", "add", "--detach", str(worktree), revision)
    if added.returncode != 0:
        print(f"Не удалось развернуть чистую копию: {added.stderr.strip()}")
        return 2

    print(f"Чистая копия {revision} ({resolved.stdout.strip()}) в {worktree}", flush=True)
    try:
        ok = run_checks(worktree)
    finally:
        remove_worktree(worktree)

    print("\nНа чистой копии всё прошло." if ok else "\nНа чистой копии проверки провалены.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
