# ADR-0039 · M24c: animation with UAL clips, short pauses, key rebinding

- **Status:** accepted
- **Date:** 2026-09-26
- **Extends:** [ADR-0032](0032-actor-models.md), decision 1 — which poses are clips,
  which are code; [ADR-0012](0012-sound-and-interface.md), item 10 — the controls screen
- **Supersedes:** "key rebinding is deferred" from ADR-0012, item 10

## Context

After M23 the user sent remarks on animation and controls; they were deferred
to M24c (ADR-0037, "Not in the milestone"). Clarification before the milestone
showed that all movement is bad, not just landing:

- **Landing.** After a jump Otto bends a leg and slowly straightens. The fall
  after the top point shows the kick pose with the supporting leg bent, and on the
  floor the body crawls from it into the stance.
- **Sluggish transitions.** Any pose change is an exponential over 0.43 s
  (`FigureRig.smoothing`): stop, turn, shot lag behind the controls.
- **A jump in one pose.** In the air a frozen pose, no push-off, flight or
  landing.
- **Walking and turning.** Start and stop are abrupt, a turn is an instant body
  rotation.

### What the check showed

- **The original.** A four-way joystick and two buttons: "shoot" and
  "jump / kick", the buttons duplicated on both sides of the joystick for right-
  and left-handed players. The cabinet has no rebinding. Jump and kick are sprites
  without phases; turn and start are instant. Smoothness here is our choice, not a
  check result.
- **The pack has few clips.** Of Business Man's 24 clips the game uses four:
  stance, walk, shot, death. The pack has no jump, crouch or landing.
- **Universal Animation Library** (Quaternius, CC0). The free part is 45
  clips, among them `Jump_Start`, `Jump_Loop`, `Jump_Land`, `Crouch_Idle_Loop`,
  `Crouch_Fwd_Loop`, `Pistol_Idle_Loop`, `Pistol_Shoot`, `Pistol_Aim_*`,
  `Walk_Loop`, `Walk_Formal_Loop`, `Death01`, `Roll`, `Hit_*`. There is no turn.
- **The UAL skeleton is different:** 53 bones in the Rigify scheme (`DEF-hips`,
  `DEF-spine.001`… `DEF-thigh.L`, `DEF-shin.L`, `DEF-foot.L`). Bone for bone it
  maps onto the pack skeleton: hips, three vertebrae, neck, head, shoulder, upper
  arm, forearm, hand, thigh, shin, foot. There is one difference, but an important
  one: the pack's feet hang from the root under IK, while in UAL they hang from the
  shin.

## Decisions

### 1. Movement — UAL clips retargeted to the pack skeleton

The user's decision. All locomotion comes from UAL so that movement has one style:
stance, walk, push-off, landing, shot and death. The kick stays a code pose: UAL
has no kick, and the jump in the original is the kick. The UAL crouch
(`Crouch_Idle_Loop`) is not used: the crouch holds the ROM bullet height, and the
code pose holds it (decision 2). The base of the code poses is the neutral UAL
stance `Idle_Loop`, arms down: from the two-handed pistol stance the arm angles
drifted.

Refined during the milestone:

- the glTF importer rotates the pack armature by 90° around X, so rotations are
  transferred in world space, not in armature space;
- the pack's legs are longer than UAL's, and every clip frame is placed on the
  floor by vertices at build time — without this the sole sank 6 cm into the
  floor in a step;
- Godot strips the `_loop` suffix from a clip name on import.

The retargeting is done by `tools/build_actors.py` in Blender, where the models are
already built: a UAL clip is read on its own skeleton, bone rotations are
transferred to the pack bones by a mapping table and baked into the model's clip.
The pack's feet are placed at the end of the shin — the same way the rig already
places them in code poses. In the game `FigureRig` still reads clips itself,
without `AnimationTree` (ADR-0032, decision 1): `snap()` and vertex-based bounds
rely on this.

The UAL source (`AnimationLibrary_Godot_Standard.glb`) lies in
`assets/source/quaternius/` with the license, like the pack source.

