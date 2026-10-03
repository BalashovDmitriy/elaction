#!/usr/bin/env python3
"""Run GUT tests headless, in several processes at once.

The suite is cut into jobs — a test file, a single test of a split file or a
batch of small files — and the jobs go through a queue: there are as many Godot
processes as the CPU has threads, and a freed one takes the next job, the heaviest
of those left. This way the run does not wait for the tail of one overloaded pile,
as it did with a layout fixed in advance.

The engine runs with `--fixed-fps`: a frame is exactly 1/60 s of game time, and the
real clock does not hold frames back. Tests with a scene wait for physics frames,
and without the flag the process slept between frames — six processes loaded the
CPU at 5–30 %, and the suite took six minutes. With the flag the same suite takes
about a minute. That is why the game code measures time in frames
(`delta / Engine.time_scale`), not with `Time.get_ticks_msec()`: under this flag
the clock and frames diverge (docs/testing.md).

Run:
    python tools/run_tests.py                # processes by thread count
    python tools/run_tests.py --jobs 1       # one process at a time
    python tools/run_tests.py --part 2/3     # second third of the suite — one CI matrix machine
    python tools/run_tests.py --real-time    # without --fixed-fps: frames by the real clock

Parts are split greedily by the `KNOWN_SLOW` weights: CI runs the suite as a matrix on
several machines, and on each its part again goes through a queue.
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

# How long we wait for one job, s. Our own limit, not the shared one from godot_bin: that one is for
# a single engine launch — resource import, taking a shot.
TEST_TIMEOUT = 600

# At what share of the limit it is time to worry about a job. The margin is eaten up one milestone
# at a time, and this has to be noticed on a run, not when the job is already being killed.
CROWDED_RATIO = 0.5

# Frames per second of game time under `--fixed-fps`: as in the game's physics.
FIXED_FPS = 60

# We do not start more processes at once: under `--fixed-fps` each loads its own thread, and beyond
# the thread count they only jostle.
JOBS_MAX = 16

# A batch of small files is one job until its weight grows to this, s. An engine start costs about
# two seconds, and a process per half-second file would eat more than the tests themselves; a bigger
# batch would hold up the tail of the run.
BATCH_COST = 8.0

# Lines after which there is nothing to wait for. The bot prints this when it hits a dead end, and
# afterwards only uses up the step budget — on the real building that is minutes.
STALLED_MARKERS = ("bot is looping",)

# Jolt under thread shortage: the physics task queue overflowed, and the engine waits for it to free
# up — the step completes, but GUT counts the engine error line as a test failure. On CI
# (2026-10-02) test_car_cut.gd failed this way; locally six parallel runs of the same job are clean.
# A job with this line is retried once: a real failure will repeat the second time too.
JOLT_STARVED = "Jolt Physics job system exceeded the maximum number of jobs"

# A script that failed to parse silently drops out of the run: GUT counts the tests of the other
# files and reports success. So we look for traces of breakage separately.
BROKEN_SCRIPT_MARKERS = (
    "Parse Error",
    "Failed to load script",
    "SCRIPT ERROR",
)

# Files that are split by individual tests: a job cannot split a file, and
# `test_building_playthrough.gd` weighed a third of the suite (docs/testing.md). It is split without
# a single edit in the test itself: GUT accepts `-gunit_test_name`.
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

# How long each one takes under `--fixed-fps`, s, with twelve processes at once — measured with
# `python tools/run_tests.py --batch-cost 0 --slowest 120` (M24j). Files shorter than three seconds
# are not listed — they go by [UNKNOWN_COST]. The queue takes the heavy ones first; if the numbers
# drift, the run will survive it, only the tail will come out longer.
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

# What to count a file as when nothing is known about it.
UNKNOWN_COST = 1.5

# GUT output verbosity. Our own number, not from the config: the job does not read the config.
LOG_LEVEL = 1

# How many of the longest jobs to print at the end: `KNOWN_SLOW` is corrected by them.
SLOWEST_SHOWN = 8


class Unit:
    """A whole file or one test of a split file."""

    def __init__(self, script: Path, only: str = "") -> None:
        self.script = script
        self.only = only

    def cost(self) -> float:
        return KNOWN_SLOW.get(self.only or self.script.name, UNKNOWN_COST)

    def label(self) -> str:
        return self.only or self.script.name


class Job:
    """What one Godot process runs: one split test or a batch of files."""

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
    """Splits the suite into work units: a file or a single test in it."""
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
    """Queue jobs, heaviest first: a split test and a known heavy file go one
    by one, small files in batches of up to [BATCH_COST] s."""
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
    """Spreads units over piles: the longest goes into the lightest."""
    ordered = sorted(units, key=lambda unit: -unit.cost())
    found: list[list[Unit]] = [[] for _ in range(piles)]
    weights = [0.0] * piles
    for unit in ordered:
        lightest = weights.index(min(weights))
        found[lightest].append(unit)
        weights[lightest] += unit.cost()
    return [pile for pile in found if pile]


def part_of(units: list[Unit], part: str) -> list[Unit]:
    """Units of part `K/N`: the suite is split into N piles, the K-th is taken, from one."""
    number, _, total = part.partition("/")
    wrong = f"часть {part}: ждём K/N, где 1 ≤ K ≤ N"
    if not (number.isdigit() and total.isdigit()):
        raise ValueError(wrong)
    k, n = int(number), int(total)
    if not 1 <= k <= n:
        raise ValueError(wrong)
    piles = split_units(units, n)
    # There may be fewer than N piles if there are fewer units than machines: the extra machine has
    # nothing to do.
    return piles[k - 1] if k <= len(piles) else []


def run_job(godot: str, job: Job, home: Path, real_time: bool) -> tuple[int, str, float]:
    """Runs a job in its own Godot process.

    A separate `user://` folder is needed because `test_records` and `test_interface`
    write to it, and Godot has no flag for it — it derives it from `APPDATA` or
    `HOME`. Without this the processes overwrite each other's high score file.
    """
    home.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env["APPDATA"] = str(home)
    env["HOME"] = str(home)
    env["XDG_DATA_HOME"] = str(home)
    pace = [] if real_time else ["--fixed-fps", str(FIXED_FPS)]
    started = time.monotonic()
    # An empty `-gconfig=` opts out of `.gutconfig.json`, and it is mandatory. Otherwise `-gdir` is
    # taken from there, and every process runs the whole suite.
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


def run_job_once_more(
    godot: str, job: Job, home: Path, real_time: bool
) -> tuple[int, str, float, bool]:
    """A job, and one that failed from Jolt's thread shortage — once more.

    The last field is whether there was a retry: it is printed so it does not pass silently.
    """
    code, output, took = run_job(godot, job, home, real_time)
    if verdict(code, output, job.label()) and JOLT_STARVED in output:
        code, output, again = run_job(godot, job, home, real_time)
        return code, output, took + again, True
    return code, output, took, False


def verdict(code: int, output: str, where: str) -> str:
    """What is wrong with a job, or an empty string if everything is fine."""
    if code != 0 and SUCCESS_MARKER in output:
        return f"{where}: провал, код возврата {code}."
    broken = [marker for marker in BROKEN_SCRIPT_MARKERS if marker in output]
    if broken:
        return (
            f"{where}: в выводе есть {', '.join(broken)} — какой-то скрипт не разобрался. "
            "Такой файл выпадает из прогона незаметно, поэтому это провал."
        )
    # GUT returns 0 even when no tests were found, so we check against the summary.
    if SUCCESS_MARKER not in output:
        return f'{where}: в выводе GUT нет строки "{SUCCESS_MARKER}" — тесты не прошли.'
    if code != 0:
        return f"{where}: провал, код возврата {code}."
    return ""


def passing(output: str) -> int:
    """How many tests passed according to the GUT summary."""
    total = 0
    for line in output.splitlines():
        # When none passed, GUT writes "none", not 0: without the check, parsing crashed the whole
        # run, and the list of failed ones never got printed.
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
                pool.submit(
                    run_job_once_more, godot, job, Path(shared) / f"job{number}", args.real_time
                ): job
                for number, job in enumerate(jobs)
            }
            for done in as_completed(running):
                job = running[done]
                code, output, took, retried = done.result()
                if retried:
                    print(f"  {job.label()}: у Jolt кончилась очередь задач — повтор", flush=True)
                timings.append((took, job.label()))
                tests += passing(output)
                trouble = verdict(code, output, job.label())
                if trouble:
                    failures.append(trouble)
                    # Full output is needed only for a failed one: for a green one it is hundreds of
                    # lines with nothing to look for.
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
