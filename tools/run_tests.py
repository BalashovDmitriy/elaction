#!/usr/bin/env python3
"""Прогон тестов GUT в headless-режиме.

Набор тестов и настройки берутся из `.gutconfig.json` в корне проекта.

Запуск:
    python tools/run_tests.py
"""

from __future__ import annotations

import sys
import time

from godot_bin import require_godot, run, use_utf8_output

GUT_CMDLN = "addons/gut/gut_cmdln.gd"
SUCCESS_MARKER = "All tests passed"

# Сколько ждём весь набор, с. Свой лимит, а не общий из godot_bin: там он на
# один запуск движка — импорт ресурсов, съёмка кадра, — а здесь идут сотни
# тестов, часть из них со сценами и ботом.
#
# На M17 набор шёл 575 с при общем лимите 600, и один зависший бот снимал бы
# прогон по таймауту, не сказав, что именно упало. Двадцать минут — двойной
# запас от сегодняшнего времени.
TEST_TIMEOUT = 1200

# С какой доли лимита пора беспокоиться. Запас съедается по вехе за раз, и
# заметить это надо на прогоне, а не когда прогон уже снимается.
CROWDED_RATIO = 0.75

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

    started = time.monotonic()
    code, output = run(godot, ["--headless", "-s", GUT_CMDLN], timeout=TEST_TIMEOUT)
    spent = time.monotonic() - started
    print(output.strip())
    print(f"\nНабор шёл {spent:.0f} с при лимите {TEST_TIMEOUT}.")
    if spent > TEST_TIMEOUT * CROWDED_RATIO:
        print("Запас до лимита меньше четверти — пора разрезать самый дорогой тест.")

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
