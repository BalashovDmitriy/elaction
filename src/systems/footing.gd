class_name Footing
extends RefCounted

## Сцепление ног с полом (ADR-0054, решение 4). На сухом полу шаг — как в ROM:
## скорость ходьбы сразу, остановка сразу. На заснеженной крыше ноги держат
## хуже: Otto и агенты разгоняются и тормозят с конечным сцеплением и
## проскальзывают на остановке и развороте.

## Группа Otto: по ней снег крыши ([SnowTracks]) находит, кто ходит по настилу.
const OTTO_GROUP := &"otto"

## Разгон и торможение на снегу, м/с²: шаг ROM — 2.2 м/с, и с ходу на снегу
## встают за четверть секунды, проехав около четверти метра.
const SNOW_GRIP: float = 9.0


## Скорость по горизонтали на этот шаг: [param wanted] — та, что задают ноги,
## [param current] — та, что есть. На сухом — сразу, на снегу ([param icy]) —
## не быстрее сцепления.
static func step(current: float, wanted: float, icy: bool, delta: float) -> float:
	if not icy:
		return wanted
	return move_toward(current, wanted, SNOW_GRIP * delta)
