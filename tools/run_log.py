#!/usr/bin/env python3
"""Разбор журнала прогона (`RunLog`): что происходило, без перезапуска.

Журнал пишут тесты прохождения (`logs/playthrough_seed<N>.jsonl`) и инструменты с
флагом `--log=путь`. По строке JSON на событие: кадр, игровое время, вид и
подробности.

    python tools/run_log.py logs/playthrough_seed3.jsonl            # сводка
    python tools/run_log.py logs/playthrough_seed3.jsonl --deaths   # каждая смерть
    python tools/run_log.py FILE --kind hit --floor 25              # фильтр
    python tools/run_log.py FILE --from 120 --to 140                # окно времени, с
    python tools/run_log.py FILE --kind bot --around 3440 --span 30 # вокруг кадра

Сводка: сколько каких событий, смерти Otto по этажам и причинам, кто стрелял.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path


def read(path: Path) -> list[dict]:
    events: list[dict] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            print(f"строка {number}: не JSON, пропущена", file=sys.stderr)
    return events


def keep(event: dict, args: argparse.Namespace) -> bool:
    if args.kind and event.get("kind") != args.kind:
        return False
    if args.floor is not None and event.get("floor") != args.floor:
        return False
    t = event.get("t", 0.0)
    if args.start is not None and t < args.start:
        return False
    if args.end is not None and t > args.end:
        return False
    if args.around is not None and abs(event.get("frame", 0) - args.around) > args.span:
        return False
    return True


def summary(events: list[dict]) -> None:
    kinds = Counter(e.get("kind") for e in events)
    print("События:", ", ".join(f"{k} {n}" for k, n in kinds.most_common()))
    deaths = [e for e in events if e.get("kind") == "otto_death"]
    if not deaths:
        print("Смертей Otto нет.")
        return
    print(f"Смертей Otto: {len(deaths)}")
    by_place = Counter((e.get("floor"), round((e.get("at") or [0, 0])[0])) for e in deaths)
    print("  по месту (этаж, x):", ", ".join(f"{p} ×{n}" for p, n in by_place.most_common(8)))
    by_cause = Counter(e.get("cause") for e in deaths)
    print("  по причине:", ", ".join(f"{c} {n}" for c, n in by_cause.most_common()))
    shooters = Counter(
        (e.get("floor"), round((e.get("shooter") or [0, 0])[0])) for e in deaths if e.get("shooter")
    )
    if shooters:
        print("  откуда стреляли (этаж, x):", ", ".join(f"{p} ×{n}" for p, n in shooters.most_common(8)))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", type=Path)
    parser.add_argument("--kind", help="только события этого вида")
    parser.add_argument("--floor", type=int, help="только на этом этаже")
    parser.add_argument("--from", dest="start", type=float, help="с этого времени, с")
    parser.add_argument("--to", dest="end", type=float, help="до этого времени, с")
    parser.add_argument("--around", type=int, help="вокруг этого кадра физики")
    parser.add_argument("--span", type=int, default=60, help="сколько кадров вокруг, по умолчанию 60")
    parser.add_argument("--deaths", action="store_true", help="каждая смерть Otto со всеми подробностями")
    args = parser.parse_args()
    events = read(args.path)
    if args.deaths:
        args.kind = "otto_death"
    filtering = any(
        value is not None and value is not False
        for value in (args.kind, args.floor, args.start, args.end, args.around)
    )
    if not filtering:
        summary(events)
        return 0
    for event in events:
        if keep(event, args):
            print(json.dumps(event, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
