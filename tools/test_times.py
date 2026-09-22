#!/usr/bin/env python3
"""Сколько идёт каждый файл тестов.

Числа нужны раскладке по шардам в `run_tests.py`: класть надо сперва тяжёлое,
а тяжёлое надо знать, а не угадывать. Каждый файл гоняется своим процессом,
несколько разом — замер идёт примерно столько же, сколько обычный прогон.

Запуск:
    python tools/test_times.py              # все файлы
    python tools/test_times.py --jobs 4     # сколько процессов разом
    python tools/test_times.py --by-test    # разрезанные файлы — по тестам
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

GUT_CMDLN = "addons/gut/gut_cmdln.gd"
TIMEOUT = 1200

# Сколько процессов разом по умолчанию. Замер под нагрузкой врёт в свою сторону:
# шесть Godot на двенадцати потоках мешают друг другу, и файл выходит дольше,
# чем он же в одиночку. Для раскладки важны доли, а не абсолютные секунды,
# поэтому меряем в тех же условиях, в каких потом и гоняем.
JOBS_DEFAULT = 6

TESTS_FOUND = re.compile(r"^Tests\s+(\d+)", re.MULTILINE)


def time_one(godot: str, script: Path, only: str, home: Path) -> tuple[str, float, int]:
    """Гоняет один файл (или один тест в нём) и возвращает имя, время и число тестов."""
    home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["APPDATA"] = str(home)
    env["HOME"] = str(home)
    env["XDG_DATA_HOME"] = str(home)

    path = f"res://{script.relative_to(PROJECT_ROOT).as_posix()}"
    args = ["--headless", "-s", GUT_CMDLN, "-gconfig=", f"-gtest={path}", "-glog=1", "-gexit"]
    if only:
        args.append(f"-gunit_test_name={only}")

    started = time.monotonic()
    _, output = run(godot, args, timeout=TIMEOUT, echo=False, env=env)
    spent = time.monotonic() - started
    found = TESTS_FOUND.search(output)
    return (only or script.name), spent, int(found.group(1)) if found else 0


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Замер времени тестов")
    parser.add_argument("--jobs", type=int, default=JOBS_DEFAULT)
    parser.add_argument(
        "--by-test",
        action="store_true",
        help="файлы из SPLIT_BY_TEST мерить по отдельным тестам",
    )
    args = parser.parse_args()

    from run_tests import SPLIT_BY_TEST

    godot = require_godot()
    scripts = sorted((PROJECT_ROOT / "tests").glob("test_*.gd"))
    jobs: list[tuple[Path, str]] = []
    for script in scripts:
        names = SPLIT_BY_TEST.get(script.name) if args.by_test else None
        if names:
            jobs.extend((script, name) for name in names)
        else:
            jobs.append((script, ""))

    print(f"Мерим {len(jobs)} единиц по {args.jobs} разом.", flush=True)
    started = time.monotonic()
    rows: list[tuple[str, float, int]] = []
    with tempfile.TemporaryDirectory(prefix="elaction-times-") as shared:
        with ThreadPoolExecutor(max_workers=max(args.jobs, 1)) as pool:
            futures = [
                pool.submit(time_one, godot, script, only, Path(shared) / f"job{number}")
                for number, (script, only) in enumerate(jobs)
            ]
            for future in futures:
                row = future.result()
                rows.append(row)
                print("  %-52s %6.1f с  тестов %d" % row, flush=True)

    rows.sort(key=lambda row: -row[1])
    total = sum(row[1] for row in rows)
    spent = time.monotonic() - started
    print(f"\nЗамер шёл {spent:.0f} с, сумма времён {total:.0f} с.")
    print("\nСамые дорогие:")
    for name, took, count in rows[:12]:
        print("  %-52s %6.1f с  тестов %d" % (name, took, count))
    print("\nГотовая таблица для KNOWN_SLOW (всё, что дороже 10 с):")
    for name, took, _count in rows:
        if took >= 10.0:
            print('    "%s": %.0f,' % (name, took))
    return 0


if __name__ == "__main__":
    sys.exit(main())
