#!/usr/bin/env python3
"""gdformat --check и gdlint по всему коду, параллельно (M24j).

gdtoolkit разбирает файлы по одному в одном процессе: на двух с половиной
сотнях скриптов форматтер и линтер шли по пять-шесть секунд каждый, подряд —
одиннадцать, на одном потоке. Здесь файлы режутся на куски, и куски обоих
инструментов идут разом процессами по числу потоков процессора.

Вывод — тот же, что у самих инструментов: ошибки и итог по каждому куску,
код возврата 1, если хоть один кусок не прошёл.

    python tools/gd_tools.py              # формат и линт src, tests, tools
    python tools/gd_tools.py --format     # только формат
    python tools/gd_tools.py --lint       # только линт
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = ("src", "tests", "tools")

# Модулями, а не gdformat.exe и gdlint.exe: неподписанные обёртки pip блокирует
# управление приложениями Windows (WinError 4551), см. .pre-commit-config.yaml.
TOOLS = {
    "gdformat": ["-m", "gdtoolkit.formatter", "--check"],
    "gdlint": ["-m", "gdtoolkit.linter"],
}


def scripts() -> list[str]:
    found: list[str] = []
    for directory in DIRS:
        found.extend(str(path.relative_to(ROOT)) for path in sorted((ROOT / directory).rglob("*.gd")))
    return found


def chunks(files: list[str], count: int) -> list[list[str]]:
    count = max(1, min(count, len(files)))
    return [files[index::count] for index in range(count)]


def run_chunk(tool: str, files: list[str]) -> tuple[str, int, str]:
    completed = subprocess.run(
        [sys.executable, *TOOLS[tool], *files],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    return tool, completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--format", action="store_true", help="только формат")
    parser.add_argument("--lint", action="store_true", help="только линт")
    args = parser.parse_args()
    wanted = [name for name, on in (("gdformat", args.format), ("gdlint", args.lint)) if on]
    wanted = wanted or list(TOOLS)

    files = scripts()
    threads = os.cpu_count() or 1
    # Потоки делятся между инструментами поровну.
    per_tool = max(1, threads // len(wanted))
    jobs = [(tool, piece) for tool in wanted for piece in chunks(files, per_tool)]
    failed: set[str] = set()
    problems: dict[str, list[str]] = {tool: [] for tool in wanted}
    with ThreadPoolExecutor(max_workers=threads) as pool:
        for tool, code, output in pool.map(lambda job: run_chunk(*job), jobs):
            if code != 0:
                failed.add(tool)
                # Итоговые строки кусков («Success…», «N files would be left
                # unchanged») не повторяем — печатаем только сами замечания.
                lines = [
                    line
                    for line in output.splitlines()
                    if line.strip()
                    and not line.startswith(("Success", "Failure"))
                    and "files would be left unchanged" not in line
                    and "file would be left unchanged" not in line
                ]
                problems[tool].extend(lines)
    for tool in wanted:
        if tool in failed:
            print(f"== {tool}: есть замечания ==")
            for line in problems[tool]:
                print(line)
        else:
            print(f"== {tool}: {len(files)} файлов, замечаний нет ==")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
