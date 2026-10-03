# ADR-0043 · M24g: animation and look

- **Status:** accepted
- **Date:** 2026-09-28
- **Extends:** [ADR-0025](0025-shafts-escalators-and-riders.md) (escalator),
  [ADR-0038](0038-building-start-and-end.md) (helicopter, red door, exit)

## Context

The second half of the user's remarks after M24e (2026-09-28); the first is M24f,
[ADR-0042](0042-bugs-and-settings.md).

### What the check showed

- On the rope, on the escalator and in the door Otto stands in the pistol pose:
  these states have no pose of their own. He does not walk into the door but is
  moved onto the mat and vanishes in one frame. In the ROM Otto walks into the
  door for 7 ticks at 2 px and only then vanishes (@3BDA–3C25).
- Our UAL clips have no "hanging on a rope" clip.
- The car headlights at the exit are one narrow beam 9 m long with no trace in the
  air; the street has almost no light.
- The escalator is assembled in code from boxes; there is no ready model in the
  assets.

## Decisions

All decisions are the user's.

1. **Rope — a code pose:** arms up on the rope, legs together, a slight sway; at
   the bottom the landing clip.
2. **On the escalator Otto walks up the steps** with the walk clip, facing the
   direction of travel.
3. **The escalator — a model from our own Blender script:** truss, glass
   balustrade, stainless steel, step comb — to our dimensions.
4. **The red door — entry into depth:** a turn to the door, a couple of steps
   into the opening, the door closes behind him; exit — a step toward the camera
   and a turn.
5. **Headlights light the way:** the beam is visible in the air and falls on the
   ramp and the street right until the fade.
6. **City windows do not only blink:** random windows turn on and off.

## Added during M24f

