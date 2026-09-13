#!/usr/bin/env python3
"""Палитра игры в одном месте (ADR-0011, пункт 6).

Отсюда цвета берёт генератор окружения и материалы Blender. Цвета света —
`CanvasModulate`, заливки этажей, столб шахты — живут в коде игры и
зафиксированы в ADR-0010; здесь только альбедо поверхностей.

Правило палитры: здание приглушённое, картинку делает свет. Яркими остаются
ровно два опознавательных знака из оригинала — красная дверь и светлый костюм
Otto, — плюс тёплые источники (лампа, вспышка, пуля).
"""

from __future__ import annotations

from typing import NamedTuple

type Rgb = tuple[int, int, int]


class Material(NamedTuple):
    """Поверхность: чем светлее `specular`, тем резче блик на ней от света 2D.

    `shininess` уходит в `CanvasTexture.specular_shininess`, `specular` — в силу
    блика. Штукатурка почти не блестит, металл и стекло блестят заметно.
    """

    specular: float
    shininess: float


# --- Здание -----------------------------------------------------------------

WALL_BASE: Rgb = (0x3C, 0x41, 0x52)
WALL_SHADE: Rgb = (0x2B, 0x2F, 0x3D)
WALL_TRIM: Rgb = (0x4B, 0x51, 0x66)

SLAB_TOP: Rgb = (0x5A, 0x60, 0x70)
SLAB_EDGE: Rgb = (0x6B, 0x72, 0x85)
SLAB_FACE: Rgb = (0x3E, 0x44, 0x56)
SLAB_SHADOW: Rgb = (0x22, 0x26, 0x31)

# --- Двери ------------------------------------------------------------------

DOOR_FRAME: Rgb = (0x59, 0x51, 0x3F)
DOOR_PANEL: Rgb = (0x6B, 0x5C, 0x44)
DOOR_PANEL_SHADE: Rgb = (0x4A, 0x3F, 0x2E)

# Якорь оригинала: единственное красное в кадре.
DOOR_RED: Rgb = (0xB5, 0x32, 0x2C)
DOOR_RED_SHADE: Rgb = (0x7D, 0x21, 0x1D)

# Коврик у двери: по нему видно, где вход, ещё до того как дверь открылась.
MAT: Rgb = (0xB0, 0xAD, 0xA0)

# --- Лифт, эскалатор --------------------------------------------------------

METAL: Rgb = (0x5B, 0x63, 0x76)
METAL_SHADE: Rgb = (0x3A, 0x40, 0x51)
METAL_TRIM: Rgb = (0x8A, 0x93, 0xA8)

# --- Окна и город -----------------------------------------------------------

GLASS: Rgb = (0x9F, 0xB6, 0xC9)
CITY_BODY: Rgb = (0x1E, 0x23, 0x33)
CITY_WINDOW: Rgb = (0xEB, 0xD4, 0x80)

# --- Свет, огонь ------------------------------------------------------------

LAMP_SHADE: Rgb = (0x8D, 0x8F, 0x98)
LAMP_GLOW: Rgb = (0xF2, 0xE0, 0x8C)
BULLET: Rgb = (0xFA, 0xE0, 0x8C)
IMPACT: Rgb = (0xE8, 0x66, 0x3C)
EXIT_SIGN: Rgb = (0x4F, 0xA8, 0x6A)

# Машина у выхода: в оригинале здание заканчивается красной машиной. С красной
# дверью она не спорит — дверь внутри здания, машина снаружи и в кадре одна.
CAR_BODY: Rgb = (0xC4, 0x44, 0x3A)

# --- Актёры -----------------------------------------------------------------

# Якорь оригинала: самое светлое пятно среди актёров, чтобы своего было видно
# и на погашенном этаже.
OTTO_SUIT: Rgb = (0xE8, 0xE3, 0xD2)
OTTO_SUIT_SHADE: Rgb = (0xB9, 0xB4, 0xA4)
# Помпадур: тёмный, иначе на светлом костюме голова читается как одно пятно.
OTTO_HAIR: Rgb = (0x3A, 0x2E, 0x27)
OTTO_SKIN: Rgb = (0xD8, 0xA6, 0x7B)
OTTO_TIE: Rgb = (0x3A, 0x3F, 0x4E)

AGENT_SUIT: Rgb = (0x2F, 0x35, 0x47)
AGENT_SUIT_SHADE: Rgb = (0x23, 0x28, 0x3A)
AGENT_HAT: Rgb = (0x26, 0x2B, 0x3B)
AGENT_SKIN: Rgb = (0xC0, 0x8F, 0x68)

# --- Материалы --------------------------------------------------------------

PLASTER = Material(specular=0.06, shininess=0.15)
CONCRETE = Material(specular=0.10, shininess=0.20)
WOOD = Material(specular=0.16, shininess=0.30)
PAINT = Material(specular=0.22, shininess=0.40)
POLISHED_METAL = Material(specular=0.65, shininess=0.85)
WINDOW_GLASS = Material(specular=0.80, shininess=0.90)
FABRIC = Material(specular=0.08, shininess=0.12)


def to_float(color: Rgb) -> tuple[float, float, float]:
    """sRGB 0..255 -> 0..1. Для тех, кому нужен не байт, а доля."""
    return (color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)


def to_linear(color: Rgb) -> tuple[float, float, float]:
    """sRGB -> линейное пространство: в таком виде цвет ждут материалы Blender."""

    def channel(value: int) -> float:
        part = value / 255.0
        if part <= 0.04045:
            return part / 12.92
        return ((part + 0.055) / 1.055) ** 2.4

    return (channel(color[0]), channel(color[1]), channel(color[2]))


def to_hex(color: Rgb) -> str:
    """Для документации и отладочного вывода."""
    return "#{:02X}{:02X}{:02X}".format(*color)


def mix(first: Rgb, second: Rgb, amount: float) -> Rgb:
    """Линейная смесь двух цветов: amount=0 — первый, amount=1 — второй."""
    part = min(max(amount, 0.0), 1.0)
    return (
        round(first[0] + (second[0] - first[0]) * part),
        round(first[1] + (second[1] - first[1]) * part),
        round(first[2] + (second[2] - first[2]) * part),
    )
