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
from collections.abc import Callable
from pathlib import Path

import numpy as np
from PIL import Image

import palette
from godot_bin import use_utf8_output
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
# `SpriteTextures.FRAME_MARGIN`, и тест следит, чтобы они не разошлись.
FRAME_MARGIN: int = 8


def normals(
    height_map: np.ndarray,
    wrap_x: bool = False,
    wrap_y: bool = False,
    strength: float = NORMAL_STRENGTH,
) -> np.ndarray:
    """Карта нормалей из карты высот, готовая к записи в PNG.

    Вынесена из [class Canvas] отдельно, потому что ей пользуется и генератор
    актёров: у него высота приходит из рендера глубины в Blender, а соглашение
    о каналах должно остаться одно на проект.
    """
    padded = np.pad(height_map, ((1, 1), (0, 0)), mode="wrap" if wrap_y else "edge")
    padded = np.pad(padded, ((0, 0), (1, 1)), mode="wrap" if wrap_x else "edge")

    gradient_x = (padded[1:-1, 2:] - padded[1:-1, :-2]) * 0.5
    gradient_y = (padded[2:, 1:-1] - padded[:-2, 1:-1]) * 0.5

    normal_x = -gradient_x * strength
    # В картинке y растёт вниз, а в нормали зелёный смотрит вверх, поэтому
    # знак меняется: склон, уходящий вниз по картинке, светится сверху.
    normal_y = gradient_y * strength
    if not NORMAL_GREEN_UP:
        normal_y = -normal_y
    normal_z = np.ones_like(normal_x)

    length = np.sqrt(normal_x**2 + normal_y**2 + normal_z**2)
    stacked = np.stack((normal_x / length, normal_y / length, normal_z / length), axis=-1)
    return np.clip(np.rint((stacked * 0.5 + 0.5) * 255.0), 0, 255).astype(np.uint8)


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

        Шум кладётся по всей карте без оглядки на швы: замкнутым тайл делает не
        он, а [method normal_map] — на замкнутой оси наклон на краю считается по
        соседу с другого края, и подгонять сами высоты незачем.
        """
        rng = np.random.default_rng(seed)
        noise = rng.uniform(-amount, amount, size=self.height_map.shape).astype(np.float32)
        self.height_map = np.clip(self.height_map + noise, 0.0, 1.0)

    def normal_map(self) -> np.ndarray:
        """Нормаль из карты высот: наклон поверхности, посчитанный, а не угаданный."""
        return normals(self.height_map, self.wrap_x, self.wrap_y)

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
    """Боковая стена здания: кирпичная кладка в ширину стены.

    Ширина — `GreyboxLevel.WALL_WIDTH`, иначе стена собиралась бы из обрезков.
    В порте бока здания — красный кирпич с белым швом (ADR-0017); красным его
    делает тон раунда, а здесь кладётся только рисунок: ряды со смещением
    и светлый шов между ними.

    Ряд — 8 px, и тайл в 32 px закрывает четыре ряда, замыкаясь по вертикали.
    """
    canvas = Canvas(16, 32, wrap_y=True)
    canvas.rect(0, 0, 16, 32, palette.BRICK_BASE, 0.5, palette.CONCRETE)

    for row in range(4):
        top = row * 8
        # Горизонтальный шов: он же отделяет ряд от ряда.
        canvas.rect(0, top, 16, 1, palette.BRICK_MORTAR, 0.75, palette.CONCRETE)
        # Вертикальный шов: через ряд он сдвигается на полкирпича — иначе
        # кладка читается сеткой, а не кладкой.
        seam = 3 if row % 2 == 0 else 11
        canvas.rect(seam, top + 1, 1, 7, palette.BRICK_MORTAR, 0.7, palette.CONCRETE)
        # Тень под швом: кирпич должен быть телом, а не плоским прямоугольником.
        canvas.rect(0, top + 6, 16, 2, palette.BRICK_SHADE, 0.42, palette.CONCRETE)

    canvas.speckle(seed=1985, amount=4, area=(0, 0, 16, 32))
    canvas.roughen(seed=1986, amount=0.05)
    return canvas


def shaft_rail() -> Canvas:
    """Направляющая шахты: узкая стойка, идущая по краю проёма во всю высоту.

    Шахта у нас была дырой в перекрытии со столбом света — в кадре её почти
    не было, хотя спуск по зданию и есть игра (ADR-0017, решение 3). Стойка
    даёт шахте край: по ней видно, где она начинается и докуда идёт.

    Серая: цвет ей задаёт тон раунда. Тайл замкнут по вертикали, ширина —
    `GreyboxLevel.SHAFT_RAIL_WIDTH`.
    """
    canvas = Canvas(6, 16, wrap_y=True)
    canvas.rect(0, 0, 6, 16, palette.SHAFT_RAIL, 0.55, palette.POLISHED_METAL)
    # Рисунок симметричен нарочно: тайл кладётся на оба края проёма одним и тем
    # же узлом, без зеркала, и несимметричная стойка светилась бы справа не с той
    # стороны, с которой слева.
    canvas.rect(0, 0, 1, 16, palette.SHAFT_RAIL_SHADE, 0.4, palette.POLISHED_METAL)
    canvas.rect(5, 0, 1, 16, palette.SHAFT_RAIL_SHADE, 0.4, palette.POLISHED_METAL)
    canvas.rect(2, 0, 2, 16, palette.SHAFT_RAIL_TRIM, 0.9, palette.POLISHED_METAL)
    # Стыки стойки: по ним видно движение кабины мимо.
    canvas.rect(0, 0, 6, 1, palette.SHAFT_RAIL_SHADE, 0.45, palette.POLISHED_METAL)
    return canvas


def shaft_door() -> Canvas:
    """Створки шахты на этаже: по ним видно, где кабина останавливается.

    Размер — ширина шахты на `GreyboxLevel.SHAFT_DOOR_HEIGHT`. Две половинки
    со швом посередине и светлая перемычка сверху — та самая, что в порте
    отмечает этаж поперёк шахты. Серые: цвет даёт тон раунда.
    """
    canvas = Canvas(40, 34)
    canvas.rect(0, 0, 40, 34, palette.SHAFT_RAIL_SHADE, 0.45, palette.POLISHED_METAL)
    # Перемычка над проёмом.
    canvas.rect(0, 0, 40, 5, palette.SHAFT_RAIL_TRIM, 0.85, palette.POLISHED_METAL)
    canvas.rect(0, 5, 40, 1, palette.SHAFT_RAIL, 0.6, palette.POLISHED_METAL)
    # Сами створки и шов между ними.
    canvas.rect(2, 7, 36, 27, palette.SHAFT_RAIL, 0.6, palette.POLISHED_METAL)
    canvas.rect(19, 7, 2, 27, palette.SHAFT_RAIL_SHADE, 0.35, palette.POLISHED_METAL)
    # Кромки створок: свет цепляется за них и створки читаются створками.
    canvas.rect(2, 7, 1, 27, palette.SHAFT_RAIL_TRIM, 0.8, palette.POLISHED_METAL)
    canvas.rect(37, 7, 1, 27, palette.SHAFT_RAIL_TRIM, 0.8, palette.POLISHED_METAL)
    return canvas


def machine_room() -> Canvas:
    """Надстройка машинного отделения над верхней шахтой.

    В порте это домик на крыше со своей двускатной крышей и кирпичными боками
    (ADR-0017, решение 4). Размер — `GreyboxLevel.MACHINE_ROOM_SIZE`.

    Весь домик серый: уровень красит его тоном раунда целиком, одним
    `modulate` на узел. Крыша поэтому не белая, а просто светлее боков —
    отдельным белым она была бы, только если бы домик собирался из двух узлов,
    а ради одной надстройки это лишний узел на здание.

    Ряд кладки — 8 px, кирпич — 24 px: 72 делится на него нацело, и крайний
    кирпич выходит такой же, как остальные. На 32 px последний шов ложился бы
    за край холста, `Canvas.rect` молча его отбрасывал, и справа оставался
    кирпич в полтора раза шире прочих.
    """
    canvas = Canvas(72, 44)
    # Кирпичные бока.
    canvas.rect(0, 10, 72, 34, palette.BRICK_BASE, 0.5, palette.CONCRETE)
    for row in range(4):
        top = 12 + row * 8
        canvas.rect(0, top, 72, 1, palette.BRICK_MORTAR, 0.72, palette.CONCRETE)
        seam = 6 if row % 2 == 0 else 18
        for step in range(0, 72, 24):
            canvas.rect(seam + step, top + 1, 1, 7, palette.BRICK_MORTAR, 0.68, palette.CONCRETE)

    # Двускатная крыша: две плоскости и конёк между ними.
    for step in range(6):
        inset = step * 6
        canvas.rect(inset, 10 - step * 2, 72 - inset * 2, 2, palette.SLAB_TOP, 0.9, palette.CONCRETE)
    canvas.rect(30, 0, 12, 2, palette.SLAB_EDGE, 1.0, palette.CONCRETE)
    # Проём, в котором ходит кабина: он же подсказывает, что домик над шахтой.
    canvas.rect(26, 24, 20, 20, palette.SLAB_SHADOW, 0.2, palette.CONCRETE)
    canvas.speckle(seed=1989, amount=4, area=(0, 10, 72, 34))
    return canvas


def rope() -> Canvas:
    """Трос, по которому Otto съезжает на крышу: жёлтый пунктир до края кадра.

    Тайл замкнут по вертикали и тянется вверх от места, где Otto встаёт.
    Тоном раунда не красится: в порте трос жёлтый в любом кадре.
    """
    canvas = Canvas(4, 12, wrap_y=True)
    canvas.rect(1, 0, 2, 7, palette.ROPE, 0.7, palette.POLISHED_METAL)
    canvas.rect(1, 7, 2, 2, palette.ROPE_SHADE, 0.45, palette.POLISHED_METAL)
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


## Размер створки двери: он же размер узла `Panel` в `door.tscn`.
DOOR_SIZE = (24, 34)


def _door(panel: Rgb, ajar: bool = False, opened: bool = False) -> Canvas:
    """Створка двери: косяк, две филёнки и ручка.

    Состояний у двери четыре, и они различаются не оттенком одного
    прямоугольника, как было в greybox, а тем, что нарисовано внутри косяка.
    """
    width, height = DOOR_SIZE
    canvas = Canvas(width, height)
    canvas.rect(0, 0, width, height, palette.DOOR_FRAME, 0.7, palette.WOOD)

    if opened:
        # Открытая дверь — это не дверь, а проём: за ней темнота комнаты.
        canvas.rect(2, 2, width - 4, height - 2, palette.SLAB_SHADOW, 0.15, palette.PLASTER)
        return canvas

    canvas.rect(2, 2, width - 4, height - 2, panel, 0.55, palette.WOOD)
    shade = palette.mix(panel, palette.SLAB_SHADOW, 0.35)
    canvas.rect(5, 5, width - 10, 11, shade, 0.42, palette.WOOD)
    canvas.rect(5, 19, width - 10, 11, shade, 0.42, palette.WOOD)
    canvas.rect(width - 6, height // 2 - 1, 2, 3, palette.METAL_TRIM, 0.95, palette.POLISHED_METAL)

    if ajar:
        # Приоткрытая: у косяка чёрная щель, и по ней видно, что створка пошла.
        canvas.rect(2, 2, 4, height - 2, palette.SLAB_SHADOW, 0.2, palette.PLASTER)
    return canvas


def door() -> Canvas:
    """Обычная дверь: из таких выходят агенты."""
    return _door(palette.DOOR_PANEL)


def door_red() -> Canvas:
    """Красная дверь — за ней документ. Единственное красное в кадре."""
    return _door(palette.DOOR_RED)


def door_ajar() -> Canvas:
    """Дверь пошла открываться."""
    return _door(palette.DOOR_PANEL, ajar=True)


def door_open() -> Canvas:
    """Дверь открыта: за ней темнота комнаты."""
    return _door(palette.DOOR_PANEL, opened=True)


def door_mat() -> Canvas:
    """Коврик у двери: по нему видно вход раньше, чем дверь откроется."""
    canvas = Canvas(20, 3)
    canvas.rect(0, 0, 20, 3, palette.MAT, 0.3, palette.FABRIC)
    canvas.rect(0, 0, 20, 1, palette.mix(palette.MAT, palette.OTTO_SUIT, 0.3), 0.4, palette.FABRIC)
    canvas.speckle(seed=1987, amount=6, area=(0, 0, 20, 3))
    return canvas


def car_slab() -> Canvas:
    """Настил кабины: одна и та же плита идёт и на пол, и на крышу.

    Размер — как у `RectangleShape2D_slab` в `elevator_car.tscn`. Металл
    блестит заметно: по блику кабина и отличается от бетона перекрытия.
    """
    canvas = Canvas(40, 6)
    canvas.rect(0, 0, 40, 6, palette.METAL, 0.7, palette.POLISHED_METAL)
    canvas.rect(0, 0, 40, 1, palette.METAL_TRIM, 0.9, palette.POLISHED_METAL)
    canvas.rect(0, 5, 40, 1, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)
    for x in range(4, 40, 8):
        canvas.rect(x, 2, 2, 2, palette.METAL_TRIM, 0.85, palette.POLISHED_METAL)
    return canvas


def escalator_belt() -> Canvas:
    """Полотно эскалатора: тайл в одну ступень, тянется вдоль наклонной линии."""
    canvas = Canvas(8, 6, wrap_x=True)
    canvas.rect(0, 0, 8, 6, palette.METAL_SHADE, 0.6, palette.POLISHED_METAL)
    canvas.rect(0, 0, 8, 1, palette.METAL_TRIM, 0.85, palette.POLISHED_METAL)
    canvas.rect(0, 0, 1, 6, palette.SLAB_SHADOW, 0.35, palette.POLISHED_METAL)
    return canvas


def lamp() -> Canvas:
    """Лампа под потолком: подвес, абажур и горящий низ.

    Размер — как коллизия в `lamp.tscn`: она сбивается выстрелом в прыжке, и
    менять её ради картинки нельзя (ADR-0011, пункт 4).
    """
    canvas = Canvas(16, 24)
    canvas.rect(7, 0, 2, 8, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)
    # Абажур расширяется книзу: строка за строкой, чтобы нормаль пошла конусом.
    for row in range(8, 20):
        # Абажур расходится от 3 px до 8 px — до края холста, но не за него:
        # вылезший конус обрезался бы прямоугольником и читался как коробка.
        half = round(3 + 5 * (row - 8) / 11)
        left = 8 - half
        # Абажур тёмный: он стоит в своём же пятне света, и светлый выбеливался
        # в белое пятно. Лампа читается силуэтом вокруг горящего низа.
        tone = palette.mix(palette.SLAB_SHADOW, palette.LAMP_SHADE, (row - 8) / 11.0 * 0.45)
        canvas.rect(left, row, half * 2, 1, tone, 0.5 + (row - 8) * 0.03, palette.PAINT)
    canvas.rect(2, 20, 12, 4, palette.LAMP_GLOW, 0.95, palette.PAINT)
    return canvas


def exit_way() -> Canvas:
    """Выход на улицу: проём со светящейся вывеской над ним.

    Размер — `GreyboxLevel.EXIT_WIDTH` на `EXIT_HEIGHT`. Зелёный тут
    единственный: по нему выход виден с другого конца этажа.
    """
    canvas = Canvas(64, 40)
    canvas.rect(0, 0, 64, 40, palette.WALL_SHADE, 0.6, palette.PLASTER)
    canvas.rect(4, 10, 56, 30, palette.SLAB_SHADOW, 0.2, palette.PLASTER)
    canvas.rect(2, 8, 60, 2, palette.METAL_TRIM, 0.8, palette.POLISHED_METAL)
    canvas.rect(18, 1, 28, 7, palette.EXIT_SIGN, 0.9, palette.PAINT)
    canvas.rect(20, 3, 24, 3, palette.mix(palette.EXIT_SIGN, palette.OTTO_SUIT, 0.7), 0.95, palette.PAINT)
    return canvas


def bullet() -> Canvas:
    """Пуля: 6×2, как коллизия в `bullet.tscn`. Горячая середина, тусклые концы.

    Симметрично нарочно: `bullet.gd` не зеркалит спрайт, потому что направление
    показывает сам полёт. Яркий конец вместо середины летел бы влево хвостом
    вперёд — половину выстрелов в игре.
    """
    canvas = Canvas(6, 2)
    canvas.rect(0, 0, 6, 2, palette.mix(palette.BULLET, palette.IMPACT, 0.5), 0.6, palette.PAINT)
    canvas.rect(2, 0, 2, 2, palette.BULLET, 0.9, palette.PAINT)
    return canvas


def city_wall() -> Canvas:
    """Стена дальней башни. Света здания на неё не падает — рельеф ей ни к чему,
    но зерно нужно: ровная заливка на весь силуэт читается как дыра в кадре."""
    canvas = Canvas(16, 16, wrap_x=True, wrap_y=True)
    canvas.rect(0, 0, 16, 16, palette.CITY_BODY, 0.5, palette.CONCRETE)
    canvas.speckle(seed=1988, amount=3, area=(0, 0, 16, 16))
    return canvas


ASSETS: dict[str, Callable[[], Canvas]] = {
    "slab": slab,
    "wall": wall,
    "wall_side": wall_side,
    "window_frame": window_frame,
    "door": door,
    "door_red": door_red,
    "door_ajar": door_ajar,
    "door_open": door_open,
    "door_mat": door_mat,
    "car_slab": car_slab,
    "escalator_belt": escalator_belt,
    "shaft_rail": shaft_rail,
    "shaft_door": shaft_door,
    "machine_room": machine_room,
    "rope": rope,
    "lamp": lamp,
    "exit_way": exit_way,
    "bullet": bullet,
    "city_wall": city_wall,
}


def _shown(path: Path) -> str:
    """Путь для вывода: внутри проекта — относительный, снаружи — как есть.

    `--out` умеет показывать куда угодно, и `relative_to` на такой путь падает.
    """
    try:
        return path.relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def main() -> int:
    # До разбора аргументов: подсказки и ошибки argparse тоже по-русски.
    use_utf8_output()

    parser = argparse.ArgumentParser(description="Рендер ассетов окружения.")
    parser.add_argument("names", nargs="*", help="какие ассеты рисовать; по умолчанию все")
    parser.add_argument("--list", action="store_true", help="перечислить ассеты и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать PNG")
    arguments = parser.parse_args()

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
            print(_shown(path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
