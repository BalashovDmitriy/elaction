# ADR-0040 · M24d: takedowns instead of the kick

- **Status:** accepted, implementation — M24d
- **Date:** 2026-09-26
- **Supersedes:** the jump kick — [ADR-0006](0006-combat-and-enemies.md),
  item 2 ("in the air Otto always kicks"), and the kick rule from
  [ADR-0027](0027-rom-combat.md) ("counts in any phase of the jump")
- **Extends:** [ADR-0039](0039-animation-and-controls.md) — buttons and clips

## Context

The user after M24c: when jumping Otto sticks out a leg, and the kick fires by
itself. The proposal — remove the automatic kick and instead make close-range
takedowns: short scripted scenes, picked at random, worth more than a shot.

### What the research showed

- **The 1983 original** (ROM @3127–3198). The kick is built into the jump: any
  contact with an agent during the whole jump kills, there is no separate
  close-range attack. Points (@577B): shot 100, kick 150; in a dark building or on
  floors 11–15 — 150 and 200; lamp and elevator — 300.
- **Elevator Action Returns (1994)** — closest to the intent: a "shot" next to an
  enemy turns into melee, the same button by context; such a kill gives double
  points. The jump there no longer hits by itself.
- **Other games** (Mark of the Ninja, Metal Gear, The Last of Us, Hotline Miami,
  Shadow Complex, Streets of Rage): a takedown always has an entry condition —
  point-blank, from behind, the enemy does not see, knocked down; the benefit is
  paid for with risk — during the scene the player is vulnerable, other enemies
  act; a scene lasts 0.6–3 s; there are 2–4 variants, by approach or random.
- **Animations.** No ready free paired animations (attacker and victim in sync)
  were found — only in paid sets. Mixamo cannot be used in a public repository:
  its terms forbid distributing the raw files. Universal Animation Library 2
  (Quaternius, CC0) fits: a hook, knockback from a hit, "lying on the back"; plus
  UAL 1 punches and reactions. Grab and choke are code poses on top of clips, as
  crouch and kick already are.

## Decisions

All decisions are the user's.

### 1. No more kick, a jump is just a jump

A jump does not kill and does not stick out a leg. In flight — the UAL flight clip
(`Jump_Loop`, back in the build); the kick zone and kick points go away.

### 2. Everything on the shoot button

Away from an agent the button shoots. Point-blank to an agent, on the same floor,
it performs a takedown. There are still two buttons, as on the cabinet.

### 3. Point-blank from any side; separate scenes from behind and from the front

A variant is picked at random from those matching the side, without repeating in a
row.

| Side | Scenes | Points |
|---|---|---|
| From behind | choke; neck snap | 300 |
| From the front | a series of punches (jab, cross, hook — knockback onto the back); pistol-whip | 200 |
| From above | pounce: Otto knocks the agent to the floor and finishes him | 300 |

In a dark building and on floors 11–15 — a +100 bonus, as the ROM gives for a shot
and a kick.

### 4. From above — automatic, on landing on an agent

Fell onto an agent from a floor above or from a cab — the pounce scene without a
press. The only takedown without a button: landing on an agent's head is hard
enough as it is.

### 5. The world slows down during the scene, Otto is vulnerable

Everything around — agents, bullets, cabs — goes slower, the scene runs at its own
pace. A neighbor's bullet can arrive by the end of the scene: a takedown with a
second agent on the line is a risk.

### 6. Close-up: the camera pushes in on the pair

The user's wish during the milestone: the scene should be cinematic. For the
scene the camera smoothly pushes in on the pair — the frame 0.38 times as wide,
the midpoint between Otto and the agent at chest height — holds close until a
little after the key frame and pulls back by the end of the scene. The first try,
0.62, did not read as a close-up: almost four floors were in the frame, and the
figure took a fifth of the height. The combat frame (`SideCamera.rule_view`) is not
touched by the close-up: it decides who sees whom.

### 7. Refinements from the milestone frames

- **The pistol-whip — with code poses.** The UAL 2 overhead throw taken first is a
  lunge downward: Otto dived at the agent's legs, like a slide tackle.
- **The UAL 2 hook is not used:** from the second half of the clip the body goes
  into a horizontal lunge. The front series is the UAL 1 jab and cross.
- **From behind Otto is 14 cm farther from the camera:** the bodies stand
  point-blank in one plane, and the agent must be in front, with Otto's arms behind
  him.
- **One clip from UAL 2 goes into the game** — knockback from a hit; its end is the
  corpse of the "on the back" scene.

## Implementation plan (M24d)

- Clips: from UAL 2 Standard — `Hit_Knockback`; from UAL 1 — `Punch_Jab`,
  `Punch_Cross`, `Hit_Head`, `Hit_Chest`, `Jump_Loop`. The UAL 2 skeleton is the
  same as UAL 1, with different bone names: a name table is enough for
  retargeting.
- The scene director: puts the agent at an offset from Otto in 0.1–0.15 s, turns
  off physics and brain for both, drives the two rigs by one clock, on the key
  frame — death and points.
- Slowdown — via `Engine.time_scale`, threefold: the world has no separate time
  scale, and introducing one would mean threading it through every system. The
  scene runs at its own pace — the director divides time by the slowdown and speeds
  up both rigs by the same factor; pause cancels the slowdown. The HUD slows down
  together with the world. The scene is driven by the physics step, not the frame:
  the agent's death and the points decide the outcome of the game, and the scene
  draw is seeded from the building seed — the bot run is reproducible.
- Rules — separate from nodes, with tests: who is point-blank, from which side,
  which scene, how many points.
- The test bot also killed with the jump kick; without it the combat test is run
  again, the bot learns to do takedowns.

## Consequences

- The shoot button does not shoot point-blank: an agent at point-blank range now
  cannot be shot, only taken down.
- The jump is again only a dodge from a low bullet and a way between levels.
