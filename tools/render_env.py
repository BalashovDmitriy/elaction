#!/usr/bin/env python3
"""Генератор ассетов окружения: диффуз, нормаль и specular из одной геометрии.

ADR-0011, пункты 1 и 7: у окружения нет анимации, поэтому его дешевле описать
кодом, чем моделить. И раз геометрия известна до картинки, нормаль считается
точно — из карты высот, которую рисует тот же код, что и цвет, — а не угадывается
по яркости готового спрайта.

Ассеты коммитятся в репозиторий (ADR-0011, пункт 2): этот скрипт — инструмент
разработчика, а не шаг сборки. В CI он не вызывается.

    python tools/render_env.py           # всё, в масштабе набора
    python tools/render_env.py slab      # только один ассет
    python tools/render_env.py --list
    python tools/render_env.py --scale 6 --out assets/sprites/env6   # проба под 4K
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

# Ширина рамки девятикусочных ассетов, в единицах мира. В пикселях она выходит
# в `SCALE` раз больше, и ровно это число стоит в `SpriteTextures.FRAME_MARGIN`
# (8 × 3 = 24); тест следит, чтобы они не разошлись.
FRAME_MARGIN: int = 8

# Во сколько раз крупнее рисовать. Ассеты описаны в единицах мира, а не в
# пикселях экрана: холст и каждый прямоугольник умножаются здесь, и ни один
# ассет об этом не знает. Так набор перерисовывается под другое разрешение,
# не переписываясь по числу в каждой функции.
#
# Умолчание — это масштаб набора, который лежит в репозитории (ADR-0018): запуск
# без флага обязан перерисовать те же ассеты, что уже закоммичены. Тройка здесь,
# а не в памяти запускающего: с умолчанием 1 обычный `python tools/render_env.py`
# молча уменьшал весь набор втрое, и здание рассыпалось на обрезки.
DEFAULT_SCALE: int = 3
SCALE: int = DEFAULT_SCALE


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
        # Размер приходит в единицах мира, холст живёт в пикселях: на масштабе 3
        # тайл в 32 единицы становится 96 пикселями, а рисуется тем же кодом.
        self.scale = SCALE
        self.width = width * self.scale
        self.height = height * self.scale
        # Тайл замыкается по своим осям: у нормали на швах берётся сосед
        # с другого края, иначе на стыке двух копий видна тёмная линия.
        # Перекрытие повторяется только вбок, стена — во все стороны.
        self.wrap_x = wrap_x
        self.wrap_y = wrap_y
        # Карты — в пикселях холста, а не в единицах мира: на масштабе 3
        # тайл в 32 единицы занимает 96 пикселей.
        self.diffuse = np.zeros((self.height, self.width, 4), dtype=np.uint8)
        self.height_map = np.zeros((self.height, self.width), dtype=np.float32)
        self.specular = np.zeros((self.height, self.width, 2), dtype=np.float32)

    def rect(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        color: Rgb,
        depth: float,
        material: Material,
        alpha: int = 255,
    ) -> None:
        """Прямоугольник во все три карты разом. Координаты — от левого верха.

        Координаты и размеры — в единицах мира, и они дробные: в пиксели их
        переводит масштаб холста. Так мелкая деталь — фаска в треть единицы,
        волос шва, блик на кромке — появляется сама на крупном холсте и молча
        исчезает на мелком, где ей всё равно не нашлось бы пикселя
        ([ADR-0018](../docs/adr/0018-native-fullhd.md), решение 2).
        """
        left = max(round(x * self.scale), 0)
        top = max(round(y * self.scale), 0)
        right = min(round((x + width) * self.scale), self.width)
        bottom = min(round((y + height) * self.scale), self.height)
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
        x, y, width, height = (round(side * self.scale) for side in area)
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
        """Нормаль из карты высот: наклон поверхности, посчитанный, а не угаданный.

        Сила наклона умножается на масштаб: на крупном холсте та же фаска
        растянута втрое, перепад на пиксель втрое мельче — и без поправки
        рельеф выглядел бы приглаженным ровно во столько же раз.
        """
        return normals(
            self.height_map, self.wrap_x, self.wrap_y, NORMAL_STRENGTH * float(self.scale)
        )

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

    Толщина — 20 единиц, как `BuildingRules.slab_height`; ширина тайла 32, и
    плита любой длины набирается повтором. Сверху — ходовая поверхность с
    блестящей кромкой, снизу — потолок нижнего этажа, темнее всего.

    С M13 у плиты есть чему бликовать: фаска в треть единицы, желобок вдоль
    кромки, выщербины на ходовой полосе и тень под нависающим краем. На мелком
    холсте всё это схлопывается в прежние полосы (ADR-0018).
    """
    canvas = Canvas(32, 20, wrap_x=True)
    canvas.rect(0, 0, 32, 20, palette.SLAB_FACE, 0.55, palette.CONCRETE)

    # Кромка и ходовая поверхность: свет сверху, значит верх ловит его первым.
    canvas.rect(0, 0, 32, 1, palette.SLAB_EDGE, 1.0, palette.CONCRETE)
    canvas.rect(0, 1, 32, 2, palette.SLAB_TOP, 0.95, palette.CONCRETE)
    # Фаска под кромкой: треть единицы, ради которой и затевался FullHD.
    canvas.rect(0, 3, 32, 0.34, palette.mix(palette.SLAB_TOP, palette.SLAB_EDGE, 0.6), 0.99, palette.CONCRETE)
    canvas.rect(0, 3.34, 32, 0.66, palette.mix(palette.SLAB_TOP, palette.SLAB_FACE, 0.5), 0.72, palette.CONCRETE)

    # Желобок вдоль плиты: по нему видно, что это плита, а не полоса.
    canvas.rect(0, 5, 32, 0.34, palette.SLAB_SHADOW, 0.5, palette.CONCRETE)
    canvas.rect(0, 5.34, 32, 0.34, palette.mix(palette.SLAB_FACE, palette.SLAB_EDGE, 0.4), 0.62, palette.CONCRETE)

    # Шов между плитами: вертикальная канавка на стыке тайлов. Она же
    # доказывает, что тайл замкнут — на шве нормаль не рвётся.
    canvas.rect(0, 4, 2, 13, palette.SLAB_SHADOW, 0.38, palette.CONCRETE)
    canvas.rect(1.66, 4, 0.34, 13, palette.mix(palette.SLAB_FACE, palette.SLAB_EDGE, 0.35), 0.52, palette.CONCRETE)

    # Выщербины на торце: бетон не бывает ровным.
    for offset, top, size in ((7, 8, 1.34), (14, 11, 1.0), (23, 7, 1.66), (27, 12, 1.0)):
        canvas.rect(offset, top, size, size * 0.66, palette.mix(palette.SLAB_FACE, palette.SLAB_SHADOW, 0.45), 0.47, palette.CONCRETE)
        canvas.rect(offset, top - 0.34, size, 0.34, palette.mix(palette.SLAB_FACE, palette.SLAB_EDGE, 0.3), 0.6, palette.CONCRETE)

    # Потолок нижнего этажа: сюда свет почти не достаёт.
    canvas.rect(0, 17, 32, 2, palette.mix(palette.SLAB_FACE, palette.SLAB_SHADOW, 0.6), 0.48, palette.CONCRETE)
    canvas.rect(0, 16.66, 32, 0.34, palette.mix(palette.SLAB_FACE, palette.SLAB_SHADOW, 0.3), 0.55, palette.CONCRETE)
    canvas.rect(0, 19, 32, 1, palette.SLAB_SHADOW, 0.42, palette.CONCRETE)

    canvas.speckle(seed=1983, amount=5, area=(0, 4, 32, 13))
    canvas.roughen(seed=1993, amount=0.02)
    return canvas


