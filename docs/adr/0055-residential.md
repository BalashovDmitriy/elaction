# ADR-0055 · M24m: a residential building and own agents for each building kind

- **Status:** accepted
- **Date:** 2026-10-02
- **Extends:** [ADR-0033](0033-dressing-from-packs.md) (hotel or office by draw),
  [ADR-0047](0047-room-behind-the-door.md) (the room behind the door),
  [ADR-0048](0048-hotel-and-office-apart.md) (hotel and office apart),
  [ADR-0032](0032-actor-models.md) (actor models)

## Context

Since M21b a building is a hotel or an office (`BuildingIdentity.Kind`), since M24i they
differ in corridor, doors, light fixtures and the room behind the door. The user's
request (2026-09-30): a third kind — a residential complex, and each kind with its own
agents.

**Check against the original.** In the 1983 arcade there is one building: the geometry
is one ROM table for all buildings (`docs/reference/arcade-rom.md`, section Building),
the agents are the same in all buildings — dark suits and hats. Building kinds and
different agents are an extension of the remake. The closest reference is the sequel
Elevator Action Returns (1994): the locations differ (a tower, an airport, a shopping
mall, sewers), each with its own set of enemies — agents in trench coats,
businessmen, police, punks — while the combat mechanics are shared.

**Code.** The kind is `enum Kind { HOTEL, OFFICE }`, almost all branches are a binary
`is_hotel()`: corridor style, textures, furniture, sign, HUD, footsteps, the room behind
the door, tests and `tools/room_shot.gd`. The agent is a single file `agent.glb`, colors
baked in at build time in `tools/build_actors.py`. The furniture catalog has no kitchen,
TV or dining table.

## Decisions

Questions asked of the user on 2026-10-02.

1. **An American residential building of the 80s.** A brick residential tower in the
   spirit of New York of the arcade era, names and sign in English, like the hotel and
   office.
2. **An even three-way draw.** Hotel, office and residential building — a third each;
   the first building stays the EMPIRE hotel. Kinds for seeds are reshuffled; tests take
   the kind from `BuildingIdentity.of`, not from memory. `is_hotel()` branches move to
   `Kind`: the third kind has its own value in every place, not "everything that is not
   a hotel".
3. **The sign — the same vertical neon on the corner,** with its own color for the
   residential building, not matching the game indicator lights or the hotel and office
   neon. Neon on a residential building is a liberty taken for style.
4. **The residential corridor:**
   - apartment doors — a painted steel leaf, a peephole, an apartment number like
     `12C`, a mat at the threshold, sometimes a grocery bag or a bicycle;
   - floor — checkerboard tile or linoleum, walls painted in two tones, dish-shaped
     ceiling lights;
   - wear — cracks, stains, graffiti tags, a flickering lamp on some floors;
   - dressing — mailboxes, a baby stroller, radiators, trash bags, a fire extinguisher
     instead of the hotel's sofas and plants.

   The lamp flicker is a look, not a mechanic: the zone stays lit while the lamp is
   intact, as in the ROM.
5. **Behind the red door — an apartment, a draw of three:** a kitchen, a living room
   with a sofa and a TV, or a bedroom. The TV glows flickering blue in the dark. The
   room rules of ADR-0047 are the same: the main item in line with the door, the leaf
   area free.
6. **Missing furniture — from CC0 packs** (Kenney Furniture Kit, Quaternius and
   poly.pizza): fridge, stove, sink, kitchen units, TV, a dining table with chairs,
   mailboxes, a stroller, a radiator. First the search and a catalog frame, then the
   placement.
7. **Own agents for each kind — their own wardrobe, shared mechanics.** One Business Man
   model, recoloring and headwear as profiles of the same `tools/build_actors.py` build
   as the old agent: three `.glb` files, the level picks the body by building kind
   (`AgentWardrobe`). In-game recoloring, as for the M24l pedestrians, was rejected
   along the way: the pedestrian model is assembled from parts, while the agent's fedora
   and glasses are build meshes, and in the game they would have to be built anew.
   - hotel — the current noir: dark suit, fedora, glasses;
   - office — a charcoal business suit without a hat, a burgundy tie, glasses;
   - residential — street wear: a dark-brown jacket over a turtleneck, a tweed flat cap,
     no glasses. A trench coat cannot be built on this model: skirts on the hip bones
     already read as a bag on the pedestrians (ADR-0054, decision 11).

   An agent reads as an agent in any kind: the silhouette and dark tone hold, and there
   are no pedestrians inside the building.
8. **Sound:** its own corridor ambience for each of the three kinds, and in the
   residential building also rare muffled sounds from behind doors — a TV, a dog,
   neighbors arguing. The user picks the sounds by ear from a listening page, as in
   M24l. Footsteps on linoleum.

### Sound chosen by ear

Listening page, 2026-10-02: the office corridor ambience — Soup_UnderScore 708021 (CC0),
an empty office with air-conditioning hum; the residential one — SpliceSound 338104
(CC0), a building corridor in Brooklyn, occasional neighbors; behind the door — a TV by
markb 104578 (CC-BY 4.0), a dog by klankbeeld 773829 (CC-BY 4.0), an argument by
SieuAmThanh 848362 (CC0); footsteps — roman_gens 475080 (CC-BY 4.0), four steps. What was
recorded up close is muffled at build time by cutting the highs (`muffle` in
`build_audio.py`). The sound behind a door is `DoorLife`: a closed apartment door without
a document on a floor in the frame, once every one to two and a half minutes, audible
within seven meters.

## Consequences

- Every place that branches by kind gets a third branch; tests that go through
  `[true, false]` for hotel and office go through all three `Kind` values.
- The agent stops being one file: there are three models, by building kind. Takedowns
  look for the hat by mesh name (`takedown_scene.gd`) — the cap has the same name and
  flies off the same way, the office agent has no hat, and the scene does without it.
- Sounds from behind doors are the first building sounds unrelated to the player and
  agents; their volume and frequency are tuned in the mix so they are not confused with
  an agent's door.
