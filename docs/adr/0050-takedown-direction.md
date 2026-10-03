# ADR-0050 · M24i: takedown direction

- **Status:** accepted
- **Date:** 2026-09-30
- **Extends:** [ADR-0045](0045-takedowns-helicopter-dressing.md), decisions 1–4,
  [ADR-0040](0040-takedowns.md) (takedowns)

## Context

The M24d takedown scenes looked too simple: the world is evenly slowed to 0.3, the
camera smoothly pushes in and pulls out, the agent lies down in a ready corpse pose.
Decisions 1–4 of ADR-0045 (the user's) — direction without changing the angle:
rhythm with a freeze frame, a camera jolt, light and sound as accents, the agent's
acting and a ragdoll.

## Decisions

1. **Rhythm — a curve of world speed.** The approach is 0.6, smoothly down to 0.3
   toward the blow, on the blow a freeze frame: for 0.14 s of real time the world runs
   at 0.03, the rigs stand still; after the blow it ramps back to normal speed by the
   end of the scene. Scene time is counted in real seconds, as before — scene lengths
   and key frames do not change.
2. **The camera jolts on the blow:** a shift, a tilt and a short extra push-in,
   fading over 0.45 s of real time ([method SideCamera.kick]). The jolt does not touch
   the combat frame — it is computed from the frame center, not from the camera.
3. **Light and sound.** On the blow — a warm flash at the faces of the two, fading
   over 0.32 s; for the whole scene the background is less colorful and darker
   (saturation 0.35, brightness 0.8 of the scene frame), and the music is muffled; on
   the blow it drops out, and the blow sounds twice — a second layer a tone lower and
   louder, hollow. Everything returns on any exit from the scene: end, interruption,
   building unload.
4. **The agent acts.** From the front he manages to reach for the gun, from behind —
   to sense it and look over his shoulder; on the blow his hat flies off — it is now
   its own mesh (`tools/build_actors.py`), the game hides it and releases a copy as a
   body flying up away from Otto with a spin. The agent falls as a ragdoll right on
   the blow, thrown away from Otto, not into a ready pose at the end of the scene.

## Consequences

- `Sounds.play_tuned` and `Sounds.duck_music` — pitch, volume and the music drop from
  outside the audio code.
- Hats, like corpses, lie until the end of the building.
- The takedown test checks the slowdown on the approach, the freeze frame on the blow,
  death and ragdoll on the blow and the flown-off hat; the camera test — the jolt and
  the return.
