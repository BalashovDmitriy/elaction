# ADR-0051 · M24j: time of day

- **Status:** accepted
- **Date:** 2026-10-01
- **Extends:** [ADR-0029](0029-city-weather-dressing.md) (weather by seed),
  [ADR-0030](0030-grading-and-quality.md) (noir grading),
  [ADR-0007](0007-lamps-and-darkness.md) and [ADR-0023](0023-light-and-readability.md)
  (darkness), [ADR-0035](0035-menu.md) (menu)

## Context

The user's request (2026-09-30): add morning, day and evening to the night, and snow
to clear weather and rain. Everything in the frame is built for night: the city
behind the building is drawn with unlit materials in night tones, the sky is one dark
color, grading is night noir, the darkness rule relies on it being dark outside.

**Check against the original.** In the 1983 arcade there is black emptiness around
the building in all four ROM palettes (`set_level_palette_26ca`, color 0 —
`#000000`); from building to building only the four trim colors cycle. The game does
not name a time of day, there is no weather. None of the ports found (NES, Game Boy,
ZX, CPC, C64, MSX) know day or weather. Elevator Action Returns (1994) has a night
high-rise ("Colors of Night") and a twilight city. So night and evening rest on the
series, while morning and day, rain and snow are an extension of the remake; the
closest period reference for snow is the winter section of Spy Hunter (1983).

## Decisions

Questions asked of the user on 2026-10-01.

1. **The milestone is split.** M24j — a new city and sky for all four times of day
   together with the time mechanics (decisions 10–13); M24k — time of day for the
   rest: the exit street, the room window, the helicopter, music and ambience; M24l —
   snow; M24m — the residential complex.
2. **Four weathers, fog stays:** clear, fog, rain and (from M24k) snow. Together with
   four times of day — 16 combinations, 12 in M24j.
3. **Time of day — its own draw by the building seed** with its own salt, independent
   of weather and of the round palette. Weather assignment by seed does not change.
   Night comes up more often: night 40 %, morning, day and evening 20 % each.
4. **Time in the building is frozen:** it is drawn for the whole building, from the
   helicopter to the car.
5. **Darkness — only at night.** In the morning, day and evening there are no dark
   floors 11–15, a shot-out lamp falls but does not darken the zone, and agents see
   Otto on the whole floor. At night the rule of ADR-0007 and ADR-0023 is as before.
   This diverges from the ROM, where dark floors exist in every building; the darkness
   mechanic remains in 40 % of buildings.
6. **Lights — as in real life.** In the day street lamps, street neon, rooftop lights
   and the street glow are off, the building sign glows faintly, the city windows are
   glass reflecting the sky, only a few are lit. In the morning and evening lights are
   partly on. Car headlights in the day are on only in rain and fog.
7. **Thunderstorms — only in the evening and at night.** In the morning and day rain
   comes without lightning.
8. **Music — its own per time of day:** in addition to the night noir jazz — a free
   track of the same style for morning, day and evening. Ambience — its own per
   combination: in the day the street is noisier, in the morning quieter.
9. **The menu — always night,** weather by draw, as before: the menu is the face of
   the game with the neon title sign.

The questions of the second block were asked on 2026-10-01, after the first daytime
frames: the M19 city cannot be saved by daylight. At night it held up through
darkness — a silhouette and a scatter of lights — while in the day it became visible
that these are unlit boxes with a painted window grid. The user: "the background will
need to be completely redone depending on the time of day".

10. **The city — from free pack models** (Kenney City Kit, Quaternius, CC0) with real
    materials: the sun gives volume and shadows, at night windows are lit. Like the
    dressing in M21b ([ADR-0033](0033-dressing-from-packs.md)).
11. **The sky — Poly Haven HDRI panoramas (CC0)** for each time of day and weather;
    they also light the city — shadow color, reflections in glass. The user picks the
    variants from pictures.
12. **One city for all times of day,** night is its state: windows and neon are lit,
    the sky is dark. The night look changes; the goal is no worse than before.
13. **The temporary day look of the old city** (`city_sky.gdshader`, daytime numbers
    in the facade and window shaders) is only a bridge to the new city and goes away
    together with the old one.

## How it works

- `TimeOfDay` is the building's time of day, as `Weather` is the weather: a draw by
  seed and a look table for each time — the sky (zenith and horizon), the sun
  (direction, color, strength), the building air and its grading curve, the tone of
  the city facades, the share of lit windows, the strength of lights.
- The sun shines only outside: on the city, the roof and the street. The building is
  shown as a cutaway, and the light inside is lamps and the building's ambient light;
  in the day the ambient light is brighter, so a shot-out lamp does not darken the zone
  visually either.
- `BuildingRules` carries the time of day, the darkness rule asks it.

- **City (decision 10).** Whole pack buildings are 18–45 thousand triangles, and the
  city is hundreds of buildings, so the facade is baked: `tools/build_city.py`
  assembles in Blender, from the Downtown modules, three rows — cornice, floor, ground
  floor — for each of six styles (brick, double windows, recess, glass, office, stone)
  and shoots them with an ortho camera in four passes: color, normal, occlusion with
  roughness and metalness, window mask. The game applies the atlas to the building
  boxes of the old layout ([CityPlan]) with the shader `city_building.gdshader`: floors
  repeat, the light is real, windows are smooth glass, at night a share of windows is
  lit by the mask and a window hash. The pack does not go into the repository, like the
  sound sources: it is in `.cache/downtown/`.
- **Sky (decision 11).** The user's choice (2026-10-01): morning —
  `syferfontein_0d_clear_puresky`, day — `qwantani_mid_morning_puresky`, evening —
  `belfast_sunset_puresky`, night — `qwantani_moonrise_puresky`, fog in the morning and
  day — `kloofendal_28d_misty_puresky`, rain in the morning and day —
  `mud_road_puresky`, bad weather in the evening and at night —
  `kloppenheim_01_puresky`. In 1k: the city behind them is blurred.
  `tools/build_sky.py` finds the sun on each one, and [CitySky] rotates the panorama
  with its shader so that it stands where the city light comes from — the sun, and at
  night the moon. The sky is also the shadow light and the reflections in glass.

## Consequences

- The city, sky, exit street, the room window behind a door, the sign and the
  helicopter get a daytime look; the night look does not change.
- Tests check the draw and the share of night, darkness only at night, lights by time,
  thunderstorms only in the evening and at night, and that each of the twelve
  combinations builds.
- Milestone frames — for all twelve combinations.
