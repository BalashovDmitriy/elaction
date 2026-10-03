# ADR-0057 · M24o: special floors, cab and music by building kind

- **Status:** accepted
- **Date:** 2026-10-03
- **Extends:** [ADR-0056](0056-building-character.md) (the character of a building kind),
  [ADR-0055](0055-residential.md) (three kinds),
  [ADR-0052](0052-day-for-the-rest-and-arrival.md) (music by time of day),
  [ADR-0028](0028-building-by-the-map.md) (the building by the ROM map)

## Context

After M24n the three building kinds differ in air, light, palette, the corridor back
wall and light fixtures. Everything else is shared: all floors are the same, one cab
and one shaft, one music. The silhouette, roof, garage and exit street are also shared,
but they go into the next milestone (decision 1).

**Check against the original** (2026-10-03).
- **The 1983 arcade.** The arcade has one building for the whole game. The map is baked
  into the ROM: door masks `table_280E`, lamps `init_building_2700`. From round to round
  only the red doors, the shaft to the basement, the layout of double elevators and the
  difficulty change. There are no special floors by purpose, but floors differ by
  structure:
  - floors 1–6 have almost no doors: one door at each edge (mask `81`);
  - floor 7 has no doors at all (mask `00`), at Elevator World this is a
    "sky lobby" with a transfer between elevators;
  - the dark floors 11–15 have no lamps at all.

  The cabs are the same, only the two-floor ones differ. Music is one melody for the
  whole game, plus the alarm melody and jingles.
- **Elevator Action Returns (1994).** This is the closest example of different
  buildings. Each of the six missions has its own location, its own finale and its own
  music, usually two melodies or more: the theme changes at the mission's turns. There
  are no special cab types, only the finish differs. The first mission is the same
  building map as the original, but it is a tenement with gangsters, that is, a
  precedent for our residential building.

**Code** (review before the milestone):
- There is no notion of a floor role: `BuildingDressing`, `WallFeatures` and
  `OpenSpace` lay out the dressing the same way on all floors of the building.
- The cab (`CarDetail`), the shaft and indicator boards (`BuildingShafts`) and the floor
  numbers (`FloorSigns`) do not depend on the building kind.
- Music is chosen by `Sounds.theme_for(time)` from the single building seed. The
  building kind takes no part in the choice.
- The cab has no doors: it is open at the front, as in the original, and Otto enters it
  from the side.

## Decisions

Questions asked of the user on 2026-10-03, in two blocks of four.

1. **The milestone is split in two.**
   - M24o: special floors, cab and shaft, music. This is what is seen and heard the
     whole game.
   - M24p: silhouette and facade, roof, garage, exit street and car by kind.
2. **Special floors follow the ROM structure, the same in all buildings of a kind.**
   Special floors occupy two bands:
   - the lower one, ROM floors 1–7, where there are few or no doors: these are public
     halls;
   - the dark one, ROM floors 11–15: these are technical floors.

   Each floor of a band is special and does not repeat its neighbor. The floor is taken
   by `Arcade.rom_floor`. The bottom floor of the building stays the garage, the roof
   the roof.

   | ROM | Hotel | Office | Residential |
   |---|---|---|---|
   | 1–2 | lobby with a reception desk | lobby with a security post and turnstiles | lobby with mailboxes and a doorman's desk |
   | 3 | restaurant | cafeteria | common room |
   | 4 | ballroom | gym | storage cages |
   | 5 | swimming pool | conference hall | gym |
   | 6 | conference hall | meeting rooms | storage cages |
   | 7 | sky lobby bar | sky lobby reception | laundry |
   | 11 | boiler room | ventilation and pumps | boiler room |
   | 12 | ventilation and pumps | server room | workshop |
   | 13 | laundry | archive | storeroom |
   | 14 | kitchen | server room | ventilation and pumps |
   | 15 | linen storeroom | warehouse | laundry |

3. **A special floor is a hall into depth.** On a special floor there is no corridor
   back wall, as with the office open space: behind the play plane a hall through the
   whole slab depth is visible.
   - Public halls have columns instead of a wall: marble in the hotel, brick piers in
     the residential building, glass in the office.
   - Technical floors have chain-link mesh on steel posts instead of a wall. The
     exception is the office server room: it is behind glass.

   The play plane, doors, lamps and layout stay per the ROM. A door on a special floor
   opens into the hall itself, as in the office: a room behind it would appear and
   disappear in the middle of the hall (code review). The leaf strip in front of the
   door is kept free.
   Corridor dressing and items on the
   back wall are not placed on a special floor: there is no wall, and the hall itself
   serves as dressing.
4. **Only the look and harmless details.** A special floor does not touch mechanics. It
   has:
   - its own ambience: the splash and echo of the pool, the hum of the server room, the
     rumble of the boiler room, the drums of the laundry, the chatter and dishes of the
     restaurant;
   - live details without bodies: steam over the boiler, ripples on the water, blinking
     server indicators, glowing bar bottles.

   At night on the ROM dark floors the whole technical floor is dark, like the office
   open space.
