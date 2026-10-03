# ADR-0033 · M21b: floors, roof and elevator from pack models

- **Status:** accepted
- **Date:** 2026-09-24

## Context

After M21 the people in the frame are real, but the world around them is not. The
user's remarks: "the floors are just some unclear squares", "make the roof even
more detailed", "the shaft barely stands out from the background", the elevator
needs "up/down buttons with the number of the floor where the elevator is now,
everything natural like in real life", the HOTEL sign "is covered by objects".

### What the check showed

- **A floor** in the frame is flat colored rectangles: back wall panels in the
  round tone, a dark lower panel and six kinds of items as boxes
  (`BuildingProps`). There are no textures anywhere.
- **Models.** The poly.pizza catalog was sorted by license, 327 models. CC0 —
  Quaternius (Ultimate House Interior, Furniture Pack, individual roof models),
  CreativeTrio (Household Props), Kenney. CC-BY 3.0 — most of The Office
  Pack (water cooler, file cabinet, fire extinguisher, exit sign, vending machine,
  board, clock, pictures), J-Toastie, Poly by Google.
- **Roof.** Tank, air conditioners, pipes, mast — boxes and cylinders of `RoofKit`;
  the HOTEL neon stands behind the equipment and on the way down goes off the top
  of the frame and under the HUD.
- **Shaft.** A back wall in the shaft tone, guide rails, portals; above each
  portal an indicator board with the floor number — static. The cab knows its
  floor (`ElevatorCar.floor_reached`) — a live indicator board is possible without
  new mechanics.
- **Textures.** ambientCG (CC0): wallpaper, carpets, plaster, metal sheets,
  diamond-plate metal, concrete — 1K PBR sets.

## Decisions

### 1. Building kind — a draw: hotel or office tower

The user's decision. The kind and name are drawn by the building number and seed,
like the car (ADR-0032, decision 7). The sign, wall finish and dressing set
depend on the kind. Mechanics are the same.

### 2. The sign — vertical, on the facade corner, with a name from a list

The user's decisions. Letters in a column on the corner post along the upper
floors, facing the camera — roof equipment does not cover it, and it is visible
all the way down. Hotel — HOTEL and a name above it (EMPIRE, ROYAL, METRO,
SAVOY…), office — a corporation name (KRONOS, ATLAS, VECTOR…): it is the one Otto
steals documents from. Neon, one letter blinks occasionally. The HOTEL neon on the
roof goes away.

### 3. Dressing — pack models, rich but readable

The user's decision.

- **Walls:** there is always something between doors — sconces, pictures,
  clocks, notice boards, room numbers at doors (hotel) or plaques (office).
- **Floor:** furniture on every second free spot — less than half was "sparse",
  more and the actors get lost on a busy background.
- Everything without bodies and without its own light sources, more muted than
  the actors; only what glows in real life glows (sconces — via emission).
- Models are placed from a **catalog in code** (`PropCatalog`): file, height in
  meters, rotation toward the camera, where it hangs (floor or wall), which
  building kind. Height is scaled to the catalog on load — the model depth must
  fit between the back wall and the play plane; a test holds this.
- Source `.glb` files lie in `assets/models/props/` as is: they do not need
  Blender, unlike the actors.

### 4. Licenses — CC0 and CC-BY 3.0, authors in CREDITS

The user's decision (M21). Every model and texture is a line in `CREDITS.md`:
what, author, license, link. A test checks the catalog against CREDITS: a model
without a line cannot exist. README links to CREDITS.

### 5. Walls — textures by building kind

Hotel — wallpaper above wooden paneling, office — painted plaster above plastic
paneling. The round tone (`BuildingPalette`) is applied to the texture as a
multiplier, not a fill: rounds still differ to the eye (M20). Texture mapping is
triplanar: wall boxes have different sizes and no UV unwrap of their own.

### 6. Shaft — steel

The user's decision. The back wall of the shaft is metal sheets with bolts, the
sides are concrete; guide rails and braces, the portal is a chrome frame with a
diamond-plate threshold. Warm cab light on cold metal — the shaft reads as a
column through the building.

### 7. At the portal — the cab indicator board and call buttons, visual only

The user's decision. Above the portal an indicator board: the floor where the cab
is now, and a travel arrow. Next to it a ▲▼ panel; a button lights up when the cab
is heading to this floor. There is no call mechanic: cabs move on their own, as
in the original, the balance is untouched. The indicator board updates on a cab
signal, not every frame.

### 8. Roof — models and texture

The tank and air conditioners are Quaternius models; antennas, a satellite dish,
ventilation, solar panels and a roof exit are added. The surface is a gravel or
concrete texture. The layout still follows the roof plan: equipment does not
stand in front of the shaft or in Otto's path.

## Consequences

- There are more items in the frame, but no light sources are added: the frame
  keeps the ADR-0029 budget, measured by `light_bench` at the end of the
  milestone.
- `BuildingDressing.Kind` gives way to the catalog; the "where one can stand"
  layout (`free_spots`) stays and gets its counterpart for walls.
- `CREDITS.md` is a new document read from outside, like README.
