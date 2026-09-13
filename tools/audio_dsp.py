#!/usr/bin/env python3
"""Небольшая студия на numpy: осцилляторы, фильтры, реверб, мастеринг.

Отдельно от `render_audio.py` по той же причине, по которой `palette.py` отделён
от генератора картинок: здесь инструменты, там — сами звуки.

Всё считается офлайн и целиком в памяти, поэтому фильтры работают в частотной
области, а реверб — свёрткой с синтезированным импульсным откликом. Это и проще
рекурсивных схем, и качественнее: нет ни дрожания фазы, ни накопленной ошибки.

Звук стерео и 44 100 Гц: игра ремейк, и звучать она должна как игра 2026 года,
а не как чип 1983-го (ADR-0012, правка после прослушивания).
"""

from __future__ import annotations

import numpy as np

RATE = 44100

## Форма сигнала внутри студии: float32, значения около -1..1, моно — одномерный
## массив, стерео — массив (n, 2).
Mono = np.ndarray
Stereo = np.ndarray


def samples(duration: float) -> int:
    return max(int(round(RATE * duration)), 1)


def time(duration: float) -> Mono:
    """Ось времени в секундах."""
    return np.arange(samples(duration), dtype=np.float32) / RATE


def silence(duration: float) -> Mono:
    return np.zeros(samples(duration), dtype=np.float32)


# --- Осцилляторы -------------------------------------------------------------


def _phase(pitch: float | Mono, duration: float) -> Mono:
    """Фаза от частоты: частота может быть и числом, и кривой."""
    count = samples(duration)
    if np.isscalar(pitch):
        curve = np.full(count, float(pitch), dtype=np.float32)
    else:
        curve = np.asarray(pitch, dtype=np.float32)[:count]
        if curve.size < count:
            curve = np.pad(curve, (0, count - curve.size), mode="edge")
    return np.cumsum(curve, dtype=np.float32) / RATE


def sine(pitch: float | Mono, duration: float, phase: float = 0.0) -> Mono:
    return np.sin(2.0 * np.pi * (_phase(pitch, duration) + phase)).astype(np.float32)


def _polyblep(phase: Mono, step: Mono) -> Mono:
    """Сглаживание скачка пилы и меандра: без него они звенят алиасингом."""
    correction = np.zeros_like(phase)
    rising = phase < step
    part = phase[rising] / np.maximum(step[rising], 1e-9)
    correction[rising] = part + part - part * part - 1.0

    falling = phase > 1.0 - step
    part = (phase[falling] - 1.0) / np.maximum(step[falling], 1e-9)
    correction[falling] = part * part + part + part + 1.0
    return correction


def saw(pitch: float | Mono, duration: float, detune: float = 0.0) -> Mono:
    """Пила со сглаженным скачком. [param detune] — расстройка в центах."""
    factor = 2.0 ** (detune / 1200.0)
    scaled = pitch * factor if np.isscalar(pitch) else np.asarray(pitch) * factor
    phase = np.mod(_phase(scaled, duration), 1.0).astype(np.float32)
    step = np.full_like(phase, float(np.mean(scaled)) / RATE if np.isscalar(scaled) else 0.0)
    if not np.isscalar(scaled):
        curve = np.asarray(scaled, dtype=np.float32)[: phase.size]
        step = np.pad(curve, (0, max(phase.size - curve.size, 0)), mode="edge") / RATE
    return (2.0 * phase - 1.0 - _polyblep(phase, step)).astype(np.float32)


def pulse(pitch: float | Mono, duration: float, duty: float = 0.5) -> Mono:
    """Меандр с изменяемой скважностью — две пилы со сдвигом."""
    first = saw(pitch, duration)
    shift = samples(duty / max(float(np.mean(pitch)), 1e-6))
    second = np.roll(first, shift)
    return ((first - second) * 0.5).astype(np.float32)


def noise(duration: float, seed: int) -> Mono:
    """Белый шум. Сид фиксирован: тот же прогон — тот же файл."""
    rng = np.random.default_rng(seed)
    return rng.uniform(-1.0, 1.0, samples(duration)).astype(np.float32)


# --- Огибающие ---------------------------------------------------------------


