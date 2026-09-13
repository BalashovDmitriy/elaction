#!/usr/bin/env python3
"""Генератор звука: квадрат, шум и огибающие — словарь PSG 1983 года.

ADR-0012, пункт 1. В оригинале четыре чипа AY-3-8910 и отдельный Z80 под звук:
сэмплов там нет и взяться им неоткуда, весь звук игры — это три голоса на чип,
квадратная волна, шум и ступенчатая громкость. Ровно это и синтезируется здесь.

Файлы коммитятся, как PNG у графики (ADR-0011, пункт 2): скрипт — инструмент
разработчика, в CI он не вызывается.

    python tools/render_audio.py            # всё
    python tools/render_audio.py shot       # один звук
    python tools/render_audio.py --list
"""

from __future__ import annotations

import argparse
import sys
import wave
from collections.abc import Callable
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

PROJECT_ROOT = TOOLS.parent
OUT_DIR = PROJECT_ROOT / "assets/audio"

## Частота дискретизации. 22 050 Гц хватает с запасом: у квадратной волны всё
## слышимое лежит ниже восьми килогерц, а файл выходит вдвое легче.
RATE = 22050

## PSG знает шестнадцать уровней громкости, а не плавную кривую. Огибающие
## квантуются по ним — отсюда характерная «ступенька» затухания.
PSG_LEVELS = 16

## Полутоновая сетка от ля первой октавы.
A4 = 440.0
NOTE_STEPS = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def frequency(note: str) -> float:
    """Частота ноты по имени: `A4`, `C#5`, `Eb3`. Пауза — пустая строка."""
    if not note:
        return 0.0
    step = NOTE_STEPS[note[0].upper()]
    rest = note[1:]
    if rest.startswith("#"):
        step += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        step -= 1
        rest = rest[1:]
    octave = int(rest)
    return A4 * 2.0 ** ((step + (octave - 4) * 12) / 12.0)


def _samples(duration: float) -> int:
    return max(int(RATE * duration), 1)


def square(
    pitch: float, duration: float, duty: float = 0.5, to_pitch: float | None = None
) -> np.ndarray:
    """Квадратная волна, при желании с уводом высоты от [param pitch] к [param to_pitch]."""
    count = _samples(duration)
    if pitch <= 0.0:
        return np.zeros(count, dtype=np.float32)

    finish = pitch if to_pitch is None else to_pitch
    # Фаза копится интегралом частоты: иначе при уводе высоты волна рвётся.
    sweep = np.linspace(pitch, finish, count, dtype=np.float32)
    phase = np.cumsum(sweep) / float(RATE)
    return np.where(np.mod(phase, 1.0) < duty, 1.0, -1.0).astype(np.float32)


def noise(duration: float, seed: int, colour: float = 1.0) -> np.ndarray:
    """Шумовой канал. [param colour] < 1 приглушает верх — получается «глуше».

    Сид фиксирован, поэтому повторный прогон даёт тот же файл.
    """
    count = _samples(duration)
    rng = np.random.default_rng(seed)
    raw = rng.uniform(-1.0, 1.0, count).astype(np.float32)
    if colour >= 1.0:
        return raw

    # Однополюсный фильтр: дешёвый способ убрать песок и оставить рокот.
    smoothed = np.empty_like(raw)
    previous = 0.0
    for index in range(count):
        previous += (raw[index] - previous) * colour
        smoothed[index] = previous
    return smoothed


def envelope(
    wave_in: np.ndarray, attack: float = 0.005, hold: float = 0.0, release: float = 0.05
) -> np.ndarray:
    """Огибающая по уровням PSG: атака, полка, затухание.

    Ступеньки — не стилизация, а как есть: у AY-3-8910 громкость задаётся
    четырьмя битами, и плавных затуханий он не умеет.
    """
    count = wave_in.size
    attack_count = min(_samples(attack), count)
    hold_count = min(_samples(hold), count - attack_count)
    release_count = max(count - attack_count - hold_count, 0)

    shape = np.concatenate(
        [
            np.linspace(0.0, 1.0, attack_count, endpoint=False, dtype=np.float32),
            np.ones(hold_count, dtype=np.float32),
            np.linspace(1.0, 0.0, release_count, dtype=np.float32),
        ]
    )[:count]
    stepped = np.floor(shape * (PSG_LEVELS - 1) + 0.5) / float(PSG_LEVELS - 1)
    return (wave_in * stepped).astype(np.float32)