def wall() -> Canvas:
    """Задняя стена комнаты: штукатурка, замкнутая во все стороны.

    Ровный тон без рисунка: стена — дальний план, и любая полоска на ней
    повторилась бы сеткой по всему зданию, потому что высота этажа на размер
    тайла не делится. Свету достаётся не рисунок, а шероховатость — и вот её
    с M13 хватает на настоящую: редкие оспины и наплывы в треть единицы,
    которые в прежнем масштабе просто не помещались.
    """
    canvas = Canvas(32, 32, wrap_x=True, wrap_y=True)
    canvas.rect(0, 0, 32, 32, palette.WALL_BASE, 0.5, palette.PLASTER)

    # Оспины и наплывы. Сид фиксирован, поэтому стена одна и та же от прогона
    # к прогону, а глазу видна фактура, а не сетка.
    rng = np.random.default_rng(1994)
    for _ in range(26):
        x = float(rng.uniform(0.0, 31.0))
        y = float(rng.uniform(0.0, 31.0))
        size = float(rng.uniform(0.34, 1.0))
        if rng.random() < 0.5:
            tone = palette.mix(palette.WALL_BASE, palette.WALL_SHADE, float(rng.uniform(0.2, 0.5)))
            canvas.rect(x, y, size, size, tone, 0.46, palette.PLASTER)
        else:
            tone = palette.mix(palette.WALL_BASE, palette.WALL_TRIM, float(rng.uniform(0.2, 0.45)))
            canvas.rect(x, y, size, size, tone, 0.54, palette.PLASTER)

    canvas.speckle(seed=1983, amount=4, area=(0, 0, 32, 32))
    canvas.roughen(seed=1984, amount=0.05)
    return canvas


