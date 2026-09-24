# Правила аркадного ROM: заметки по дизассемблеру

Источник — аннотированный дизассемблер аркадного ROM Elevator Action (Z80,
набор `elevatorb`), сделанный jotd для точного переноса игры на Amiga:
https://github.com/jotd666/elevator_action, файл `src/elevator_z80.asm`.
Метки и комментарии в нём — jotd; выводы ниже (помечены `=>`) — наши, со
сверки перед M18d (2026-09-23). Адреса вида `@1BDF` — места в том файле.
В коде эти числа живут в `Arcade` (`src/systems/arcade.gd`) — с теми же адресами
в комментариях.

Частота логики подтверждена драйвером MAME `taitosj.cpp`: кадр 59.19 Гц,
логика раз в 4 кадра — **14.8 тика в секунду, тик 67.6 мс**. Все «тики» ниже —
тики логики. Высоты — в пикселях клетки этажа 48 px, где ступни стоящего на
полу — 6; над полом = значение − 6. Пиксель оригинала у нас 0.075 м
(`Proportions.PX`).

Независимая проверка по видео аркады (60 кадров/с) сошлась до пикселя:
прыжок +25–26 px за 0.87–0.95 с, низкая пуля на 8 px над полом.

**Вторая часть заметок уточняет первую:** агенты сами не прыгают (от пули
они приседают и ложатся), а `$834C` — скорость пули агента.

Карта здания целиком — StrategyWiki, `Elevator_Action_Level.png`; совпадает
с NES- и ZX-картами.

---

# Notes on the arcade Z80 disassembly (jotd666/elevator_action, src/elevator_z80.asm)

Source: https://github.com/jotd666/elevator_action (a local clone at the time, not kept in this repo). An annotated disassembly of the
arcade ROM (bootleg set elevatorb, protection removed), made by jotd for a 1:1 Amiga transcode.
Labels and comments are jotd's; the interpretations below (marked "=>") are mine.

## Logic tick rate
- IRQ dispatcher runs the in-game screen every `timer_8bit_reload_value_80A9` IRQs; for levels it is
  `game_speed_8233` = 4 (init_level_skill_params_2A2E @2A44). The main loop waits on $80AB (game_tick_73cf @73F2).
  => the game logic runs at 60/4 = 15 Hz (assuming the usual 60 Hz vblank IRQ). All tick counts below are logic ticks.

## Difficulty variables
- skill_level_8237 = DIP difficulty (DSW3 & 3, @2EAD) at game start; `inc` after each building (@0A0A).
- level_timer_16bit_8231: +1 per tick (@58FB), reset to 0 on building start/next life? (@2A41 reset in init_level_skill_params).
- compute_difficulty_592F: instant_difficulty_8374 = min(15, skill + timer_msb/4); when timer_msb >= $10 (alarm):
  min(15, skill + (timer_msb - 12)).  => +1 per 1024 ticks (~68 s) before the alarm, +1 per 256 ticks (~17 s) after it.
- Alarm = timer_msb reaching $10 = 4096 ticks => ~273 s ≈ 4.5 min at 15 Hz. Switches to hurry-up music (@466E).
- After the alarm $82F0 = min(12, 2*(msb-15)) = number of ticks the joystick must be held before the elevator
  obeys (player_elevator_control, @4686-4695) => "elevators slower to respond".
- $837A = max enemies per floor near Otto: 1 while msb<3 (first ~51 s), 2 while msb<12, then 3 (@5905).
- max_nb_enemies_837B = 3, or 4 when skill*4 + timer_msb >= 14 (@594D). 4 enemy slots in RAM.
- probability_to_spawn_837C = instant_difficulty*4 (/256) = chance to force spawn on Otto's own floor.
- $8375 = max(0, 0x50 - 6*instant_difficulty) = cooldown (ticks) before a dead/removed enemy slot can respawn (@3866, @3C9B).
- $834C init = min(8, skill/4 + 6), +1 during alarm up to 8 (used as vertical step, @508C; meaning unclear).

## Spawning (try_to_spawn_an_enemy_5A26 / maybe_spawn_an_enemy_5a4c / must_spawn_enemy_5AAB)
- Floor = Otto's floor + e - 1, e = random mod 3  => floor below / same / above. With probability 837C, e = 1 (Otto's floor).
- Door = random 0..7 slot on that floor; spawns only if that slot exists (per-floor mask table_280E) and it is not
  the floor's red door (red_door_position_array_8210).  (Exception @5ADF: floor 20 right part in alarm.)
