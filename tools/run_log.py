#!/usr/bin/env python3
"""Analysis of a run log (`RunLog`): what happened, without rerunning.

The log is written by playthrough tests (`logs/playthrough_seed<N>.jsonl`) and by tools with
the `--log=path` flag. One JSON line per event: frame, game time, kind and
details.

    python tools/run_log.py logs/playthrough_seed3.jsonl            # summary
    python tools/run_log.py logs/playthrough_seed3.jsonl --deaths   # every death
    python tools/run_log.py FILE --kind hit --floor 25              # filter
    python tools/run_log.py FILE --from 120 --to 140                # time window, s
    python tools/run_log.py FILE --kind bot --around 3440 --span 30 # around a frame

Summary: how many events of each kind, Otto's deaths by floor and cause, who fired.
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
            print(f"line {number}: not JSON, skipped", file=sys.stderr)
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
    print("Events:", ", ".join(f"{k} {n}" for k, n in kinds.most_common()))
    deaths = [e for e in events if e.get("kind") == "otto_death"]
    if not deaths:
        print("No Otto deaths.")
        return
    print(f"Otto deaths: {len(deaths)}")
    by_place = Counter((e.get("floor"), round((e.get("at") or [0, 0])[0])) for e in deaths)
    print("  by place (floor, x):", ", ".join(f"{p} ×{n}" for p, n in by_place.most_common(8)))
    by_cause = Counter(e.get("cause") for e in deaths)
    print("  by cause:", ", ".join(f"{c} {n}" for c, n in by_cause.most_common()))
    shooters = Counter(
        (e.get("floor"), round((e.get("shooter") or [0, 0])[0])) for e in deaths if e.get("shooter")
    )
    if shooters:
        print("  shot from (floor, x):", ", ".join(f"{p} ×{n}" for p, n in shooters.most_common(8)))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path", type=Path)
    parser.add_argument("--kind", help="only events of this kind")
    parser.add_argument("--floor", type=int, help="only on this floor")
    parser.add_argument("--from", dest="start", type=float, help="from this time, s")
    parser.add_argument("--to", dest="end", type=float, help="up to this time, s")
    parser.add_argument("--around", type=int, help="around this physics frame")
    parser.add_argument("--span", type=int, default=60, help="how many frames around, 60 by default")
    parser.add_argument("--deaths", action="store_true", help="every Otto death with all the details")
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