def wall_side() -> Canvas:
    """Боковая стена здания: кирпичная кладка в ширину стены.

    Ширина — `GreyboxLevel.WALL_WIDTH`, иначе стена собиралась бы из обрезков.
    В порте бока здания — красный кирпич с белым швом (ADR-0017); красным его
    делает тон раунда, а здесь кладётся рисунок.

    Ряд — 8 единиц, и тайл в 32 закрывает четыре ряда, замыкаясь по вертикали.
    С M13 у кирпича есть свой тон, фаска и сколы: ровная кладка читалась обоями,
    а неровная — кладкой.
    """
    canvas = Canvas(16, 32, wrap_y=True)
    canvas.rect(0, 0, 16, 32, palette.BRICK_SHADE, 0.42, palette.CONCRETE)

    rng = np.random.default_rng(1985)
    for row in range(4):
        top = row * 8
        # Через ряд кладка сдвигается на полкирпича — иначе она читается сеткой.
        offset = 0.0 if row % 2 == 0 else -4.0
        for column in range(-1, 3):
            left = offset + column * 8
            tone = palette.mix(
                palette.BRICK_SHADE, palette.BRICK_BASE, float(rng.uniform(0.45, 1.0))
            )
            canvas.rect(left + 0.66, top + 0.66, 6.68, 6.68, tone, 0.62, palette.CONCRETE)
            # Фаска: сверху светлее, снизу темнее — кирпич становится телом.
            canvas.rect(left + 0.66, top + 0.66, 6.68, 0.66, palette.mix(tone, palette.BRICK_MORTAR, 0.45), 0.7, palette.CONCRETE)
            canvas.rect(left + 0.66, top + 6.34, 6.68, 1.0, palette.mix(tone, palette.SLAB_SHADOW, 0.35), 0.5, palette.CONCRETE)
            # Скол на каждом третьем: глаз цепляется за неровность, а не за ряд.
            if rng.random() < 0.35:
                chip = float(rng.uniform(1.0, 4.66))
                canvas.rect(left + chip, top + 0.66, 1.0, 1.0, palette.mix(tone, palette.SLAB_SHADOW, 0.5), 0.46, palette.CONCRETE)

        # Шов с глубиной: он ниже кирпича, и свет ложится в него тенью.
        canvas.rect(0, top, 16, 0.66, palette.BRICK_MORTAR, 0.3, palette.CONCRETE)

    canvas.speckle(seed=1986, amount=6, area=(0, 0, 16, 32))
    canvas.roughen(seed=1987, amount=0.04)
    return canvas


def shaft_rail() -> Canvas:
    """Направляющая шахты: стойка по краю проёма во всю его высоту.

    Шахта была дырой в перекрытии со столбом света — в кадре её почти не было,
    хотя спуск по зданию и есть игра (ADR-0017, решение 3). Стойка даёт шахте
    край: по ней видно, где она начинается и докуда идёт.

    Симметрична нарочно: одна и та же текстура стоит на обоих краях проёма,
    и несимметричная давала бы стойки, освещённые с разных сторон (найдено
    авторевью M12). Тайл замкнут по вертикали, ширина — `SHAFT_RAIL_WIDTH`.
    """
    canvas = Canvas(6, 16, wrap_y=True)
    canvas.rect(0, 0, 6, 16, palette.SHAFT_RAIL, 0.55, palette.POLISHED_METAL)
    # Тень по обеим кромкам, блик посередине: стойка круглится к шахте.
    canvas.rect(0, 0, 1, 16, palette.SHAFT_RAIL_SHADE, 0.4, palette.POLISHED_METAL)
    canvas.rect(5, 0, 1, 16, palette.SHAFT_RAIL_SHADE, 0.4, palette.POLISHED_METAL)
    canvas.rect(2.34, 0, 1.32, 16, palette.SHAFT_RAIL_TRIM, 0.9, palette.POLISHED_METAL)
    canvas.rect(1.66, 0, 0.68, 16, palette.mix(palette.SHAFT_RAIL, palette.SHAFT_RAIL_TRIM, 0.5), 0.72, palette.POLISHED_METAL)

    # Стык звена и заклёпки на нём: по ним видно, как мимо идёт кабина.
    canvas.rect(0, 0, 6, 0.66, palette.SHAFT_RAIL_SHADE, 0.45, palette.POLISHED_METAL)
    canvas.rect(0, 0.66, 6, 0.34, palette.SHAFT_RAIL_TRIM, 0.8, palette.POLISHED_METAL)
    for top in (2.5, 9.5):
        canvas.rect(1, top, 1, 1, palette.SHAFT_RAIL_TRIM, 0.95, palette.POLISHED_METAL)
        canvas.rect(4, top, 1, 1, palette.SHAFT_RAIL_TRIM, 0.95, palette.POLISHED_METAL)
        canvas.rect(1, top + 0.66, 1, 0.34, palette.SHAFT_RAIL_SHADE, 0.5, palette.POLISHED_METAL)
        canvas.rect(4, top + 0.66, 1, 0.34, palette.SHAFT_RAIL_SHADE, 0.5, palette.POLISHED_METAL)
    return canvas