- Per-floor cap: count of enemies on floors (Otto-1 .. Otto+1) in $8377..$8379 vs $837A.
- When Otto is not on the ground (in/on elevator, escalator, in room) or no "alert", the cap is 1 per floor (@59F4-5A1B).
- Alert: if instant_difficulty > 0 and one of the player-bullet sprites ($8123 table) is active => $8376 = 90 ticks and every
  enemy's +0E field = 90 (@59C8-59F3). While $8376>0 and Otto on ground, the full cap ($837A) is used.
  => firing your gun makes more agents come out (from building 2 / after ~68 s in building 1).
- Enemy +0E = 90 also set on entering/riding an elevator (@1AED, @1B42, @1C1C). With +0E set the enemy shoots
  regardless of facing (@0568) and uses the second pose table (@0529).

## Per-enemy aggressivity (+13)
- set to instant_difficulty at spawn (@5AA4), +1 every 256 ticks up to 15 (@5AFC).
- table_0548 (normal) : 00 00 10 10 20 20 30 30 40 40 50 50 60 60 70 70  (/256) indexed by aggressivity
- table_0558 (alert)  : 00 10 20 30 40 50 60 70 80 90 A0 B0 C0 D0 E0 F0
  => probability of a pose/variant flag (+12) — likely crouch/prone choice; not fully decoded.
- odds_table_0659: 00 00 02 02 04 08 10 10 20 20 40 40 60 80 C4 FF (/256) => chance to react to Otto's bullet
  within 0x14 px on the same floor (@05F5-0655); sets +12 = 1 or 2 depending on bullet height (low vs high),
  2 is converted to 1 near shaft edges on floors 1-7 (@0669). => dodge by jumping/ducking; enemy has jump sprites (TCRF).

## Lamp / darkness (update_shot_lamp_31BA)
- lamp_shot_state counter +1 per tick; lamp falls ticks 3..0x15; building goes dark at 0x18; lights restored at 0x5A
  => dark lasts 66 ticks ≈ 4.4 s. Only one lamp at a time.
- dark flag $8242 is read only by scoring (@569A/@56BF: dark or floors 11-15 => 150/200 instead of 100/150)
  and by sprite palette (@627D). No AI code reads it => no measurable behaviour change in darkness.
- Score table @577B (BCD): 100 shoot, 150 shoot-dark, 150 kick, 200 kick-dark, 300 lamp, 300 (crush), 500 document.

## Building
- Door masks per floor (table_280E, floor 0..30): 00, 81x6 (floors 1-6: 1 door each side), 00 (7), 7E 7E (8-9: 6 doors),
  66 66 (10-11: 4), E6 (12: 5), 7E (13: 6), 7F (14: 7), 67 (15: 5), E6 (16: 5), 66 (17: 4), 7E (18: 6), 66 x12 (19-30: 4).
  => the geometry is a fixed ROM table, identical in every building.
- Red doors: number per floor band from tables indexed by min(skill,8) (@27D2), one red door max per floor,
  floor chosen at random within the band, door = random one of 2 candidate slots per floor (table @2875).
  bands: 1-6 {0,1,2,2,2,2,3,4,5}; 8 {0,0,0,1,1,1,1,1,1}; 9-11 {2,2,2,1,1,2,1,1,1}; 12-14 {1..}; 15-17 {1..}; 18-20 {1..};
  21-25 {0,0,0,1,1,1,1,1,0}; 26-30 {0,0,0,0,1,1,1,0,0}
  totals by skill 0..8: 5,6,7,8,9,10,10,10,10.
- Floors are counted from the bottom: floor 0 is the basement with the car, 30 the top (red-door bands, @2753 lower floors 1-6).
- Lamps (init_building_2700 @270A): $81DA holds 23 two-bit lamp masks for floors 8..30, all set to 3 (two lamps),
  $81E6 (floor 20) = 2 (one lamp), $81DD..$81E1 (floors 11..15) = 0 (no lamps). Floors below 8 have no lamps
  (display_broken_lamp_if_needed_035f, @089A). => the dark floors are 11-15.
- Kill score (@56A1, @56C6): dark building ($8242) OR victim on the ground on floors 0x0B..0x0F (11-15) => 150 shoot / 200 kick.
- Red door band tables @282D..@2874, indexed by min(skill, 8): 1-6 {0,1,2,2,2,2,3,4,5}; 8 {0,0,0,1,1,1,1,1,1};
  9-11 {2,2,2,1,1,2,1,1,1}; 12-14, 15-17, 18-20 {1 x9}; 21-25 {0,0,0,1,1,1,1,1,0}; 26-30 {0,0,0,0,1,1,1,0,0}.
- Exit shaft ($802D) and double-elevator layout (@2A75) chosen randomly per building.
- End bonus = 1000 * min(10, skill - DIP + 1) (@5793).

## Part 2 (coordinator follow-up)

