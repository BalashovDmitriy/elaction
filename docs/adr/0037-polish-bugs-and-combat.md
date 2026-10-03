# ADR-0037 · M24a: bugs, rain, fast bullets, falling by height

- **Status:** accepted
- **Date:** 2026-09-25
- **Extends:** [ADR-0004](0004-elevator-mechanics.md), items 5 and 6;
  [ADR-0027](0027-rom-combat.md), bullet speeds and dodging;
  [ADR-0028](0028-building-by-the-map.md), decision 3 — the number of red doors
- **Supersedes:** the agent corpse time from [ADR-0011](0011-asset-pipeline.md), item 12

## Context

After M23 the user played several games and sent fifteen remarks. They are split
into three milestones: M24a — bugs, look and combat; M24b — the start and end of
a building: how Otto gets onto the roof, the garage, getting into the car; M24c —
smooth animation and key rebinding.

The M24a analysis found the causes in real frames and in the code:

- **The cab gets stuck with Otto.** Otto becomes a passenger as soon as his body
  enters the opening by 6 cm, although the cab is still a couple of meters below
  the floor. An occupied cab obeys only "up/down" and stands still without them;
  when not level with the floor Otto cannot step out. Both stand forever. The same
  with a cab from above and with a two-floor pair.
- **The top and bottom of the shaft flicker:** buffers at the shaft ends lie in
  one plane with the guide rails, at the top also with the machine room facade.
  It is visible only while the camera moves; the M22 flicker capture shot a still
  frame.
- **Rain through the roof.** A drop dies by a timer, not on the roof; its lifetime
  is rounded to particle ticks (30 per second), and half the drops fly an extra
  meter — under the roof slab, onto floor 30. Some drops stand in front of the
  slab.
- **The background redraws in stripes.** The city camera is tilted by 10°, like
  the game camera, but it has perspective: verticals converge, window edges go in
  steps, and the city view is drawn without antialiasing and stretched twofold.
  While moving, the steps crawl along the rows of windows. The blur boundary also
  cuts through the near row.
- **Bullets** fly exactly at ROM speed: a frame in 2.6 s.
- **Corpses** disappear after half a second.
- **There are always five documents in the first building:** the number grows
  with skill per the ROM.
- **The fall rule is unclear:** death only at the bottom of a shaft, but onto a
  cab roof — even from ten floors.
- **There is no controls help on pause:** the screen exists, but only from the
  main menu.
- **The HUD has no building number.**

## Decisions

### 1. One boards a cab only when it can be entered

Otto becomes a passenger if the cab stands level with his floor or he already
stands on its floor. A cab approaching a floor arrives, pauses, and Otto enters.
One who steps into the opening while the cab is lower falls onto its roof or
down — per item 7. A test on any building: Otto at a shaft with a cab coming to
his floor from above or below never freezes together with it.

### 2. A shaft without coinciding faces

Buffers sit between the guide rails, the machine room is a few centimeters deeper.
A test on any building: shaft parts with different materials have no faces in one
plane. The flicker capture moves the camera by fractions of a millimeter between
frames — otherwise coinciding faces are not visible.

### 3. Rain anew

The user's decision: "drops naturally hit the roof, and it is visible".

- Drops die on the roof geometry — particle collision, not a timer: slab, steps,
  parapet, machine room, equipment.
- Splashes where a drop hit; ripples on puddles; a wet roof — darker and
  smoother, with reflections on levels with SSR; dripping from the parapet.
- There is no rain in front of floors: the building is a cutaway, and rain in
  front of a floor would read as rain in a room.
- In the city — layers at different depths: large near streaks, small far ones
  in the fog, a curtain between rows of buildings.
- Budget: `light_bench --whole` before and after.

**Addition: rain as light.** Streaks of their own color read as a gray grid over
the whole frame. The user compared frames of three variants and chose "B": a drop
is visible not by its own color but by light.

