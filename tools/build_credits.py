#!/usr/bin/env python3
"""Авторы для страницы «Авторы» в меню (ADR-0042, решение 6).

Источник — `CREDITS.md`: его правят руками, когда в проект приходит чужой
ассет. Сам он в сборку не идёт — это markdown в корне, — поэтому игра читает
`assets/credits.json`, собранный отсюда: разделы в порядке файла, в каждом —
авторы в порядке первого появления и их лицензии. Свои работы проекта
(«elaction») в список не идут.

    python tools/build_credits.py            # пересобрать assets/credits.json
    python tools/build_credits.py --check    # только сверить, код 1 — расходятся

Тест `test_credits` сверяет то же самое из игры.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "CREDITS.md"
TARGET = ROOT / "assets" / "credits.json"

# Раздел `CREDITS.md` — ключ перевода его заголовка на странице.
SECTIONS = {
    "Люди и машины": "UI_CREDITS_ACTORS",
    "Обстановка и крыша": "UI_CREDITS_PROPS",
    "Фактуры": "UI_CREDITS_TEXTURES",
    "Звук": "UI_CREDITS_SOUND",
    "Шрифты": "UI_CREDITS_FONTS",
}
AUTHOR = "Автор"
LICENCE = "Лицензия"
OWN = "elaction"


def _cells(line: str) -> list[str]:
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def parse(text: str) -> list[dict]:
    """Разделы с авторами: [{key, authors: [{name, licences}]}]."""
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
