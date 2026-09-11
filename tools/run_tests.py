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


def main() -> int:
    use_utf8_output()
    godot = require_godot()

    code, output = run(godot, ["--headless", "-s", GUT_CMDLN])
    print(output.strip())

    if code != 0:
        print(f"\nТесты провалены (код возврата {code}).")
        return 1

    # GUT возвращает 0 и когда тесты не нашлись, поэтому сверяемся с итогом.
    if SUCCESS_MARKER not in output:
        print(f'\nВ выводе GUT нет строки "{SUCCESS_MARKER}" — тесты не прошли или не запустились.')
        return 1

    print("\nТесты пройдены.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
