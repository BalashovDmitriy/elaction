#!/usr/bin/env python3
"""Поиск и запуск Blender для рендера актёров.

Парный модуль к `godot_bin.py`: тот же порядок поиска, тот же способ ругаться,
когда инструмента нет. Нужен только скриптам рендера актёров (ADR-0011, пункт 1);
окружение рисует `render_env.py`, и ему Blender не требуется.

Порядок поиска: $BLENDER_BIN -> PATH -> Program Files -> пути winget.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

# Общее с поиском Godot не переписывается: код возврата таймаута, приведение
# вывода к тексту и UTF-8 на выходе одинаковы для обоих инструментов, и свои
# копии этих трёх разошлись бы с оригиналом при первой же правке.
from godot_bin import TIMEOUT_EXIT_CODE, as_text, use_utf8_output

# Версия, на которой пайплайн собран и проверен (ADR-0011).
EXPECTED_VERSION = "5.2"


def _program_files_candidates() -> list[Path]:
    """Установка msi-пакетом: winget не кладёт blender.exe в свои Links."""
    roots: list[Path] = []
    for variable in ("ProgramFiles", "ProgramFiles(x86)"):
        value = os.environ.get(variable)
        if value:
            roots.append(Path(value))
    if not roots:
        roots.append(Path("C:/Program Files"))

    found: list[Path] = []
    for root in roots:
        # Сначала ожидаемая версия, потом всё остальное по убыванию имени:
        # так 5.2 выигрывает у 4.x, даже если стоят обе.
        blender_root = root / "Blender Foundation"
        preferred = blender_root / f"Blender {EXPECTED_VERSION}" / "blender.exe"
        if preferred.exists():
            found.append(preferred)
        for candidate in sorted(blender_root.glob("Blender */blender.exe"), reverse=True):
            if candidate != preferred:
                found.append(candidate)
    return found


def find_blender() -> str | None:
    """Возвращает путь к исполняемому файлу Blender или None, если он не найден."""
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
    """Как find_blender, но печатает подсказку и завершает процесс, если Blender нет."""
    blender = find_blender()
    if blender is None:
        print("Blender не найден. Установите его или задайте BLENDER_BIN=<путь к blender>.")
        print("Windows: winget install --id BlenderFoundation.Blender")
        raise SystemExit(127)
    return blender


def run_script(blender: str, script: Path, args: list[str] | None = None, timeout: int = 600) -> tuple[int, str]:
    """Прогоняет скрипт в Blender без окна и возвращает (код возврата, вывод).

    Аргументы после `--` достаются скрипту: Blender до этого разделителя разбирает
    командную строку сам.
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
        return TIMEOUT_EXIT_CODE, f"{output}\nBlender не ответил за {timeout} с и был снят."
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def version_of(blender: str) -> str:
    """Первая строка `blender --version`, например «Blender 5.2.1 LTS»."""
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
    """`python tools/blender_bin.py` печатает найденный Blender и его версию."""
    use_utf8_output()
    blender = require_blender()
    print(blender)
    print(version_of(blender))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
