#!/usr/bin/env python3
"""Генератор ассетов окружения: диффуз, нормаль и specular из одной геометрии.

ADR-0011, пункты 1 и 7: у окружения нет анимации, поэтому его дешевле описать
кодом, чем моделить. И раз геометрия известна до картинки, нормаль считается
точно — из карты высот, которую рисует тот же код, что и цвет, — а не угадывается
по яркости готового спрайта.

Ассеты коммитятся в репозиторий (ADR-0011, пункт 2): этот скрипт — инструмент
разработчика, а не шаг сборки. В CI он не вызывается.

    python tools/render_env.py           # всё
    python tools/render_env.py slab      # только один ассет
    python tools/render_env.py --list
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

import numpy as np
from PIL import Image

import palette
from palette import Material, Rgb

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets/sprites/env"

# Насколько резко карта высот превращается в наклон нормали. Подобрано на
# перекрытии: при 1.0 фаска почти не видна, при 6.0 плоская плита выглядит
# надутой и свет ползёт по ней пятном.
NORMAL_STRENGTH: float = 3.0

# Зелёный канал нормали смотрит вверх — соглашение OpenGL, его же ждёт Godot.
# Если свет однажды ляжет наоборот, переключается здесь, а не в каждом ассете.
NORMAL_GREEN_UP: bool = True

# Суффиксы карт. Diffuse лежит под собственным именем ассета.
NORMAL_SUFFIX = "_n"
SPECULAR_SUFFIX = "_s"

# Ширина рамки девятикусочных ассетов. Та же величина стоит в
# `EnvTextures.FRAME_MARGIN`, и тест следит, чтобы они не разошлись.
FRAME_MARGIN: int = 8


class Canvas:
    """Три карты одного ассета, которые рисуются вместе.

    `diffuse` — цвет с альфой, `height` — высота 0..1 для расчёта нормали,
    `specular` — сила блика и его резкость. Всё рисуется одними и теми же
    прямоугольниками, поэтому карты не могут разъехаться между собой.
    """

    def __init__(self, width: int, height: int, wrap_x: bool = False, wrap_y: bool = False) -> None:
        self.width = width
        self.height = height
        # Тайл замыкается по своим осям: у нормали на швах берётся сосед
        # с другого края, иначе на стыке двух копий видна тёмная линия.
        # Перекрытие повторяется только вбок, стена — во все стороны.
        self.wrap_x = wrap_x
        self.wrap_y = wrap_y
        self.diffuse = np.zeros((height, width, 4), dtype=np.uint8)
        self.height_map = np.zeros((height, width), dtype=np.float32)
        self.specular = np.zeros((height, width, 2), dtype=np.float32)

    def rect(
        self,
        x: int,
        y: int,
        width: int,
        height: int,
        color: Rgb,
        depth: float,
        material: Material,
        alpha: int = 255,
    ) -> None:
        """Прямоугольник во все три карты разом. Координаты — от левого верха."""
        left = max(x, 0)
        top = max(y, 0)
        right = min(x + width, self.width)
        bottom = min(y + height, self.height)
        if right <= left or bottom <= top:
            return

        self.diffuse[top:bottom, left:right] = (*color, alpha)
        self.height_map[top:bottom, left:right] = depth
        self.specular[top:bottom, left:right] = (material.specular, material.shininess)

    def speckle(self, seed: int, amount: int, area: tuple[int, int, int, int]) -> None:
        """Крапинка на диффузе: бетон без неё читается как пластик.

        Сид фиксирован, поэтому повторный рендер даёт тот же файл (ADR-0011,
        пункт 2: ассеты производные, но воспроизводимые).
        """
        rng = np.random.default_rng(seed)
        x, y, width, height = area
        patch = self.diffuse[y : y + height, x : x + width, :3].astype(np.int16)
        noise = rng.integers(-amount, amount + 1, size=patch.shape[:2])
        patch += noise[:, :, None]
        self.diffuse[y : y + height, x : x + width, :3] = np.clip(patch, 0, 255).astype(np.uint8)

    def roughen(self, seed: int, amount: float) -> None:
        """Мелкая шероховатость высоты: свет по такой стене идёт не стеклом.

        Шум добавляется ко всей карте разом и повторяется по краям, поэтому
        замкнутый тайл остаётся замкнутым.
        """
        rng = np.random.default_rng(seed)
        noise = rng.uniform(-amount, amount, size=self.height_map.shape).astype(np.float32)
        if self.wrap_x:
            noise[:, -1] = noise[:, 0]
        if self.wrap_y:
            noise[-1, :] = noise[0, :]
        self.height_map = np.clip(self.height_map + noise, 0.0, 1.0)

    def normal_map(self) -> np.ndarray:
        """Нормаль из карты высот: наклон поверхности, посчитанный, а не угаданный."""
        padded = np.pad(self.height_map, ((1, 1), (0, 0)), mode="wrap" if self.wrap_y else "edge")
        padded = np.pad(padded, ((0, 0), (1, 1)), mode="wrap" if self.wrap_x else "edge")

        gradient_x = (padded[1:-1, 2:] - padded[1:-1, :-2]) * 0.5
        gradient_y = (padded[2:, 1:-1] - padded[:-2, 1:-1]) * 0.5

        normal_x = -gradient_x * NORMAL_STRENGTH
        # В картинке y растёт вниз, а в нормали зелёный смотрит вверх, поэтому
        # знак меняется: склон, уходящий вниз по картинке, светится сверху.
        normal_y = gradient_y * NORMAL_STRENGTH
        if not NORMAL_GREEN_UP:
            normal_y = -normal_y
        normal_z = np.ones_like(normal_x)

        length = np.sqrt(normal_x**2 + normal_y**2 + normal_z**2)
        stacked = np.stack((normal_x / length, normal_y / length, normal_z / length), axis=-1)
        return np.clip(np.rint((stacked * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)

    def specular_map(self) -> np.ndarray:
        """RGB — сила блика, альфа — его резкость: так карту читает CanvasTexture."""
        strength = np.clip(np.rint(self.specular[:, :, 0] * 255.0), 0, 255).astype(np.uint8)
        shininess = np.clip(np.rint(self.specular[:, :, 1] * 255.0), 0, 255).astype(np.uint8)
        return np.stack((strength, strength, strength, shininess), axis=-1)

    def save(self, out_dir: Path, name: str) -> list[Path]:
        """Пишет три PNG и возвращает их пути."""
        out_dir.mkdir(parents=True, exist_ok=True)
        written: list[Path] = []
        for suffix, data in (
            ("", self.diffuse),
            (NORMAL_SUFFIX, self.normal_map()),
            (SPECULAR_SUFFIX, self.specular_map()),
        ):
            # Форму Pillow выводит сам: диффуз и specular четырёхканальные,
            # нормаль трёхканальная — альфа ей не нужна.
            path = out_dir / f"{name}{suffix}.png"
            Image.fromarray(data).save(path, optimize=True)
            written.append(path)
        return written


# --- Ассеты -----------------------------------------------------------------


def slab() -> Canvas:
    """Перекрытие: тайл во всю его толщину, замыкающийся по горизонтали.

    Толщина — 20 px, как `BuildingRules.slab_height`; ширина тайла 32 px, и
    плита любой длины набирается повтором. Сверху — ходовая поверхность с
    блестящей кромкой, снизу — потолок нижнего этажа, темнее всего.
    """
    canvas = Canvas(32, 20, wrap_x=True)
    canvas.rect(0, 0, 32, 20, palette.SLAB_FACE, 0.55, palette.CONCRETE)

    # Кромка и ходовая поверхность: свет сверху, значит верх ловит его первым.
    canvas.rect(0, 0, 32, 1, palette.SLAB_EDGE, 1.0, palette.CONCRETE)
    canvas.rect(0, 1, 32, 2, palette.SLAB_TOP, 0.95, palette.CONCRETE)
    canvas.rect(0, 3, 32, 1, palette.mix(palette.SLAB_TOP, palette.SLAB_FACE, 0.5), 0.72, palette.CONCRETE)

    # Шов между плитами: вертикальная канавка на стыке тайлов. Она же
    # доказывает, что тайл замкнут — на шве нормаль не рвётся.
    canvas.rect(0, 4, 2, 13, palette.SLAB_SHADOW, 0.38, palette.CONCRETE)

    # Потолок нижнего этажа: сюда свет почти не достаёт.
    canvas.rect(0, 17, 32, 2, palette.mix(palette.SLAB_FACE, palette.SLAB_SHADOW, 0.6), 0.48, palette.CONCRETE)
    canvas.rect(0, 19, 32, 1, palette.SLAB_SHADOW, 0.42, palette.CONCRETE)

    canvas.speckle(seed=1983, amount=5, area=(0, 4, 32, 13))
    return canvas


def wall() -> Canvas:
    """Задняя стена комнаты: штукатурка, замкнутая во все стороны.

    Ровный тон без рисунка: стена — дальний план, и любая полоска на ней
    повторилась бы сеткой по всему зданию, потому что высота этажа (120 px)
    на размер тайла не делится. Свету достаётся не рисунок, а шероховатость.
    """
    canvas = Canvas(32, 32, wrap_x=True, wrap_y=True)
    canvas.rect(0, 0, 32, 32, palette.WALL_BASE, 0.5, palette.PLASTER)
    canvas.speckle(seed=1983, amount=4, area=(0, 0, 32, 32))
    canvas.roughen(seed=1984, amount=0.05)
    return canvas


def wall_side() -> Canvas:
    """Боковая стена здания: та же штукатурка, но тайл в ширину стены.

    Ширина — `GreyboxLevel.WALL_WIDTH`, иначе стена собиралась бы из обрезков.
    Тёмная кромка внутрь: угол комнаты должен читаться как угол.
    """
    canvas = Canvas(16, 32, wrap_y=True)
    canvas.rect(0, 0, 16, 32, palette.WALL_SHADE, 0.5, palette.PLASTER)
    canvas.rect(0, 0, 3, 32, palette.mix(palette.WALL_SHADE, palette.WALL_BASE, 0.6), 0.62, palette.PLASTER)
    canvas.rect(13, 0, 3, 32, palette.mix(palette.WALL_SHADE, palette.WALL_BASE, 0.6), 0.62, palette.PLASTER)
    canvas.speckle(seed=1985, amount=3, area=(0, 0, 16, 32))
    canvas.roughen(seed=1986, amount=0.04)
    return canvas


def window_frame() -> Canvas:
    """Рама окна: девятикусочный ассет с пустой серединой.

    Кладётся поверх проёма, в котором виден город, поэтому центр прозрачен.
    Сторона — 3 × [constant FRAME_MARGIN]: угол, повторяемая середина, угол.
    Внутренняя кромка приподнята — на ней и играет свет этажа.
    """
    side = FRAME_MARGIN * 3
    canvas = Canvas(side, side)
    canvas.rect(0, 0, side, side, palette.METAL_SHADE, 0.35, palette.PAINT)
    canvas.rect(1, 1, side - 2, side - 2, palette.METAL, 0.75, palette.PAINT)
    # Блестит только внутренняя кромка: рама целиком из полированного металла
    # выбеливалась под заливкой этажа и спорила яркостью с красной дверью.
    canvas.rect(
        FRAME_MARGIN - 2,
        FRAME_MARGIN - 2,
        side - 2 * (FRAME_MARGIN - 2),
        side - 2 * (FRAME_MARGIN - 2),
        palette.mix(palette.METAL, palette.METAL_TRIM, 0.4),
        0.95,
        palette.POLISHED_METAL,
    )
    # Середина вырезается: в неё смотрит город, а не стена.
    canvas.rect(
        FRAME_MARGIN,
        FRAME_MARGIN,
        side - 2 * FRAME_MARGIN,
        side - 2 * FRAME_MARGIN,
        palette.GLASS,
        0.0,
        palette.WINDOW_GLASS,
        alpha=0,
    )
    return canvas


ASSETS: dict[str, Callable[[], Canvas]] = {
    "slab": slab,
    "wall": wall,
    "wall_side": wall_side,
    "window_frame": window_frame,
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Рендер ассетов окружения.")
    parser.add_argument("names", nargs="*", help="какие ассеты рисовать; по умолчанию все")
    parser.add_argument("--list", action="store_true", help="перечислить ассеты и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать PNG")
    arguments = parser.parse_args()

    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")

    if arguments.list:
        for name in sorted(ASSETS):
            print(name)
        return 0

    names = arguments.names or sorted(ASSETS)
    unknown = [name for name in names if name not in ASSETS]
    if unknown:
        print(f"Неизвестные ассеты: {', '.join(unknown)}")
        print(f"Известные: {', '.join(sorted(ASSETS))}")
        return 2

    for name in names:
        canvas = ASSETS[name]()
        for path in canvas.save(arguments.out, name):
            print(path.relative_to(PROJECT_ROOT).as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
