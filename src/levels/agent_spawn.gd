class_name AgentSpawn
extends RefCounted

## Жребий выпуска агентов по правилам ROM: ячейки, этаж, дверь (ADR-0027, решение 2).
##
## Своим классом, а не в уровне: уровень знает двери, этажи и Otto, а сколько
## агентов может жить и кто выходит следующим — правило, и проверяется оно без
## сцены. ROM держит четыре ячейки агентов (@594D): занятыми бывают три или
## четыре, и освободившаяся ждёт смены по сложности (@3866).

## Ячеек агентов: столько держит ROM. Ручной потолок здания ([member
## BuildingRules.agents_at_once_cap]) может просить больше — тогда ячейки
## добавляются в [method open_slot], иначе он молча упирался бы в четыре.
const SLOTS: int = 4

## Генератор жребия: свой у здания и посеянный его сидом — прогон бота
## повторяется до шага.
var rng := RandomNumberGenerator.new()

var _busy: Array[bool] = [false, false, false, false]
var _wait: Array[float] = [0.0, 0.0, 0.0, 0.0]
## Сколько накопилось до следующего тика жребия, с.
var _clock: float = 0.0


## Отсчитывает время. Возвращает true в тот кадр, когда подошёл тик логики:
## жребий в ROM бросается раз в тик, а не раз в кадр — иначе на 60 Гц он шёл
## бы вчетверо чаще, а на 30 вдвое реже.
func tick(delta: float) -> bool:
	for index in _wait.size():
		_wait[index] = maxf(_wait[index] - delta, 0.0)
	_clock += delta
	if _clock < Arcade.TICK:
		return false
	_clock = fmod(_clock, Arcade.TICK)
	return true


## Свободная ячейка из первых [param available] или -1: занятая или ещё ждущая
## смены не годится.
##
## [param lead] — сколько до конца смены ячейка уже годится. Столько идёт
## створка двери: она начинает открываться в конце смены, и агент выходит там,
## где ROM его и выпускает, а не на ход створки позже (ADR-0028, решение 7).
func open_slot(available: int, lead: float = 0.0) -> int:
	while _busy.size() < available:
		_busy.append(false)
		_wait.append(0.0)
	for index in available:
		if not _busy[index] and _wait[index] <= lead:
			return index
	return -1


## Занимает ячейку: агент в ней выходит или вышел.
func take(slot: int) -> void:
	_busy[slot] = true


## Освобождает ячейку: смена в ней придёт через паузу по сложности [param level].
func release(slot: int, level: int) -> void:
	if slot < 0 or slot >= _busy.size():
		return
	_busy[slot] = false
	_wait[slot] = Arcade.respawn_wait(level)


## Этаж жребия: этаж Otto, выше или ниже, а с шансом по сложности — именно
## этаж Otto (@5A4C).
func pick_floor(here: int, level: int) -> int:
	var floor_index := here + rng.randi_range(-1, 1)
	if rng.randf() < Arcade.own_floor_chance(level):
		floor_index = here
	return floor_index


## Случайный из годных; годных нет — -1.
func pick(count: int) -> int:
	return -1 if count <= 0 else rng.randi_range(0, count - 1)
