#!/usr/bin/env python3
"""Поиск и запуск исполняемого файла Godot.

Общий модуль для скриптов в `tools/`: godot_check.py, run_tests.py, capture.py.

Порядок поиска: $GODOT_BIN -> PATH -> стандартные пути установки winget.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Код возврата для «Godot не уложился в таймаут» — как у утилиты timeout(1).
TIMEOUT_EXIT_CODE = 124

# На Windows обычная сборка не пишет в родительскую консоль — нужен _console.
_BINARY_NAMES = ["godot_console", "godot"] if sys.platform == "win32" else ["godot"]


def find_godot() -> str | None:
    """Возвращает путь к исполняемому файлу Godot или None, если он не найден."""
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
    """Как find_godot, но печатает подсказку и завершает процесс, если Godot нет."""
    godot = find_godot()
    if godot is None:
        print("Godot не найден. Установите его или задайте GODOT_BIN=<путь к godot>.")
        print("Windows: winget install --id GodotEngine.GodotEngine")
        raise SystemExit(127)
    return godot


def as_text(value: str | bytes | None) -> str:
    """Вывод снятого по таймауту процесса: он бывает str, bytes и None сразу.

    На POSIX TimeoutExpired несёт то, что успело прочитаться, — байтами, а поток,
    в который никто не написал, остаётся None. Складывать их напрямую нельзя.
    """
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def run(godot: str, args: list[str], timeout: int = 600) -> tuple[int, str]:
    """Запускает Godot в папке проекта и возвращает (код возврата, объединённый вывод).

    Зависший Godot (например, модальное окно ошибки) снимается по таймауту и
    отдаётся как обычный неуспех с кодом TIMEOUT_EXIT_CODE, а не как traceback.
    """
    try:
        completed = subprocess.run(
            [godot, "--path", str(PROJECT_ROOT), *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        output = as_text(expired.stdout) + as_text(expired.stderr)
        return TIMEOUT_EXIT_CODE, f"{output}\nGodot не ответил за {timeout} с и был снят."
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def use_utf8_output() -> None:
    """Вывод в UTF-8 независимо от кодовой страницы консоли Windows."""
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
