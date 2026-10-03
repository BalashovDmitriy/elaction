# ADR-0046 · M24i: a car with an interior, turn signal, traffic situation

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0045](0045-takedowns-helicopter-dressing.md), decision 8
  (boarding the car), [ADR-0044](0044-street-and-cab.md), decisions 1–2 (traffic),
  [ADR-0032](0032-actor-models.md), decision 7 (pack cars)

## Context

Decision 8 of ADR-0045 — redo boarding the car: the dome light under the roof, the
body cut along the door opening, the interior in the opening. During the work the
user added three requests (2026-09-30):

- blink the turn signal while Otto's car waits for a gap;
- proper boarding, door and interior for **every** car in the draw, not only the
  red sports car of the first building, and the interior matching its car;
- the traffic situation at the exit is random: sometimes there is a gap right away,
  sometimes one has to wait; the cars in the traffic are always different.

The original has none of this: Otto's car in 1983 is a sprite, there is no street
with traffic at all. There is nothing to check against; this is the remake's look
and flow.

## Decisions

1. **The opening, door and interior — in the model itself, built in Blender**
   (`tools/build_actors.py cars`). The body is cut by planes along the door edges
   and the sill, the side faces between them go into the `DriverDoor` part with its
   origin at the hinge by the front pillar; the opening edge is extruded inward —
   the body thickness is visible. Inside, the door has trim — a copy of its faces
   shifted inward, with an end face. The `CarInterior` is built from the model's
   windows, the ceiling by a ray to the roof (the roof narrows toward the top, and a
   ceiling at window height stuck out of it at the corners). The dome light point is
   an empty `DomeLight`: the game puts a weak source there, and the one getting in
   is no longer burned by a spot at the waist. Our own painted door panel on top of
   a solid body is removed.

   The interior is by car type: the two sports coupes have a long door, low bucket
   seats with side bolsters and a parcel shelf at the back; the sedan has a bench;
   the wagon and SUV also have a trunk behind the bench, the SUV sits higher and more
   upright. All have a floor mat, an armrest, a tunnel with a lever, a dashboard with
   an instrument cluster and a steering wheel.

   LOD generation on import is disabled for the car models: with it Godot merged
   vertices with close normals, and the faceted door showed patchy highlights.

2. **Right turn signal.** The car pulls off the edge of the roadway into the near
   lane — away from the camera, which is to the right in the direction of travel.
   Turn signals sit at the four corners of the body (materials `IndicatorLeft` and
   `IndicatorRight`), unlit they are amber plastic. Otto's car blinks the right one:
   from approaching the edge of the roadway, while it waits and while it pulls out;
   in the lane it goes off. The right-side lights are on the side away from the
   camera, so each has its own flash of light, and the blinking reads by the spot on
   the asphalt and the body.

3. **The traffic situation — a building draw.** The first draw of the traffic is the
   density: free (gaps 20–48 m), normal (7–24 m) or dense (3.5–11 m), in shares of
   35 / 40 / 25 %. Three meters before the edge of the roadway Otto's car looks at
   the lane: free — it does not stop but pulls out on the go; occupied — it stops and
   waits. How long to wait before the traffic holds back to let it in depends on the
   situation: 1.5, 2.2 or 4 s. The model and paint of each car in the traffic is its
   own draw, as it has been since M24h. The draw is from the building seed: within
   one game a building repeats identically, in another game the game salt gives a
   different one.

## Consequences

- The exit test no longer requires the car to always stop: the test sets up an
  occupied and a free lane itself and checks both.
- Car models are rebuilt by the script; after the build
  `godot --headless --import` is needed — running the game does not reimport `.glb`.
- `tools/car_shot.tscn` shoots all five cars from the side — closed, with the door
  open and from the rear — and each one close up; `tools/m24b_shot.tscn` accepts
  `--building=` (the car draw by building number) and `--only=exit`.
