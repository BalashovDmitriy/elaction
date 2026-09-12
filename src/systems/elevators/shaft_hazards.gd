class_name ShaftHazards
extends RefCounted

## Правила гибели в шахте лифта.
##
## Физику определяют узлы, а решение «жив или нет» принимается здесь: так его
## видно в одном месте и можно проверить тестами. Основания — в ADR-0004.


## Смертельно ли попадание на дно шахты.
##
## Упасть в открытый проём — смерть; войти на этаж ногами или приехать в кабине —
## нет. Одного факта опоры мало: нижний этаж сплошной, и собственный прыжок над
## шахтой приземляется в ту же зону уже в воздухе. Поэтому смотрим и на глубину:
## своим прыжком Otto поднимается на [param survivable_height], значит всё, что
## глубже, — падение с этажа выше.
static func is_deadly_fall(
	grounded: bool, riding: bool, fall_height: float, survivable_height: float
) -> bool:
	return not grounded and not riding and fall_height > survivable_height


## Раздавит ли кабина того, кто попал ей под днище.
##
## Само перекрытие областей проверяет узел; здесь решается остальное. Смертельно
## сочетание трёх вещей: кабина идёт вниз, деться жертве некуда (она стоит на
## полу) и это не пассажир — тот стоит на полу кабины и едет с ней заодно.
##
## Флагами [code]is_on_ceiling[/code] это не ловится: кабина двигает игрока
## физическим сервером, а флаг выставляет только собственный move_and_slide.
static func crushes(car_speed: float, victim_grounded: bool, victim_is_passenger: bool) -> bool:
	return car_speed > 0.0 and victim_grounded and not victim_is_passenger
