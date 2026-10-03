# ADR-0059 · Deterministic bot combat run

- **Status:** accepted
- **Date:** 2026-10-03
- **Amends:** [ADR-0053](0053-open-questions-and-debt.md) (respawn by the ROM),
  [ADR-0042](0042-bugs-and-settings.md) (takedowns, the pounce),
  [ADR-0016](0016-combat-balance.md) (the combat gate)

## Context

The pre-push hook failed three times in a row on `test_bot_survives_the_real_building_
with_agents_seed_3`: "9 deaths with a threshold of 6". On a clean `main` the same test
failed on about half the runs. It is meant to be deterministic: same seed, same run.

Run logs (`RunLog`) of a passing and a failing run matched to the millimetre — Otto,
agents, every cab, even the agents' random generator states — up to frame 6877. There
an agent fired at Otto from 0.84 m while Otto rode a cab past its floor. The bullet was
born inside both Otto and the cab floor, and which of them it hit was decided by the
`body_entered` signal of the bullet's `Area3D`: Jolt reported the two overlaps in a
different order, or not at all, from run to run.

With hits decided by a direct query the runs became identical (six out of six), and the
honest numbers on seeds 1–3 were 2, 3, 11. Seed 3 lost Otto three times in a row to the
same pattern: he came back on floor 24, an agent from the next door lay down 2 m away
and fired low; the bot jumped the first shot, landed into the second (the landing pause
leaves no time for another jump) and meanwhile crouch-fired at the prone agent — a crouch
shot flies over a prone agent, as in the ROM ("crouch shot 15 misses prone (top 11)").

The run is chaotic: any change of the bot or of timing reshuffles the whole fight, so a
single seed's death count jumps between 2 and 13. The sum over seeds cannot be the gate:
CI splits the suite into parts (`--part K/N`), and the seeds land on different machines.

## Decisions

Questions asked to the user on 2026-10-03.

1. **A bullet decides its hits itself.** `Bullet.monitoring` is off. The bullet checks
   what its shape overlaps with a direct `intersect_shape` query — at the shot
   (`strike_point_blank`, same physics frame as the engine used to report it) and at the
   start of each of its frames — and its flight with `cast_motion` as before. The same
   positions give the same answer on every run.
2. **The bot does not duel a prone agent.** Holding the line from a crouch only wastes
   shots on it. It goes for the takedown from up to 4 m, and over a prone agent's low
   shot it jumps towards it, so as to land on it (the pounce).
3. **A calm after the return — our deviation from the ROM.** For 4 s after Otto comes
   back, a door on his floor does not release an agent closer than 4 m to him
   (`BuildingRules.agent_respawn_calm`, `agent_respawn_gap`). The ROM has no distance
   check (@5AAB); the user chose fairness here.
4. **The gate stays per seed, 6 deaths.** Measured after the fix: 2, 5, 3. The number is
   now stable and changes only with the code; when it crosses the threshold, it is
   measured again, as `DEATHS_ALLOWED` says.

## Consequences

- `test_bullet_flight` checks the point-blank hit by query with monitoring off;
  `test_respawn` checks the calm after the return.
- Anything else that relied on the bullet's `body_entered` would have broken: nothing did.
