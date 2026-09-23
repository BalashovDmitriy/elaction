extends GutTest

## Ячейки выпуска агентов по ROM (ADR-0027, решение 2): занятая и ждущая смены
## не годятся, а ручной потолок прогонов сверх четырёх ячеек ROM получает свои.


func test_a_taken_slot_is_not_offered_again() -> void:
	var spawn := AgentSpawn.new()
	var first := spawn.open_slot(3)
	assert_gt(first, -1, "свободная нашлась")
	spawn.take(first)
	assert_ne(spawn.open_slot(3), first, "занятую второй раз не дают")


## Освободившаяся ячейка ждёт смены по сложности (@3866), и только потом годна.
func test_a_released_slot_waits_for_its_shift() -> void:
	var spawn := AgentSpawn.new()
	for slot: int in 3:
		spawn.take(slot)
	spawn.release(0, 0)
	assert_eq(spawn.open_slot(3), -1, "смена ещё не пришла")
	for _tick: int in int(ceilf(Arcade.respawn_wait(0) / Arcade.TICK)) + 1:
		spawn.tick(Arcade.TICK)
	assert_eq(spawn.open_slot(3), 0, "пришла — ячейка снова годна")


## `tools/playthrough.gd --at-once=8`: потолок сверх четырёх ячеек ROM не
## упирается в них молча.
func test_a_manual_cap_above_the_rom_gets_its_slots() -> void:
	var spawn := AgentSpawn.new()
	for _agent: int in 8:
		var slot := spawn.open_slot(8)
		assert_gt(slot, -1, "ячейка нашлась")
		spawn.take(slot)
	assert_eq(spawn.open_slot(8), -1, "девятой нет")


## Телеграф в конце смены (ADR-0028, решение 7): ячейка годится за ход створки
## до конца смены, и агент выходит, когда смена кончилась, а не на 0.7 с позже.
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