def mix(*tracks: np.ndarray, gain: float = 1.0) -> np.ndarray:
    """Складывает голоса и приводит пик ровно к [param gain].

    Не подрезает: сумма двух голосов легко переваливает за единицу, и жёсткий
    срез слышен как песок поверх звука. Тише — честнее, чем грязнее, а заодно
    [param gain] означает ровно то, на что похоже: громкость этого звука
    относительно остальных.
    """
    length = max((track.size for track in tracks), default=1)
    total = np.zeros(length, dtype=np.float32)
    for track in tracks:
        total[: track.size] += track

    peak = float(np.abs(total).max())
    if peak <= 0.0:
        return total
    return (total * (gain / peak)).astype(np.float32)


def sequence(*parts: np.ndarray) -> np.ndarray:
    """Склеивает куски подряд — фраза из нот."""
    return np.concatenate(parts).astype(np.float32) if parts else np.zeros(1, dtype=np.float32)


def silence(duration: float) -> np.ndarray:
    return np.zeros(_samples(duration), dtype=np.float32)


def line(notes: list[tuple[str, float]], duty: float = 0.5, gap: float = 0.12) -> np.ndarray:
    """Голос из нот: список пар «нота, длительность».

    [param gap] — доля длительности, которая уходит в тишину перед следующей
    нотой. Без неё две одинаковые ноты подряд сливаются в одну длинную.
    """
    parts: list[np.ndarray] = []
    for note, duration in notes:
        sound = duration * (1.0 - gap)
        pitch = frequency(note)
        if pitch <= 0.0:
            parts.append(silence(duration))
            continue
        parts.append(envelope(square(pitch, sound, duty), attack=0.004, hold=sound * 0.6))
        parts.append(silence(duration - sound))
    return sequence(*parts)


def drums(pattern: str, step: float, seed: int) -> np.ndarray:
    """Шумовая перкуссия: `x` — удар, `.` — пауза. Третий голос у PSG чаще всего он."""
    parts: list[np.ndarray] = []
    for index, mark in enumerate(pattern):
        if mark == "x":
            hit = envelope(noise(step * 0.6, seed + index, colour=0.35), release=step * 0.5)
            parts.append(sequence(hit, silence(step - step * 0.6)))
        else:
            parts.append(silence(step))
    return sequence(*parts)


# --- Эффекты -----------------------------------------------------------------


def step_sound() -> np.ndarray:
    """Шаг: короткий глухой щелчок. Он звучит чаще всех, поэтому тихий."""
    return mix(envelope(noise(0.05, 11, colour=0.25), release=0.045), gain=0.25)


def shot() -> np.ndarray:
    """Выстрел: щелчок шума и уходящий вниз квадрат."""
    crack = envelope(noise(0.06, 21, colour=0.8), release=0.055)
    body = envelope(square(880.0, 0.09, duty=0.25, to_pitch=180.0), release=0.08)
    return mix(crack, body, gain=0.62)


def hit() -> np.ndarray:
    """Попадание в тело: короткий низкий удар."""
    return mix(envelope(square(220.0, 0.07, duty=0.3, to_pitch=90.0), release=0.06), gain=0.7)


def kick() -> np.ndarray:
    """Удар ногой: свист и глухой шлепок."""
    swing = envelope(noise(0.08, 31, colour=0.5), attack=0.03, release=0.05)
    thud = envelope(square(160.0, 0.1, duty=0.4, to_pitch=70.0), release=0.09)
    return mix(swing, thud, gain=0.7)


def lamp_break() -> np.ndarray:
    """Лампа разбита: звон на верхах и осыпающийся шум."""
    glass = envelope(square(1760.0, 0.12, duty=0.15, to_pitch=2200.0), release=0.11)
    shards = envelope(noise(0.25, 41), attack=0.002, release=0.24)
    return mix(glass, shards, gain=0.58)


