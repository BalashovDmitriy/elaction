#!/usr/bin/env python3
"""Прогон тестов GUT в headless-режиме.

Набор тестов и настройки берутся из `.gutconfig.json` в корне проекта.

Запуск:
    python tools/run_tests.py
"""

from __future__ import annotations

import sys

from godot_bin import require_godot, run, use_utf8_output

GUT_CMDLN = "addons/gut/gut_cmdln.gd"
SUCCESS_MARKER = "All tests passed"

# Скрипт, не прошедший разбор, молча выпадает из прогона: GUT считает тесты
# остальных файлов и рапортует об успехе. Поэтому ищем следы поломки отдельно.
BROKEN_SCRIPT_MARKERS = (
    "Parse Error",
    "Failed to load script",
    "SCRIPT ERROR",
)


def main() -> int:
    use_utf8_output()
    godot = require_godot()

    code, output = run(godot, ["--headless", "-s", GUT_CMDLN])
    print(output.strip())

    if code != 0:
        print(f"\nТесты провалены (код возврата {code}).")
        return 1

    broken = [marker for marker in BROKEN_SCRIPT_MARKERS if marker in output]
    if broken:
        print(f"\nВ выводе есть {', '.join(broken)} — какой-то скрипт не разобрался.")
        print("Такой файл выпадает из прогона незаметно, поэтому это провал.")
        return 1

    # GUT возвращает 0 и когда тесты не нашлись, поэтому сверяемся с итогом.
    if SUCCESS_MARKER not in output:
        print(f'\nВ выводе GUT нет строки "{SUCCESS_MARKER}" — тесты не прошли или не запустились.')
        return 1

    print("\nТесты пройдены.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
