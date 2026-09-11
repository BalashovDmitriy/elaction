#!/usr/bin/env python3
"""Проверка проекта движком Godot.

Godot умеет то, чего не умеют gdlint/gdformat: импортировать ресурсы, связать
сцены со скриптами и поймать реальные ошибки разбора. Скрипт запускает
`godot --headless --import`, а затем `--check-only` по каждому .gd.

Godot нередко завершается с кодом 0 даже при ошибках в скриптах, поэтому вывод
дополнительно просматривается на маркеры ошибок.

Запуск:
    python tools/godot_check.py            # полная проверка
    python tools/godot_check.py --no-scripts   # только импорт ресурсов

Бинарь ищется в порядке: $GODOT_BIN -> PATH -> стандартные пути winget.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCRIPT_DIRS = ("src", "tests", "tools")
TIMEOUT_SECONDS = 600

ERROR_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"SCRIPT ERROR", re.IGNORECASE),
    re.compile(r"Parse Error", re.IGNORECASE),
    re.compile(r"Failed to load script", re.IGNORECASE),
    re.compile(r"Failed loading resource", re.IGNORECASE),
    re.compile(r"Cannot open file", re.IGNORECASE),
    re.compile(r"Invalid call", re.IGNORECASE),
)


def find_godot() -> str | None:
    """Возвращает путь к исполняемому файлу Godot или None."""
    from_env = os.environ.get("GODOT_BIN")
    if from_env and Path(from_env).exists():
        return from_env

    # На Windows обычная сборка не пишет в родительскую консоль — нужен _console.
    names = ["godot_console", "godot"] if sys.platform == "win32" else ["godot"]
    for name in names:
        found = shutil.which(name)
        if found:
            return found

    winget_links = Path.home() / "AppData/Local/Microsoft/WinGet/Links"
    for name in names:
        candidate = winget_links / f"{name}.exe"
        if candidate.exists():
            return str(candidate)

    packages = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    for pattern in ("GodotEngine*/Godot*_win64_console.exe", "GodotEngine*/Godot*_win64.exe"):
        for candidate in sorted(packages.glob(pattern)):
            return str(candidate)

    return None


def run_godot(godot: str, args: list[str]) -> tuple[int, str]:
    """Запускает Godot и возвращает (код возврата, объединённый вывод)."""
    completed = subprocess.run(
        [godot, "--headless", "--path", str(PROJECT_ROOT), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=TIMEOUT_SECONDS,
        check=False,
    )
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def find_errors(output: str) -> list[str]:
    """Возвращает строки вывода, похожие на ошибки."""
    return [
        line.strip()
        for line in output.splitlines()
        if any(pattern.search(line) for pattern in ERROR_PATTERNS)
    ]


def gd_scripts() -> list[Path]:
    scripts: list[Path] = []
    for directory in SCRIPT_DIRS:
        scripts.extend(sorted((PROJECT_ROOT / directory).rglob("*.gd")))
    return scripts


def report(step: str, code: int, output: str) -> bool:
    """Печатает результат шага. Возвращает True, если шаг успешен."""
    errors = find_errors(output)
    if code == 0 and not errors:
        print(f"  OK   {step}")
        return True

    print(f"  FAIL {step} (код возврата {code})")
    for line in errors[:20]:
        print(f"       {line}")
    if not errors and output.strip():
        for line in output.strip().splitlines()[-10:]:
            print(f"       {line}")
    return False


def main(argv: list[str]) -> int:
    # Вывод в UTF-8 независимо от кодовой страницы консоли Windows.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")

    godot = find_godot()
    if godot is None:
        print("Godot не найден. Установите его или задайте GODOT_BIN=<путь к godot>.")
        print("Windows: winget install --id GodotEngine.GodotEngine")
        return 127

    print(f"Godot: {godot}")
    ok = True

    code, output = run_godot(godot, ["--import"])
    ok &= report("импорт ресурсов (--import)", code, output)

    if "--no-scripts" not in argv:
        for script in gd_scripts():
            relative = script.relative_to(PROJECT_ROOT).as_posix()
            code, output = run_godot(godot, ["--check-only", "--script", f"res://{relative}"])
            ok &= report(f"разбор {relative}", code, output)

    print("Проверка пройдена." if ok else "Проверка провалена.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