def shaft_buffer() -> Canvas:
    """Упор в конце полосы шахты: дальше кабина не идёт.

    Шахты не сквозные (ADR-0008), и у каждой есть верх и низ. Пока предел ничем
    не показывался, игрок читал его как поломку: «лифт не слушается команд и
    стоит, а сошёл — уехал». Упор объясняет это без единого слова.

    Ширина — во всю шахту, полосы наискось: знак, который в любой игре читается
    как «дальше нельзя».
    """
    canvas = Canvas(40, 8)
    canvas.rect(0, 0, 40, 8, palette.METAL_SHADE, 0.55, palette.POLISHED_METAL)
    canvas.rect(0, 0, 40, 0.66, palette.METAL_TRIM, 0.8, palette.POLISHED_METAL)
    canvas.rect(0, 7.34, 40, 0.66, palette.SLAB_SHADOW, 0.4, palette.POLISHED_METAL)
    # Косые полосы: каждая сдвинута на свою высоту, оттого и наискось.
    for step in range(10):
        left = step * 4
        for row in range(6):
            canvas.rect(left + row * 0.66, 1 + row, 2, 1, palette.LAMP_GLOW, 0.7, palette.PAINT)
    return canvas


def car_arrow() -> Canvas:
    """Указатель в кабине: куда она ещё может пойти.

    Одна стрелка вверх; вниз она же, перевёрнутая узлом. Гаснет, когда в эту
    сторону ходу нет, — по ней и видно, что кабина дошла до конца полосы,
    а не перестала слушаться (ADR-0018, решение 6).
    """
    canvas = Canvas(10, 8)
    # Треугольник строками: чем ниже, тем шире.
    for row in range(6):
        half = 1 + row * 0.8
        canvas.rect(5 - half, 1 + row, half * 2, 1, palette.LAMP_GLOW, 0.9, palette.PAINT)
    # Ножка и тень под ней: стрелка не парит, а нарисована на панели.
    canvas.rect(4, 5, 2, 2, palette.LAMP_GLOW, 0.9, palette.PAINT)
    canvas.rect(3.34, 7, 3.32, 0.66, palette.mix(palette.LAMP_GLOW, palette.SLAB_SHADOW, 0.6), 0.6, palette.PAINT)
    return canvas


def shaft_door() -> Canvas:
    """Створки шахты на этаже: по ним видно, где кабина останавливается.

    Размер — ширина шахты на `GreyboxLevel.SHAFT_DOOR_HEIGHT`. Две половинки
    со швом посередине и светлая перемычка сверху — та самая, что в порте
    отмечает этаж поперёк шахты. Серые: цвет даёт тон раунда.
    """
    canvas = Canvas(40, 34)
    canvas.rect(0, 0, 40, 34, palette.SHAFT_RAIL_SHADE, 0.45, palette.POLISHED_METAL)

    # Перемычка над проёмом: козырёк с фаской и тенью под ним.
    canvas.rect(0, 0, 40, 4.34, palette.SHAFT_RAIL_TRIM, 0.85, palette.POLISHED_METAL)
    canvas.rect(0, 4.34, 40, 0.66, palette.mix(palette.SHAFT_RAIL_TRIM, palette.SHAFT_RAIL_SHADE, 0.5), 0.6, palette.POLISHED_METAL)
    canvas.rect(0, 5, 40, 0.66, palette.SHAFT_RAIL_SHADE, 0.38, palette.POLISHED_METAL)

    # Створки: панель с рамкой, чтобы они читались створками, а не заливкой.
    for left in (2.0, 21.0):
        canvas.rect(left, 7, 17, 27, palette.SHAFT_RAIL, 0.6, palette.POLISHED_METAL)
        canvas.rect(left, 7, 17, 0.66, palette.SHAFT_RAIL_TRIM, 0.82, palette.POLISHED_METAL)
        canvas.rect(left, 7, 0.66, 27, palette.SHAFT_RAIL_TRIM, 0.78, palette.POLISHED_METAL)
        canvas.rect(left + 16.34, 7, 0.66, 27, palette.SHAFT_RAIL_SHADE, 0.5, palette.POLISHED_METAL)
        # Утопленная филёнка: свет в ней ложится иначе, чем на створке.
        canvas.rect(left + 2.34, 10, 12.32, 21, palette.mix(palette.SHAFT_RAIL, palette.SHAFT_RAIL_SHADE, 0.35), 0.54, palette.POLISHED_METAL)
        canvas.rect(left + 2.34, 10, 12.32, 0.34, palette.SHAFT_RAIL_SHADE, 0.48, palette.POLISHED_METAL)
        canvas.rect(left + 2.34, 30.66, 12.32, 0.34, palette.SHAFT_RAIL_TRIM, 0.7, palette.POLISHED_METAL)

    # Шов между створками: он же показывает, где они разъезжаются.
    canvas.rect(19, 7, 2, 27, palette.SHAFT_RAIL_SHADE, 0.35, palette.POLISHED_METAL)
    canvas.rect(19, 7, 0.34, 27, palette.SLAB_SHADOW, 0.3, palette.POLISHED_METAL)
    return canvas


