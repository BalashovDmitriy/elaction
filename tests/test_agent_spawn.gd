extends GutTest

## Agent release cells by the ROM (ADR-0027, decision 2): an occupied cell and one waiting for a
## change do not fit, and a manual cap of runs above the ROM's four cells gets its own.


func test_a_taken_slot_is_not_offered_again() -> void:
	var spawn := AgentSpawn.new()
	var first := spawn.open_slot(3)
	assert_gt(first, -1, "свободная нашлась")
	spawn.take(first)
	assert_ne(spawn.open_slot(3), first, "занятую второй раз не дают")


## A freed cell waits for a change by difficulty (@3866), and only then is it usable.
func test_a_released_slot_waits_for_its_shift() -> void:
	var spawn := AgentSpawn.new()
	for slot: int in 3:
		spawn.take(slot)
	spawn.release(0, 0)
	assert_eq(spawn.open_slot(3), -1, "смена ещё не пришла")
	for _tick: int in int(ceilf(Arcade.respawn_wait(0) / Arcade.TICK)) + 1:
		spawn.tick(Arcade.TICK)
	assert_eq(spawn.open_slot(3), 0, "пришла — ячейка снова годна")


## `tools/playthrough.gd --at-once=8`: a cap above the ROM's four cells does not silently run into
## them.
func test_a_manual_cap_above_the_rom_gets_its_slots() -> void:
	var spawn := AgentSpawn.new()
	for _agent: int in 8:
		var slot := spawn.open_slot(8)
		assert_gt(slot, -1, "ячейка нашлась")
		spawn.take(slot)
	assert_eq(spawn.open_slot(8), -1, "девятой нет")


## Telegraph at the end of the change (ADR-0028, decision 7): a cell becomes usable one leaf
## movement before the end of the change, and the agent comes out when the change has ended, not 0.7
## s later.
func test_a_slot_opens_a_door_travel_before_its_shift_ends() -> void:
	var spawn := AgentSpawn.new()
	for slot: int in 3:
		spawn.take(slot)
	spawn.release(0, 0)
	var wait := Arcade.respawn_wait(0)
	spawn.tick(wait - Door.AGENT_OPEN_TIME - 0.05)
	assert_eq(spawn.open_slot(3, Door.AGENT_OPEN_TIME), -1, "до хода створки ещё рано")
	spawn.tick(0.1)
	assert_eq(spawn.open_slot(3, Door.AGENT_OPEN_TIME), 0, "створка пошла в конце смены")
	assert_eq(spawn.open_slot(3), -1, "без упреждения смена ещё идёт")
