#!/usr/bin/env python3
"""Проверка проекта движком Godot.

Godot умеет то, чего не умеют gdlint и gdformat: импортировать ресурсы, связать
сцены со скриптами и поймать реальные ошибки разбора. Скрипт запускает
`godot --headless --import`, а затем `--check-only` по каждому .gd.

Godot нередко завершается с кодом 0 даже при ошибках в скриптах, поэтому вывод
дополнительно просматривается на маркеры ошибок.

Скрипты разбираются пачками: процесс движка грузит пачку скриптов
(`tools/check_scripts.gd`), и пачки идут разом по числу потоков процессора.
Загрузка компилирует скрипт со всем, от чего он зависит, — то же, что
`--check-only`; по одному запуску на скрипт, подряд, две с половиной сотни
стартов движка шли две с половиной минуты на 10–15 % процессора (M24j). Импорт
— один и до них: разбор читает уже импортированные ресурсы.

Запуск:
    python tools/godot_check.py              # полная проверка
    python tools/godot_check.py --no-scripts # только импорт ресурсов
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

SCRIPT_DIRS = ("src", "tests", "tools")

ERROR_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"SCRIPT ERROR", re.IGNORECASE),
    re.compile(r"Parse Error", re.IGNORECASE),
    re.compile(r"Failed to load script", re.IGNORECASE),
    re.compile(r"Failed loading resource", re.IGNORECASE),
    re.compile(r"Cannot open file", re.IGNORECASE),
    re.compile(r"Invalid call", re.IGNORECASE),
)


def find_errors(output: str) -> list[str]:
    """Возвращает строки вывода, похожие на ошибки."""
    return [
        line.strip()
        for line in output.splitlines()
        if any(pattern.search(line) for pattern in ERROR_PATTERNS)
    ]


def import_resources(godot: str) -> tuple[int, str]:
    """Импортирует ресурсы. На чистом чекауте — в два прохода.

    `project.godot` грузит `res://assets/i18n/*.translation` на старте движка,
    а делает эти файлы тот же самый импорт — из `assets/i18n/ui.csv`. Файлы
    генерируемые и в `.gitignore` (так предписывает стандартный Godot.gitignore),
    поэтому на свежем клоне первый проход всегда ругается на их отсутствие,
    хотя к концу прохода они уже лежат на месте.

    Настоящая поломка ресурса никуда не девается и на втором проходе, так что
    повтор ничего не прячет: судим по нему.
    """
    code, output = run(godot, ["--headless", "--import"])
    if not find_errors(output):
        return code, output

    print("  ..   первый импорт с ошибками — повторяю на готовых ресурсах")
    return run(godot, ["--headless", "--import"])


def gd_scripts() -> list[Path]:
    scripts: list[Path] = []
    for directory in SCRIPT_DIRS:
        scripts.extend(sorted((PROJECT_ROOT / directory).rglob("*.gd")))
    return scripts


# Сколько пачек на поток процессора: пачки неравны — одна тянет за собой
# полпроекта зависимостей, другая нет, — и мелкие ровнее делят хвост.
CHUNKS_PER_THREAD = 2

CHECKER = "res://tools/check_scripts.gd"


def check_scripts(godot: str) -> bool:
    """Разбор всех скриптов пачками; печатает упавшие и итог."""
    scripts = [f"res://{path.relative_to(PROJECT_ROOT).as_posix()}" for path in gd_scripts()]
    count = max(1, min(len(scripts), (os.cpu_count() or 1) * CHUNKS_PER_THREAD))
    piles = [scripts[index::count] for index in range(count)]

    def check(pile: list[str]) -> tuple[list[str], int, str]:
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as listing:
            listing.write(chr(10).join(pile))
        try:
            code, output = run(
                godot, ["--headless", "-s", CHECKER, "--", listing.name], echo=False
            )
        finally:
            os.unlink(listing.name)
        return pile, code, output

    ok = True
    checked = 0
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 1) as pool:
        for pile, code, output in pool.map(check, piles):
            passed = {
                line.split(" ", 2)[2].strip()
                for line in output.splitlines()
                if line.startswith("CHECK OK ")
            }
            checked += len(passed)
            missing = [path for path in pile if path not in passed]
            errors = find_errors(output)
            if code == 0 and not missing and not errors:
                continue
            ok = False
            for path in missing:
                print(f"  FAIL разбор {path.removeprefix('res://')}")
            if not missing:
                print(f"  FAIL разбор пачки из {len(pile)} скриптов (код возврата {code})")
            for line in errors[:20]:
                print(f"       {line}")
    if ok:
        print(f"  OK   разбор {checked} скриптов")
    return ok


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
    use_utf8_output()
    godot = require_godot()
    print(f"Godot: {godot}")
    ok = True

    code, output = import_resources(godot)
    ok &= report("импорт ресурсов (--import)", code, output)

    if "--no-scripts" not in argv:
        ok &= check_scripts(godot)

    print("Проверка пройдена." if ok else "Проверка провалена.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
