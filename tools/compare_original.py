#!/usr/bin/env python3
"""Кадр вехи рядом с кадром оригинала: одна высота, слева аркада, справа мы.

Так расхождения видно глазом, а не по таблице: на M18c сравнение сразу показало
то, чего не было ни в одном замере, — пустоватый этаж, отсутствие номеров
этажей, крышу, которая не читается верхом дома.

Кадры оригинала — нативные снимки MAME, 256×224. Они скачиваются по требованию
в `screens/_original/` и в репозиторий не идут: это снимки чужой игры, как и
вся папка `screens/`. Из кадра оригинала берётся поле здания — без HUD сверху и
кирпичной полосы снизу, 176 px, — потому что именно его показывает наша камера.

Запуск:
    python tools/compare_original.py M18C                 # последний кадр вехи
    python tools/compare_original.py M18C --shot stopped  # кадр по метке шага
    python tools/compare_original.py M18C --original elevator

Пишет `screens/<веха>/compare_original.jpg`.
"""

from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

from PIL import Image

from godot_bin import PROJECT_ROOT, use_utf8_output

SCREENS = PROJECT_ROOT / "screens"
ORIGINALS = SCREENS / "_original"

# Снимки MAME: этажи 30–27 с крышей и этажи 19–16 с эскалаторами.
SOURCES = {
    "elevatorb": "https://adb.arcadeitalia.net/media/mame.current/ingames/elevatorb.png",
    "elevator": "https://adb.arcadeitalia.net/media/mame.current/ingames/elevator.png",
}

# Поле здания в кадре оригинала: ниже HUD и выше кирпичной полосы.
FIELD = (0, 16, 256, 192)
HEIGHT = 1080
GAP = 20


def original(name: str) -> Path:
    """Путь к кадру оригинала, скачанному при первом обращении."""
    ORIGINALS.mkdir(parents=True, exist_ok=True)
    path = ORIGINALS / f"{name}.png"
    if not path.exists():
        request = urllib.request.Request(SOURCES[name], headers={"User-Agent": "elaction"})
        with urllib.request.urlopen(request, timeout=30) as response:
            path.write_bytes(response.read())
    return path


def our_shot(milestone: str, label: str | None) -> Path:
    """Последний кадр вехи, а с меткой — последний кадр этого шага."""
    folder = SCREENS / milestone
    shots = sorted(p for p in folder.glob("*.jpg") if not p.name.startswith("compare"))
    if label:
        shots = [p for p in shots if p.stem.endswith(f"_{label}")]
    if not shots:
        raise SystemExit(f"В {folder} нет кадров{f' шага {label}' if label else ''}: сначала capture.py")
    return shots[-1]


def main() -> int:
    use_utf8_output()
    parser = argparse.ArgumentParser(description="Кадр вехи рядом с оригиналом.")
    parser.add_argument("milestone", help="веха, как у capture.py, например M18C")
    parser.add_argument("--shot", help="метка шага сценария, например stopped")
    parser.add_argument("--original", choices=sorted(SOURCES), default="elevatorb")
    args = parser.parse_args()

    arcade = Image.open(original(args.original)).convert("RGB").crop(FIELD)
    arcade = arcade.resize((round(arcade.width * HEIGHT / arcade.height), HEIGHT), Image.NEAREST)
    ours = Image.open(our_shot(args.milestone, args.shot)).convert("RGB")
    ours = ours.resize((round(ours.width * HEIGHT / ours.height), HEIGHT), Image.LANCZOS)

    sheet = Image.new("RGB", (arcade.width + GAP + ours.width, HEIGHT))
    sheet.paste(arcade, (0, 0))
    sheet.paste(ours, (arcade.width + GAP, 0))
    out = SCREENS / args.milestone / "compare_original.jpg"
    sheet.save(out, quality=90)
    print(out.relative_to(PROJECT_ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