def lamp_crash() -> np.ndarray:
    """Лампа долетела до пола: глухой удар, после которого этаж гаснет."""
    return mix(
        envelope(square(120.0, 0.2, duty=0.45, to_pitch=45.0), release=0.19),
        envelope(noise(0.2, 51, colour=0.2), release=0.19),
        gain=0.72,
    )


def elevator_ding() -> np.ndarray:
    """«Динь» лифта — один из двух эффектов, которые источники называют прямо."""
    first = envelope(square(1046.5, 0.18, duty=0.5), attack=0.002, hold=0.02, release=0.16)
    second = sequence(silence(0.14), envelope(square(784.0, 0.3, duty=0.5), release=0.28))
    return mix(first, second, gain=0.6)


def elevator_hum() -> np.ndarray:
    """Ход кабины: ровный гул, который зацикливается на время поездки."""
    body = square(58.0, 0.5, duty=0.5)
    rattle = noise(0.5, 61, colour=0.08)
    return mix(body * 0.5, rattle * 0.5, gain=0.4)


def escalator_hum() -> np.ndarray:
    """Полотно эскалатора: механический стрёкот, тоже петлёй."""
    return mix(
        square(96.0, 0.4, duty=0.2) * 0.4,
        envelope(noise(0.4, 71, colour=0.15), attack=0.1, release=0.1) * 0.5,
        gain=0.35,
    )


def door_open() -> np.ndarray:
    """Дверь открывается: скрип вверх."""
    return mix(envelope(square(300.0, 0.16, duty=0.12, to_pitch=520.0), release=0.14), gain=0.5)


def door_close() -> np.ndarray:
    """Дверь закрывается: тот же скрип вниз и стук."""
    creak = envelope(square(520.0, 0.14, duty=0.12, to_pitch=300.0), release=0.12)
    knock = sequence(silence(0.12), envelope(noise(0.06, 81, colour=0.3), release=0.05))
    return mix(creak, knock, gain=0.5)


def document() -> np.ndarray:
    """Документ взят: арпеджио вверх. Единственный безусловно хороший звук в игре."""
    return mix(line([("C5", 0.07), ("E5", 0.07), ("G5", 0.07), ("C6", 0.16)], gap=0.05), gain=0.6)


def otto_death() -> np.ndarray:
    """Смерть Otto: длинный уход вниз."""
    fall = envelope(square(440.0, 0.7, duty=0.35, to_pitch=60.0), release=0.65)
    return mix(fall, envelope(noise(0.7, 91, colour=0.12), release=0.68) * 0.4, gain=0.8)


def agent_death() -> np.ndarray:
    """Смерть агента: короче и суше, чем у Otto, — их много."""
    return mix(
        envelope(square(300.0, 0.18, duty=0.3, to_pitch=80.0), release=0.17),
        envelope(noise(0.18, 101, colour=0.25), release=0.17) * 0.5,
        gain=0.6,
    )


def car_away() -> np.ndarray:
    """Машина уезжает: мотор, уходящий вверх и вдаль."""
    engine = envelope(square(70.0, 1.1, duty=0.35, to_pitch=150.0), attack=0.05, release=0.9)
    smoke = envelope(noise(1.1, 111, colour=0.1), attack=0.05, release=0.9)
    return mix(engine * 0.7, smoke * 0.5, gain=0.7)


def building_bonus() -> np.ndarray:
    """Бонус за здание: восходящая фраза, пока начисляются очки."""
    return mix(
        line(
            [("G4", 0.09), ("C5", 0.09), ("E5", 0.09), ("G5", 0.09), ("C6", 0.22)],
            duty=0.25,
            gap=0.06,
        ),
        gain=0.6,
    )


def game_over() -> np.ndarray:
    """Game Over: то же, что смерть, но окончательно."""
    return mix(
        line([("C4", 0.25), ("G3", 0.25), ("E3", 0.25), ("C3", 0.7)], duty=0.4, gap=0.04),
        gain=0.7,
    )


# --- Музыка ------------------------------------------------------------------


