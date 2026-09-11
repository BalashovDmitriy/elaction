#!/usr/bin/env python3
"""Снимки экрана игры для анализа после играбельной вехи.

Запускает игру с аргументом `--capture=<веха>`. Автолоад Screenshotter
прогоняет короткий сценарий (стоим, идём, прыгаем, приседаем), сохраняет по
кадру на каждый шаг и закрывает игру.

Снимки складываются в `screens/<веха>/<время>_<шаг>.jpg`.

Важно: рендер настоящий, не headless — нужен экран. В CI не запускается.

Запуск:
    python tools/capture.py M1
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

SCREENS_ROOT = PROJECT_ROOT / "screens"
TIMEOUT_SECONDS = 180


def existing_shots(folder: Path) -> set[Path]:
    return set(folder.glob("*.jpg")) if folder.is_dir() else set()


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Снять экраны игры для вехи эпика.")
    parser.add_argument("milestone", help="Название вехи, например M1")
    args = parser.parse_args()

    godot = require_godot()
    folder = SCREENS_ROOT / args.milestone
    before = existing_shots(folder)

    code, output = run(
        godot, ["--", f"--capture={args.milestone}"], timeout=TIMEOUT_SECONDS
    )

    new_shots = sorted(existing_shots(folder) - before)
    for shot in new_shots:
        print(f"  {shot.relative_to(PROJECT_ROOT).as_posix()}")

    # Игра закрывает себя сама после сценария: любой другой код — падение
    # посреди прогона, и набор кадров тогда неполный, даже если что-то снялось.
    if code != 0:
        print(f"Игра завершилась с кодом {code}, набор кадров неполон. Вывод игры:")
        print(output.strip()[-2000:])
        return 1

    if not new_shots:
        print("Снимки не появились. Вывод игры:")
        print(output.strip()[-2000:])
        return 1

    print(f"Снято кадров: {len(new_shots)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
