# ADR-0047 · M24i: a room behind an open door

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0045](0045-takedowns-helicopter-dressing.md), decision 7,
  [ADR-0033](0033-dressing-from-packs.md) (dressing from packs)

## Context

Decision 7 of ADR-0045 — behind an open door, a red one and one an agent comes out
of, there should be a room by building kind, not darkness. In the 1983 arcade there
is a black opening behind the door; the room is the remake's look and does not touch
mechanics.

The camera is orthographic and looks into the opening almost head-on, tilted 10°
from above. Through a 1.2 m wide opening a narrow strip of the room is visible: its
back wall up to about 2.6 m and a strip of floor in front of it. The ceiling and side
walls do not get into the frame. The door leaf swings inward by its own width.

## Decisions

1. **The room — a [DoorRoom] node at the door, only while the leaf is open.** The door
   builds it when the leaf starts moving and removes it when it has closed: there are
   fifty doors in a building, and keeping fifty rooms with light sources is
   unnecessary. The draw is from the building seed, the floor and the door's place:
   the same door opens into the same room. The level passes the building and the draw
   to the door (`Door.furnish`); without them — in door tests — it is dark behind it,
   as before.
2. **Contents.** Width 4.2 m, depth 3.6 m, height — a floor without the slab. A back
   wall with a window onto the night city (shader `room_window.gdshader`: building
   silhouettes and windows by draw; the office has blinds), a sill and a frame.
   - Hotel room: a bed with its headboard to the wall (two models by draw), a
     nightstand with a lamp and its warm glow, a rug, curtains, a picture above the
     bed; wallpaper and a burgundy floor, warm light.
   - Office: a workstation at the wall (two ready ones by dook, CC-BY, or a Quaternius
     desk with a chair), a bookcase or file cabinet, a plant, a board, a calendar or a
     clock on the wall; gray paint and carpet, cold white light.
3. **The main item — in line with the door.** The bed or desk is placed with its
   middle no farther than half the opening width from the opening's middle: otherwise
   only a nightstand or a plant is visible in the opening. The room around is shifted
   by draw, so that the doors of one floor do not open onto the same picture.
4. **Furniture does not go under the door leaf.** Nothing stands closer to the
   corridor wall than the leaf width with a margin (1.3 m), and an item that is too
   deep is scaled down.
5. **Light — without shadows**, two sources per room (ceiling and the bedside lamp),
   and only while the door is open: within the frame budget. On a ROM dark floor the
   room has no light of its own, only the window with the city glows: an agent's open
   door must not light up a darkened corridor (the user's decision on code review). A
   room at the outermost door abuts the outer wall rather than sticking out of the
   building silhouette.
6. **Models.** Catalog place `ROOM`: it does not go into the corridor draw and is not
   compressed in depth. New poly.pizza models — beds, nightstands, curtains, a rug
   (Quaternius, CreativeTrio, CC0), a desk and a chair (Quaternius, CC0),
   workstations (dook, CC-BY 3.0); attribution in `CREDITS.md`.

## Consequences

- `tools/room_shot.tscn` shoots four hotel rooms and four offices: in openings, as in
  the game, and without the wall — the whole room.
- A test checks a hundred draws of each kind: the main item in line with the door,
  furniture not under the leaf, nothing sticks out of the room, there is light and a
  window; the door builds the room only while open.
- The window is night for now: day, morning and evening are milestone M24j.