def theme() -> np.ndarray:
    """Тема здания: короткая петля на трёх голосах.

    Своя, а не из оригинала (ADR-0012, пункт 2): тема Taito — их собственность.
    Идиома та же — простая тревожная мелодия, ровный бас, шум вместо барабанов.
    """
    beat = 0.16
    melody = line(
        [
            ("E5", beat), ("", beat), ("D5", beat), ("E5", beat),
            ("G5", beat), ("", beat), ("E5", beat), ("D5", beat),
            ("C5", beat), ("", beat), ("D5", beat), ("C5", beat),
            ("A4", beat * 2), ("", beat * 2),
            ("E5", beat), ("", beat), ("F5", beat), ("E5", beat),
            ("D5", beat), ("", beat), ("C5", beat), ("D5", beat),
            ("B4", beat), ("", beat), ("C5", beat), ("B4", beat),
            ("A4", beat * 2), ("", beat * 2),
        ],
        duty=0.25,
    )
    bass = line(
        [
            ("A2", beat * 2), ("A2", beat * 2), ("E2", beat * 2), ("E2", beat * 2),
            ("F2", beat * 2), ("F2", beat * 2), ("E2", beat * 2), ("E2", beat * 2),
            ("A2", beat * 2), ("A2", beat * 2), ("G2", beat * 2), ("G2", beat * 2),
            ("F2", beat * 2), ("E2", beat * 2), ("A2", beat * 2), ("", beat * 2),
        ],
        duty=0.5,
        gap=0.06,
    )
    percussion = drums("x..x..x." * 4, beat, seed=201)
    return mix(melody * 0.5, bass * 0.45, percussion * 0.3, gain=0.85)


def alarm_theme() -> np.ndarray:
    """Мотив тревоги: сирена работает с M5b, а звучать ей было нечем.

    Две ноты в терцию, качающиеся туда-обратно, — то же, что делает сирена,
    и по ним слышно, что здание теперь против тебя.
    """
    beat = 0.22
    siren = line([("A4", beat), ("D5", beat)] * 8, duty=0.5, gap=0.02)
    bass = line([("D2", beat * 2)] * 8, duty=0.5, gap=0.05)
    percussion = drums("x.x.x.x." * 2, beat, seed=211)
    return mix(siren * 0.5, bass * 0.5, percussion * 0.35, gain=0.82)


SOUNDS: dict[str, Callable[[], np.ndarray]] = {
    "step": step_sound,
    "shot": shot,
    "hit": hit,
    "kick": kick,
    "lamp_break": lamp_break,
    "lamp_crash": lamp_crash,
    "elevator_ding": elevator_ding,
    "elevator_hum": elevator_hum,
    "escalator_hum": escalator_hum,
    "door_open": door_open,
    "door_close": door_close,
    "document": document,
    "otto_death": otto_death,
    "agent_death": agent_death,
    "car_away": car_away,
    "building_bonus": building_bonus,
    "game_over": game_over,
    "theme": theme,
    "alarm_theme": alarm_theme,
}


def write_wav(path: Path, samples: np.ndarray) -> None:
    """16 бит, моно. Стерео чипу неоткуда взять, да и незачем."""
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(samples, -1.0, 1.0)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes((clipped * 32767.0).astype("<i2").tobytes())


def main() -> int:
    parser = argparse.ArgumentParser(description="Синтез звуков игры.")
    parser.add_argument("names", nargs="*", help="какие звуки писать; по умолчанию все")
    parser.add_argument("--list", action="store_true", help="перечислить и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать WAV")
    arguments = parser.parse_args()

    from godot_bin import use_utf8_output

    use_utf8_output()

    if arguments.list:
        for name in sorted(SOUNDS):
            print(name)
        return 0

    wanted = arguments.names or sorted(SOUNDS)
    unknown = [name for name in wanted if name not in SOUNDS]
    if unknown:
        print(f"Неизвестные звуки: {', '.join(unknown)}")
        print(f"Известные: {', '.join(sorted(SOUNDS))}")
        return 2

    for name in wanted:
        samples = SOUNDS[name]()
        path = arguments.out / f"{name}.wav"
        write_wav(path, samples)
        seconds = samples.size / float(RATE)
        try:
            shown = path.relative_to(PROJECT_ROOT).as_posix()
        except ValueError:
            shown = str(path)
        print(f"{shown}  {seconds:.2f} с")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
