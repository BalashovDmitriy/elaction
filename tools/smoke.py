#!/usr/bin/env python3
"""Прогон собранного билда: он должен запуститься, а не просто собраться.

Экспорт возвращает 0 и когда собрал нерабочее, поэтому сборка проверяется
запуском ([ADR-0013](../docs/adr/0013-release-and-versioning.md), пункт 6).
Проверяем три вещи сразу:

1. **Маркер запуска.** Игра печатает `elaction <версия> · <платформа>` первой
   строкой (`Release.banner`). Процесс, упавший на первом кадре, тоже выходит
   с нулём — без маркера «запустилось» считать нельзя.
2. **Ни одного `SCRIPT ERROR`** и прочих маркеров поломки в выводе.
3. **Билд дожил до конца прогона** — либо сам вышел по `--quit-after`, либо был
   снят по таймауту, прожив всё отведённое время. Оба исхода нормальны: главное,
   что он не умер раньше.

    python tools/smoke.py build/linux/elaction.x86_64
    python tools/smoke.py build/linux/elaction.x86_64 --frames 600
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, as_text, use_utf8_output
from godot_check import find_errors
from version import read as project_version

# Сколько кадров игра должна прожить. 300 — это пять секунд при 60 FPS: меню
# успевает собраться, музыка запуститься, а автолоады отработать.
DEFAULT_FRAMES: int = 300

# Запас по времени на случай, если --quit-after не сработает: кадры при этом
# всё равно идут, и прожитое время само по себе годный признак.
TIMEOUT_SECONDS: int = 60


def marker() -> str:
    """Начало строки запуска. Версия берётся из project.godot, как и везде."""
    return f"elaction {project_version()}"


def launch(binary: Path, frames: int) -> tuple[str, bool]:
    """Запускает билд. Возвращает вывод и признак «дожил до конца прогона»."""
    command = [
        str(binary),
        "--headless",
        # Звуковой карты на runner'е нет, а без явного драйвера Godot ищет её
        # и жалуется — в выводе это лишний шум, который легко принять за поломку.
        "--audio-driver",
        "Dummy",
        "--quit-after",
        str(frames),
    ]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as expired:
        # Потоки снятого процесса приезжают вразнобой — str, bytes или None,
        # поэтому каждый приводится к строке отдельно (godot_bin.as_text).
        output = as_text(expired.stdout) + as_text(expired.stderr)
        # Снят по таймауту — значит, всё это время был жив. Это успех, а не сбой.
        return output, True
    return (completed.stdout or "") + (completed.stderr or ""), completed.returncode == 0


def parse(argv: list[str]) -> tuple[list[str], int] | None:
    """Делит аргументы на пути и число кадров. None — если разобрать не вышло."""
    paths: list[str] = []
    frames = DEFAULT_FRAMES
    index = 0
    while index < len(argv):
        if argv[index] != "--frames":
            paths.append(argv[index])
            index += 1
            continue
        # Без явной проверки «--frames» последним аргументом валит скрипт
        # трассировкой вместо внятного сообщения.
        if index + 1 >= len(argv) or not argv[index + 1].isdigit():
            print("После --frames нужно число кадров: python tools/smoke.py <билд> --frames 600")
            return None
        frames = int(argv[index + 1])
        index += 2
    return paths, frames


def main(argv: list[str]) -> int:
    use_utf8_output()
    parsed = parse(argv)
    if parsed is None:
        return 2

    paths, frames = parsed
    if not paths:
        print("Нужен путь к собранному билду: python tools/smoke.py build/linux/elaction.x86_64")
        return 2

    binary = Path(paths[0])
    if not binary.is_absolute():
        binary = PROJECT_ROOT / binary
    if not binary.exists():
        print(f"Нет такого файла: {binary}")
        return 2

    print(f"Прогон {binary.name}: {frames} кадров, маркер «{marker()}»", flush=True)
    output, survived = launch(binary, frames)
    print(output.strip())

    errors = find_errors(output)
    started = marker() in output

    if not started:
        print(f"\nБилд не напечатал строку запуска «{marker()}» — считаем, что он не поднялся.")
    if errors:
        print("\nВ выводе есть ошибки:")
        for line in errors[:20]:
            print(f"  {line}")
    if not survived:
        print("\nБилд вышел с ненулевым кодом.")

    if started and survived and not errors:
        print("\nПрогон пройден: билд запустился, отработал и не ругался.")
        return 0

    print("\nПрогон провален.")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