def machine_room() -> Canvas:
    """Надстройка машинного отделения над верхней шахтой.

    В порте это домик на крыше со своей двускатной крышей и кирпичными боками
    (ADR-0017, решение 4). Размер — `GreyboxLevel.MACHINE_ROOM_SIZE`.

    Кладка — та же, что у боковых стен: ряд 8 единиц со сдвигом через ряд.
    Крыша светлее боков: она белая и в порте.
    """
    canvas = Canvas(72, 44)
    canvas.rect(0, 10, 72, 34, palette.BRICK_SHADE, 0.5, palette.CONCRETE)

    rng = np.random.default_rng(1989)
    for row in range(4):
        top = 12 + row * 8
        offset = 0.0 if row % 2 == 0 else -4.0
        for column in range(10):
            left = offset + column * 8
            tone = palette.mix(
                palette.BRICK_SHADE, palette.BRICK_BASE, float(rng.uniform(0.5, 1.0))
            )
            canvas.rect(left + 0.66, top + 0.66, 6.68, 6.68, tone, 0.6, palette.CONCRETE)
            canvas.rect(left + 0.66, top + 0.66, 6.68, 0.66, palette.mix(tone, palette.BRICK_MORTAR, 0.4), 0.68, palette.CONCRETE)
            canvas.rect(left + 0.66, top + 6.34, 6.68, 1.0, palette.mix(tone, palette.SLAB_SHADOW, 0.3), 0.5, palette.CONCRETE)
        canvas.rect(0, top, 72, 0.66, palette.BRICK_MORTAR, 0.34, palette.CONCRETE)

    # Двускатная крыша: скаты ступенями и конёк между ними.
    for step in range(6):
        inset = step * 6
        canvas.rect(inset, 10 - step * 2, 72 - inset * 2, 2, palette.SLAB_TOP, 0.9, palette.CONCRETE)
        canvas.rect(inset, 10 - step * 2, 72 - inset * 2, 0.34, palette.SLAB_EDGE, 0.96, palette.CONCRETE)
    canvas.rect(30, 0, 12, 2, palette.SLAB_EDGE, 1.0, palette.CONCRETE)
    # Карниз: крыша нависает над кладкой, и под ней тень.
    canvas.rect(0, 10, 72, 0.66, palette.SLAB_SHADOW, 0.44, palette.CONCRETE)

    # Проём, в котором ходит кабина: он же подсказывает, что домик над шахтой.
    canvas.rect(26, 24, 20, 20, palette.SLAB_SHADOW, 0.2, palette.CONCRETE)
    canvas.rect(26, 24, 20, 0.66, palette.mix(palette.SLAB_SHADOW, palette.BRICK_MORTAR, 0.4), 0.3, palette.CONCRETE)
    canvas.rect(26, 24, 0.66, 20, palette.mix(palette.SLAB_SHADOW, palette.BRICK_BASE, 0.3), 0.28, palette.CONCRETE)
    canvas.rect(45.34, 24, 0.66, 20, palette.mix(palette.SLAB_SHADOW, palette.BRICK_BASE, 0.3), 0.28, palette.CONCRETE)

    canvas.speckle(seed=1990, amount=5, area=(0, 10, 72, 34))
    return canvas


def rope() -> Canvas:
    """Трос, по которому Otto съезжает на крышу: жёлтый пунктир до края кадра.

    Тайл замкнут по вертикали и тянется вверх от места, где Otto встаёт.
    Тоном раунда не красится: в порте трос жёлтый в любом кадре.
    """
    canvas = Canvas(4, 12, wrap_y=True)
    canvas.rect(1, 0, 2, 7, palette.ROPE, 0.7, palette.POLISHED_METAL)
    # Блик по левой пряди: трос витой, а не лента.
    canvas.rect(1, 0, 0.66, 7, palette.mix(palette.ROPE, palette.SLAB_EDGE, 0.45), 0.8, palette.POLISHED_METAL)
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
    # Профиль рамы: наружная фаска ловит свет, следом идёт канавка.
    canvas.rect(0.66, 0.66, side - 1.32, 0.66, palette.METAL_TRIM, 0.85, palette.PAINT)
    canvas.rect(2.34, 2.34, side - 4.68, 0.34, palette.METAL_SHADE, 0.6, palette.PAINT)
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
DOOR_SIZE = (28, 57)


