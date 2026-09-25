class_name DoorWatch
extends RefCounted

## Агент у двери, за которой спрятался Otto: кто пойдёт ждать и где встанет.
##
## В ROM этого нет — решение пользователя (ADR-0038, решение 2): агенты, потерявшие
## Otto на его этаже, иногда подходят к его двери и ждут, пока он внутри. Вышел —
## агент снова живёт как жил, и скорее всего тут же стреляет: в этом и смысл.
##
## Ни узлов, ни физики — факты об агенте приходят снаружи, ответ — координата,
## где ждать, или NAN. Поэтому правило проверяется без сцены, как [EnemyBrain] и
## [AgentLifts]. Уровень держит один такой объект на здание: Otto прячется разом
## только за одной дверью.
##
## Жребий — у агента один на визит: при первом взгляде на него, пока Otto
## внутри. Выпало «нет» — этот агент к этой двери в этот раз не пойдёт, сколько
## бы кадров ни прошло; иначе жребий за кадр дал бы «иногда» у каждого за
## секунду. Генератор свой, не выпуска агентов: заберись он в тот, прогон бота
## поменялся бы и там, где Otto ни в одну дверь не заходил.

## Шанс агента пойти к двери. Выбран, а не замерен: «иногда» — каждый второй.
const CHANCE: float = 0.5

## Насколько от середины двери агент встаёт ждать, м: край коврика, полкорпуса
## и зазор. На коврик он не встаёт — Otto выходит туда, — и до коврика соседнего
## места при шаге сетки 1.8 м тоже не достаёт.
const STANDOFF: float = Proportions.DOOR_MAT * 0.5 + Proportions.BODY_WIDTH * 0.5 + 0.15

## Генератор жребия. Сеет уровень от сида здания: прогон повторяется до шага.
var rng := RandomNumberGenerator.new()

## Этаж и середина двери, за которой Otto; этаж −1 — Otto ни за какой.
var _floor: int = -1
var _door_x: float = NAN
## Кто ждёт у двери: id экземпляра агента, 0 — никто.
var _watcher: int = 0
## Видели ли ждущего в этом кадре. Не видели — он убит, ушёл или его убрал уровень:
## место у двери освобождается, и помнить об этом никому снаружи не надо.
var _watcher_seen: bool = false
## Кому жребий уже брошен в этот визит: id → true.
var _rolled: Dictionary = {}


## Otto спрятался за дверью с серединой [param door_x] на этаже [param floor_index].
func begin(floor_index: int, door_x: float) -> void:
	_floor = floor_index
	_door_x = door_x
	_watcher = 0
	_watcher_seen = false
	_rolled.clear()


## Otto вышел: ждать больше некого.
func end() -> void:
	_floor = -1
	_door_x = NAN
	_watcher = 0
	_rolled.clear()


## Спрятан ли Otto на этаже [param floor_index]. Уровень спрашивает, прежде чем
## считать преграды этажа: для остальных этажей они не нужны.
func covers(floor_index: int) -> bool:
	return _floor >= 0 and floor_index == _floor


## Середина двери, за которой Otto, или NAN.
func door_x() -> float:
	return _door_x


## Кто ждёт у двери: id экземпляра агента или 0.
func watcher() -> int:
	return _watcher


## Начало кадра: уровень дальше спросит [method post_for] про каждого живого.
func start_frame() -> void:
	if not _watcher_seen:
		_watcher = 0
	_watcher_seen = false


## Где ждать агенту [param agent] на этаже [param floor_index] в точке [param x],
## или NAN — ждать ему незачем.
##
## [param blocks] — что режет этаж для ходьбы ([method BuildingPlan.blocks_on]):
## за проём или стену между ним и дверью агент не ходит, а место в проёме
## ждать не годится.
func post_for(agent: int, floor_index: int, x: float, blocks: Array[Vector2]) -> float:
	if agent == _watcher and _watcher != 0:
		if floor_index != _floor:
			# Уехал или упал с этажа: место свободно, второй раз он не пойдёт.
			_watcher = 0
			return NAN
		_watcher_seen = true
		return spot(x)
	if not covers(floor_index) or _watcher != 0 or _rolled.has(agent):
		return NAN
	var post := spot(x)
	if not _walks(blocks, x, post):
		return NAN
	_rolled[agent] = true
	if rng.randf() >= CHANCE:
		return NAN
	_watcher = agent
	_watcher_seen = true
	return post


## Место ожидания для агента, стоящего в [param x]: с его стороны двери.
func spot(x: float) -> float:
	var side := 1.0 if x >= _door_x else -1.0
	return _door_x + side * STANDOFF


## Дойдёт ли агент из [param x] до места [param post] и видна ли оттуда дверь:
## ни проёма, ни стены на всём отрезке от агента до двери через место.
func _walks(blocks: Array[Vector2], x: float, post: float) -> bool:
	var low := minf(minf(x, post), _door_x)
	var high := maxf(maxf(x, post), _door_x)
	for block: Vector2 in blocks:
		if maxf(block.x, block.y) > low and minf(block.x, block.y) < high:
			return false
	return true