### Tick rate (confirmed)
MAME src/mame/taito/taitosj.cpp (a local copy at the time, not kept in this repo): `m_screen->set_raw(12_MHz_XTAL / 2, 384, 0, 256, 264, 16, 240); // verified from schematics`
and `m_screen->screen_vblank().set_inputline(m_maincpu, INPUT_LINE_IRQ0, HOLD_LINE);`
=> 6 MHz / (384*264) = 59.19 Hz, one IRQ per vblank. game_speed_8233 = 4 (@2A44) and main loop spins on $80AB (@73F2)
=> logic tick = 4 frames = 67.6 ms, 14.8 ticks/s. Alarm 4096 ticks = 277 s; blackout 66 ticks = 4.46 s.

### Character vertical fields
+03 = bottom (feet) height, +02 = top height, in px inside a 48 px (0x30) floor cell. Standing: bottom 6, top 0x1D=29 (@439F).
Crouch: bottom 6, top 0x14=20 (@443F). Prone (enemies only, @4533-4557): top 0x0B=11, x-=5, width 0x12=18 px (normal 8 px).
Hit test @0920-0947: same floor, bullet height in [bottom, top), x overlap. DIP DSW3 bit6 = no hit.

### Otto jump (is_jumping_43F5 -> state 7 -> 4251/4266/42A7, table_42E2)
- delta_x fixed at start: -2/0/+2 px per tick (@43FA-440B); facing may change mid-air (@42A7), direction of travel may not.
- per tick feet dy: +7 +5 +7 +3 +2 +1 0 -1 -2 -3 -4 -5 -7 -7 ...; top = feet + 21 (frames 0,1,12+) or + 15 (tuck).
- apex: feet 6 -> 31 (+25 px) at tick 6; top 46. Landing when feet < 7 and frame >= 8 (@427B) => 14 ticks = 0.95 s.
- horizontal range 14*2 = 28 px (3.5 Otto widths).
- ceiling clip @4274: if top >= 0x30 (48) -> top forced to 0x2E and frame jumps to 8 (start of descent).
- shooting allowed while jumping (@4572: state 7 accepted).
- stepping out of an elevator uses a separate forced hop, table_44D8 (@446E), 14 frames, feet up to 0x1F.

### Bullets (handle_shoot_5054, table_50D8, update_bullet_4be7)
table_50D8 row = pose(+0C, >=7 -> -3)*2 + facing: [height above feet, x offset L/R, dx, sprite]
- pose 0/1 stand/walk: +15  -> 21 in the cell, 15 px above floor
- pose 2 crouch:       +9   -> 15 in the cell, 9 px above floor
- pose 3/4/5 (jump frames, move with feet): +12 / +12 / +6
- pose 6 (=9 prone):   +3   -> 9 in the cell, 3 px above floor, x offset 0x15 forward
- Otto bullet speed 8 px/tick (table byte F8/08), no wind-up ($82F6/7 = 0).
- enemy bullet speed = $834C px/tick = min(8, skill/4 + 6): 6 (buildings 1-4 at DIP0), 7 (5-8), 8 (9+); alarm +1 up to 8 (@463D).
- enemy wind-up before the bullet leaves = $82F8[enemy] = max(0, 10 - aggressivity) ticks (@1BDF, @1CA4).
- consequences: stand shot 21 misses crouched (top 20); crouch shot 15 misses prone (top 11); prone shot 9 hits standing/crouched.
  Jump: feet 13 after tick 1, 18 after tick 2, 25 after tick 3 => clears 9 at once, 15 from tick 2, 21 from ticks 3..~9.

### Enemy fire rate / pose choice (1BAA, 1C44, 1C7A, 1D3F)
- one bullet per enemy in flight (checks its slot ($85BD) is free).
- after shooting: +19 cooldown = max(0, 80 - 8*aggr) ticks (@0055, decremented @5B22) - only non-shooting actions meanwhile.
- action duration +10 = max(7, windup + 2) ticks.
- shooting pose by aggressivity (enemies 1-2, table_1D75, pairs of aggr): thresholds t1,t2,t3 /256 -> 4 stand-fire, 5 crouch-fire, 6 prone-fire, 7 other(walk+fire)
  aggr0-1 C4,C4,C4 | 2-3 80,C4,C4 | 4-5 40,C4,C4 | 6-7 20,80,C4 | 8-9 08,40,C4 | 10-11 08,20,C4 | 12-13 08,10,C4 | 14-15 00,08,C4
  => prone 0% (aggr<6), 27% (6-7), 52% (8-9), 64%, 70%, 73%; crouch peaks 52% at 4-5; 23% "other" always.
  enemies 3-4 (table_1D95): 40,40,40 ... 00,00,40 => 75% "other", 25% shooting, shifting to prone.