def _door(panel: Rgb, ajar: bool = False, opened: bool = False) -> Canvas:
    """Дверь этажа: рама с профилем, две филёнки, ручка и порог.

    Одна функция на все четыре состояния: закрытая, приоткрытая, открытая и
    красная. Разъезжаются они створкой, а не рисунком — иначе четыре ассета
    расходились бы при первой же правке рамы.

    С M13 у створки есть профиль: фаска рамы, утопленные филёнки с кромкой,
    ручка с бликом и порог. В прежнем масштабе всё это было одним прямоугольником.
    """
    width, height = DOOR_SIZE
    canvas = Canvas(width, height)

    # Рама: тёмный короб с внутренней фаской, которая ловит свет этажа.
    canvas.rect(0, 0, width, height, palette.DOOR_FRAME, 0.5, palette.PAINT)
    canvas.rect(1, 1, width - 2, height - 1, palette.mix(palette.DOOR_FRAME, palette.MAT, 0.25), 0.58, palette.PAINT)
    canvas.rect(1, 1, width - 2, 0.34, palette.mix(palette.DOOR_FRAME, palette.MAT, 0.5), 0.64, palette.PAINT)
    # Проём за створкой: в него видно темноту комнаты.
    canvas.rect(2, 2, width - 4, height - 2, palette.SLAB_SHADOW, 0.2, palette.PLASTER)

    if opened:
        # Открытая: створки не видно вовсе, только косяк и темнота за ним.
        canvas.rect(2, 2, 1, height - 2, palette.mix(palette.DOOR_FRAME, palette.SLAB_SHADOW, 0.5), 0.3, palette.PAINT)
        return canvas

    # Приоткрытая: створка ушла вбок на треть проёма.
    leaf_left = 2.0 + (width - 4) * (0.34 if ajar else 0.0)
    leaf_width = (width - 4) * (0.66 if ajar else 1.0)
    canvas.rect(leaf_left, 2, leaf_width, height - 2, panel, 0.7, palette.PAINT)
    # Кромка створки: с одной стороны блик, с другой тень.
    canvas.rect(leaf_left, 2, 0.34, height - 2, palette.mix(panel, palette.MAT, 0.45), 0.76, palette.PAINT)
    canvas.rect(leaf_left + leaf_width - 0.34, 2, 0.34, height - 2, palette.mix(panel, palette.SLAB_SHADOW, 0.35), 0.62, palette.PAINT)

    if not ajar:
        # Две филёнки: створка перестаёт быть цветным прямоугольником.
        shade = palette.DOOR_RED_SHADE if panel == palette.DOOR_RED else palette.DOOR_PANEL_SHADE
        for top in (4.0, 19.0):
            canvas.rect(4, top, width - 8, 11, shade, 0.64, palette.PAINT)
            canvas.rect(5, top + 1, width - 10, 9, panel, 0.72, palette.PAINT)
            canvas.rect(5, top + 1, width - 10, 0.34, palette.mix(panel, palette.MAT, 0.4), 0.78, palette.PAINT)
            canvas.rect(5, top + 9.66, width - 10, 0.34, shade, 0.66, palette.PAINT)

        # Ручка с бликом и тенью под ней: на ней глаз и находит дверь.
        canvas.rect(width - 6, 16, 2, 3, palette.METAL_TRIM, 0.86, palette.POLISHED_METAL)
        canvas.rect(width - 6, 19, 2, 0.66, palette.METAL_SHADE, 0.6, palette.POLISHED_METAL)

    # Порог: дверь стоит на полу, а не висит над ним.
    canvas.rect(1, height - 1, width - 2, 1, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)
    canvas.rect(1, height - 1, width - 2, 0.34, palette.METAL_TRIM, 0.7, palette.POLISHED_METAL)
    return canvas


def door() -> Canvas:
    """Обычная дверь: за ней засада."""
    return _door(palette.DOOR_PANEL)


def door_red() -> Canvas:
    """Красная дверь: за ней документ. Единственное красное среди дверей."""
    return _door(palette.DOOR_RED)


def door_ajar() -> Canvas:
    """Створка пошла вбок: дверь открывается."""
    return _door(palette.DOOR_PANEL, ajar=True)


def door_open() -> Canvas:
    """Проём без створки: внутри темно."""
    return _door(palette.DOOR_PANEL, opened=True)


def door_mat() -> Canvas:
    """Коврик у двери: по нему видно вход раньше, чем дверь откроется.

    С M13 у коврика есть кант и ворс: полоска в треть единицы по краю и редкая
    штриховка поперёк. На мелком холсте это была одна светлая полоса.
    """
    canvas = Canvas(20, 3)
    canvas.rect(0, 0, 20, 3, palette.MAT, 0.3, palette.FABRIC)
    # Кант: коврик лежит на полу, а не нарисован на нём.
    canvas.rect(0, 0, 20, 0.34, palette.mix(palette.MAT, palette.OTTO_SUIT, 0.5), 0.42, palette.FABRIC)
    canvas.rect(0, 2.66, 20, 0.34, palette.mix(palette.MAT, palette.SLAB_SHADOW, 0.35), 0.24, palette.FABRIC)
    # Ворс поперёк: свет цепляется за него и коврик перестаёт быть заливкой.
    for x in range(1, 20, 2):
        canvas.rect(x, 0.66, 0.66, 1.68, palette.mix(palette.MAT, palette.SLAB_SHADOW, 0.18), 0.33, palette.FABRIC)
    canvas.speckle(seed=1987, amount=6, area=(0, 0, 20, 3))
    return canvas


