class_name BuildingRules
extends Resource

## Правила, по которым собирается здание.
##
## В оригинале здания почти одинаковы и различаются расположением красных дверей
## (ADR-0008, пункт 2), поэтому зданием считается не список этажей, а эти правила
## плюс сид. Меняя правила от здания к зданию, в M5b получим нарастающую сложность.

## Этажей в здании. Нулевой — крыша, последний — первый этаж с выходом.
@export var floors: int = 30

## Высота этажа и толщина перекрытия, px.
@export var floor_height: float = 120.0
@export var slab_height: float = 20.0

## Ширина здания и отступ от стен, px.
@export var width: float = 1280.0
@export var margin: float = 80.0

## Сколько мест по горизонтали. Всё, что стоит на этаже, занимает место целиком,
## поэтому шахта, эскалатор, дверь и лампа не могут оказаться друг на друге.
@export var slots: int = 9

## Сколько этажей обслуживает одна шахта. Шахты не сквозные: доехал до предела —
## переходи к следующей, и в этом весь спуск (ADR-0008).
@export var shaft_span: int = 6

## Красных дверей на здание. Пять — по Hardcore Gaming 101, единственному
## источнику, который называет число. Не сверено.
@export var documents: int = 5

## Дверей на этаже, считая красную.
@export var doors_per_floor: int = 2

## Ламп на этаже.
@export var lamps_per_floor: int = 1


## Координата места по горизонтали.
func slot_x(slot: int) -> float:
	if slots <= 1:
		return width * 0.5
	var usable := width - margin * 2.0
	return margin + usable * float(slot) / float(slots - 1)


## Поверхность этажа: нулевой этаж — самый верхний.
func floor_surface(index: int) -> float:
	return slab_height + float(index) * floor_height


## Высота здания целиком, px.
func total_height() -> float:
	return floor_surface(floors - 1) + slab_height


## Ближайший этаж к точке по вертикали.
func floor_index_near(y: float) -> int:
	var raw := roundf((y - slab_height) / floor_height)
	return clampi(int(raw), 0, floors - 1)


## Потолок этажа: низ перекрытия сверху, у самого верхнего — край здания.
func story_top(index: int) -> float:
	return 0.0 if index <= 0 else floor_surface(index - 1) + slab_height
