#!/usr/bin/env python3
"""Прогон тестов GUT в headless-режиме, несколькими процессами сразу.

Набор режется на задания — файл тестов, отдельный тест разрезанного файла или
пачку мелких файлов, — и задания идут очередью: процессов Godot столько, сколько
потоков у процессора, и освободившийся берёт следующее, самое тяжёлое из
оставшихся. Так прогон не ждёт хвоста одной перегруженной кучки, как ждал при
раскладке заранее.

Движок идёт с `--fixed-fps`: кадр — ровно 1/60 с игрового времени, а настоящие
часы кадры не держат. Тесты со сценой ждут кадров физики, и без флага процесс
спал между кадрами — шесть процессов грузили процессор на 5–30 %, а набор шёл
шесть минут. С флагом тот же набор идёт около минуты. Код игры поэтому меряет
время кадрами (`delta / Engine.time_scale`), а не `Time.get_ticks_msec()`: под
этим флагом часы и кадры расходятся (docs/testing.md).

Запуск:
    python tools/run_tests.py                # процессов по числу потоков
    python tools/run_tests.py --jobs 1       # один процесс за раз
    python tools/run_tests.py --part 2/3     # вторая треть набора — одна машина матрицы CI
    python tools/run_tests.py --real-time    # без --fixed-fps: кадры по настоящим часам

Части делятся жадно по весам `KNOWN_SLOW`: CI гоняет набор матрицей на
нескольких машинах, и на каждой её часть снова идёт очередью.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from godot_bin import PROJECT_ROOT, require_godot, run, use_utf8_output

GUT_CMDLN = "addons/gut/gut_cmdln.gd"
SUCCESS_MARKER = "All tests passed"

# Сколько ждём одно задание, с. Свой лимит, а не общий из godot_bin: там он на
# один запуск движка — импорт ресурсов, съёмка кадра.
TEST_TIMEOUT = 600

# С какой доли лимита пора беспокоиться о задании. Запас съедается по вехе за
# раз, и заметить это надо на прогоне, а не когда задание уже снимается.
CROWDED_RATIO = 0.5

# Кадров в секунду игрового времени под `--fixed-fps`: как у физики игры.
FIXED_FPS = 60

# Больше процессов разом не заводим: под `--fixed-fps` каждый грузит свой поток,
# и сверх числа потоков они только толкаются.
JOBS_MAX = 16

# Пачка мелких файлов — одно задание, пока её вес не дорос до этого, с. Старт
# движка стоит секунды две, и процесс на файл в полсекунды съел бы больше, чем
# сами тесты; а пачка крупнее держала бы хвост прогона.
BATCH_COST = 8.0

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

# Файлы, которые режутся по отдельным тестам: задание не умеет делить файл, а
# `test_building_playthrough.gd` весил треть набора (docs/testing.md). Режется он
# без единой правки в самом тесте: GUT принимает `-gunit_test_name`.
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

# Кто сколько идёт под `--fixed-fps`, с, двенадцатью процессами разом — замер
# `python tools/run_tests.py --batch-cost 0 --slowest 120` (M24j). Файлы короче
# трёх секунд не записаны — они идут по [UNKNOWN_COST]. Очередь берёт тяжёлое первым; разъехались числа — прогон это
# переживёт, только хвост выйдет длиннее.
KNOWN_SLOW: dict[str, float] = {
    "test_bot_survives_the_real_building_with_agents_seed_1": 53.0,
    "test_bot_survives_the_real_building_with_agents_seed_3": 51.0,
    "test_car_corpses.gd": 44.0,
    "test_bot_survives_the_real_building_with_agents_seed_2": 35.0,
    "test_building_architecture.gd": 29.0,
    "test_building_basement.gd": 23.0,
    "test_bot_finishes_the_real_building_seed_1": 16.0,
    "test_bot_finishes_the_real_building_seed_2": 16.0,
    "test_car_boarding.gd": 14.0,
    "test_roof_arrival.gd": 14.0,
    "test_building_map.gd": 14.0,
    "test_agent_doors.gd": 13.0,
    "test_building_dressing.gd": 11.0,
    "test_time_of_day.gd": 10.0,
    "test_building_shafts.gd": 10.0,
    "test_darkness.gd": 10.0,
    "test_elevator_control.gd": 10.0,
    "test_building_plan.gd": 9.0,
    "test_rain.gd": 9.0,
    "test_basement_lock.gd": 9.0,
    "test_building_walls.gd": 9.0,
    "test_red_door.gd": 8.0,
    "test_garage.gd": 8.0,
    "test_building_scenery.gd": 8.0,
    "test_agent_lifts.gd": 8.0,
    "test_demo.gd": 8.0,
    "test_readability.gd": 7.0,
    "test_exit_street.gd": 7.0,
    "test_building_dress.gd": 7.0,
    "test_bot_finishes_every_building": 7.0,
    "test_figure_rig.gd": 7.0,
    "test_exit_car.gd": 6.0,
    "test_building_assembly.gd": 6.0,
    "test_building_route.gd": 6.0,
    "test_shaft_boards.gd": 6.0,
    "test_shaft_faces.gd": 6.0,
    "test_escalator_edges.gd": 5.0,
    "test_escalator_depth.gd": 5.0,
    "test_bot_fights.gd": 5.0,
    "test_car_cut.gd": 5.0,
    "test_building_transition.gd": 4.0,
    "test_takedown.gd": 4.0,
    "test_corpse_freeze.gd": 4.0,
    "test_otto_fall.gd": 4.0,
    "test_graphics.gd": 3.0,
    "test_menu.gd": 3.0,
    "test_door_room.gd": 3.0,
    "test_building_style.gd": 3.0,
    "test_street_traffic.gd": 3.0,
    "test_otto_pauses.gd": 3.0,
    "test_sounds.gd": 3.0,
    "test_muzzle.gd": 3.0,
    "test_enemy_corpse.gd": 3.0,
    "test_enemy_dodge.gd": 3.0,
    "test_car_crush.gd": 3.0,
    "test_car_walk.gd": 3.0,
    "test_alarm.gd": 3.0,
    "test_actor_pose.gd": 3.0,
    "test_agent_spawn.gd": 3.0,
}

# Во сколько считать файл, о котором ничего не известно.
UNKNOWN_COST = 1.5

# Подробность вывода GUT. Своё число, а не из конфига: конфиг задание не читает.
LOG_LEVEL = 1

# Сколько самых долгих заданий печатать в конце: по ним правится `KNOWN_SLOW`.
SLOWEST_SHOWN = 8


class Unit:
    """Файл целиком или один тест из разрезанного файла."""

    def __init__(self, script: Path, only: str = "") -> None:
        self.script = script
        self.only = only

    def cost(self) -> float:
        return KNOWN_SLOW.get(self.only or self.script.name, UNKNOWN_COST)

    def label(self) -> str:
        return self.only or self.script.name


class Job:
    """Что гоняет один процесс Godot: один разрезанный тест или пачка файлов."""

    def __init__(self, units: list[Unit]) -> None:
        self.units = units

    def cost(self) -> float:
        return sum(unit.cost() for unit in self.units)

    def label(self) -> str:
        if len(self.units) == 1:
            return self.units[0].label()
        return f"{self.units[0].label()} и ещё {len(self.units) - 1}"

    def arguments(self) -> list[str]:
        def path(unit: Unit) -> str:
            return f"res://{unit.script.relative_to(PROJECT_ROOT).as_posix()}"

        if self.units[0].only:
            only = self.units[0]
            return [f"-gtest={path(only)}", f"-gunit_test_name={only.only}"]
        return ["-gtest=" + ",".join(path(unit) for unit in self.units)]


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


def jobs_of(units: list[Unit], batch_cost: float = BATCH_COST) -> list[Job]:
    """Задания очереди, тяжёлые первыми: разрезанный тест и известный тяжёлый
    файл — по одному, мелкие файлы — пачками до [BATCH_COST] с."""
    jobs: list[Job] = []
    batch: list[Unit] = []
    for unit in sorted(units, key=lambda unit: -unit.cost()):
        if unit.only or unit.cost() >= batch_cost:
            jobs.append(Job([unit]))
            continue
        batch.append(unit)
        if sum(item.cost() for item in batch) >= batch_cost:
            jobs.append(Job(batch))
            batch = []
    if batch:
        jobs.append(Job(batch))
    return sorted(jobs, key=lambda job: -job.cost())


def split_units(units: list[Unit], piles: int) -> list[list[Unit]]:
    """Раскидывает единицы по кучкам: самая долгая — в самую лёгкую."""
    ordered = sorted(units, key=lambda unit: -unit.cost())
    found: list[list[Unit]] = [[] for _ in range(piles)]
    weights = [0.0] * piles
    for unit in ordered:
        lightest = weights.index(min(weights))
        found[lightest].append(unit)
        weights[lightest] += unit.cost()
    return [pile for pile in found if pile]


def part_of(units: list[Unit], part: str) -> list[Unit]:
    """Единицы части `K/N`: набор делится на N кучек, берётся K-я, с единицы."""
    number, _, total = part.partition("/")
    wrong = f"часть {part}: ждём K/N, где 1 ≤ K ≤ N"
    if not (number.isdigit() and total.isdigit()):
        raise ValueError(wrong)
    k, n = int(number), int(total)
    if not 1 <= k <= n:
        raise ValueError(wrong)
    piles = split_units(units, n)
    # Кучек бывает меньше N, если единиц меньше машин: лишней машине нечего делать.
    return piles[k - 1] if k <= len(piles) else []


def run_job(godot: str, job: Job, home: Path, real_time: bool) -> tuple[int, str, float]:
    """Гоняет задание своим процессом Godot.

    Своя папка `user://` нужна потому, что `test_records` и `test_interface`
    пишут в неё, а флага для неё у Godot нет — он выводит её из `APPDATA` или
    `HOME`. Без этого процессы затирают друг другу файл рекордов.
    """
    home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["APPDATA"] = str(home)
    env["HOME"] = str(home)
    env["XDG_DATA_HOME"] = str(home)
    pace = [] if real_time else ["--fixed-fps", str(FIXED_FPS)]
    started = time.monotonic()
    # `-gconfig=` пустым — это отказ от `.gutconfig.json`, и он обязателен.
    # Иначе `-gdir` берётся оттуда, и каждый процесс гоняет набор целиком.
    code, output = run(
        godot,
        [
            "--headless",
            *pace,
            "-s",
            GUT_CMDLN,
            "-gconfig=",
            *job.arguments(),
            f"-glog={LOG_LEVEL}",
            "-gexit",
        ],
        timeout=TEST_TIMEOUT,
        echo=False,
        stop_on=STALLED_MARKERS,
        env=env,
    )
    if code == 0 and SUCCESS_MARKER not in output:
        code = 1
    return code, output, time.monotonic() - started


def verdict(code: int, output: str, where: str) -> str:
    """Что не так с заданием, или пустая строка, если всё в порядке."""
    if code != 0 and SUCCESS_MARKER in output:
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
    if code != 0:
        return f"{where}: провал, код возврата {code}."
    return ""


def passing(output: str) -> int:
    """Сколько тестов прошло по итогу GUT."""
    total = 0
    for line in output.splitlines():
        # Когда не прошёл ни один, GUT пишет «none», а не 0: без проверки разбор
        # ронял весь прогон, и список упавших до печати не доходил.
        count = line.split()[-1] if "Passing Tests" in line else ""
        if count.isdigit():
            total += int(count)
    return total


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Прогон тестов GUT")
    parser.add_argument(
        "--jobs",
        type=int,
        default=min(os.cpu_count() or 1, JOBS_MAX),
        help="сколько процессов Godot запускать разом",
    )
    parser.add_argument("--part", default="", help="какую часть набора гнать, K/N — для CI")
    parser.add_argument(
        "--real-time", action="store_true", help="без --fixed-fps: кадры по настоящим часам"
    )
    parser.add_argument(
        "--batch-cost",
        type=float,
        default=BATCH_COST,
        help="вес пачки мелких файлов, с; 0 — каждый файл своим процессом (замер весов)",
    )
    parser.add_argument("--slowest", type=int, default=SLOWEST_SHOWN, help="сколько долгих печатать")
    args = parser.parse_args()

    godot = require_godot()
    scripts = sorted((PROJECT_ROOT / "tests").glob("test_*.gd"))
    if not scripts:
        print("В tests/ нет ни одного test_*.gd — прогонять нечего.")
        return 1

    units = units_of(scripts)
    scope = ""
    if args.part:
        everything = len(units)
        try:
            units = part_of(units, args.part)
        except ValueError as error:
            parser.error(str(error))
        scope = f" Часть {args.part}: единиц {len(units)} из {everything}."
        if not units:
            print(f"Тестовых файлов {len(scripts)}.{scope} Этой машине гнать нечего.")
            return 0
    jobs = jobs_of(units, args.batch_cost)
    workers = max(1, min(args.jobs, len(jobs)))
    pace = "по настоящим часам" if args.real_time else f"--fixed-fps {FIXED_FPS}"
    print(
        f"Тестовых файлов {len(scripts)}, единиц {len(units)}, заданий {len(jobs)}, "
        f"процессов {workers}, {pace}.{scope}",
        flush=True,
    )

    started = time.monotonic()
    failures: list[str] = []
    timings: list[tuple[float, str]] = []
    tests = 0
    with tempfile.TemporaryDirectory(prefix="elaction-tests-") as shared:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            running = {
                pool.submit(run_job, godot, job, Path(shared) / f"job{number}", args.real_time): job
                for number, job in enumerate(jobs)
            }
            for done in as_completed(running):
                job = running[done]
                code, output, took = done.result()
                timings.append((took, job.label()))
                tests += passing(output)
                trouble = verdict(code, output, job.label())
                if trouble:
                    failures.append(trouble)
                    # Вывод целиком нужен только у упавшего: у зелёного это
                    # сотни строк, в которых нечего искать.
                    print(output.strip(), flush=True)
                if took > TEST_TIMEOUT * CROWDED_RATIO:
                    print(f"  {job.label()}: {took:.0f} с — запас до лимита меньше половины")

    spent = time.monotonic() - started
    print(f"\nНабор шёл {spent:.0f} с, тестов прошло {tests}. Самые долгие задания:")
    for took, label in sorted(timings, reverse=True)[: args.slowest]:
        print(f"  {took:5.1f} с  {label}")

    if failures:
        print()
        for trouble in failures:
            print(trouble)
        return 1

    print("\nТесты пройдены.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
