#!/usr/bin/env python3
"""Иконка приложения: `icon.ico` из той же геометрии, что и `icon.svg`.

Windows берёт иконку из `.exe`, а вписывает её туда `rcedit` — и только из
`.ico`, SVG он не понимает. Рисовать её отдельно в редакторе значит завести
вторую копию картинки, которая разъедется с первой; поэтому она собирается
кодом, как и остальные ассеты (ADR-0011, пункт 1, и ADR-0013, пункт 9).

Геометрия — шахта с кабиной и три ряда окон, где одно красное: то же, что
в `icon.svg`, только в пикселях и во всех размерах, которые спрашивает Windows.
Результат коммитится в репозиторий, в CI скрипт не вызывается.

    python tools/render_icon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

from godot_bin import PROJECT_ROOT, use_utf8_output

OUT_FILE = PROJECT_ROOT / "icon.ico"

# Размеры внутри .ico. 256 — для крупных плиток проводника, 16 — для заголовка окна.
SIZES: tuple[int, ...] = (16, 24, 32, 48, 64, 128, 256)

# Холст оригинала: те же 128 единиц, что в viewBox иконки-SVG.
CANVAS: int = 128

# Рисуем крупно и уменьшаем: края ровные на всех размерах, а не рваные на мелких.
SUPERSAMPLE: int = 8

type Rgba = tuple[int, int, int, int]

BACKDROP: Rgba = (0x14, 0x16, 0x1F, 0xFF)
SHAFT: Rgba = (0x0B, 0x0D, 0x14, 0xFF)
CABLE: Rgba = (0x3B, 0x42, 0x57, 0xFF)
CAR: Rgba = (0xF2, 0xC1, 0x4E, 0xFF)
CAR_TOP: Rgba = (0xFF, 0xF0, 0xC2, 0xFF)
WINDOW_DARK: Rgba = (0x3B, 0x42, 0x57, 0xFF)
WINDOW_LIT: Rgba = (0xF2, 0xC1, 0x4E, 0xD9)
WINDOW_RED: Rgba = (0xC0, 0x39, 0x2B, 0xFF)

CORNER_RADIUS: int = 20

# Прямоугольники поверх фона: (x, y, ширина, высота, цвет) в единицах холста.
PARTS: tuple[tuple[int, int, int, int, Rgba], ...] = (
    (46, 14, 36, 100, SHAFT),  # шахта
    (63, 14, 2, 44, CABLE),  # трос
    (50, 56, 28, 32, CAR),  # кабина
    (50, 56, 28, 4, CAR_TOP),  # блик на крыше кабины
    (18, 30, 18, 12, WINDOW_LIT),  # окна: слева горит, справа нет
    (92, 30, 18, 12, WINDOW_DARK),
    (18, 62, 18, 12, WINDOW_DARK),
    (92, 62, 18, 12, WINDOW_LIT),
    (18, 94, 18, 12, WINDOW_RED),  # красная дверь — опознавательный знак игры
    (92, 94, 18, 12, WINDOW_DARK),
)


def draw(scale: int) -> Image.Image:
    """Рисует иконку на холсте `CANVAS * scale`."""
    size = CANVAS * scale
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas = ImageDraw.Draw(image)
    canvas.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=CORNER_RADIUS * scale,
        fill=BACKDROP,
    )

    for x, y, width, height, color in PARTS:
        # Полупрозрачные окна кладём отдельным слоем: рисовать их прямо по фону
        # Pillow не умеет — он подменяет альфу, а не смешивает цвета.
        layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).rectangle(
            (x * scale, y * scale, (x + width) * scale - 1, (y + height) * scale - 1),
            fill=color,
        )
        image = Image.alpha_composite(image, layer)

    return image


def main() -> int:
    use_utf8_output()
    master = draw(SUPERSAMPLE)
    largest = max(SIZES)
    # Pillow сам разложит крупный кадр по остальным размерам, уменьшая его тем же
    # LANCZOS; наше дело — отдать ему кадр, уже сведённый с крупного холста.
    frame = master.resize((largest, largest), Image.Resampling.LANCZOS)
    frame.save(OUT_FILE, format="ICO", sizes=[(size, size) for size in SIZES])
    print(f"{Path(OUT_FILE).name}: {', '.join(str(size) for size in SIZES)} px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
