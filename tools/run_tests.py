#!/usr/bin/env python3
"""Прогон тестов GUT в headless-режиме, несколькими процессами сразу.

Настройки берутся из `.gutconfig.json` в корне проекта; файлы тестов
раскидываются по шардам, и каждый шард — свой процесс Godot.

Запуск:
    python tools/run_tests.py                # шардов по числу ядер, но не больше SHARDS_MAX
    python tools/run_tests.py --shards 1     # один процесс, как было до шардинга
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

GUT_CMDLN = "addons/gut/gut_cmdln.gd"
SUCCESS_MARKER = "All tests passed"

# Сколько ждём один шард, с. Свой лимит, а не общий из godot_bin: там он на один
# запуск движка — импорт ресурсов, съёмка кадра, — а здесь идут сотни тестов,
# часть из них со сценами и ботом.
TEST_TIMEOUT = 1200

# С какой доли лимита пора беспокоиться. Запас съедается по вехе за раз, и
# заметить это надо на прогоне, а не когда прогон уже снимается.
CROWDED_RATIO = 0.75

# Больше шардов не заводим. Упирается прогон не в ядра, а в самый долгий файл:
# набор идёт ровно столько, сколько идёт `test_building_playthrough`.
SHARDS_MAX = 6

# Строки, после которых ждать нечего. Бот печатает это, упершись в тупик, и
# дальше только добирает бюджет шагов — на настоящем здании это минуты.
STALLED_MARKERS = ("бот зациклился",)

# Скрипт, не прошедший разбор, молча выпадает из прогона: GUT считает тесты
# остальных файлов и рапортует об успехе. Поэтому ищем следы поломки отдельно.
BROKEN_SCRIPT_MARKERS = (
    "Parse Error",
    "Failed to load script",
    "SCRIPT ERROR",
)

# Файлы, которые режутся по отдельным тестам. Шард не умеет делить файл, а
# `test_building_playthrough.gd` один весит треть набора: пока он ходил целиком,
# шесть шардов давали 574 с против 755 — весь прогон стоял и ждал его.
#
# Режется он без единой правки в самом тесте: GUT принимает `-gunit_test_name`,
# и каждый такой кусок идёт своим процессом.
SPLIT_BY_TEST: dict[str, list[str]] = {
    "test_building_playthrough.gd": [
        "test_bot_survives_the_real_building_with_agents_seed_1",
        "test_bot_survives_the_real_building_with_agents_seed_2",
        "test_bot_survives_the_real_building_with_agents_seed_3",
        "test_bot_finishes_the_real_building_seed_1",
        "test_bot_finishes_the_real_building_seed_2",
        "test_bot_finishes_every_building",
        "test_a_tick_is_two_physics_frames",
    ],
}

# Кто сколько идёт, с. Замер — `python tools/test_times.py --by-test`, шесть
# процессов разом, то есть в тех же условиях, в каких потом идёт прогон.
#
# Раскладка жадная, и класть надо сперва тяжёлое: иначе самый долгий кусок
# ляжет последним и растянет прогон на свою длину плюс всё, что легло до него.
# Разъехались числа — прогон это переживёт, просто раскладка станет хуже.
KNOWN_SLOW: dict[str, float] = {
    "test_bot_survives_the_real_building_with_agents_seed_1": 120.0,
    "test_bot_survives_the_real_building_with_agents_seed_2": 120.0,
    "test_bot_survives_the_real_building_with_agents_seed_3": 90.0,
    "test_bot_finishes_the_real_building_seed_1": 95.0,
    "test_bot_finishes_the_real_building_seed_2": 95.0,
    "test_bot_finishes_every_building": 60.0,
    "test_building_architecture.gd": 54.0,
    "test_agent_doors.gd": 36.0,
    "test_agent_lifts.gd": 30.0,
    "test_darkness.gd": 26.0,
    "test_elevator_control.gd": 26.0,
    "test_building_assembly.gd": 5.0,
    "test_building_shafts.gd": 5.0,
}

# Во сколько считать файл, о котором ничего не известно. Тесты правил без сцены
# идут доли секунды, и переоценивать их незачем.
UNKNOWN_COST = 2.0

# Подробность вывода GUT. Своё число, а не из конфига: конфиг шард не читает.
LOG_LEVEL = 1


class Unit:
    """Что гоняет один процесс Godot: файл целиком или один тест из него."""

    def __init__(self, script: Path, only: str = "") -> None:
        self.script = script
        self.only = only

    def cost(self) -> float:
        return KNOWN_SLOW.get(self.only or self.script.name, UNKNOWN_COST)

    def label(self) -> str:
        return self.only or self.script.name


def units_of(scripts: list[Path]) -> list[Unit]:
    """Разбивает набор на единицы работы: файл или отдельный тест в нём."""
    found: list[Unit] = []
    for script in scripts:
        names = SPLIT_BY_TEST.get(script.name)
        if names is None:
            found.append(Unit(script))
            continue
        for name in names:
            found.append(Unit(script, name))
    return found


def shard_units(units: list[Unit], shards: int) -> list[list[Unit]]:
    """Раскидывает единицы по шардам: самая долгая — в самый свободный."""
    ordered = sorted(units, key=lambda unit: -unit.cost())
    piles: list[list[Unit]] = [[] for _ in range(shards)]
    weights = [0.0] * shards
    for unit in ordered:
        lightest = weights.index(min(weights))
        piles[lightest].append(unit)
        weights[lightest] += unit.cost()
    return [pile for pile in piles if pile]


def run_shard(godot: str, units: list[Unit], home: Path) -> tuple[int, str, float]:
    """Гоняет шард: единицы идут подряд, каждая своим процессом Godot.

    Своя папка `user://` нужна потому, что `test_records` и `test_interface`
    пишут в неё, а флага для неё у Godot нет — он выводит её из `APPDATA` или
    `HOME`. Без этого шарды затирают друг другу файл рекордов, и падает то один,
    то другой, без всякой связи с тем, что менялось в коде.

    Процесс на единицу, а не один на шард: разрезанный файл иначе не разложить —
    `-gunit_test_name` у GUT один на запуск. Старт движка стоит пару секунд,
    и на фоне самого дешёвого теста это заметно, а на фоне прогона бота — нет.
    """
    home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["APPDATA"] = str(home)
    env["HOME"] = str(home)
    env["XDG_DATA_HOME"] = str(home)

    started = time.monotonic()
    whole = [unit for unit in units if not unit.only]
    pieces = [unit for unit in units if unit.only]

    calls: list[list[str]] = []
    if whole:
        paths = ",".join(
            f"res://{unit.script.relative_to(PROJECT_ROOT).as_posix()}" for unit in whole
        )
        calls.append([f"-gtest={paths}"])
    for unit in pieces:
        path = f"res://{unit.script.relative_to(PROJECT_ROOT).as_posix()}"
        calls.append([f"-gtest={path}", f"-gunit_test_name={unit.only}"])

    collected: list[str] = []
    for extra in calls:
        # `-gconfig=` пустым — это отказ от `.gutconfig.json`, и он обязателен.
        # Иначе `-gdir` берётся оттуда, к списку шарда добавляется весь
        # `res://tests`, и каждый процесс гоняет набор целиком: шесть шардов
        # шли те же одиннадцать минут, что и один, только вшестером.
        code, output = run(
            godot,
            ["--headless", "-s", GUT_CMDLN, "-gconfig=", *extra, f"-glog={LOG_LEVEL}", "-gexit"],
            timeout=TEST_TIMEOUT,
            echo=False,
            stop_on=STALLED_MARKERS,
            env=env,
        )
        collected.append(output)
        if code != 0 or SUCCESS_MARKER not in output:
            return code or 1, "\n".join(collected), time.monotonic() - started
    return 0, "\n".join(collected), time.monotonic() - started


def verdict(code: int, output: str, where: str) -> str:
    """Что не так с шардом, или пустая строка, если всё в порядке."""
    if code != 0:
        return f"{where}: провал, код возврата {code}."
    broken = [marker for marker in BROKEN_SCRIPT_MARKERS if marker in output]
    if broken:
        return (
            f"{where}: в выводе есть {', '.join(broken)} — какой-то скрипт не разобрался. "
            "Такой файл выпадает из прогона незаметно, поэтому это провал."
        )
    # GUT возвращает 0 и когда тесты не нашлись, поэтому сверяемся с итогом.
    if SUCCESS_MARKER not in output:
        return f'{where}: в выводе GUT нет строки "{SUCCESS_MARKER}" — тесты не прошли.'
    return ""


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Прогон тестов GUT")
    parser.add_argument(
        "--shards",
        type=int,
        default=min(os.cpu_count() or 1, SHARDS_MAX),
        help="сколько процессов Godot запускать разом",
    )
    args = parser.parse_args()

    godot = require_godot()
    scripts = sorted((PROJECT_ROOT / "tests").glob("test_*.gd"))
    if not scripts:
        print("В tests/ нет ни одного test_*.gd — прогонять нечего.")
        return 1

    units = units_of(scripts)
    piles = shard_units(units, max(args.shards, 1))
    print(
        f"Тестовых файлов {len(scripts)}, единиц {len(units)}, шардов {len(piles)}.",
        flush=True,
    )

    started = time.monotonic()
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="elaction-shards-") as shared:
        with ThreadPoolExecutor(max_workers=len(piles)) as pool:
            jobs = [
                pool.submit(run_shard, godot, pile, Path(shared) / f"shard{number}")
                for number, pile in enumerate(piles)
            ]
            for number, job in enumerate(jobs):
                code, output, took = job.result()
                where = f"шард {number + 1}"
                trouble = verdict(code, output, where)
                totals = [line.strip() for line in output.splitlines() if "Passing Tests" in line]
                # Время каждого шарда печатается всегда: по нему видно, какой
                # файл держит прогон, а без этого раскладку не поправить.
                print(
                    "  %s: %3.0f с, единиц %d, %s"
                    % (where, took, len(piles[number]), "; ".join(totals) or "итога нет"),
                    flush=True,
                )
                if trouble:
                    failures.append(trouble)
                    # Вывод целиком нужен только у упавшего: у зелёного это
                    # сотни строк, в которых нечего искать.
                    print(output.strip())

    spent = time.monotonic() - started
    print(f"\nНабор шёл {spent:.0f} с при лимите {TEST_TIMEOUT} на шард.")
    if spent > TEST_TIMEOUT * CROWDED_RATIO:
        print("Запас до лимита меньше четверти — пора разрезать самый дорогой тест.")

    if failures:
        print()
        for trouble in failures:
            print(trouble)
        return 1

    print("\nТесты пройдены.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
