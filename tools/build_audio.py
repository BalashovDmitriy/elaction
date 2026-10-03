#!/usr/bin/env python3
"""Game sound from free libraries (ADR-0036).

Music — Kevin MacLeod (incompetech.com, CC-BY 4.0), jingles and menu sounds —
Kenney packs (CC0), effects and ambience — freesound.org (CC0 and CC-BY). Each file
was chosen by the user by ear; here is where it was taken from and how it is fitted to the game:
trimming, a loop with a crossfade, loudness, mono for positional sounds.

    python tools/build_audio.py              # download and build everything
    python tools/build_audio.py shot theme   # only these names
    python tools/build_audio.py --list

Writes to `assets/audio/`: short effects as WAV, long ones as OGG. Several
variants of one name are `name.ogg`, `name.2.ogg`, …: the game picks music and ambience
by a draw per building, effects per sound (`Sounds`). Authors are in
`assets/audio/credits.json`; the table for `CREDITS.md` is printed by `--credits`.

Downloads go to `.cache/audio/` next to the project: freesound answers 429
if asked often.
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

# Loudness. Music and ambience — by the RMS loudness of the sounding part,
# effects — by peak, and then a balance correction: a step must not compete with
# a shot.
MUSIC_RMS = -18.0
JINGLE_RMS = -17.0
LOOP_RMS = -24.0
AMBIENCE_RMS = -26.0
PEAK = -1.0


@dataclass
class Source:
    """Where the sound was taken from and how to fit it."""

    title: str
    author: str
    licence: str
    page: str
    url: str = ""
    # File inside the Kenney archive.
    member: str = ""
    # Segment, s. Negative — from the end; `end` None — to the end.
    start: float = 0.0
    end: float | None = None
    # Loop with a crossfade of this many seconds; 0 — plays once.
    loop: float = 0.0
    fade_in: float = 0.0
    fade_out: float = 0.0
    mono: bool = False
    # How to level: "music", "jingle", "loop", "ambience", "peak".
    level: str = "peak"
    gain: float = 0.0
    # Trim silence at the start: freesound recordings can have half a second before the sound.
    trim: bool = True
    excerpt: bool = False
    # How much to keep after trimming silence, s; 0 — all. That way one click is taken
    # from a recording with a series of clicks.
    length: float = 0.0
    # Cut highs above this many hertz: sound from behind a door or wall; 0 — no cut.
    muffle: float = 0.0


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
    # Whole tracks: the game gives them the loop, and a track has a start and an end anyway.
    return macleod(title, level="music", trim=False)


SOUNDS: dict[str, list[Source]] = {
    # --- Music: a track per screen, building and alarm tracks — a draw per building.
    # Theme — by building kind and time of day (ADR-0057, decision 7; ADR-0052,
    # decision 1): night — "theme", morning, day and evening — with a suffix. Hotel —
    # swing, lounge and saxophone; office — cold synth noir, elevator music
    # by day; residential building — blues and funk. From the middle of the building the next
    # track of the set plays, if there is one. Alarm — its own per kind. Tracks chosen by the user
    # by ear from the listening page (2026-10-03).
    "theme": [_track("Covert Affair"), _track("Dances and Dames"), _track("Spy Glass"), _track("Hard Boiled")],
    "theme_morning": [_track("Shades of Spring"), _track("Walking Along")],
    "theme_day": [_track("Lobby Time"), _track("George Street Shuffle"), _track("Fig Leaf Rag")],
    "theme_evening": [_track("Apero Hour"), _track("Backbay Lounge")],
    "alarm_theme": [_track("Fast Talkin"), _track("Hot Swing"), _track("Private Eye")],
    "theme_office": [_track("Spy Glass"), _track("Chill Wave"), _track("Lightless Dawn")],
    "theme_office_morning": [_track("Clean Soul")],
    "theme_office_day": [_track("Local Forecast - Elevator")],
    "theme_office_evening": [_track("Ice Flow"), _track("Chill Wave")],
    "alarm_office": [_track("Hiding Your Reality"), _track("Voltaic"), _track("Movement Proposition")],
    "theme_residential": [_track("Hard Boiled"), _track("Bass Walker")],
    "theme_residential_morning": [_track("Walking Along"), _track("Groove Grove")],
    "theme_residential_day": [_track("George Street Shuffle"), _track("Groove Grove"), _track("Rollin at 5")],
    "theme_residential_evening": [_track("Backed Vibes Clean"), _track("Bass Vibes")],
    "alarm_residential": [_track("Private Eye"), _track("Faster Does It")],
    "menu_theme": [_track("Cool Vibes")],
    "game_over_theme": [_track("Just As Soon")],
    # --- Jingles.
    "document": [kenney("jingles", "Audio/Sax jingles/jingles_SAX16.ogg", "Music Jingles: SAX16",
                        level="jingle")],
    "extra_life": [freesound(578401, 10522382, "nomiqbomi", "Inquisitive Vibraphone 09", CC0,
                             end=2.4, fade_out=0.5, level="jingle")],
    "building_bonus": [macleod("Rollin at 5", start=-13.0, end=-7.3, fade_in=0.03,
                               fade_out=0.35, level="jingle", trim=False, excerpt=True)],
    "game_over": [macleod("Hard Boiled", start=-8.5, fade_in=0.03, fade_out=0.35,
                          level="jingle", trim=False, excerpt=True)],
    # --- Effects.
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
    # --- M24b: helicopter, rope, car, gate, basement shaft (ADR-0038).
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
    # --- M24k: gaps found by the sound audit (ADR-0052, decision 7).
    "heli_door": [freesound(269520, 2843367, "MrAuralization", "Van sliding door open", BY4,
                            mono=True, fade_out=0.3, gain=-2.0)],
    "winch": [freesound(683808, 4257513, "mpuffenbarger", "SFX Electric Actuator Jack 1", CC0,
                        mono=True, start=0.5, end=5.0, loop=0.5, level="loop", gain=-2.0,
                        trim=False)],
    "rope_drop": [freesound(1949, 1198, "nicStage", "rbhRopeRMX1", BY4, mono=True, gain=-2.0)],
    "bullet_wall": [freesound(78092, 634166, "Benboncan", "Ricochet 3_2", BY4, mono=True,
                              fade_out=0.2, gain=-4.0)],
    "bullet_metal": [freesound(423107, 3325582, "OGsoundFX",
                               "Guns & Explosions Album - Bullet Impact 14", BY4, mono=True,
                               fade_out=0.15, gain=-4.0)],
    "enemy_shot": [freesound(163456, 2263027, "LeMudCrab", "Pistol Shot", CC0, mono=True,
                             fade_out=0.15, gain=-3.0)],
    "body_fall": [freesound(447922, 9159316, "Breviceps", "Thud", CC0, mono=True, gain=-4.0)],
    "crush": [freesound(392883, 3530854, "clif_creates", "Hard Candy / Bone Crunch", CC0,
                        mono=True, fade_out=0.2, gain=-2.0)],
    "slowmo": [freesound(377829, 4067257, "newagesoup", "long wispy woosh2", BY4,
                         fade_out=0.6, gain=-6.0)],
    "jump": [freesound(494797, 4682121, "brandondelehoy", "Jacket/Cloth Rustle 9", CC0,
                       mono=True, gain=-10.0)],
    "land": [freesound(464607, 7787874, "D001447733", "Jump_End_Gravel", BY3, mono=True,
                       gain=-8.0)],
    "crouch": [freesound(494797, 4682121, "brandondelehoy", "Jacket/Cloth Rustle 9", CC0,
                         mono=True, gain=-12.0)],
    "step_metal": [freesound(816413, 17614127, "atleastrelatively", "metal footstep", CC0,
                             mono=True, gain=-9.0)],
    "respawn": [kenney("interface", "Audio/bong_001.ogg", "Interface Sounds: bong_001",
                       mono=True, gain=-6.0)],
    "elevator_start": [freesound(439435, 8080193, "maxmaxmaxmaxmaxmaxmax",
                                 "Elevator Stalling 2", CC0, mono=True, fade_out=0.3,
                                 gain=-6.0)],
    "elevator_stop": [freesound(175668, 2762119, "simpsi", "elevator_stop", BY3, mono=True,
                                end=2.6, fade_out=0.6, gain=-6.0)],
    "car_door_open": [freesound(844708, 10643461, "Geoff-Bremner-Audio", "Car Door Open 2",
                                BY4, mono=True, gain=-4.0)],
    "turn_signal": [freesound(61053, 27178, "morgantj", "turnsignal", BY4, mono=True,
                              length=0.22, fade_out=0.05, gain=-8.0)],
    "car_pass": [freesound(664770, 14565628, "koirankarva84581682", "car_4", CC0, mono=True,
                           fade_in=0.3, fade_out=0.8, gain=-2.0)],
    "horn": [freesound(705723, 15236906, "mudflea2", "Double car horn", CC0, mono=True,
                       fade_out=0.15, gain=-3.0)],
    "alarm": [freesound(678345, 14784311, "msx2plus", "fire alarm bell", CC0, end=3.2,
                        fade_out=0.8, gain=-4.0)],
    "neon_flicker": [kenney("interface", "Audio/glitch_004.ogg", "Interface Sounds: glitch_004",
                            mono=True, gain=-10.0)],
    "bonus_tick": [freesound(253546, 4157918, "xtrgamr", "SCORE COUNT", BY4, mono=True,
                             end=1.25, fade_out=0.15, gain=-8.0)],
    "record": [freesound(270333, 5123851, "LittleRobotSoundFactory", "Jingle_Win_00", BY4,
                         level="jingle")],
    "ui_move": [kenney("ui", "Audio/click1.ogg", "UI Audio: click1", mono=True, gain=-10.0)],
    "ui_select": [kenney("interface", "Audio/confirmation_001.ogg",
                         "Interface Sounds: confirmation_001", mono=True, gain=-8.0)],
    "ui_back": [kenney("ui", "Audio/mouserelease1.ogg", "UI Audio: mouserelease1", mono=True,
                       gain=-8.0)],
    # --- Ambience. Outdoor loops are a minute each: in the game one does not stand still longer.
    "city": [freesound(361088, 1648170, "klankbeeld", "city night hum", BY4, start=10.0,
                       end=72.0, loop=2.0, level="ambience", trim=False)],
    "city_morning": [freesound(261307, 3452716, "VlatkoBlazek", "Morning on my street", BY4,
                               start=10.0, end=72.0, loop=2.0, level="ambience", trim=False)],
    "city_day": [freesound(169080, 1648170, "klankbeeld", "city from pasture 03", BY4,
                           start=10.0, end=72.0, loop=2.0, level="ambience", trim=False)],
    "city_evening": [freesound(413335, 7723777, "flood-mix", "Baltimore City Ambience at Dusk",
                               CC0, start=10.0, end=72.0, loop=2.0, level="ambience",
                               trim=False)],
    "rain": [freesound(217236, 4054839, "roofusj", "steady rain in the city", CC0, start=5.0,
                       end=67.0, loop=2.0, level="ambience", trim=False)],
    "rain_window": [freesound(346642, 5121236, "InspectorJ", "Rain on Windows, Interior", BY4,
                              loop=2.0, level="ambience", trim=False)],
    "wind": [freesound(454072, 612689, "kyles", "rushing air, distant skyline", CC0, start=5.0,
                       end=67.0, loop=2.0, level="ambience", trim=False)],
    # Snow (M24l, ADR-0054): wind, steps on snow and tyres on slush — chosen
    # by the user by ear from the listening page.
    "wind_snow": [freesound(454213, 612689, "kyles", "swirling winter wind gusty grains sand",
                            CC0, start=5.0, end=67.0, loop=2.0, level="ambience", trim=False)],
    "step_snow": [freesound(615658, 10150854, "Lumamorph", "Crispy_snow_footsteps-01", CC0,
                            mono=True, start=at, length=0.42, fade_out=0.08, trim=False,
                            gain=-8.0) for at in (3.47, 4.52, 5.92, 8.01)],
    "car_pass_slush": [freesound(190997, 2580450, "Zabuhailo", "Cars_driving_slush_road", BY4,
                                 mono=True, start=20.0, end=32.0, loop=1.0, fade_in=0.3,
                                 gain=-2.0, trim=False)],
    # Residential building and office (M24m, ADR-0055, decision 8): corridor ambience, life behind
    # a flat door and a step on linoleum — chosen by the user by ear from
    # the listening page. Close-up recordings are muffled by a high cut.
    "room_tone_office": [freesound(708021, 14714083, "Soup_UnderScore",
                                   "Empty Office Space Room Tone with Aircon SFX", CC0,
                                   start=10.0, end=70.0, loop=2.0, level="ambience", gain=-4.0,
                                   trim=False)],
    "room_tone_residential": [freesound(338104, 1480854, "SpliceSound",
                                        "1st floor apartment hallway, neighbors talking", CC0,
                                        start=10.0, end=70.0, loop=2.0, level="ambience",
                                        gain=-4.0, trim=False)],
    "door_tv": [freesound(104578, 103289, "markb",
                          "car_crash_interior_ambience_w_television_next_door", BY4, mono=True,
                          start=40.0, length=12.0, muffle=900.0, fade_in=0.4, fade_out=1.0,
                          trim=False, gain=-6.0)],
    "door_dog": [freesound(773829, 1648170, "klankbeeld",
                           "dog next doors room-tone 0407 PM 240215_0660", BY4, mono=True,
                           start=2.0, length=12.0, fade_in=0.3, fade_out=1.0, trim=False,
                           gain=-6.0)],
    "door_argue": [freesound(848362, 7554526, "SieuAmThanh", "Two People Argue - Part 1", CC0,
                             mono=True, start=2.0, length=12.0, muffle=700.0, fade_in=0.4,
                             fade_out=1.0, trim=False, gain=-6.0)],
    "step_lino": [freesound(475080, 6858456, "roman_gens", "Footsteps Boots_Linoleum", BY4,
                            mono=True, start=at, length=0.42, fade_out=0.08, trim=False,
                            gain=-9.0) for at in (16.88, 18.04, 19.29, 22.39)],
    # Special-floor halls and the freight cab gate (M24o, ADR-0057, decisions 4 and
    # 6) — chosen by the user by ear from the listening page.
    "hall_pool": [freesound(495399, 10725617, "tosha73", "Public Swimming Pool Atmosphere.wav",
                            CC0, start=5.0, end=65.0, loop=2.0, level="ambience", trim=False)],
    "hall_server": [freesound(465613, 9250976, "Nox_Sound", "Object_Fan_Server_Room.wav", CC0,
                              start=2.0, end=48.0, loop=2.0, level="ambience", trim=False)],
    "hall_boiler": [freesound(164746, 2978883, "rucisko", "boiler room", CC0, start=0.5,
                              end=21.5, loop=1.5, level="ambience", trim=False)],
    "hall_laundry": [freesound(454465, 612689, "kyles",
                               "laundromat washers washing machines rattle vibrate4.flac", CC0,
                               start=10.0, end=70.0, loop=2.0, level="ambience", trim=False)],
    "hall_dining": [freesound(718019, 36188, "LG", "20231229 - Hotel restaurant breakfast 7", CC0,
                              start=3.0, end=66.0, loop=2.0, level="ambience", trim=False)],
    "hall_kitchen": [freesound(162662, 57789, "cognito perceptu", "restaurant kitchen.wav", CC0,
                               start=9.0, end=55.0, loop=2.0, level="ambience", trim=False)],
    "hall_gym": [freesound(370967, 5835751, "waweee", "gym ambience", CC0, start=2.0, end=45.0,
                           loop=2.0, level="ambience", trim=False)],
    "hall_bar": [freesound(666292, 1472937, "oliwoli", "room tone - small hotel bar", BY4,
                           start=5.0, end=65.0, loop=2.0, level="ambience", trim=False)],
    "hall_mechanical": [freesound(161224, 544580, "lolamadeus",
                                  "Hilton Basement Ambience - Plant Room.wav", CC0, start=1.0,
                                  end=39.5, loop=2.0, level="ambience", trim=False)],
    "cab_gate": [freesound(140896, 1810340, "exuberate", "Elevator_OldApartmentBuilding", CC0,
                           mono=True, start=7.2, end=9.6, fade_out=0.15, trim=False, gain=-3.0)],
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

# What plays as a loop: they need the crossfade, and OGG as the format.
LONG = {"winch", "car_pass", "car_pass_slush", "wind_snow", "alarm", "city_morning", "city_day", "city_evening", "theme", "theme_morning", "theme_day", "theme_evening", "alarm_theme",
        "theme_office", "theme_office_morning", "theme_office_day", "theme_office_evening",
        "alarm_office", "theme_residential", "theme_residential_morning",
        "theme_residential_day", "theme_residential_evening", "alarm_residential", "menu_theme", "game_over_theme", "city", "rain",
        "rain_window", "wind", "room_tone", "room_tone_office", "room_tone_residential",
        "door_tv", "door_dog", "door_argue", "hall_pool", "hall_server", "hall_boiler",
        "hall_laundry", "hall_dining", "hall_kitchen", "hall_gym", "hall_bar",
        "hall_mechanical", "shaft_hum", "elevator_hum", "escalator_hum",
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
    # Loudness of the sounding part: silence in the tail would lower the average.
    mono = signal.mean(axis=1)
    envelope = np.abs(mono)
    loud = mono[envelope > envelope.max() * 0.05] if envelope.max() > 0 else mono
    return 20.0 * np.log10(np.sqrt(np.mean(loud * loud)) + 1e-12)


def _muffle(signal: np.ndarray, rate: int, cutoff: float) -> np.ndarray:
    """Muffled, as from behind a door: a smooth high cut above [cutoff] hertz (4th order)."""
    spectrum = np.fft.rfft(signal, axis=0)
    freqs = np.fft.rfftfreq(len(signal), 1.0 / rate)
    gain = 1.0 / (1.0 + (freqs / cutoff) ** 4)
    return np.fft.irfft(spectrum * gain[:, None], n=len(signal), axis=0)


def _shape(source: Source, signal: np.ndarray, rate: int) -> np.ndarray:
    length = len(signal)
    start = _seconds(source.start, length, rate)
    end = length if source.end is None else _seconds(source.end, length, rate)
    tail = int(source.loop * rate)
    # A loop needs headroom after the end: it is crossfaded with the start.
    signal = signal[start : min(length, end + tail)].copy()
    if source.mono:
        signal = signal.mean(axis=1, keepdims=True)

    if source.trim:
        envelope = np.abs(signal).max(axis=1)
        above = np.nonzero(envelope > envelope.max() * 0.02)[0]
        if len(above):
            signal = signal[max(0, above[0] - int(0.004 * rate)) :]
    if source.length > 0:
        signal = signal[: int(source.length * rate)]
    if source.muffle > 0:
        signal = _muffle(signal, rate, source.muffle)

    if tail > 0:
        body = len(signal) - tail
        head = np.linspace(0.0, 1.0, tail)[:, None]
        # Equal power: a linear crossfade dips by three decibels in the middle.
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
    # The peak after loudness levelling can go above zero — clamp it.
    peak = np.abs(signal).max()
    ceiling = 10.0 ** (PEAK / 20.0)
    if peak > ceiling:
        signal *= ceiling / peak
    return signal


def _write_ogg(target: Path, signal: np.ndarray, rate: int) -> None:
    # In chunks: libsndfile 1.2 on Windows crashes with a stack overflow if
    # given a three-minute track in one call.
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
        # Previous variants of this name go away: the number of variants may have shrunk.
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
                "title": source.title + (" (excerpt)" if source.excerpt else ""),
                "author": source.author,
                "licence": source.licence,
                "url": source.page,
            }
            print(f"{target.name:28s} {len(shaped) / rate:6.1f} s  {source.author}")
        # Import settings of a file that no longer exists (fewer variants,
        # WAV changed to OGG) would remain in the repository as orphans. A rewritten
        # file keeps its own — together with its uid.
        for old in removed:
            if not old.exists():
                old.with_name(old.name + ".import").unlink(missing_ok=True)
    ordered = dict(sorted(credits.items()))
    credits_path.write_bytes((json.dumps(ordered, ensure_ascii=False, indent=1) + "\n").encode())


def credits_table() -> str:
    rows = ["| Name | Sound | Author | Licence | Source |", "|---|---|---|---|---|"]
    for name, sources in SOUNDS.items():
        for index, source in enumerate(sources):
            stem = _file_name(name, index, name in LONG).rsplit(".", 1)[0]
            host = urllib.parse.urlparse(source.page).netloc.removeprefix("www.")
            title = source.title + (" (excerpt)" if source.excerpt else "")
            rows.append(f"| `{stem}` | {title} | {source.author} | {source.licence} "
                        f"| [{host}]({source.page}) |")
    return "\n".join(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("names", nargs="*", help="which sounds to build; all if no names")
    parser.add_argument("--list", action="store_true", help="list the sounds")
    parser.add_argument("--credits", action="store_true", help="table for CREDITS.md")
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
        sys.exit(f"no such sounds: {', '.join(unknown)}")
    build(args.names or list(SOUNDS))


if __name__ == "__main__":
    main()