- pose 6 (prone) downgraded to crouch if x<0x10, x>=0xF0, or near shafts on floors 1-7 (@1CFC-1D3A).
- pose adjusted to Otto's height (@1CD8): Otto lower by > 8 px -> crouch-fire, Otto higher -> stand-fire (not when aggr 0).
- dodge (@05F5, odds_table_0659): Otto's bullet on the same floor, height 12..30, within 20 px: high (>=21) -> action 1 (crouch,
  85EF), low (<21) -> action 2 (down again = prone, 85CF), prone replaced by crouch near shafts/edges (@0669). Otto's prone-height
  bullets do not exist, so Otto's crouch shot is dodged only by lying down.
- no code path sets the jump bit ($10) for enemies => enemies do not jump by themselves; TCRF "jumping" frames are most likely the
  forced hop in/out of an elevator (table_44D8, shared by all characters). Confidence medium.

### Other speeds
- walk: +-2 px per tick for Otto and agents (same routine 4450/445F), 29.6 px/s; no difficulty or alarm term found.
- elevator: direction values +-2 (player_control_07 = $02/$FE @45D8/45E0, scroll_speed 2 "@03C3") => 2 px/tick, 24 ticks
  (1.6 s) per 48 px floor. Medium confidence.

## Part 3 (coordinator follow-up 2)

### Screen-space body box
+16 = sprite screen y of the feet, +15 = +16 + (top - bottom) (@61A4-61AD), updated only while the character is on screen
(screen y in 0x18..0xE7). Player copies: $8530 (= player+16), $852F (= player+15).

### Fire decision (should_enemy_shoot_0568)
1. unless alerted (+0E != 0): agent must face Otto (sign of Otto.x - agent.x == facing +0B) (@056E-057B).
2. Otto situation < 3: on ground, in cab or on cab roof; never while on an escalator (4), in a room (5) or falling (@057E).
3. vertical overlap of the screen boxes (@05E1-05F4): agent.feet <= Otto.feet < agent.head, or Otto.head >= agent.feet.
   => "same floor" for firing = bodies overlap in screen height, not the floor number; works for Otto in a moving cab.
4. wall check on floors 18 (x split 0x7D) and 20 (x split 0xAC): no firing across the wall (@0590-05E0).
- No |dx| test anywhere => the range is the whole floor width (the play area is 256 px wide, all on screen).
- plus the gates from Part 2: own bullet slot free, cooldown +19 == 0, action timer +10.

### Movement (enemy_walk_state_53F6, 5B33, 5D13, 04E6, 0434)
- target x in +1A, mode in +1C. Facing while walking = toward the target (@55F8-5601).
- Otto on another floor (@5B33): target = the elevator/escalator x of that floor from a per-floor table (table_5B93: 0x58/0x98,
  0x18/0xD8, 0x78, 0xC2...), with the parity of the enemy index choosing left/right; mode 3/0x0B.
- same floor (@5D13): mode 0x0D, target x = 0x40 + random(0..15); when reached (|dx| < 3, @5411-5419) -> pause 7 ticks, new
  target. => agents do not chase Otto horizontally; they stroll and fire whenever facing him (and always when alerted).
- random action/pause timer (@04E6-0528): 10 or 7 (+random) ticks between decisions, halved odds of long pause when alerted.
- despawn (@041F-04E5): if an agent on the ground is on a floor other than the dense one and its screen feet are >= 0x50 px
  (80 px, ~1.7 floors) from Otto's, and floor >= 8 and != 20, it gets mode 0x0C = walk to the nearest existing door and
  re-enter it (@55B0: situation IN_ROOM) => agents left behind go back into doors.
- walking speed 2 px/tick like Otto (Part 2). No "keep distance" logic found.

### Hitboxes and bullet hit (enemy_shot_collision_08F8)
- width: x_right = x + 8 for everybody (@43E1, @4495, @42BC); prone agent x-5 .. x+13 (18 px, @4541-4548).
- bullet hits when: bullet floor == character floor (+07) (@0920), bullet height in [bottom +03, top +02) (@0927-0931),
  and the character's leading edge lies in the segment swept this tick, +3 px margin (@0932-0947).
- character in/on a cab (situation 1/2): floor and height are recomputed from the cab position (@095C) => Otto in a cab can be hit.
- ignored: dying (+09 == 5), on escalator (situation 4, special check @0911-091F) - escalators are safe as the sources say.
- player bullet vs agents and agent bullet vs Otto use the same routine; DSW3 bit 6 disables hits on Otto (@08BB).

### Kick (@3127-3198)
- Otto in jump state (+09 == 7) and situation < 3 (ground, cab, roof).
- for each agent not dying and situation < 3: screen boxes overlap vertically (agent.head >= Otto.feet and agent.feet < Otto.head)
  and horizontally (agent.x < Otto.x_right and agent.x_right >= Otto.x).
- => any overlap during the whole jump (rising or falling) kills: 150 / 200 in dark (@56B9). Walking into an agent is harmless.