- A drop is lit by the scene lamps, brightest against the light, and the light
  falls off with distance more steeply than the lamp's own: drops near a lamp
  glow, not across the whole roof. The light of one lamp in a drop is capped —
  up close it does not turn white.
- A drop carries a blurred, shifted copy of what is behind it — refraction: in
  front of windows and neon the rain sparkles, in front of the dark sky it
  vanishes. Drops have different width, length and brightness, a tenth are wide
  and soft, out of focus; two waves of gusts run through the rain.
- Fog does not apply to drops: adding fog brightened the city twofold. Neither
  does ambient light: in a lightning flash the rain does not glow white.
- Above the roof — a thin haze of volumetric fog, denser at the deck, the lamp
  cone is visible in it. Only where there is volumetric fog — from the medium
  level.
- The lamp above the roof and the neon have a halo broken into falling streaks:
  the background behind the roof is the city canvas, and the building fog does
  not apply to it. On any level.
- Curtains in the city — also as light: visible only where it is bright behind
  them.

### 4. The background is smooth while moving

The city camera looks straight, and the view from above uses a lens shift, not a
tilt: verticals stay vertical. The city view is drawn with antialiasing per the
quality level. The blur starts behind the near row of buildings.

### 5. Bullets three times faster — for both sides

The user's decision. ROM speeds are multiplied by three: Otto's is ~27 m/s, a frame
in 0.9 s. So as not to break what the game relied on:

- **An agent dodges in the same time as in the ROM:** the distance at which he
  notices a bullet grows with the bullet speed (`DODGE_REACH` × multiplier).
- **An agent's bullet is visible in advance — by a wind-up and an aiming beam**
  (the user's decision). The wind-up time is from the ROM, it grows with anger.
  While the agent winds up, he raises the pistol, and a thin red beam goes from
  the barrel at the height of the coming shot: high — jump or crouch, low — jump.
  In shadow the beam is the only sign.
- **The wind-up is no shorter than 0.25 s** (an addition after a bot run): in the
  ROM at anger 10 and above there is no wind-up, and in a long building where
  anger has time to grow, a triple-speed bullet without a beam became unavoidable
  — the bot died on it, and a human would have even less chance. The ROM table is
  untouched; the minimum lives in the agent brain.
- **Look:** a thin long tracer, a short bright flash with light, smoke at the
  barrel, sparks and a mark on the wall and door.
- A bullet moves less than a wall's thickness per physics frame — it cannot slip
  through a wall.

### 6. Corpses lie until the end of the building

The user's decision. A killed agent lies where he fell: bullets fly through him,
physics and pose go to sleep as soon as the body has settled. One killed in a cab
rides with it, one who fell into a shaft lies at the bottom.

### 7. Whoever falls more than a floor dies

The user's decision. One rule for the floor, the cab roof and the shaft bottom:
jumping down one floor or onto a cab one floor below is allowed, from two floors
and deeper — death. The old "the shaft bottom kills, a cab roof saves from any
height" goes away. There is no hint about the rule in the game — the user's
decision, as in item 9.

### 8. 5–10 documents by draw

The user's decision. The number is drawn by the building seed from the first
building. Placement follows the ROM table for that number, in bands, as in the
arcade: the skill column whose sum is that number. Everything else that grows
with skill — anger, release, speeds — grows as before.

### 9. Help and HUD

The controls screen also opens from pause. It shows only keys: hints about how
the game works — "up and down in place", the fall rule, the aiming beam — are
removed. The user's decision: "other games don't have this, let the player figure
it out along the way". The HUD shows the round number large, in the center.

## Not in the milestone

- How Otto gets onto the roof, a garage on the bottom floor, exit via the car — M24b.
- Smooth animation, landing without "knees", key rebinding — M24c.

## Consequences

- The combat test bot learns to see the aiming beam: the bullet is faster than
  its old reaction. The death threshold of the combat test may need revision —
  per the run.
- `ShaftHazards.is_deadly_fall` changes meaning: fall height versus a floor.
- Building map tests check the document count against the draw, not against
  skill.