def fade(signal: Mono, attack: float = 0.002, release: float = 0.004) -> Mono:
    """Микрофейды на краях: без них в начале и конце слышен щелчок."""
    out = np.array(signal, dtype=np.float32, copy=True)
    head = min(samples(attack), out.size // 2)
    tail = min(samples(release), out.size // 2)
    if head > 0:
        out[:head] *= np.linspace(0.0, 1.0, head, dtype=np.float32)
    if tail > 0:
        out[-tail:] *= np.linspace(1.0, 0.0, tail, dtype=np.float32)
    return out


def decay(signal: Mono, tau: float, attack: float = 0.002) -> Mono:
    """Экспоненциальное затухание — так гаснет всё, во что ударили."""
    curve = np.exp(-np.arange(signal.size, dtype=np.float32) / max(tau * RATE, 1.0))
    head = min(samples(attack), signal.size)
    if head > 0:
        curve[:head] *= np.linspace(0.0, 1.0, head, dtype=np.float32)
    return (signal * curve).astype(np.float32)


def adsr(
    signal: Mono, attack: float = 0.01, hold: float = 0.05, release: float = 0.2, floor: float = 0.0
) -> Mono:
    """Атака, полка, спад. Полка держит уровень, спад уводит к [param floor]."""
    count = signal.size
    attack_count = min(samples(attack), count)
    hold_count = min(samples(hold), count - attack_count)
    release_count = max(count - attack_count - hold_count, 0)
    curve = np.concatenate(
        [
            np.linspace(0.0, 1.0, attack_count, endpoint=False, dtype=np.float32),
            np.ones(hold_count, dtype=np.float32),
            np.linspace(1.0, floor, release_count, dtype=np.float32) ** 2,
        ]
    )[:count]
    return (signal * curve).astype(np.float32)


def glide(start: float, finish: float, duration: float, curve: float = 3.0) -> Mono:
    """Кривая высоты от [param start] к [param finish] — «уход» выстрела вниз."""
    shape = np.linspace(0.0, 1.0, samples(duration), dtype=np.float32) ** curve
    return (start + (finish - start) * shape).astype(np.float32)


# --- Фильтры -----------------------------------------------------------------


def _response(size: int, cutoff: float, kind: str, resonance: float, slope: float) -> Mono:
    freqs = np.fft.rfftfreq(size, 1.0 / RATE).astype(np.float32)
    # Отношение зажато снизу: у нулевой частоты обратное отношение в восьмой
    # степени переполняет float32, и фильтр отдаёт NaN вместо тишины.
    ratio = np.clip(freqs / max(cutoff, 1e-6), 1e-4, 1e4).astype(np.float64)
    if kind == "low":
        magnitude = 1.0 / np.sqrt(1.0 + ratio ** (2.0 * slope / 6.0))
    elif kind == "high":
        magnitude = 1.0 / np.sqrt(1.0 + (1.0 / ratio) ** (2.0 * slope / 6.0))
    else:
        magnitude = 1.0 / np.sqrt(1.0 + (ratio - 1.0 / ratio) ** 2 * (12.0 / max(slope, 1e-6)))

    if resonance > 0.0:
        # Горб у среза — то, что делает фильтр «поющим»; без него движение среза
        # слышно как глухое открывание, а не как в синтезаторе.
        width = 0.22 / max(resonance, 0.05)
        magnitude = magnitude + resonance * np.exp(-((np.log2(np.maximum(ratio, 1e-6)) / width) ** 2))
    return magnitude.astype(np.float32)


def filtered(
    signal: Mono, cutoff: float, kind: str = "low", resonance: float = 0.0, slope: float = 24.0
) -> Mono:
    """Фильтр в частотной области: спектр умножается на кривую отклика.

    Офлайн это и проще рекурсивной схемы, и чище: фаза не едет, ошибка не копится.
    """
    spectrum = np.fft.rfft(signal)
    spectrum *= _response(signal.size, cutoff, kind, resonance, slope)
    return np.fft.irfft(spectrum, n=signal.size).astype(np.float32)


def sweeping(
    signal: Mono, cutoff: Mono, kind: str = "low", resonance: float = 0.0, block: int = 2048
) -> Mono:
    """Фильтр с движущимся срезом: сигнал режется на блоки с перекрытием.

    Нужен арпеджио и падам: в synthwave движение среза — половина звука.
    """
    window = np.hanning(block * 2).astype(np.float32)
    out = np.zeros(signal.size + block * 2, dtype=np.float32)
    curve = np.interp(
        np.linspace(0.0, 1.0, max(signal.size // block, 1) + 1),
        np.linspace(0.0, 1.0, cutoff.size),
        cutoff,
    )
    for index, start in enumerate(range(0, signal.size, block)):
        chunk = np.zeros(block * 2, dtype=np.float32)
        piece = signal[start : start + block * 2]
        chunk[: piece.size] = piece
        shaped = filtered(chunk * window, float(curve[min(index, curve.size - 1)]), kind, resonance)
        out[start : start + block * 2] += shaped
    return out[: signal.size] * 0.5


# --- Пространство и насыщение ------------------------------------------------


def impulse_response(seconds: float, brightness: float, seed: int, predelay: float = 0.01) -> Mono:
    """Синтезированный отклик комнаты: шум, который гаснет.

    Здание бетонное, и хвост у него короткий и тёмный — этим комната и отличается
    от зала. Ранние отражения добавлены отдельными всплесками: без них хвост
    звучит как ровный шипящий шлейф, а не как стены вокруг.
    """
    tail = decay(noise(seconds, seed), tau=seconds * 0.28, attack=0.001)
    tail = filtered(tail, cutoff=brightness, kind="low", slope=12.0)
    tail = filtered(tail, cutoff=120.0, kind="high", slope=12.0)

    rng = np.random.default_rng(seed + 1)
    for _reflection in range(6):
        offset = samples(rng.uniform(0.004, 0.07))
        gain = rng.uniform(0.15, 0.5)
        if offset < tail.size:
            tail[offset] += gain

    head = samples(predelay)
    return np.concatenate([np.zeros(head, dtype=np.float32), tail]).astype(np.float32)


def reverb(signal: Mono, room: Mono, mix: float = 0.3) -> Mono:
    """Свёртка с откликом комнаты. Быстро — через частотную область."""
    size = 1 << int(np.ceil(np.log2(signal.size + room.size)))
    wet = np.fft.irfft(np.fft.rfft(signal, size) * np.fft.rfft(room, size), n=size)
    wet = wet[: signal.size + room.size].astype(np.float32)
    peak = float(np.abs(wet).max())
    if peak > 0.0:
        wet *= float(np.abs(signal).max()) / peak

    out = np.zeros(wet.size, dtype=np.float32)
    out[: signal.size] += signal * (1.0 - mix)
    out += wet * mix
    return out


def echo(signal: Mono, delay_time: float, feedback: float = 0.35, mix: float = 0.25) -> Mono:
    """Дилей отражениями: конечная сумма копий вместо рекурсии."""
    step = samples(delay_time)
    taps = 6
    out = np.zeros(signal.size + step * taps, dtype=np.float32)
    out[: signal.size] += signal
    level = mix
    for tap in range(1, taps + 1):
        start = step * tap
        out[start : start + signal.size] += signal * level
        level *= feedback
    return out.astype(np.float32)


def saturate(signal: Mono, drive: float = 2.0) -> Mono:
    """Мягкое насыщение: добавляет гармоник и склеивает слои."""
    return np.tanh(signal * drive).astype(np.float32) / np.tanh(drive)


def compress(signal: Mono, threshold: float = 0.35, ratio: float = 4.0) -> Mono:
    """Компрессор со сглаженным детектором: выравнивает удары по громкости."""
    level = filtered(np.abs(signal), cutoff=25.0, kind="low", slope=12.0)
    level = np.maximum(level, 1e-6)
    over = np.maximum(level / threshold, 1.0)
    gain = over ** (1.0 / ratio - 1.0)
    return (signal * gain).astype(np.float32)


# --- Стерео и мастеринг ------------------------------------------------------


def mono_to_stereo(signal: Mono, pan: float = 0.0) -> Stereo:
    """Панорама по равной мощности: -1 — слева, 0 — по центру, 1 — справа."""
    angle = (np.clip(pan, -1.0, 1.0) + 1.0) * 0.25 * np.pi
    return np.stack([signal * np.cos(angle), signal * np.sin(angle)], axis=1).astype(np.float32)


def widen(stereo: Stereo, amount: float = 0.35, offset: float = 0.012) -> Stereo:
    """Расширение по Хаасу: правый канал чуть отстаёт, и картинка раздаётся вширь."""
    shift = samples(offset)
    out = np.array(stereo, dtype=np.float32, copy=True)
    delayed = np.roll(stereo[:, 1], shift)
    delayed[:shift] = 0.0
    out[:, 1] = stereo[:, 1] * (1.0 - amount) + delayed * amount
    return out


def layer(*parts: Stereo) -> Stereo:
    """Складывает слои разной длины в один стерео-сигнал."""
    length = max(part.shape[0] for part in parts)
    out = np.zeros((length, 2), dtype=np.float32)
    for part in parts:
        out[: part.shape[0]] += part
    return out


def limit(stereo: Stereo, ceiling: float = 0.92) -> Stereo:
    """Лимитер с просмотром вперёд: подрезает пики, не плюща всё подряд."""
    peak = np.max(np.abs(stereo), axis=1)
    over = np.maximum(peak / ceiling, 1.0)
    # Сглаженная кривая усиления: резкий излом слышен как щелчок.
    gain = 1.0 / filtered(over, cutoff=60.0, kind="low", slope=12.0).clip(1.0, None)
    return (stereo * gain[:, None]).astype(np.float32)


def master(stereo: Stereo, peak: float = 0.89, edges: bool = True) -> Stereo:
    """Итоговая обработка: убрать постоянную составляющую, подрезать, выровнять.

    [param edges] — гасить ли края. Одноразовому звуку это нужно, иначе на старте
    и в конце слышен щелчок. Петле — противопоказано: край петли и есть её шов,
    и десять миллисекунд тишины там слышны как дыра на каждом обороте.
    """
    out = stereo - np.mean(stereo, axis=0, keepdims=True)
    out = limit(out, ceiling=peak)
    top = float(np.abs(out).max())
    if top > 0.0:
        out = out * (peak / top)
    if not edges:
        return out.astype(np.float32)

    head = min(samples(0.003), out.shape[0] // 2)
    tail = min(samples(0.01), out.shape[0] // 2)
    if head > 0:
        out[:head] *= np.linspace(0.0, 1.0, head, dtype=np.float32)[:, None]
    if tail > 0:
        out[-tail:] *= np.linspace(1.0, 0.0, tail, dtype=np.float32)[:, None]
    return out.astype(np.float32)


def shelf(signal: Mono, cutoff: float = 3000.0, amount: float = 0.5) -> Mono:
    """Полка сверху: добавляет воздуха, не трогая низ.

    Нужна миксу: после лимитера верх слышно хуже, чем он есть, и без полки
    картинка выходит глухой.
    """
    return (signal + filtered(signal, cutoff, "high", slope=12.0) * amount).astype(np.float32)


def trim(stereo: Stereo, floor_db: float = -60.0, tail: float = 0.05) -> Stereo:
    """Срезает тишину в хвосте: реверб уходит в ноль задолго до конца массива.

    Без этого половина файла — нули, которые всё равно лежат в репозитории.
    """
    level = np.max(np.abs(stereo), axis=1)
    loud = np.nonzero(level > 10.0 ** (floor_db / 20.0))[0]
    if loud.size == 0:
        return stereo
    finish = min(int(loud[-1]) + samples(tail), stereo.shape[0])
    return np.ascontiguousarray(stereo[:finish])


def loop_seamlessly(stereo: Stereo, length: float) -> Stereo:
    """Заворачивает хвост в начало: петля без шва и без обрыва реверба.

    Кусок, вышедший за длину петли, — это звон последних нот. Если его просто
    обрезать, на стыке будет слышна дыра; если оставить — петля разъедется.
    """
    count = samples(length)
    out = np.zeros((count, 2), dtype=np.float32)
    out += stereo[:count]
    overhang = stereo[count:]
    if overhang.shape[0] > 0:
        tail = min(overhang.shape[0], count)
        out[:tail] += overhang[:tail]
    return out.astype(np.float32)
