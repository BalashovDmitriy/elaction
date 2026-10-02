#!/usr/bin/env python3
"""Следы жизни на стенах жилого дома: граффити, пятна, трещины (ADR-0055, решение 4).

Коридор жилого дома восьмидесятых — не гостиничный: на крашеной стене тэги
маркером и баллончиком, ржавые потёки и пятна, трещины в штукатурке. Свободных
наклеек такого рода в нужном стиле нет, и они рисуются здесь кодом, как обои
отеля в `build_textures.py`: PNG с прозрачностью, игра кладёт их на стену
плоскостью перед штукатуркой.

- `tag_*` — тэг: росчерк из нескольких букв-петель одним цветом с обводкой,
  край — брызгами, как у баллончика;
- `stain_*` — пятно: бурая клякса с неровным краем и потёком вниз;
- `crack_*` — трещина: ветвистая тёмная линия;
- `brick_*` — голый кирпич там, где осыпалась штукатурка (ADR-0056, решение
  4): кладка с затиркой, край штукатурки рваный, со светлым сколом.

Жребий посеян: пересборка даёт те же картинки, и в истории не шумит.

    python tools/build_wear.py

Пишет в `assets/textures/wear/<имя>.png`.
"""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT = PROJECT_ROOT / "assets/textures/wear"
SIZE = 256

# Цвета тэгов: маркер и баллончик тех лет — красный, синий, чёрный, серебро,
# зелёный. Не цвет огоньков игры (ADR-0023, решение 6) — тэги матовые и не
# светятся.
TAG_COLOURS = [(170, 30, 36), (36, 60, 150), (20, 20, 22), (170, 172, 176), (40, 120, 60)]
TAGS = 4
STAINS = 2
CRACKS = 2
BRICKS = 2


def _stroke(draw: ImageDraw.ImageDraw, points: list[tuple[float, float]], width: int, colour) -> None:
    draw.line(points, fill=colour, width=width, joint="curve")
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=colour)


def _letter(rng: random.Random, x: float, base: float, height: float) -> list[tuple[float, float]]:
    """Буква-петля: кривая через несколько опорных точек по высоте строки."""
    points = []
    steps = rng.randint(3, 5)
    for index in range(steps * 6):
        t = index / (steps * 6 - 1)
        angle = t * math.pi * steps
        px = x + t * height * 0.55 + math.sin(angle * 1.3) * height * 0.12
        py = base - (0.5 + 0.5 * math.sin(angle)) * height * rng.uniform(0.7, 1.0)
        points.append((px, py))
    return points


def tag(index: int) -> Image.Image:
    rng = random.Random(1000 + index)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    colour = TAG_COLOURS[index % len(TAG_COLOURS)]
    outline = (12, 12, 14) if sum(colour) > 200 else (230, 228, 220)
    letters = rng.randint(3, 5)
    height = SIZE * rng.uniform(0.32, 0.42)
    base = SIZE * 0.68
    strokes = []
    x = SIZE * 0.08
    for _ in range(letters):
        strokes.append(_letter(rng, x, base + rng.uniform(-8, 8), height))
        x += height * rng.uniform(0.38, 0.5)
    # Подчёркивание-росчерк под тэгом.
    tail = [(SIZE * 0.1 + i * SIZE * 0.08, base + 14 + math.sin(i * 0.9) * 6) for i in range(11)]
    strokes.append(tail)
    width = rng.randint(9, 13)
    draw = ImageDraw.Draw(image)
    for points in strokes:
        _stroke(draw, points, width + 6, (*outline, 255))
    for points in strokes:
        _stroke(draw, points, width, (*colour, 255))
    # Брызги баллончика вокруг линий.
    spray = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    spray_draw = ImageDraw.Draw(spray)
    for points in strokes:
        for px, py in points[:: 2]:
            for _ in range(3):
                dx, dy = rng.gauss(0, width * 0.9), rng.gauss(0, width * 0.9)
                r = rng.uniform(0.6, 1.6)
                spray_draw.ellipse((px + dx - r, py + dy - r, px + dx + r, py + dy + r), fill=(*colour, 170))
    image = Image.alpha_composite(spray, image)
    # Краска выцвела и легла на штукатурку неровно.
    alpha = image.getchannel("A").point(lambda v: int(v * 0.88))
    image.putalpha(alpha)
    return image.filter(ImageFilter.GaussianBlur(0.6))


