# ADR-0058 · M24p: the building exterior by kind

- **Status:** accepted
- **Date:** 2026-10-03
- **Extends:** [ADR-0057](0057-floors-cab-music-by-kind.md) (decision 1: M24p
  split from M24o), [ADR-0024](0024-building-geometry.md) (silhouette by threshold),
  [ADR-0033](0033-dressing-from-packs.md) (roof from pack models),
  [ADR-0038](0038-building-start-and-end.md) (garage and exit),
  [ADR-0044](0044-street-and-cab.md) (exit street)

## Context

After M24o the building kinds differ inside: light, back wall, halls, cab, music.
Outside they all have the same: silhouette, parapet, roof with equipment, garage, exit
street and a car drawn by building number.

**Check against the original.** In the 1983 arcade the facade, roof and exit are the
same in all buildings. The roof with the rope is shown once per game, at the bottom
there is always a basement garage, the car stands on the left. In Elevator Action
Returns each mission has its own location and its own finale, but there is no single
"building bottom" there. Distinguishing buildings from outside by kind was invented in
the remake, Returns is the reference in spirit.

**Code** (review before the milestone):
- **The silhouette is mechanics.** The width of floors (`slots`, `top_slots`,
  `wide_from`) sets, per the ROM, the number of doors, lamps and shafts (ADR-0028,
  decision 2), and silhouette tests guard it.
- **Free for the look:**
  - the roof parapet;
  - everything behind the play plane and above the roof;
  - the podium setback ledge: from the tower floors 10 m is visible on each side — the
    sky, the city and the roof of the wide part of the building;
  - the tower end walls;
  - the garage finish;
  - the facade at the exit street.
- **Constraints:**
  - the surroundings have exactly two light sources;
  - the helicopter flies around everything above the roof;
  - the first building of a game is the red sports car;
  - tests against face flicker in the garage and on the street.
- **There are five cars,** all from the Quaternius pack. There is no limousine, taxi or
  van.

## Decisions

Questions asked of the user on 2026-10-03, in two blocks.

1. **The silhouette — look only.** The floor layout is the same for all kinds, per the
   ROM. The kind reads outside the play plane: the crown above the roof, the parapet
   and cornice, the podium setback ledge, the tower end walls.
2. **A tall crown for each kind, its own.**
   - Hotel: a stepped art deco crown with a spire and neon edges.
   - Office: a cut glass top with an antenna mast and a beacon.
   - Residential: a wooden water tank on tall supports and a brick cornice.

   The crown stands behind the play plane. The helicopter flies around it by its own
   obstacle rule.

   *Correction after code review.* The intro frame was not re-framed: even the tallest
   frame the camera limits allow does not fit the hotel spire and the office mast. The
   crown steps, the top and the rope are visible in the frame, and the top of the spire
   and mast goes beyond the edge, as a silhouette above the city. If the crown needs to
   fit entirely, it will have to be made lower.
3. **The podium setback ledge and tower end walls by kind.**
   - Hotel: on the ledge a terrace with umbrellas and a string of lights; on the end
     walls stone rustication and flags.
   - Office: on the ledge skylights and equipment; on the end walls glass fins.
   - Residential: on the ledge roofing felt, satellite dishes and clotheslines; on the
     end wall a zigzag fire escape.

   All without bodies and without new light sources: glowing is done with emission.
4. **The car at the exit — a draw by kind from its own five models.** Each kind has its
   own model weights and its own colors:
   - hotel — a black sedan or sports car;
   - office — a dark executive car;
   - residential — a hatchback and an SUV in faded colors.

   The first building of a game still exits in the red sports car. Cars parked in the
   garage have the same bias by kind. The street traffic and the car at the curb are the
   city's, shared: there is one street for the whole city.
5. **The garage and the street facade by kind.**
   - Hotel: the garage is clean, VALET signs and a valet stand; at the street — a canopy
     over the entrance with a carpet.
   - Office: in the garage a barrier gate and "Reserved" spots; at the street — a glass
     lobby.
   - Residential: in the garage peeling walls, graffiti, bicycles and a dumpster; at the
     street — a stoop and a fire escape.
6. **The barrier and the valet are alive but do not interfere with the game.**
   - The office barrier rises in front of Otto's car.
   - At the hotel exit stands a valet — a pedestrian model.

   The course and timing of the exit do not change.
7. **No new sounds.** The milestone is only about the look.

## Consequences

- The crown, ledge, end walls, garage and street read `rules.kind`; the builders get no
  new parameters.
- `CarModel.choose` gets the building kind. The first-building test (red sports car)
  stays.
- Helicopter and intro tests check every building kind: flying around the crown and the
  frame with the rope.