### 2. ROM heights remain law

Crouch, an agent on one knee and a prone agent hold the ROM bullet heights
(ADR-0027), and vertex tests check this. A UAL clip replaces such a pose only if it
passes the same test; otherwise the pose stays code, and the clip provides the
entry into and exit from it.

### 3. Turn — by rotating the body in code

UAL has no turn clip. The body rotates to the new direction during the turn pause
(decision 4); the legs meanwhile play the stance or step clip.

### 4. Short control pauses

The user's decision: turning and landing slightly delay control. Movement feels
weightier, but this diverges from the cabinet, where everything is instant, and it
changes combat: agent bullets fly three times faster than in the ROM (ADR-0037).

- **Turn:** while the body rotates, Otto does not walk; shooting is allowed. Only
  on the floor: in the air turning to face is free, as in the ROM (@42A7).
- **Landing:** after a jump or a fall a short recovery during which one cannot
  walk or jump; shooting and crouching are allowed. A jump pressed during recovery
  and held fires as soon as it ends: a lost press would read as a button that did
  not work.

Durations are tuned against frames and the combat test with agents: it must not
exceed the death threshold (ADR-0027). Chosen: 0.1 s for a turn and 0.15 s for
landing: with them the combat test is within the threshold, and the test bot
passed without changes. The pauses are rule numbers, without nodes, and are tested
the same way as `OttoStateMachine`. Agents obey the same pauses.

### 5. Transitions between poses are shorter and per case

One exponential for everything goes away. Each transition has its own time: into
and out of the walk clip — fast, into landing — immediately from the first frame,
out of death — never. Blending two clips is by time, not by a fraction of the
remainder, so a transition ends rather than creeping in.

### 6. Agents — the same clips

The skeleton is shared: an agent walks, jumps (if jumping down) and dies with the
same clips. Poses for ROM heights — on one knee, prone — stay code (decision 2).

### 7. Rebinding: one key and one button per action

The user's decision. The controls screen goes from showing to configuring: each
action has one keyboard key and one gamepad button, plus "reset to defaults".

- Six game actions are rebindable: four directions, jump, shoot.
- **Pause on Esc and Start is not rebindable:** without it one cannot leave the
  game after assigning something wrong. The screenshot on F12 is also fixed.
- The gamepad stick always drives directions together with the D-pad.
- **A taken key is swapped:** the action it was taken from gets the new action's
  previous key. No action is left without a key.
- Keys are by physical location (`physical_keycode`), as now: the scheme survives
  a layout change.
- The scheme is stored in `settings.cfg` next to the other settings.

Defaults are arrows, space, X; WASD, Z and J, which are now secondary keys, leave
the defaults: there is one keyboard slot. Those who play on WASD will assign them
themselves.

### 8. Shader warm-up

The first shot stutters the frame: shaders for the flash, smoke, sparks, blood and
lightning are compiled at the moment of first display. Two means together:

- **Shader Baker** in the export presets: the build ships with ready shaders for
  the target driver. Caveat: `tools/export.py` exports with `--headless`, and
  without a real renderer Godot 4.7 does not bake everything ("won't be able to
  include core shaders"). CI runners have no graphics card, so the main means is
  the second one.
- **First display under black:** the first building of a launch opens from black,
  and under it every rare effect is drawn once in the camera frame — one hidden or
  out of frame is not drawn and does not warm up. The lightning bolt warms up in
  the city window, where it is drawn. The pipeline cache is shared per process —
  warm-up once per launch.

## Not in the milestone

- **Demo mode** — a separate milestone after M24c. The user's decision: the menu
  as it is now is liked, the demo must not replace it — only turn on over it on
  idle.
- The paid part of UAL and the second library (UAL 2): the free part covers
  everything needed.

## Consequences

- The Otto and agent models get heavier by a dozen clips; a clip weighs little,
  but `build_actors.py` takes longer.
- The combat test with agents passed again with the pauses, within the threshold.
- The controls screen gets tests: key swap, reset, saving and reading the scheme.
