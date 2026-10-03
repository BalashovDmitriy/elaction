#!/usr/bin/env python3
"""Authors for the "Credits" page in the menu (ADR-0042, decision 6).

The source is `CREDITS.md`: it is edited by hand when a third-party asset comes into
the project. It does not go into the build itself — it is markdown in the root — so the
game reads `assets/credits.json`, built from here: sections in file order, in each —
authors in order of first appearance and their licences. The project's own works
("elaction") do not go into the list.

    python tools/build_credits.py            # rebuild assets/credits.json
    python tools/build_credits.py --check    # only compare, exit code 1 — they differ

The `test_credits` test checks the same thing from the game.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "CREDITS.md"
TARGET = ROOT / "assets" / "credits.json"

# A `CREDITS.md` section — the translation key of its heading on the page.
SECTIONS = {
    "People and cars": "UI_CREDITS_ACTORS",
    "Props and roof": "UI_CREDITS_PROPS",
    "Textures": "UI_CREDITS_TEXTURES",
    "City and sky": "UI_CREDITS_CITY",
    "Sound": "UI_CREDITS_SOUND",
    "Fonts": "UI_CREDITS_FONTS",
}
AUTHOR = "Author"
LICENCE = "Licence"
OWN = "elaction"


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse(text: str) -> list[dict]:
    """Sections with authors: [{key, authors: [{name, licences}]}]."""
    sections: list[dict] = []
    current: dict | None = None
    header: list[str] = []
    for line in text.splitlines():
        if line.startswith("## "):
            title = line[3:].strip()
            key = SECTIONS.get(title)
            current = {"key": key, "authors": []} if key else None
            if current:
                sections.append(current)
            header = []
            continue
        if current is None or not line.startswith("|"):
            header = [] if not line.startswith("|") else header
            continue
        cells = _cells(line)
        if not header:
            header = cells
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        if AUTHOR not in header or LICENCE not in header:
            continue
        name = cells[header.index(AUTHOR)]
        licence = cells[header.index(LICENCE)].split(",")[0].strip()
        if name == OWN:
            continue
        found = next((a for a in current["authors"] if a["name"] == name), None)
        if found is None:
            found = {"name": name, "licences": []}
            current["authors"].append(found)
        if licence not in found["licences"]:
            found["licences"].append(licence)
    return sections


def render(sections: list[dict]) -> str:
    return json.dumps({"sections": sections}, ensure_ascii=False, indent=1) + "\n"


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="только сверить")
    args = parser.parse_args()
    sections = parse(SOURCE.read_text(encoding="utf-8"))
    wanted = render(sections)
    if args.check:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != wanted:
            print("assets/credits.json расходится с CREDITS.md: python tools/build_credits.py")
            return 1
        print("assets/credits.json совпадает с CREDITS.md")
        return 0
    TARGET.write_bytes(wanted.encode("utf-8"))
    count = sum(len(section["authors"]) for section in sections)
    print(f"assets/credits.json: разделов {len(SECTIONS)}, авторов {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