def stain(index: int) -> Image.Image:
    rng = random.Random(2000 + index)
    mask = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    cx, cy = SIZE * 0.5, SIZE * 0.38
    for _ in range(40):
        r = rng.uniform(SIZE * 0.05, SIZE * 0.18)
        x = cx + rng.gauss(0, SIZE * 0.1)
        y = cy + rng.gauss(0, SIZE * 0.07)
        draw.ellipse((x - r, y - r, x + r, y + r), fill=rng.randint(60, 140))
    # Потёки вниз.
    for _ in range(rng.randint(2, 4)):
        x = cx + rng.uniform(-SIZE * 0.15, SIZE * 0.15)
        length = rng.uniform(SIZE * 0.2, SIZE * 0.45)
        draw.line([(x, cy), (x + rng.uniform(-4, 4), cy + length)], fill=110, width=rng.randint(4, 8))
    mask = mask.filter(ImageFilter.GaussianBlur(7))
    colour = Image.new("RGBA", (SIZE, SIZE), (78, 56, 34, 255))
    colour.putalpha(mask.point(lambda v: int(min(v * 1.5, 190))))
    return colour


def crack(index: int) -> Image.Image:
    rng = random.Random(3000 + index)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    def branch(x: float, y: float, angle: float, length: float, width: float, depth: int) -> None:
        points = [(x, y)]
        for _ in range(int(length / 6)):
            angle += rng.gauss(0, 0.35)
            x += math.cos(angle) * 6
            y += math.sin(angle) * 6
            points.append((x, y))
        draw.line(points, fill=(18, 16, 14, 230), width=max(1, int(width)))
        if depth > 0:
            for _ in range(rng.randint(1, 2)):
                at = rng.randrange(len(points))
                bx, by = points[at]
                branch(bx, by, angle + rng.choice((-1, 1)) * rng.uniform(0.5, 1.1), length * 0.5, width * 0.6, depth - 1)

    branch(SIZE * 0.1, SIZE * rng.uniform(0.3, 0.7), rng.uniform(-0.3, 0.3), SIZE * 0.85, 3.0, 3)
    return image.filter(ImageFilter.GaussianBlur(0.4))


def brick(index: int) -> Image.Image:
    rng = random.Random(4000 + index)
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    course = 18
    length = 44
    mortar = (128, 116, 102, 255)
    for row in range(SIZE // course + 1):
        y = row * course
        draw.rectangle((0, y, SIZE, y + course), fill=mortar)
        shift = (length // 2) * (row % 2)
        for column in range(-1, SIZE // length + 2):
            x = column * length - shift
            tone = rng.randint(-14, 14)
            base = (126 + tone, 62 + tone // 2, 46 + tone // 3, 255)
            draw.rectangle((x + 2, y + 2, x + length - 2, y + course - 2), fill=base)
    # Рваный край: клякса-маска, за её краем — светлый скол штукатурки.
    mask = Image.new("L", (SIZE, SIZE), 0)
    shape = ImageDraw.Draw(mask)
    centre = SIZE * 0.5
    points = []
    for step in range(28):
        angle = math.tau * step / 28
        radius = SIZE * rng.uniform(0.3, 0.46)
        points.append((centre + math.cos(angle) * radius, centre + math.sin(angle) * radius * 0.8))
    shape.polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    rim = mask.filter(ImageFilter.MaxFilter(9))
    chip = Image.new("RGBA", (SIZE, SIZE), (196, 188, 172, 255))
    chip.putalpha(rim.point(lambda v: 255 if v > 40 else 0))
    image.putalpha(mask.point(lambda v: 255 if v > 128 else 0))
    return Image.alpha_composite(chip, image)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    made = []
    for index in range(TAGS):
        made.append((f"tag_{index}", tag(index)))
    for index in range(STAINS):
        made.append((f"stain_{index}", stain(index)))
    for index in range(CRACKS):
        made.append((f"crack_{index}", crack(index)))
    for index in range(BRICKS):
        made.append((f"brick_{index}", brick(index)))
    for name, image in made:
        image.save(OUT / f"{name}.png", optimize=True)
        print(f"  {name}.png")
    print(f"Следы в {OUT.relative_to(PROJECT_ROOT).as_posix()}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
