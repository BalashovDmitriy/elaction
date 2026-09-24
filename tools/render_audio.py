#!/usr/bin/env python3
"""Генератор звука: слоёные эффекты и тёмный synthwave.

Формула проекта — «механика 1983 года, картинка 2026 года», и звук на той же
стороне, что картинка. Первая версия подражала чипу AY-3-8910 и звучала как
чип — решение пересмотрено после прослушивания (ADR-0012, правка от 2026-09-13).

Каждый эффект собирается так же, как их собирают в современных играх: **атака**
(щелчок, с которого всё начинается), **тело** (вес и высота) и **хвост** (комната
вокруг). Музыка — восьмитактовая петля на живых слоях: бас, арпеджио, пад,
барабаны, — сведённая и залимитированная.

Синтез, а не сэмплы: причины те же, что у картинок (ADR-0011, пункт 2) —
детерминированность, никаких чужих файлов и правка звука числом в коде.

    python tools/render_audio.py            # всё
    python tools/render_audio.py shot       # один звук
    python tools/render_audio.py --list
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

import numpy as np

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import audio_dsp as dsp
from audio_dsp import Stereo

PROJECT_ROOT = TOOLS.parent
OUT_DIR = PROJECT_ROOT / "assets/audio"

## Полутоновая сетка от ля первой октавы.
A4 = 440.0
NOTE_STEPS = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}


def note(name: str) -> float:
    """Частота ноты: `A4`, `C#5`, `Eb2`."""
    step = NOTE_STEPS[name[0].upper()]
    rest = name[1:]
    if rest.startswith("#"):
        step += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        step -= 1
        rest = rest[1:]
    return A4 * 2.0 ** ((step + (int(rest) - 4) * 12) / 12.0)


# --- Комнаты -----------------------------------------------------------------
#
# Здание бетонное, и хвост у него короткий и тёмный — этим комната отличается от
# зала. Шахта, наоборот, длинная труба, и всё, что в ней звучит, гуляет дольше.

_ROOMS: dict[str, np.ndarray] = {}


def room(kind: str = "floor") -> np.ndarray:
    if kind not in _ROOMS:
        shapes = {
            "tight": (0.22, 3200.0, 7001),
            "floor": (0.55, 2600.0, 7002),
            "shaft": (1.40, 1800.0, 7003),
            "street": (0.90, 4200.0, 7004),
        }
        seconds, brightness, seed = shapes[kind]
        _ROOMS[kind] = dsp.impulse_response(seconds, brightness, seed)
    return _ROOMS[kind]


def placed(signal: np.ndarray, kind: str = "floor", mix: float = 0.3, pan: float = 0.0) -> Stereo:
    """Ставит моно-слой в комнату и разводит по панораме."""
    return dsp.mono_to_stereo(dsp.reverb(signal, room(kind), mix=mix), pan)


def stack(*parts: np.ndarray) -> np.ndarray:
    """Складывает моно-слои разной длины."""
    length = max(part.size for part in parts)
    out = np.zeros(length, dtype=np.float32)
    for part in parts:
        out[: part.size] += part
    return out


def after(delay: float, signal: np.ndarray) -> np.ndarray:
    """Сдвигает слой вперёд по времени: защёлка звучит позже хода двери."""
    return np.concatenate([np.zeros(dsp.samples(delay), dtype=np.float32), signal]).astype(np.float32)


# --- Эффекты -----------------------------------------------------------------


def shot() -> Stereo:
    """Выстрел: щелчок, тело с уходом вниз, подхват снизу и хвост этажа."""
    crack = dsp.decay(dsp.filtered(dsp.noise(0.05, 101), 2600.0, "high"), tau=0.006)
    body = dsp.saturate(
        dsp.decay(dsp.pulse(dsp.glide(520.0, 70.0, 0.16), 0.16, duty=0.35), tau=0.035), drive=3.0
    )
    sub = dsp.decay(dsp.sine(dsp.glide(150.0, 42.0, 0.22), 0.22), tau=0.06)
    dry = dsp.filtered(stack(crack * 0.9, body * 0.7, sub * 0.8), 9000.0, "low")
    return dsp.master(dsp.widen(placed(dry, "floor", mix=0.32), amount=0.3), peak=0.85)


def hit() -> Stereo:
    """Пуля в тело: глухо и коротко, почти без хвоста."""
    thump = dsp.decay(dsp.sine(dsp.glide(180.0, 55.0, 0.18), 0.18), tau=0.05)
    flesh = dsp.decay(dsp.filtered(dsp.noise(0.08, 111), 900.0, "low"), tau=0.02)
    # Шлепок в середине: без него попадание — только глухой низ, и в общем
    # шуме боя его не слышно вовсе (проверено спектром, а не на глаз).
    slap = dsp.decay(dsp.filtered(dsp.noise(0.05, 112), 1800.0, "band"), tau=0.008)
    return dsp.master(placed(stack(thump * 0.9, flesh * 0.6, slap * 0.5), "tight", mix=0.18), peak=0.7)


def kick() -> Stereo:
    """Удар ногой: свист по дуге и шлепок."""
    arc = np.concatenate(
        [
            np.linspace(500.0, 4200.0, 32, dtype=np.float32),
            np.linspace(4200.0, 700.0, 32, dtype=np.float32),
        ]
    )
    swing = dsp.sweeping(dsp.noise(0.26, 121), cutoff=arc, kind="low", resonance=0.6, block=1024)
    swing = dsp.adsr(swing, attack=0.05, hold=0.05, release=0.16) * 0.5
    impact = dsp.decay(dsp.sine(dsp.glide(200.0, 60.0, 0.2), 0.2), tau=0.045)
    return dsp.master(placed(stack(swing, impact * 0.9), "floor", mix=0.22), peak=0.75)


def step_sound() -> Stereo:
    """Шаг: мягкий щелчок по бетону. Звучит чаще всех, поэтому тихий."""
    tap = dsp.decay(dsp.filtered(dsp.noise(0.04, 131), 1100.0, "low"), tau=0.008)
    click = dsp.decay(dsp.filtered(dsp.noise(0.02, 132), 2600.0, "high"), tau=0.003) * 0.35
    # Комната тесная и подмешана чуть-чуть: шаг звучит по пять раз в секунду,
    # и длинный хвост у него слился бы в непрерывный шорох.
    return dsp.master(placed(stack(tap, click), "tight", mix=0.15), peak=0.32)


def lamp_break() -> Stereo:
    """Лампа разбита: звон стекла и осыпающиеся осколки."""
    rng = np.random.default_rng(141)
    partials = np.zeros(dsp.samples(0.5), dtype=np.float32)
    for pitch in (2480.0, 3310.0, 4120.0, 5230.0, 6710.0):
        ring = dsp.decay(dsp.sine(pitch * rng.uniform(0.98, 1.02), 0.5), tau=rng.uniform(0.05, 0.18))
        partials += ring * rng.uniform(0.15, 0.4)

    shards = np.zeros(dsp.samples(0.6), dtype=np.float32)
    for index in range(9):
        piece = dsp.decay(dsp.filtered(dsp.noise(0.05, 150 + index), 3000.0, "high"), tau=0.008)
        start = dsp.samples(rng.uniform(0.02, 0.42))
        shards[start : start + piece.size] += piece * rng.uniform(0.2, 0.6)

    burst = dsp.decay(dsp.filtered(dsp.noise(0.12, 149), 1800.0, "high"), tau=0.02)
    return dsp.master(placed(stack(partials, shards, burst * 0.8), "floor", mix=0.4), peak=0.8)


def lamp_crash() -> Stereo:
    """Лампа долетела до пола: удар, после которого этаж гаснет."""
    thud = dsp.decay(dsp.sine(dsp.glide(120.0, 38.0, 0.35), 0.35), tau=0.08)
    body = dsp.saturate(dsp.decay(dsp.filtered(dsp.noise(0.3, 161), 700.0, "low"), tau=0.05), 2.0)

    rng = np.random.default_rng(162)
    debris = np.zeros(dsp.samples(0.5), dtype=np.float32)
    for index in range(6):
        piece = dsp.decay(dsp.filtered(dsp.noise(0.04, 170 + index), 2400.0, "high"), tau=0.006)
        start = dsp.samples(rng.uniform(0.03, 0.3))
        debris[start : start + piece.size] += piece * rng.uniform(0.1, 0.3)
    return dsp.master(placed(stack(thud, body * 0.7, debris), "floor", mix=0.35), peak=0.85)


def _bell(pitch: float, seconds: float) -> np.ndarray:
    """Колокольчик: негармоничные обертоны, иначе это просто синус."""
    out = np.zeros(dsp.samples(seconds), dtype=np.float32)
    for ratio, share, tau in ((1.0, 1.0, 0.9), (2.76, 0.5, 0.45), (5.4, 0.25, 0.22)):
        out += dsp.decay(dsp.sine(pitch * ratio, seconds), tau=tau) * share
    return out


def elevator_hum() -> Stereo:
    """Гул кабины: мотор и шум троса. Зацикливается на время поездки."""
    seconds = 2.0
    motor = dsp.filtered(dsp.saw(55.0, seconds), 380.0, "low", resonance=0.3)
    harmonic = dsp.filtered(dsp.saw(110.0, seconds), 700.0, "low") * 0.3
    rope = dsp.filtered(dsp.noise(seconds, 181), 1400.0, "low") * 0.25
    wobble = 1.0 + 0.08 * dsp.sine(2.0, seconds)
    mixed = dsp.mono_to_stereo(dsp.saturate((motor * 0.6 + harmonic + rope) * wobble, 1.6))
    return dsp.master(mixed, peak=0.45, edges=False)


def escalator_hum() -> Stereo:
    """Стрёкот эскалатора: цепь, шагающая по звёздочке, и мотор под ней."""
    seconds = 2.0
    period = 0.125
    motor = dsp.filtered(dsp.saw(74.0, seconds), 300.0, "low") * 0.4
    chain = np.zeros(dsp.samples(seconds), dtype=np.float32)
    for index in range(int(seconds / period)):
        tick = dsp.decay(dsp.filtered(dsp.noise(0.05, 190 + index), 2200.0, "high"), tau=0.004)
        start = dsp.samples(index * period)
        chain[start : start + tick.size] += tick[: max(chain.size - start, 0)] * 0.5
    return dsp.master(dsp.mono_to_stereo(motor + chain), peak=0.4, edges=False)


def door_open() -> Stereo:
    """Дверь открывается: ручка и ход полотна."""
    handle = dsp.decay(dsp.filtered(dsp.noise(0.05, 201), 2600.0, "high"), tau=0.007)
    swing = dsp.sweeping(
        dsp.noise(0.32, 202),
        cutoff=np.linspace(320.0, 1400.0, 32, dtype=np.float32),
        kind="low",
        resonance=0.8,
        block=1024,
    )
    swing = dsp.adsr(swing, attack=0.04, hold=0.1, release=0.18) * 0.45
    return dsp.master(placed(stack(handle * 0.8, swing), "floor", mix=0.3), peak=0.6)


def door_close() -> Stereo:
    """Дверь закрывается: ход полотна, защёлка и стук."""
    swing = dsp.sweeping(
        dsp.noise(0.26, 211),
        cutoff=np.linspace(1400.0, 380.0, 32, dtype=np.float32),
        kind="low",
        resonance=0.7,
        block=1024,
    )
    swing = dsp.adsr(swing, attack=0.02, hold=0.06, release=0.16) * 0.5
    latch = after(0.24, dsp.decay(dsp.filtered(dsp.noise(0.12, 212), 1600.0, "low"), tau=0.012))
    thud = after(0.24, dsp.decay(dsp.sine(dsp.glide(140.0, 60.0, 0.16), 0.16), tau=0.035))
    return dsp.master(placed(stack(swing, latch * 0.7, thud * 0.6), "floor", mix=0.3), peak=0.65)


def document() -> Stereo:
    """Документ взят: короткий светлый мотив с эхом. Единственная награда в игре."""
    phrase = np.zeros(dsp.samples(1.3), dtype=np.float32)
    for index, name in enumerate(("C5", "E5", "G5", "C6")):
        voice = _bell(note(name), 0.9) * 0.5
        start = dsp.samples(0.075 * index)
        phrase[start : start + voice.size] += voice[: max(phrase.size - start, 0)]
    delayed = dsp.echo(phrase, delay_time=0.19, feedback=0.4, mix=0.3)
    return dsp.master(dsp.widen(placed(delayed, "floor", mix=0.3), amount=0.4), peak=0.7)


def otto_death() -> Stereo:
    """Смерть Otto: всё проваливается вниз, и остаётся гулкая пустота."""
    fall = dsp.saturate(dsp.decay(dsp.saw(dsp.glide(330.0, 44.0, 1.0), 1.0), tau=0.3), 2.2)
    fall = dsp.filtered(fall, 1400.0, "low", resonance=0.4)
    air = dsp.sweeping(
        dsp.noise(1.0, 221),
        cutoff=np.linspace(3000.0, 200.0, 32, dtype=np.float32),
        kind="low",
        block=2048,
    )
    air = dsp.adsr(air, attack=0.02, hold=0.1, release=0.85) * 0.4
    return dsp.master(dsp.widen(placed(stack(fall * 0.7, air), "shaft", mix=0.45)), peak=0.85)


def agent_death() -> Stereo:
    """Смерть агента: короче и суше, чем у Otto, — их много."""
    grunt = dsp.decay(dsp.filtered(dsp.saw(dsp.glide(240.0, 90.0, 0.2), 0.2), 1200.0, "low"), tau=0.06)
    fall = after(0.18, dsp.decay(dsp.sine(dsp.glide(120.0, 48.0, 0.25), 0.25), tau=0.05))
    cloth = after(0.16, dsp.decay(dsp.filtered(dsp.noise(0.2, 231), 1500.0, "low"), tau=0.04))
    return dsp.master(placed(stack(grunt * 0.5, fall * 0.8, cloth * 0.5), "floor", mix=0.25), peak=0.7)


def car_away() -> Stereo:
    """Машина уезжает: мотор набирает обороты и уходит вбок."""
    seconds = 1.8
    revs = dsp.glide(60.0, 130.0, seconds, curve=0.6)
    engine = dsp.saturate(dsp.saw(revs, seconds) * 0.6 + dsp.saw(revs * 2.02, seconds) * 0.3, 2.5)
    engine = dsp.sweeping(
        engine, cutoff=np.linspace(700.0, 2600.0, 32, dtype=np.float32), kind="low", resonance=0.4
    )
    tyres = dsp.filtered(dsp.noise(seconds, 241), 1800.0, "low") * 0.25
    body = dsp.adsr(stack(engine * 0.7, tyres), attack=0.08, hold=0.7, release=1.0)

    wet = dsp.reverb(body, room("street"), mix=0.25)
    # Машина уезжает вправо: панорама едет вместе с ней.
    angle = (np.linspace(0.0, 0.9, wet.size, dtype=np.float32) + 1.0) * 0.25 * np.pi
    moving = np.stack([wet * np.cos(angle), wet * np.sin(angle)], axis=1).astype(np.float32)
    return dsp.master(moving, peak=0.75)


def building_bonus() -> Stereo:
    """Бонус за здание: аккорд с подъёмом фильтра — здание сдано."""
    seconds = 1.6
    chord = np.zeros(dsp.samples(seconds), dtype=np.float32)
    for name in ("A3", "C4", "E4", "A4", "B4"):
        chord += dsp.saw(note(name), seconds, detune=6.0) * 0.18
        chord += dsp.saw(note(name), seconds, detune=-6.0) * 0.18
    swept = dsp.sweeping(
        chord, cutoff=np.linspace(400.0, 6000.0, 32, dtype=np.float32), kind="low", resonance=0.7
    )
    swept = dsp.adsr(swept, attack=0.03, hold=0.5, release=1.0)
    shimmer = dsp.echo(swept * 0.4, delay_time=0.16, feedback=0.45, mix=0.35)
    return dsp.master(dsp.widen(placed(shimmer, "floor", mix=0.35), amount=0.45), peak=0.8)


def extra_life() -> Stereo:
    """Дополнительная жизнь: короткий подъём, который слышно поверх боя.

    Жизнь за очки — правка по мануалу Taito (ADR-0012, пункт 5), и звук ей нужен
    свой: без него прибавка в углу экрана проходит незамеченной.
    """
    phrase = np.zeros(dsp.samples(1.2), dtype=np.float32)
    for index, name in enumerate(("E5", "A5", "C6", "E6")):
        voice = _bell(note(name), 0.8) * 0.45
        start = dsp.samples(0.06 * index)
        phrase[start : start + voice.size] += voice[: max(phrase.size - start, 0)]
    shimmer = dsp.echo(phrase, delay_time=0.15, feedback=0.35, mix=0.3)
    return dsp.master(dsp.widen(placed(shimmer, "floor", mix=0.32), amount=0.4), peak=0.72)


def game_over() -> Stereo:
    """Game Over: тёмный аккорд и долгий хвост. Партия окончена."""
    seconds = 2.6
    chord = np.zeros(dsp.samples(seconds), dtype=np.float32)
    for name, level in (("A1", 0.8), ("A2", 0.5), ("C3", 0.35), ("E3", 0.3), ("G3", 0.2)):
        chord += dsp.saw(note(name), seconds, detune=4.0) * level * 0.3
        chord += dsp.sine(note(name), seconds) * level * 0.3
    shaped = dsp.adsr(
        dsp.filtered(chord, 1200.0, "low", resonance=0.2), attack=0.08, hold=0.6, release=1.8
    )
    sub = dsp.decay(dsp.sine(dsp.glide(90.0, 35.0, 2.0), 2.0), tau=0.7) * 0.5
    return dsp.master(dsp.widen(placed(stack(shaped, sub), "shaft", mix=0.45)), peak=0.85)


# --- Музыка ------------------------------------------------------------------


# --- Интерфейс ---------------------------------------------------------------
#
# Меню неоновое (ADR-0035), и звук у него электрический: короткие чистые тона
# с гудением трансформатора под ними, без комнаты — меню нигде не стоит.


def _neon_buzz(seconds: float, level: float) -> np.ndarray:
    """Гудение неона: сетевые 100 Гц с обертонами, приглушённые до фона."""
    hum = stack(dsp.sine(100.0, seconds) * 0.6, dsp.sine(200.0, seconds) * 0.3, dsp.pulse(300.0, seconds, 0.2) * 0.1)
    return dsp.decay(dsp.filtered(hum, 1200.0, "low"), tau=seconds * 0.4) * level


def ui_move() -> Stereo:
    """Переход по пунктам меню: короткий мягкий тик. Звучит чаще всех в меню."""
    tick = dsp.decay(dsp.sine(note("E6"), 0.06), tau=0.012)
    click = dsp.decay(dsp.filtered(dsp.noise(0.02, 201), 3500.0, "band"), tau=0.003)
    dry = stack(tick * 0.5, click * 0.25, _neon_buzz(0.06, 0.12))
    return dsp.master(dsp.mono_to_stereo(dry), peak=0.45)


def ui_select() -> Stereo:
    """Выбор: два тона вверх и вспышка неона — пункт загорелся."""
    first = dsp.decay(dsp.saw(note("A5"), 0.22, detune=0.004), tau=0.05)
    second = after(0.055, dsp.decay(dsp.saw(note("E6"), 0.3, detune=0.004), tau=0.08))
    tone = dsp.filtered(stack(first * 0.35, second * 0.35), 5200.0, "low")
    zap = dsp.decay(dsp.filtered(dsp.noise(0.05, 211), 2400.0, "high"), tau=0.006)
    dry = stack(tone, zap * 0.25, _neon_buzz(0.3, 0.2))
    return dsp.master(dsp.widen(dsp.mono_to_stereo(dsp.echo(dry, 0.09, 0.25, 0.2)), 0.3), peak=0.6)


def ui_back() -> Stereo:
    """Назад: тот же тон, но вниз и тише — неон гаснет."""
    fall = dsp.decay(dsp.saw(dsp.glide(note("E6"), note("A5"), 0.16), 0.2, detune=0.004), tau=0.05)
    dry = stack(dsp.filtered(fall, 3800.0, "low") * 0.35, _neon_buzz(0.2, 0.15))
    return dsp.master(dsp.mono_to_stereo(dry), peak=0.5)


def _kick_drum(seconds: float = 0.5) -> np.ndarray:
    body = dsp.decay(dsp.sine(dsp.glide(140.0, 45.0, seconds, curve=4.0), seconds), tau=0.08)
    click = dsp.decay(dsp.filtered(dsp.noise(0.02, 301), 1800.0, "high"), tau=0.004) * 0.4
    return dsp.saturate(stack(body, click), 1.8)


def _snare(seconds: float = 0.35) -> np.ndarray:
    body = dsp.decay(dsp.sine(190.0, seconds), tau=0.05) * 0.4
    rattle = dsp.decay(dsp.filtered(dsp.noise(seconds, 311), 1600.0, "high"), tau=0.07)
    return dsp.reverb(stack(body, rattle * 0.8), room("tight"), mix=0.35)


def _hat(seed: int) -> np.ndarray:
    return dsp.decay(dsp.filtered(dsp.noise(0.12, seed), 6500.0, "high"), tau=0.012)


def _place(track: np.ndarray, part: np.ndarray, at: float, level: float) -> None:
    start = dsp.samples(at)
    if start >= track.size:
        return
    end = min(start + part.size, track.size)
    track[start:end] += part[: end - start] * level


def _hits(row: str, index: int) -> bool:
    """Есть ли удар на этом шаге сетки. Рисунок короче петли и повторяется."""
    return row[index % len(row)] == "x"


def _drums(length: float, beat: float, pattern: dict[str, str], seed: int) -> np.ndarray:
    """Барабаны по сетке: `x` — удар, `.` — пауза. Шаг сетки — восьмая.

    Рисунок повторяется до конца петли: он задан на четыре такта, а петля
    длиной восемь, и без повтора вторая половина темы шла бы без барабанов.
    Бочка и рабочий синтезируются по разу: они одинаковы на каждом ударе, а
    у рабочего внутри свёртка с откликом комнаты.
    """
    track = np.zeros(dsp.samples(length + 1.0), dtype=np.float32)
    rng = np.random.default_rng(seed)
    step = beat * 0.5
    kick_hit = _kick_drum()
    snare_hit = _snare()
    for index in range(int(round(length / step))):
        at = index * step
        if _hits(pattern["kick"], index):
            _place(track, kick_hit, at, 0.9)
        if _hits(pattern["snare"], index):
            _place(track, snare_hit, at, 0.8)
        if _hits(pattern["hat"], index):
            _place(track, _hat(seed + index), at, float(rng.uniform(0.3, 0.5)))
    return track


def _bass(notes: list[tuple[str, float]], beat: float, length: float) -> np.ndarray:
    """Бас: синус для веса и пила для зубов, оба через насыщение."""
    track = np.zeros(dsp.samples(length + 1.0), dtype=np.float32)
    at = 0.0
    for name, beats in notes:
        seconds = beats * beat
        pitch = note(name)
        # Синус даёт вес, пила — зубы. Подвал ниже 45 Гц срезан: он не слышен
        # на обычных колонках, зато съедает весь запас громкости в миксе.
        voice = dsp.sine(pitch, seconds * 1.1) * 0.55 + dsp.saw(pitch, seconds * 1.1) * 0.45
        voice = dsp.filtered(dsp.filtered(voice, 1600.0, "low"), 45.0, "high", slope=18.0)
        voice = dsp.adsr(voice, attack=0.006, hold=seconds * 0.5, release=seconds * 0.6)
        _place(track, dsp.saturate(voice, 2.0), at, 0.5)
        at += seconds
    return track


def _arpeggio(notes: list[str], beat: float, length: float) -> np.ndarray:
    """Арпеджио шестнадцатыми через фильтр с движущимся срезом и эхом."""
    step = beat * 0.25
    track = np.zeros(dsp.samples(length + 1.0), dtype=np.float32)
    for index in range(int(length / step)):
        pitch = note(notes[index % len(notes)])
        voice = dsp.saw(pitch, step * 2.0, detune=5.0) + dsp.saw(pitch, step * 2.0, detune=-5.0)
        _place(track, dsp.decay(voice * 0.5, tau=step * 0.9), index * step, 0.3)

    # Движение среза — половина звука synthwave: без него арпеджио плоское.
    cutoff = 1500.0 + 4500.0 * (0.5 + 0.5 * np.sin(np.linspace(0.0, 4.0 * np.pi, 64, dtype=np.float32)))
    swept = dsp.sweeping(track, cutoff=cutoff, kind="low", resonance=0.9)
    return dsp.echo(swept, delay_time=beat * 0.75, feedback=0.35, mix=0.3)


def _pad(chords: list[tuple[list[str], float]], beat: float, length: float) -> np.ndarray:
    """Пад: расстроенные пилы, медленная атака, много комнаты."""
    track = np.zeros(dsp.samples(length + 2.0), dtype=np.float32)
    at = 0.0
    for names, beats in chords:
        seconds = beats * beat
        chord = np.zeros(dsp.samples(seconds * 1.4), dtype=np.float32)
        for name in names:
            chord += dsp.saw(note(name), seconds * 1.4, detune=7.0) * 0.16
            chord += dsp.saw(note(name), seconds * 1.4, detune=-7.0) * 0.16
        shaped = dsp.adsr(
            dsp.filtered(chord, 1600.0, "low", resonance=0.2),
            attack=seconds * 0.35,
            hold=seconds * 0.3,
            release=seconds * 0.7,
        )
        _place(track, shaped, at, 0.5)
        at += seconds
    # Низ у пада срезан: там уже стоит бас, и вдвоём они забивают середину.
    return dsp.reverb(dsp.filtered(track, 220.0, "high", slope=12.0), room("shaft"), mix=0.45)


def theme() -> Stereo:
    """Тема здания: тёмный synthwave, восемь тактов, ля минор.

    Своя, а не из оригинала: тема Taito — их собственность (ADR-0012, пункт 2).
    Ход Am–F–C–G держит половину жанра: он не отвлекает от игры и не приедается
    за партию, а петля замкнута так, что шва не слышно.
    """
    beat = 60.0 / 92.0
    length = beat * 32.0

    drums = _drums(
        length,
        beat,
        {
            "kick": "x..x..x...x..x..x..x..x...x..x..",
            "snare": "....x.......x.......x.......x...",
            "hat": "..x...x...x...x...x...x...x...x.",
        },
        seed=331,
    )
    bass = _bass(
        [
            ("A2", 2.0), ("A2", 1.0), ("A3", 1.0), ("F2", 2.0), ("F2", 2.0),
            ("C3", 2.0), ("C3", 2.0), ("G2", 2.0), ("G2", 1.0), ("G3", 1.0),
            ("A2", 2.0), ("A2", 1.0), ("A3", 1.0), ("F2", 2.0), ("F2", 2.0),
            ("C3", 2.0), ("C3", 2.0), ("G2", 4.0),
        ],
        beat,
        length,
    )
    arp = _arpeggio(["A4", "C5", "E5", "A5", "E5", "C5"], beat, length)
    pad = _pad(
        [
            (["A3", "C4", "E4"], 4.0),
            (["F3", "A3", "C4"], 4.0),
            (["C4", "E4", "G4"], 4.0),
            (["G3", "B3", "D4"], 4.0),
        ]
        * 2,
        beat,
        length,
    )

    # Баланс слоёв проверен спектром, а не на глаз: на первой версии бас
    # занимал четыре пятых энергии, и арпеджио с падом были не слышны вовсе.
    mixed = dsp.layer(
        dsp.mono_to_stereo(dsp.compress(drums * 0.55, threshold=0.3, ratio=3.0)),
        dsp.mono_to_stereo(dsp.shelf(bass, 900.0, 0.35) * 0.33),
        dsp.widen(dsp.mono_to_stereo(dsp.shelf(arp, 2500.0, 0.6) * 1.1), amount=0.5),
        dsp.widen(dsp.mono_to_stereo(dsp.shelf(pad, 2000.0, 0.5) * 0.9), amount=0.6, offset=0.02),
    )
    return dsp.master(dsp.loop_seamlessly(mixed, length), peak=0.82, edges=False)


def alarm_theme() -> Stereo:
    """Мотив тревоги: то же здание, но теперь оно против тебя.

    Быстрее, жёстче, с сиреной поверх. Сирена работает в игре с M5b, и звучать
    ей до сих пор было нечем.
    """
    beat = 60.0 / 116.0
    length = beat * 32.0

    drums = _drums(
        length,
        beat,
        {
            "kick": "x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.x.",
            "snare": "....x.......x.......x.......x...",
            "hat": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        },
        seed=351,
    )
    bass = _bass([("D2", 1.0), ("D2", 1.0), ("D2", 1.0), ("Eb2", 1.0)] * 8, beat, length)
    arp = _arpeggio(["D4", "Eb4", "A4", "Eb4"], beat, length)

    # Сирена: тритон, качающийся туда-обратно поверх всего остального.
    siren = np.zeros(dsp.samples(length + 1.0), dtype=np.float32)
    sweep = beat * 2.0
    rising = dsp.glide(note("A4"), note("Eb5"), sweep, curve=1.0)
    for index in range(int(length / sweep)):
        pitch = rising if index % 2 == 0 else rising[::-1]
        voice = dsp.adsr(
            dsp.pulse(pitch, sweep, duty=0.35),
            attack=0.05,
            hold=sweep * 0.5,
            release=sweep * 0.4,
        )
        _place(siren, dsp.filtered(voice, 2400.0, "low", resonance=0.5), index * sweep, 0.22)

    mixed = dsp.layer(
        dsp.mono_to_stereo(dsp.compress(drums * 0.6, threshold=0.28, ratio=3.5)),
        dsp.mono_to_stereo(dsp.shelf(bass, 900.0, 0.35) * 0.335),
        dsp.widen(dsp.mono_to_stereo(dsp.shelf(arp, 2500.0, 0.6) * 1.0), amount=0.5),
        dsp.widen(
            dsp.mono_to_stereo(dsp.shelf(dsp.reverb(siren, room("shaft"), mix=0.3), 2000.0, 0.4)),
            amount=0.3,
        ),
    )
    return dsp.master(dsp.loop_seamlessly(mixed, length), peak=0.85, edges=False)


EFFECTS: dict[str, Callable[[], Stereo]] = {
    "step": step_sound,
    "shot": shot,
    "hit": hit,
    "kick": kick,
    "lamp_break": lamp_break,
    "lamp_crash": lamp_crash,
    "elevator_hum": elevator_hum,
    "escalator_hum": escalator_hum,
    "door_open": door_open,
    "door_close": door_close,
    "document": document,
    "otto_death": otto_death,
    "agent_death": agent_death,
    "car_away": car_away,
    "building_bonus": building_bonus,
    "extra_life": extra_life,
    "game_over": game_over,
    "ui_move": ui_move,
    "ui_select": ui_select,
    "ui_back": ui_back,
}

## Музыка пишется в OGG: двадцать секунд стерео в WAV весят три с половиной
## мегабайта, а лежать им в репозитории вечно.
MUSIC: dict[str, Callable[[], Stereo]] = {
    "theme": theme,
    "alarm_theme": alarm_theme,
}

## Длинные и редкие эффекты тоже уезжают в OGG. Частые и короткие остаются WAV:
## шаг и выстрел звучат сотнями за партию, и распаковывать их каждый раз незачем.
LONG: frozenset[str] = frozenset(
    {
        "document",
        "building_bonus",
        "extra_life",
        "car_away",
        "game_over",
        "otto_death",
    }
)

## Петли режутся ровно по длине, поэтому хвост у них не срезается. Сводятся они
## через `dsp.master(..., edges=False)`: край петли — это её шов, и погашенный
## край слышен дырой на каждом обороте.
LOOPED: frozenset[str] = frozenset({"elevator_hum", "escalator_hum", "theme", "alarm_theme"})

SOUNDS: dict[str, Callable[[], Stereo]] = {**EFFECTS, **MUSIC}


def path_of(name: str, out_dir: Path) -> Path:
    compressed = name in MUSIC or name in LONG
    return out_dir / (f"{name}.ogg" if compressed else f"{name}.wav")


## Кусок, которым пишется OGG. Кодировщик Vorbis в libsndfile 1.2.2 роняет
## процесс без traceback, если отдать ему разом больше ~20 секунд стерео
## (проверено: 15 с пишутся, 21 с убивает python). Поблочная запись это обходит.
OGG_CHUNK = dsp.RATE


def write(path: Path, audio: Stereo) -> None:
    import soundfile

    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix != ".ogg":
        soundfile.write(path, audio, dsp.RATE, subtype="PCM_16")
        return

    with soundfile.SoundFile(
        path, "w", samplerate=dsp.RATE, channels=2, format="OGG", subtype="VORBIS"
    ) as handle:
        for start in range(0, audio.shape[0], OGG_CHUNK):
            handle.write(audio[start : start + OGG_CHUNK])


def main() -> int:
    parser = argparse.ArgumentParser(description="Синтез звуков и музыки игры.")
    parser.add_argument("names", nargs="*", help="что писать; по умолчанию всё")
    parser.add_argument("--list", action="store_true", help="перечислить и выйти")
    parser.add_argument("--out", type=Path, default=OUT_DIR, help="куда писать файлы")
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
        audio = SOUNDS[name]()
        if name not in LOOPED:
            audio = dsp.trim(audio)
        path = path_of(name, arguments.out)
        write(path, audio)
        seconds = audio.shape[0] / float(dsp.RATE)
        try:
            shown = path.relative_to(PROJECT_ROOT).as_posix()
        except ValueError:
            shown = str(path)
        print(f"{shown}  {seconds:.2f} с  {path.stat().st_size / 1024:.0f} КБ")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
