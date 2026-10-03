# ADR-0031 · M20: scene detail — roof, elevator, floors

- **Status:** accepted; the neon behind the roof from decision 2 is dropped — the sign
  moved to the facade corner, roof equipment became models ([ADR-0033](0033-dressing-from-packs.md),
  decisions 2 and 8); the sedan from decision 4 is replaced by a car from the Cars Pack
  ([ADR-0032](0032-actor-models.md), decision 7)
- **Date:** 2026-09-23

## Context

M19 frames and the user's remarks: the roof "looks shabby", the elevator "is not
great either", there is little detail in the scene — while the frame takes 2.3 ms
of 16.6 (ADR-0029, measurement). The roof is a dark slab, blank steps of the
slopes and a bare cube of the machine room. The shaft is a blue rectangle, the
cab is a thin frame on posts, with no walls, light or panel. City windows are
large blobs.

The user's decision — split the rest of the pivot into three milestones:

- **M20 — scene detail** (this ADR);
- **M21 — new models of Otto and agents** (Quaternius Ultimate Modular Men, CC0;
  knees and elbows in poses, the pack's proportions) — its own ADR at the start
  of the milestone;
- **M22 — grading and quality** — [ADR-0030](0030-grading-and-quality.md); tone,
  graphics quality and the city blur are already in the code, tuned against
  frames on the detailed scene.

## Decisions

### 1. Elevator — modern, as in the reference

The user's decision. The cab is open at the front — the player sees who is
inside, as in the original — but it has back and side walls, a ceiling with a
light fixture, a handrail and a control panel. In the shaft there are guide
rails, ropes above the cab and a counterweight that moves opposite to it. On
every floor at the shaft there is a portal: a steel frame, a threshold and open
doors at the sides, with the floor indicator board above (since M19).

All of this without bodies and without light sources: the cab light is emission,
and the cab bodies stay the same ones that carry and crush (ADR-0025).

### 2. Roof — equipment, parapet, antenna, neon

The user's decision — all four:

- **Equipment:** a water tank on supports, air-conditioning units, ventilation
  pipes, cable trays, a ladder up to the machine room.
- **Parapet and facade:** a parapet with flashing along the roof edges, a cornice;
  slopes with roofing sheet ribs instead of blank boxes.
- **Antenna:** a mast above the machine room with a blinking red light —
  emission, blinking in code.
- **Advertising neon:** a large sign on a frame behind the roof. The only thing
  here with a light source: a colored glow onto the roof.

All behind the play plane and without bodies: Otto walks on the deck as before
(ADR-0029, decision 4). The layout follows the building plan and seed, with a
check that items do not overlap the machine room or go beyond the roof walls.

### 3. Floors and doors — more detail

The ceiling gets panels and linear light fixtures, doors get casings and handles,
the floor gets a tile seam along the corridor. All geometry, without bodies and
without new light sources.

### 3a. Sparks and blood

The user's request. A bullet that hits a lamp knocks out sparks — streaks
stretched along the velocity in a fan downward and a flash for a tenth of a
second; a bullet that hits an agent or Otto — blood splashes along its path.
Particles are in the play plane: in the first frames sparks flying up and inward
hid in the slab and behind the wall. A picture, not a rule: combat does not
change. Blood can be turned off in the settings, as is customary in games; on by
default.

### 4. Exit floor — a garage, the car — detailed

The user's decision: the car against a background of doors looks absurd. In the
original it does not stand among doors either — it is in the basement, on floor
zero, where there are no doors at all (`table_280E`, mask 00; ADR-0028). Our exit
floor becomes such a garage: no doors and no dressing, with parking markings on
the floor and concrete instead of an office wall. Lamps stay: darkness plays on
it as on the others. There are no documents on it — a floor without doors never
has them (ADR-0028, decision 3).

The car is a sedan with a body, windows, wheels, headlights and brake lights
(emission), not a box.

### 5. Round palette — visible to the eye

The user's question: in all frames the level is one color. There are four
palettes (teal, green, purple, yellow — ADR-0017), but since M19 they entered the
walls at 18%, and frames were taken in the first round. The back wall takes the
floor tone more strongly, the shaft takes its own palette tone; rounds 1–4 are
shot side by side and differ without captions. Readability holds: game signs
glow with emission over the tone.

### 6. City — windows in a grid

Windows are smaller and denser, with dark floor mullions: a building reads as a
facade with a grid of windows, not a scatter of blobs.

## How we verify

- Elevator and roof details without bodies; no more than two light sources were
  added (roof neon); the frame budget is recorded.
- Roof layout on any seed: inside the walls, not on the machine room.
- Milestone frames: the roof in three weathers, the cab in the shaft and on a
  floor, a floor close up; comparison with the reference and with the original.
