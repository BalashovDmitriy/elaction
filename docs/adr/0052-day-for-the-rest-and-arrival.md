# ADR-0052 · M24k: time of day for the rest, a cinematic start, gaps in the sound

- **Status:** accepted
- **Date:** 2026-10-01
- **Extends:** [ADR-0051](0051-time-of-day.md) (time of day),
  [ADR-0038](0038-building-start-and-end.md) (helicopter and exit),
  [ADR-0049](0049-own-helicopter.md) (our own helicopter model),
  [ADR-0036](0036-sound-from-libraries.md) (sound from libraries),
  [ADR-0047](0047-room-behind-the-door.md) (the room behind the door)

## Context

In M24j the city, the sky, the building air and the darkness rule got time of day.
Everything else stayed at night: the street at the exit with lights and shop windows,
the window of the room behind a door with the night city, the building sign, music and
outdoor ambience. The building intro — the helicopter flies in, lowers the rope, Otto
slides down — is short and without direction: the helicopter has no door, it is drawn
pushed back, the rope simply extends from the winch.

The user asked for a cinematic start (2026-10-01): the helicopter approaches, the door
opens, Otto climbs out and descends on the rope, the helicopter flies away, the door
closes, the rope is pulled in. And separately — "some sounds seem to be missing there,
research this. The gaps will need to be closed".

**Check against the original.** In the 1983 arcade Otto does not fly in: he slides down
a rope from the neighboring roof onto the building's roof, without a helicopter, there
is no music on this, there is a short start motif. The helicopter since M24b is the
remake's decision (ADR-0038, decision 1), and the intro direction is its continuation.
The arcade has no time of day (ADR-0051). In the arcade's sound: footsteps, shots, the
elevator, doors, the lamp, death, the alarm siren; there are no ricochets or agent
footsteps — the remake's reference is not the ROM but "what is seen is heard"
(ADR-0036).

**Sound audit** (2026-10-01): we went through all the places where something visible
happens and checked them against `Sounds` calls. Found without sound: a bullet into a
wall, floor and metal; agent footsteps; Otto's jump and landing; arrival off the rope;
footsteps on metal; bodies falling and crushing; an agent's shot does not differ from
Otto's; entering the takedown and last-death slowdown; the cab starting and stopping;
street traffic, horns, the turn signal, opening the door of Otto's car; the siren at
the moment of alarm; the crackle of blinking neon; the ticking of the counting bonus; a
new high score; Otto returning after death; pause. The outdoor ambience is a single
night one at any time of day, and the sign neon hums in the day too.

## Decisions

Questions asked of the user on 2026-10-01, in two blocks and with a listening page.

1. **Music by time of day.** Night — the previous four noir-jazz themes; morning —
   Shades of Spring and Walking Along, day — George Street Shuffle and Opportunity
   Walks, evening — Apero Hour and Backbay Lounge (Kevin MacLeod, CC-BY 4.0), the track
   by draw on the building seed. Chosen by the user by ear. The alarm theme is one for
   any time of day: the siren is recognized immediately.
2. **Traffic at the exit by time of day:** the density draw stays, but the time shifts
   its shares — in the day the street is densest, in the morning and evening normal, at
   night more often free.
3. **The street at the exit.** The buildings across the road at all times of day are
   the baked M24j pack facade, like the city in the backdrop (the user's request: the
   night one too, "everything in one style"). In the morning, day and evening they are
   lit by the building's sun, at night by lit windows, neon and the real light of a
   street lamp; the street is on the sun layer
   ([`Outdoors`](../../src/systems/lighting/outdoors.gd)). The street lamp, the shop
   neon and the bracket sign are lit by the time-of-day light strength
   (`TimeOfDay.street_lights`): in the day in clear weather they are off, in the
   morning and evening they are on. Traffic headlights in the day are on only in bad
   weather.
4. **The building sign:** in the morning and day the neon is off — the tubes are visible
   in daylight, do not hum and do not blink; in the evening and at night it is lit, as
   before.
5. **The room behind the door:** in the morning and day the window shows a bright sky
   and buildings, the ceiling light and the nightstand lamp are off, sun falls from the
   window — in bad weather diffuse cold light. In the evening and at night — as before,
   in the evening a sunset outside the window.
6. **A cinematic start.** The helicopter's sliding door is a separate part of the
   model: while hovering it slides back with a clang, the cabin lights up in the
   opening, on leaving it slides shut again. The coil of rope is thrown out — it unwinds
   to the roof, swaying in the rotor downwash; on leaving the winch reels it into the
   cabin, then the door closes. Otto looks out of the opening, sits on the sill, grabs
   the rope, slips off and quickly slides down hand over hand, braking at the roof —
   and lands in a crouch. The camera — a push-in without changing the angle, as with
   takedowns: closer at the door, follows Otto down the rope, pulls back to the game
   frame. In the first building of a game the intro is full, 10–12 s; after that short,
   about 6 s: the helicopter is already hovering with the door open. Skipping is as
   before, by jump, shot or pause. Behind the glazing — a pilot, who nods on leaving.
   Leaving: nose down, bank, up and sideways accelerating past the edge of the frame;
   the rotor downwash drives dust across the roof; it does not blow away the rain.
7. **Gaps in the sound are closed in this milestone.** Each new sound is chosen by the
   user by ear from freesound and Kenney candidates (CC0 and CC-BY), as in M23. Agent
   footsteps are the same recordings as Otto's, at the agent's position and quieter;
   the agent's shot is its own recording, positional. The world slowdown lowers the
   pitch of world sounds. The cab chime does not come back — the user removed it in
   M21.
8. **Outdoor ambience — its own for each time of day:** morning — birds and occasional
   cars, day — a dense city hum, evening — the city quieter; night — as before. In the
   day the neon does not hum.

## Consequences

- The building is still one for all times of day: time changes look, light and sound,
  while layout, combat and the darkness mechanic — only at night, as in ADR-0051.
- New Otto code poses — looking out of the opening and sitting on the sill — are in the
  [`FigurePoses`](../../src/systems/assets/figure_poses.gd) table, like crouch and rope.
- The helicopter model is rebuilt by `tools/build_helicopter.py`: the door and pilot are
  separate nodes, the glazing is transparent.
- Sounds grow by a couple of dozen names; all pass the names, variants and authors test,
  as in M23.
