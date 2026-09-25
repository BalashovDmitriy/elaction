#!/usr/bin/env python3
"""Звук игры из свободных библиотек (ADR-0036).

Музыка — Kevin MacLeod (incompetech.com, CC-BY 4.0), джинглы и звуки меню —
паки Kenney (CC0), эффекты и фон — freesound.org (CC0 и CC-BY). Каждый файл
выбран пользователем на слух; здесь — откуда он взят и как приведён к игре:
обрезка, петля со сшивкой, громкость, моно для звуков на месте.

    python tools/build_audio.py              # скачать и собрать всё
    python tools/build_audio.py shot theme   # только эти имена
    python tools/build_audio.py --list

Пишет в `assets/audio/`: короткие эффекты — WAV, длинное — OGG. Несколько
вариантов одного имени — `имя.ogg`, `имя.2.ogg`, …: музыку и фон игра берёт
жребием по зданию, эффекты — на каждый звук (`Sounds`). Авторы — в
`assets/audio/credits.json`; таблица для `CREDITS.md` печатается `--credits`.

Скачанное кладётся в `.cache/audio/` рядом с проектом: freesound отвечает 429,
если спрашивать часто.
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import soundfile as sf

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT = PROJECT_ROOT / "assets/audio"
CACHE = PROJECT_ROOT / ".cache/audio"

CC0 = "CC0 1.0"
BY3 = "CC-BY 3.0"
BY4 = "CC-BY 4.0"

INCOMPETECH = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/"
MACLEOD = "Kevin MacLeod (incompetech.com)"
KENNEY = {
    "impact": "https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip",
    "interface": "https://kenney.nl/media/pages/assets/interface-sounds/fa43c1dd4d-1677589452/kenney_interface-sounds.zip",
    "ui": "https://kenney.nl/media/pages/assets/ui-audio/490d233f68-1677590494/kenney_ui-audio.zip",
    "jingles": "https://kenney.nl/media/pages/assets/music-jingles/f37e530b9e-1677590399/kenney_music-jingles.zip",
}
KENNEY_PAGES = {
    "impact": "https://kenney.nl/assets/impact-sounds",
    "interface": "https://kenney.nl/assets/interface-sounds",
    "ui": "https://kenney.nl/assets/ui-audio",
    "jingles": "https://kenney.nl/assets/music-jingles",
}

# Громкость. Музыка и фон — по среднеквадратичной громкости звучащей части,
# эффекты — по пику, а потом поправкой на баланс: шаг не должен спорить с
# выстрелом.
MUSIC_RMS = -18.0
JINGLE_RMS = -17.0
LOOP_RMS = -24.0
AMBIENCE_RMS = -26.0
PEAK = -1.0


@dataclass
class Source:
    """Откуда взят звук и как его привести."""

    title: str
    author: str
    licence: str
    page: str
    url: str = ""
    # Файл внутри архива Kenney.
    member: str = ""
    # Отрезок, с. Отрицательное — от конца; `end` None — до конца.
    start: float = 0.0
    end: float | None = None
    # Петля со сшивкой в столько секунд; 0 — звучит один раз.
    loop: float = 0.0
    fade_in: float = 0.0
    fade_out: float = 0.0
    mono: bool = False
    # Как выравнивать: "music", "jingle", "loop", "ambience", "peak".
    level: str = "peak"
    gain: float = 0.0
    # Срезать тишину в начале: у записей freesound до звука бывает полсекунды.
    trim: bool = True
    excerpt: bool = False


def freesound(sound: int, user: int, author: str, title: str, licence: str, **kw) -> Source:
    page = f"https://freesound.org/people/{author}/sounds/{sound}/"
    url = f"https://cdn.freesound.org/previews/{sound // 1000}/{sound}_{user}-hq.mp3"
    return Source(title=title, author=author, licence=licence, page=page, url=url, **kw)


def macleod(title: str, **kw) -> Source:
    url = INCOMPETECH + urllib.parse.quote(title) + ".mp3"
    page = "https://incompetech.com/music/royalty-free/licenses/"
    return Source(title=title, author=MACLEOD, licence=BY4, page=page, url=url, **kw)


def kenney(pack: str, member: str, title: str, **kw) -> Source:
    return Source(
        title=title, author="Kenney", licence=CC0, page=KENNEY_PAGES[pack],
        url=KENNEY[pack], member=member, **kw,
    )


def _track(title: str) -> Source:
    # Треки целиком: петлю им задаёт игра, а у трека и так есть начало и конец.
    return macleod(title, level="music", trim=False)


SOUNDS: dict[str, list[Source]] = {
    # --- Музыка: свой трек на экран, трек здания и тревоги — жребием по зданию.
    "theme": [_track("Spy Glass"), _track("Hard Boiled"), _track("Covert Affair"),
              _track("Dances and Dames")],
    "alarm_theme": [_track("Fast Talkin"), _track("Private Eye"), _track("On the Cool Side")],
    "menu_theme": [_track("Cool Vibes")],
    "game_over_theme": [_track("Just As Soon")],
    # --- Джинглы.
    "document": [kenney("jingles", "Audio/Sax jingles/jingles_SAX16.ogg", "Music Jingles: SAX16",
                        level="jingle")],
    "extra_life": [freesound(578401, 10522382, "nomiqbomi", "Inquisitive Vibraphone 09", CC0,
                             end=2.4, fade_out=0.5, level="jingle")],
    "building_bonus": [macleod("Rollin at 5", start=-13.0, end=-7.3, fade_in=0.03,
                               fade_out=0.35, level="jingle", trim=False, excerpt=True)],
    "death_jingle": [freesound(362204, 6629901, "TaranP", "horn_fail_wahwah_3", CC0,
                               end=3.4, fade_out=0.4, level="jingle", gain=-3.0)],
    "game_over": [macleod("Hard Boiled", start=-8.5, fade_in=0.03, fade_out=0.35,
                          level="jingle", trim=False, excerpt=True)],
    # --- Эффекты.
    "step_carpet": [freesound(38872, 15613, "swuing", "footstep-carpet.wav", BY4, mono=True,
                              gain=-9.0)],
    "step_concrete": [kenney("impact", f"Audio/footstep_concrete_00{i}.ogg",
                             f"Impact Sounds: footstep_concrete_00{i}", mono=True, gain=-9.0)
                      for i in range(5)],
    "shot": [freesound(427592, 3094998, "michorvath", "9mm pistol shot", CC0, mono=True,
                       end=1.2, fade_out=0.3)],
    "kick": [freesound(118513, 2136023, "thefsoundman", "punch", CC0, mono=True, gain=-2.0)],
    "agent_death": [freesound(447922, 9159316, "Breviceps", "thud", CC0, mono=True, gain=-2.0)],
    "otto_death": [freesound(554443, 6512859, "Blankened", "male death", CC0, mono=True)],
    "lamp_break": [freesound(322602, 1732887, "Natty23", "glass break small", BY4, mono=True,
                             gain=-3.0)],
    "lamp_crash": [freesound(258242, 1341943, "youandbiscuitme", "lamp dropped (condenser)", BY3,
                             mono=True, end=2.2, fade_out=0.4)],
    "elevator_hum": [freesound(825478, 843915, "Filmscore", "hotel elevator ride", CC0,
                               mono=True, start=6.0, end=16.0, loop=1.0, level="loop",
                               trim=False)],
    "escalator_hum": [freesound(170231, 3133582, "roachpowder", "escalator", CC0, mono=True,
                                loop=1.0, level="loop", trim=False)],
    "door_open": [freesound(431117, 5121236, "InspectorJ", "Door, Front, Opening", BY4, mono=True,
                            gain=-4.0)],
    "door_close": [freesound(117415, 1218676, "joedeshon", "wooden door close", BY4, mono=True,
                             gain=-4.0)],
    "car_away": [freesound(128190, 1160789, "soundmary", "car drive away", BY4, mono=True,
                           end=8.0, fade_out=2.0, level="loop", gain=4.0)],
    # --- M24b: вертолёт, трос, машина, ворота, шахта в подвал (ADR-0038).
    "helicopter": [freesound(541482, 11157357, "Lydmakeren", "Helicopter_Hover", CC0,
                             mono=True, start=150.0, end=170.0, loop=2.0, level="loop",
                             trim=False)],
    "helicopter_pass": [freesound(405234, 5121236, "InspectorJ", "Helicopter Flyby, Distant, A",
                                  BY4, mono=True, start=110.0, end=170.0, fade_in=2.0,
                                  fade_out=5.0, level="peak")],
    "rope_slide": [freesound(162151, 1212810, "beerbelly38", "abseil2", BY4, mono=True,
                             start=0.2, end=1.9, fade_out=0.3)],
    "car_door": [freesound(208695, 1756543, "monotraum", "car door close", CC0, mono=True,
                           gain=-4.0)],
    "car_start": [freesound(138099, 1572282, "snakebarney", "Car Start", CC0, mono=True,
                            fade_out=0.8)],
    "garage_gate": [freesound(202666, 2814925, "freesoundjon01",
                              "Automatic Garage Roller Door Opening", CC0, mono=True, start=0.8,
                              end=11.8, fade_out=0.5)],
    "basement_open": [freesound(567317, 97550, "TRP", "Door buzz alarm elevator HALIFAX 93",
                                CC0, mono=True, end=1.5)],
    "ui_move": [kenney("ui", "Audio/click1.ogg", "UI Audio: click1", mono=True, gain=-10.0)],
    "ui_select": [kenney("interface", "Audio/confirmation_001.ogg",
                         "Interface Sounds: confirmation_001", mono=True, gain=-8.0)],
    "ui_back": [kenney("ui", "Audio/mouserelease1.ogg", "UI Audio: mouserelease1", mono=True,
                       gain=-8.0)],
    # --- Фон. Петли снаружи — по минуте: дольше в игре не стоят на месте.
    "city": [freesound(361088, 1648170, "klankbeeld", "city night hum", BY4, start=10.0,
                       end=72.0, loop=2.0, level="ambience", trim=False)],
    "rain": [freesound(217236, 4054839, "roofusj", "steady rain in the city", CC0, start=5.0,
                       end=67.0, loop=2.0, level="ambience", trim=False)],
    "rain_window": [freesound(346642, 5121236, "InspectorJ", "Rain on Windows, Interior", BY4,
                              loop=2.0, level="ambience", trim=False)],
    "wind": [freesound(454072, 612689, "kyles", "rushing air, distant skyline", CC0, start=5.0,
                       end=67.0, loop=2.0, level="ambience", trim=False)],
    "thunder_near": [freesound(840628, 16682330, "loganzsound", "close-up thunder strike", CC0,
                               end=9.0, fade_out=2.5, level="jingle", gain=2.0)],
    "thunder_far": [freesound(855569, 18648074, "Shuhmi", "distant dry thunderclap", BY4,
                              fade_out=1.0, level="jingle", gain=-2.0)],
    "room_tone": [freesound(241659, 1006701, "addiofbaddi", "hotel corridor", CC0, start=5.0,
                            end=65.0, loop=2.0, level="ambience", gain=-4.0, trim=False)],
    "shaft_hum": [freesound(144046, 430339, "gchase", "low hum control room", CC0, mono=True,
                            start=5.0, end=45.0, loop=2.0, level="loop", trim=False)],
    "neon_buzz": [freesound(553075, 9250976, "Nox_Sound", "bulb buzz loop", CC0, mono=True,
                            loop=0.5, level="loop", gain=-6.0, trim=False)],
}

# Что звучит петлёй: сшивка нужна им, а форматом — OGG.
LONG = {"theme", "alarm_theme", "menu_theme", "game_over_theme", "city", "rain",
        "rain_window", "wind", "room_tone", "shaft_hum", "elevator_hum", "escalator_hum",
        "car_away", "helicopter", "helicopter_pass", "garage_gate", "thunder_near", "thunder_far", "neon_buzz", "building_bonus", "game_over"}


def _download(url: str) -> bytes:
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / urllib.parse.quote(url, safe="")
    if cached.exists():
        return cached.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": "elaction-build-audio"})
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
    cached.write_bytes(data)
    return data


def _read(source: Source) -> tuple[np.ndarray, int]:
    data = _download(source.url)
    if source.member:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            data = archive.read(source.member)
    signal, rate = sf.read(io.BytesIO(data), always_2d=True, dtype="float64")
    return signal, rate


def _seconds(value: float, length: int, rate: int) -> int:
    frames = int(round(value * rate))
    return max(0, length + frames) if value < 0 else min(length, frames)


def _rms_db(signal: np.ndarray) -> float:
    # Громкость звучащей части: тишина в хвосте занизила бы среднее.
    mono = signal.mean(axis=1)
    envelope = np.abs(mono)
    loud = mono[envelope > envelope.max() * 0.05] if envelope.max() > 0 else mono
    return 20.0 * np.log10(np.sqrt(np.mean(loud * loud)) + 1e-12)


def _shape(source: Source, signal: np.ndarray, rate: int) -> np.ndarray:
    length = len(signal)
    start = _seconds(source.start, length, rate)
    end = length if source.end is None else _seconds(source.end, length, rate)
    tail = int(source.loop * rate)
    # Петле нужен запас после конца: он сшивается с началом.
    signal = signal[start : min(length, end + tail)].copy()
    if source.mono:
        signal = signal.mean(axis=1, keepdims=True)

    if source.trim:
        envelope = np.abs(signal).max(axis=1)
        above = np.nonzero(envelope > envelope.max() * 0.02)[0]
        if len(above):
            signal = signal[max(0, above[0] - int(0.004 * rate)) :]

    if tail > 0:
        body = len(signal) - tail
        head = np.linspace(0.0, 1.0, tail)[:, None]
        # Равная мощность: линейная сшивка проседает посередине на три децибела.
        signal[:tail] = signal[:tail] * np.sqrt(head) + signal[body:] * np.sqrt(1.0 - head)
        signal = signal[:body]

    if source.fade_in > 0:
        frames = min(len(signal), int(source.fade_in * rate))
        signal[:frames] *= np.linspace(0.0, 1.0, frames)[:, None]
    if source.fade_out > 0:
        frames = min(len(signal), int(source.fade_out * rate))
        signal[-frames:] *= np.linspace(1.0, 0.0, frames)[:, None]

    if source.level == "peak":
        target = PEAK - 20.0 * np.log10(np.abs(signal).max() + 1e-12)
    else:
        rms = {"music": MUSIC_RMS, "jingle": JINGLE_RMS, "loop": LOOP_RMS,
               "ambience": AMBIENCE_RMS}[source.level]
        target = rms - _rms_db(signal)
    signal *= 10.0 ** ((target + source.gain) / 20.0)
    # Пик после выравнивания по громкости может уйти выше нуля — прижимаем.
    peak = np.abs(signal).max()
    ceiling = 10.0 ** (PEAK / 20.0)
    if peak > ceiling:
        signal *= ceiling / peak
    return signal


def _write_ogg(target: Path, signal: np.ndarray, rate: int) -> None:
    # Кусками: libsndfile 1.2 на Windows падает переполнением стека, если
    # отдать ему трек в три минуты одним вызовом.
    block = 16384
    with sf.SoundFile(target, "w", rate, signal.shape[1], format="OGG", subtype="VORBIS",
                      compression_level=0.55) as out:
        for begin in range(0, len(signal), block):
            out.write(signal[begin : begin + block])


def _file_name(name: str, index: int, long: bool) -> str:
    suffix = ".ogg" if long else ".wav"
    return f"{name}{suffix}" if index == 0 else f"{name}.{index + 1}{suffix}"


def build(names: list[str]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    credits_path = OUT / "credits.json"
    credits = json.loads(credits_path.read_text(encoding="utf-8")) if credits_path.exists() else {}
    for name in names:
        # Прежние варианты этого имени уходят: число вариантов могло сократиться.
        removed = []
        for old in list(OUT.glob(f"{name}.*")):
            if old.suffix in (".wav", ".ogg") and old.stem.split(".")[0] == name:
                old.unlink()
                credits.pop(old.stem, None)
                removed.append(old)
        for index, source in enumerate(SOUNDS[name]):
            signal, rate = _read(source)
            shaped = _shape(source, signal, rate)
            long = name in LONG
            target = OUT / _file_name(name, index, long)
            if long:
                _write_ogg(target, shaped, rate)
            else:
                sf.write(target, shaped, rate, subtype="PCM_16")
            credits[target.stem] = {
                "title": source.title + (" (фрагмент)" if source.excerpt else ""),
                "author": source.author,
                "licence": source.licence,
                "url": source.page,
            }
            print(f"{target.name:28s} {len(shaped) / rate:6.1f} с  {source.author}")
        # Настройки импорта файла, которого больше нет (вариантов стало меньше,
        # WAV сменился на OGG), остались бы в репозитории сиротой. У переписанного
        # файла они свои и остаются — вместе с его uid.
        for old in removed:
            if not old.exists():
                old.with_name(old.name + ".import").unlink(missing_ok=True)
    ordered = dict(sorted(credits.items()))
    credits_path.write_bytes((json.dumps(ordered, ensure_ascii=False, indent=1) + "\n").encode())


def credits_table() -> str:
    rows = ["| Имя | Звук | Автор | Лицензия | Источник |", "|---|---|---|---|---|"]
    for name, sources in SOUNDS.items():
        for index, source in enumerate(sources):
            stem = _file_name(name, index, name in LONG).rsplit(".", 1)[0]
            host = urllib.parse.urlparse(source.page).netloc.removeprefix("www.")
            title = source.title + (" (фрагмент)" if source.excerpt else "")
            rows.append(f"| `{stem}` | {title} | {source.author} | {source.licence} "
                        f"| [{host}]({source.page}) |")
    return "\n".join(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("names", nargs="*", help="какие звуки собрать; без имён — все")
    parser.add_argument("--list", action="store_true", help="перечислить звуки")
    parser.add_argument("--credits", action="store_true", help="таблица для CREDITS.md")
    args = parser.parse_args()
    if args.list:
        for name, sources in SOUNDS.items():
            print(f"{name:18s} {len(sources)}")
        return
    if args.credits:
        print(credits_table())
        return
    unknown = [name for name in args.names if name not in SOUNDS]
    if unknown:
        sys.exit(f"нет таких звуков: {', '.join(unknown)}")
    build(args.names or list(SOUNDS))


if __name__ == "__main__":
    main()