- **Dismemberment** (the user's request, 2026-09-28): a cab passing with its floor
  over a corpse tears off the part of the body under it, with blood splashes; it is
  turned off together with blood. Check and questions — before the milestone
  starts.
- **Corpses on top of each other** (the user's request, 2026-09-28): one killed
  next to a lying one falls on it and lies on top. Currently corpses are on layer 0
  and do not see each other — a separate corpse layer that collides with itself is
  needed.

## Check and decisions on dismemberment and corpses (start of M24g)

The ROM has neither: a killed agent falls and disappears. Both items are a
deliberate divergence, like corpses until the end of the building in M24a.

A cab passes with its floor over a body only on the bottom floor of its shaft:
there is a floor under the opening there, corpses from the shaft fall there and
the cab crushes the living there. On other floors there is a void under the
opening, and a corpse lying at the edge slides onto the landing by itself. A body
lying across the edge of the opening ends up partially under the cab floor. Before
M24g a corpse under a descending cab disappeared entirely in one frame — pinched
between the floor and the cab floor.

The user's decisions:

7. **The part under the cab floor disappears with splashes, a blood stain stays on
   the floor** until the end of the building. No body pieces remain.
8. **The cut is exactly along the cab edge,** not at a joint: the figure is cut by
   the plane of the cab wall in all its materials.
9. **It tears everyone under the cab floor:** lying corpses, an agent the cab
   crushes (300 points, as before), and Otto. Without blood — as before M24g: a
   corpse disappears, the living die in the "crushed" pose.
10. **Corpses stack on each other with physics, with no height limit:** one killed
    falls on a lying one and lies on top, one hanging by its middle slides to the
    floor. The living and Otto pass through corpses, as before.
11. **A body across the threshold is torn along the wall of a cab that starts
    moving** (the user's question during the milestone): the part in the cab rides
    off with it as a separate piece, the part on the landing lies where it lay; up
    and down the same. Without blood the body does not tear and slides onto the
    support of its middle. Along the way the M24f rule was fixed: a body lying with
    its ends on the cab floor and on a level landing no longer slides by itself —
    while the cab stands still, it lies calmly.

### How it works

- The body is [`Corpse`](../../src/systems/combat/corpse.gd) on top of the ragdoll
  [`Ragdoll`](../../src/systems/combat/ragdoll.gd): thirteen
  [PhysicalBone3D] on the pack skeleton, built when the actor is born and waiting
  disabled (empty layers), at the moment of death turned on on layer 5 `corpses`.
  Joints are like a human's: the knee bends only backward, the hip and back bend
  more forward than backward; the axes are the model's, not the bones'. The pack's
  feet hang from the skeleton root, and a separate hinge attaches them to the shin.
  The parts are locked in depth: the cab floor is a meter deep, and without the lock
  they would be squeezed out of it sideways. A part lying on the floor of a moving
  cab takes its vertical motion — otherwise the body would fall onto the receding
  floor again and again and slide off it.
- A torn-off piece is [`CorpsePiece`](../../src/systems/combat/corpse_piece.gd):
  a copy of the figure in which only the parts of this piece are physical, the rest
  hidden; the parts take the places they had in the body, with its velocities. The
  body tears only when the outer part lies on something stationary: an arm hanging
  over the shaft is not a threshold. The foot goes wherever its shin goes.
- The cut is the figure shader `carve.gdshader`: the pack materials (color, vertex
  color, roughness) are replicated in it. The cab floor cuts by world coordinate,
  exactly along the wall; torn-off and cut-off parts are hidden by skin bones. The
  back faces in the cut are flesh-colored. The mesh is not cut: it is skinned, and
  recomputing it on the fly is expensive.
- The cab floor cuts via [`CarCut`](../../src/systems/combat/car_cut.gd): the cut
  moves down together with the cab, blood sprays from the body, a stain stays at the
  floor — a `Decal`; parts the cab floor has passed through to the middle
  disappear, and the cab does not push through them.
12. **Corpses — as a ragdoll** (the user's request during the milestone,
    2026-09-29): a bar instead of a body lay on another corpse like a plank, "as if
    in invisible boxes". Each body part is its own physical body on joints with
    limits. Physics starts right from the hit — the body goes limp and flies from
    the bullet's push; the death clip goes away, a takedown scene plays out and
    releases the body into physics. Both agents and Otto fall this way; a revived
    Otto is back on his feet. The cut by the cab floor and tearing by the wall work
    per body part.
13. **Physics — Jolt instead of Godot's built-in engine** (during the milestone):
    on the ragdoll the built-in engine pushed thin parts — the forearm — through
    the floor slab on hitting the floor and did not let parts sleep: the body
    jittered finely while lying. Jolt, the second engine shipped with Godot 4.7,
    holds joints and puts settled bodies to sleep. Switching is the line
    `physics/3d/physics_engine` in `project.godot` and a zero margin for shape
    rounding (`collision_margin_fraction`): with a margin characters stood a
    centimeter above the floor. Verified by the whole test suite, including the bot
    that passes a building.
14. **The bullet's push goes into the body part it hit** (the user's question):
    in the head — the head snaps back, in the legs — they are knocked out, in the
    torso — the body is thrown back. Shot heights in the game per the ROM differ —
    standing, crouched, prone — and different deaths come out by themselves.
    Without a bullet the body is pushed backward, away from its facing.
15. **Escalators — at the floor edge, at 30°, in a zigzag** (the user's request
    during the milestone): in the middle of a floor an escalator looks absurd. It
    descends toward the edge, not away from it: the upper landing is closer to the
    middle, the lower one is at the very edge of the floor below, and the hole in
    the slab extends past the landing toward the edge, away from the walkway. One
    reaches the landing on foot, there is no need to jump over the gap. Several in a
    row — in a zigzag: to the left edge, to the right, again to the left. A 30°
    flight over a 3.6 m floor is about 6.2 m horizontally; in the frame it came out
    too shallow, and the user corrected the slope to 45°: the flight is 3.6 m, two
    places.
16. **The bullet leaves from the muzzle** (the user's remark): shot heights stay
    per the ROM, combat does not change; in the shooting pose the arm with the
    pistol is aimed so that the muzzle is where the bullet comes out.
17. **The exit from the garage — a smooth curve** (the user's remark): the straight
    ramp broke into corners at the floor and at the street, and the car bent on
    them. The rise is a smoothed step: the tangent is horizontal at both ends,
    steeper toward the middle. From one curve are built the ramp slab (in
    segments), the soil wedge under it and the car's motion — height and tilt along
    the tangent.
18. **Headlights — soft light, not a cone** (the user's remarks): a visible
    geometric cone read as a triangle. There are two headlights; at the glass — a
    soft halo, in the air the beam is visible only in volumetric fog. On the street
    the light did not fall on the asphalt for two reasons found by frame-by-frame
    analysis (`tools/m24b_shot.tscn -- --sequence`): the camera stopped at the edge
    of the building frame, and the car drove its last meters beyond the edge; the
    asphalt was almost absolutely black (0.004 in linear units), and the wet one a
    mirror, so the oblique beam went past the camera. The frame now overtakes the
    car and keeps a strip of street under it, asphalt is about 0.2 sRGB, the wet one
    shines but takes light.