def car_slab() -> Canvas:
    """Настил кабины: одна и та же плита идёт и на пол, и на крышу.

    Размер — как у `RectangleShape2D_slab` в `elevator_car.tscn`. Металл
    блестит заметно: по блику кабина и отличается от бетона перекрытия.

    С M13 у настила рифление и заклёпки по краям — то, из-за чего он читается
    металлом, а не светлой полосой.
    """
    canvas = Canvas(40, 6)
    canvas.rect(0, 0, 40, 6, palette.METAL, 0.7, palette.POLISHED_METAL)
    canvas.rect(0, 0, 40, 0.66, palette.METAL_TRIM, 0.92, palette.POLISHED_METAL)
    canvas.rect(0, 0.66, 40, 0.34, palette.mix(palette.METAL_TRIM, palette.METAL, 0.5), 0.8, palette.POLISHED_METAL)
    canvas.rect(0, 5.34, 40, 0.66, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)

    # Рифление: частые полосы поперёк настила.
    for x in range(1, 40, 2):
        canvas.rect(x, 1.34, 0.66, 3.32, palette.mix(palette.METAL, palette.METAL_TRIM, 0.35), 0.76, palette.POLISHED_METAL)
        canvas.rect(x + 0.66, 1.34, 0.34, 3.32, palette.mix(palette.METAL, palette.METAL_SHADE, 0.3), 0.66, palette.POLISHED_METAL)
    # Заклёпки по краям: у настила есть чем держаться за кабину.
    for x in (1.0, 37.66):
        canvas.rect(x, 2, 1.34, 1.34, palette.METAL_TRIM, 0.95, palette.POLISHED_METAL)
        canvas.rect(x, 3, 1.34, 0.34, palette.METAL_SHADE, 0.6, palette.POLISHED_METAL)
    return canvas


def escalator_belt() -> Canvas:
    """Полотно эскалатора: тайл в одну ступень, тянется вдоль наклонной линии.

    С M13 ступень видно ступенью: проступь светлее, подступёнок темнее, между
    ними гребёнка. Раньше это была полоса с бликом сверху.
    """
    canvas = Canvas(8, 6, wrap_x=True)
    canvas.rect(0, 0, 8, 6, palette.METAL_SHADE, 0.6, palette.POLISHED_METAL)
    # Проступь: по ней едут, и свет ложится на неё первым.
    canvas.rect(0, 0, 8, 1.34, palette.METAL, 0.86, palette.POLISHED_METAL)
    canvas.rect(0, 0, 8, 0.34, palette.METAL_TRIM, 0.95, palette.POLISHED_METAL)
    # Гребёнка на проступи: три борозды вдоль хода.
    for x in (1.66, 3.66, 5.66):
        canvas.rect(x, 0.34, 0.34, 1.0, palette.METAL_SHADE, 0.7, palette.POLISHED_METAL)
    # Подступёнок и тень под ним: ступень получает толщину.
    canvas.rect(0, 1.34, 8, 3.32, palette.mix(palette.METAL_SHADE, palette.METAL, 0.3), 0.62, palette.POLISHED_METAL)
    canvas.rect(0, 4.66, 8, 1.34, palette.SLAB_SHADOW, 0.4, palette.POLISHED_METAL)
    canvas.rect(0, 0, 0.66, 6, palette.SLAB_SHADOW, 0.35, palette.POLISHED_METAL)
    return canvas


def lamp() -> Canvas:
    """Лампа под потолком: подвес, абажур и горящий низ.

    Размер — как коллизия в `lamp.tscn`: она сбивается выстрелом в прыжке, и
    менять её ради картинки нельзя (ADR-0011, пункт 4).

    С M13 у лампы есть патрон и кольцо на абажуре — то, чего в шестнадцати
    единицах ширины не помещалось. Сам провод до потолка — это M16.
    """
    canvas = Canvas(16, 24)
    # Подвес: провод с бликом по одной пряди.
    canvas.rect(7, 0, 2, 7, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)
    canvas.rect(7, 0, 0.66, 7, palette.mix(palette.METAL_SHADE, palette.METAL_TRIM, 0.4), 0.58, palette.POLISHED_METAL)
    # Патрон: на нём провод кончается, а абажур начинается.
    canvas.rect(6, 6, 4, 2, palette.METAL, 0.72, palette.POLISHED_METAL)
    canvas.rect(6, 6, 4, 0.34, palette.METAL_TRIM, 0.85, palette.POLISHED_METAL)
    canvas.rect(6, 7.66, 4, 0.34, palette.METAL_SHADE, 0.55, palette.POLISHED_METAL)

    # Абажур расширяется книзу: строка за строкой, чтобы нормаль пошла конусом.
    for row in range(8, 20):
        # Абажур расходится от 3 до 8 единиц — до края холста, но не за него:
        # вылезший конус обрезался бы прямоугольником и читался как коробка.
        half = 3 + 5 * (row - 8) / 11
        left = 8 - half
        # Абажур тёмный: он стоит в своём же пятне света, и светлый выбеливался
        # в белое пятно. Лампа читается силуэтом вокруг горящего низа.
        tone = palette.mix(palette.SLAB_SHADOW, palette.LAMP_SHADE, (row - 8) / 11.0 * 0.45)
        canvas.rect(left, row, half * 2, 1, tone, 0.5 + (row - 8) * 0.03, palette.PAINT)
        # Блик по левому скату: конус круглый, а не гранёный.
        canvas.rect(left + 0.34, row, 0.66, 1, palette.mix(tone, palette.LAMP_GLOW, 0.22), 0.56 + (row - 8) * 0.03, palette.PAINT)

    # Кольцо по краю абажура и горящий низ.
    canvas.rect(2, 19.34, 12, 0.66, palette.mix(palette.LAMP_SHADE, palette.LAMP_GLOW, 0.4), 0.8, palette.PAINT)
    canvas.rect(2, 20, 12, 4, palette.LAMP_GLOW, 0.95, palette.PAINT)
    canvas.rect(3.34, 20.66, 9.32, 2.68, palette.mix(palette.LAMP_GLOW, palette.OTTO_SUIT, 0.5), 1.0, palette.PAINT)
    return canvas