5. **Models from free packs, the missing ones procedurally.**
   - Furniture comes from the Kenney Furniture Kit (CC0): washing machines and dryers,
     a bar counter and stools, tables with tablecloths, a kitchen, sofas. Each model gets
     an entry in CREDITS.
   - The pool, server racks, boiler, pipes, storage cages, gym, turnstiles and stage are
     built by code from primitives, as multimeshes without shadows, like the open space
     in ADR-0056.
6. **A cab and shaft of its kind: look and a live gate.**
   - Hotel: brass and wood, warm light. Above the shaft portal — a dial indicator board
     with a needle.
   - Office: brushed stainless steel and cold light. The indicator board is digits, as
     now.
   - Residential: a freight cab of painted steel, a diamond-plate floor, a caged lamp, a
     bumper rail. The portal is painted steel, the indicator board digits are white.

   The digit color was chosen neither warm nor red: amber and red are game indicator
   lights, the door indicator board and doors with a document (ADR-0023, decision 6). So
   the hotel's digits are cream, and the row of floor lamps in the residential building
   is replaced by white digits. Floor numbers on the wall (`FloorSigns`) stay shared:
   they are a game sign.

   The freight cab has a folding accordion gate at the front. The gate is closed while
   one cannot step out of the cab, and folds to the post with a sound when the cab floor
   enters the ROM step-out window: up to 18 pixels above the floor level, @36F2. So the
   gate shows the ROM rule rather than changing it. The gate is thin and dark, so that
   Otto reads through it; this is checked by a frame.

   *Correction to the question.* The question proposed the gate "on the same timing as
   the doors now". But the cab has no doors, so the gate is tied to the cab step-out
   window.
7. **Music: kind × time of day, a theme change and an alarm of its own.**
   - Each kind has its own set, in which time of day gives a variant:
     - hotel — swing, lounge and saxophone;
     - office — cold synth-noir, elevator music in the day;
     - residential — blues and funk.
   - A "kind × time of day" pair usually has two tracks or more. In the upper half of
     the building the track from the building draw plays, and from the middle down the
     next track of the set, if there is one. This is a theme change, as in Returns.
   - Each kind has its own alarm, two or three tracks.
   - All tracks are Kevin MacLeod, CC-BY 4.0, chosen by the user by ear (table below).

## Consequences

- A floor role appears (`FloorRole`) — a function of the building kind and the ROM
  floor. A test checks it without nodes.
- Halls are built by `FloorHall`. The office `OpenSpace` skips special floors,
  and `BuildingDressing` and `WallFeatures` do not place items on the back wall on
  special floors.
- `CarDetail` and `BuildingShafts` get the building kind; `Door` gets a flag for a door
  into a hall.
- `Sounds.theme_for` gets the kind and the building half. There are more music files:
  about twenty new tracks, about 50 MB.
- The frame budget for the lower band is checked by `light_bench --whole` on all three
  kinds.

## Music chosen by ear

The tracks were first picked by genre in the catalog and built in without listening —
an error of order: the user stopped the build, and the choice was made by ear from a
listening page (2026-10-03). The first pick was rebuilt per the choice.

| Set | Hotel | Office | Residential |
|---|---|---|---|
| night | Covert Affair, Dances and Dames, Spy Glass, Hard Boiled | Spy Glass, Chill Wave, Lightless Dawn | Hard Boiled, Bass Walker |
| morning | Shades of Spring, Walking Along | Clean Soul | Walking Along, Groove Grove |
| day | Lobby Time, George Street Shuffle, Fig Leaf Rag | Local Forecast - Elevator | George Street Shuffle, Groove Grove, Rollin at 5 |
| evening | Apero Hour, Backbay Lounge | Ice Flow, Chill Wave | Backed Vibes Clean, Bass Vibes |
| alarm | Fast Talkin, Hot Swing, Private Eye | Hiding Your Reality, Voltaic, Movement Proposition | Private Eye, Faster Does It |

Office morning and day have one track each: there is no theme change from the middle of
the building there.

## Sounds chosen by ear

The second listening page, 2026-10-03; candidates were found by a freesound search by
description, the user listened and chose. A hall's ambience plays over the corridor
silence while Otto is on the hall's floor; the lobby, ballroom and conference hall,
meeting rooms, common room, storerooms, archive, warehouse and workshop have no sound of
their own.

| Slot | Recording | License |
|---|---|---|
| swimming pool | tosha73 495399, Public Swimming Pool Atmosphere | CC0 |
| server room | Nox_Sound 465613, Object_Fan_Server_Room | CC0 |
| boiler room | rucisko 164746, boiler room | CC0 |
| laundry | kyles 454465, laundromat washers rattle vibrate | CC0 |
| restaurant and cafeteria | LG 718019, Hotel restaurant breakfast 7 | CC0 |
| kitchen | cognito perceptu 162662, restaurant kitchen, from 9 s | CC0 |
| gym | waweee 370967, gym ambience | CC0 |
| bar | oliwoli 666292, room tone - small hotel bar | CC-BY 4.0 |
| ventilation and pumps | lolamadeus 161224, Hilton Basement Ambience - Plant Room | CC0 |
| cab gate | exuberate 140896, Elevator_OldApartmentBuilding, 7.2–9.6 s | CC0 |