def exit_way() -> Canvas:
    """Выход на улицу: проём со светящейся вывеской над ним.

    Размер — `GreyboxLevel.EXIT_WIDTH` на `EXIT_HEIGHT`. Зелёный тут
    единственный: по нему выход виден с другого конца этажа.
    """
    canvas = Canvas(64, 40)
    canvas.rect(0, 0, 64, 40, palette.WALL_SHADE, 0.6, palette.PLASTER)
    canvas.rect(4, 10, 56, 30, palette.SLAB_SHADOW, 0.2, palette.PLASTER)

    # Двустворчатая дверь на улицу: косяки, стойки и щель между створками.
    for left in (5.0, 33.0):
        canvas.rect(left, 11, 26, 29, palette.mix(palette.SLAB_SHADOW, palette.METAL, 0.25), 0.3, palette.POLISHED_METAL)
        canvas.rect(left, 11, 0.66, 29, palette.METAL_TRIM, 0.7, palette.POLISHED_METAL)
        canvas.rect(left + 25.34, 11, 0.66, 29, palette.METAL_SHADE, 0.4, palette.POLISHED_METAL)
        # Стекло: полоса отблеска наискосок.
        canvas.rect(left + 3, 14, 20, 12, palette.mix(palette.SLAB_SHADOW, palette.GLASS, 0.3), 0.26, palette.WINDOW_GLASS)
        canvas.rect(left + 5, 15, 3, 10, palette.mix(palette.GLASS, palette.OTTO_SUIT, 0.4), 0.28, palette.WINDOW_GLASS)
        # Ручка-штанга поперёк створки.
        canvas.rect(left + 4, 28, 18, 1.34, palette.METAL_TRIM, 0.82, palette.POLISHED_METAL)

    # Козырёк над проёмом и вывеска со стрелкой наружу.
    canvas.rect(2, 8, 60, 2, palette.METAL_TRIM, 0.8, palette.POLISHED_METAL)
    canvas.rect(2, 10, 60, 0.66, palette.METAL_SHADE, 0.5, palette.POLISHED_METAL)
    canvas.rect(18, 1, 28, 7, palette.EXIT_SIGN, 0.9, palette.PAINT)
    canvas.rect(19, 2, 26, 5, palette.mix(palette.EXIT_SIGN, palette.SLAB_SHADOW, 0.35), 0.86, palette.PAINT)
    canvas.rect(21, 3.66, 16, 1.68, palette.mix(palette.EXIT_SIGN, palette.OTTO_SUIT, 0.75), 0.95, palette.PAINT)
    for step in range(4):
        canvas.rect(37 + step, 3.66 - step * 0.66, 1, 1.68 + step * 1.32, palette.mix(palette.EXIT_SIGN, palette.OTTO_SUIT, 0.75), 0.95, palette.PAINT)
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
    # Этажи дальней башни: чуть светлее полоса и тень под ней. Рисунок мелкий
    # нарочно — город стоит далеко, и заметная сетка читалась бы стеной рядом.
    for top in (3.0, 11.0):
        canvas.rect(0, top, 16, 0.34, palette.mix(palette.CITY_BODY, palette.GLASS, 0.18), 0.54, palette.CONCRETE)
        canvas.rect(0, top + 0.34, 16, 0.34, palette.mix(palette.CITY_BODY, palette.SLAB_SHADOW, 0.4), 0.46, palette.CONCRETE)
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
    "shaft_buffer": shaft_buffer,
    "car_arrow": car_arrow,
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
    parser.add_argument(
        "--scale",
        type=int,
        default=DEFAULT_SCALE,
        help="во сколько раз крупнее рисовать (по умолчанию %d — масштаб набора)" % DEFAULT_SCALE,
    )
    arguments = parser.parse_args()

    global SCALE
    if arguments.scale < 1:
        print("Масштаб меньше единицы не бывает.")
        return 2
    SCALE = arguments.scale

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
