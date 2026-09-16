class_name BuildingRules
extends Resource

## Правила, по которым собирается здание.
##
## В оригинале здания почти одинаковы и различаются расположением красных дверей
## (ADR-0008, пункт 2), поэтому зданием считается не список этажей, а эти правила
## плюс сид. Меняя правила от здания к зданию, в M5b получим нарастающую сложность.

## На сколько злее становятся агенты с каждым следующим зданием и докуда это
## растёт. Без потолка к двадцатому зданию дальность стрельбы обгоняет ширину
## самого здания, и агенты простреливают этаж насквозь откуда угодно.
## Сами значения потолков оригиналом не подтверждены.
const MENACE_PER_BUILDING: float = 0.2

## Общий потолок злости — со всеми надбавками разом, тревогу включая. Наложен
## в [method menace_with]: потолок на одной надбавке обходится второй, и по
## тревоге дальность выстрела уходила на 900 px при 1120 px полезного этажа —
## агент простреливал почти весь этаж, и хода игроку не оставалось.
const MENACE_CAP: float = 3.0

## Докуда злость растёт от самого здания. Ниже общего потолка намеренно: остаток
## оставлен тревоге, иначе на дальних зданиях сирена уже ничего не меняла бы.
const MENACE_BY_BUILDING_CAP: float = 2.0

## Крыша: уровень над зданием, с которого начинается спуск.
##
## Не этаж и потому не входит в [member floors]: на ней нет ни дверей, ни ламп,
## ни агентов, а над ней небо вместо перекрытия. Отдельный индекс, а не нулевой
## этаж, — ADR-0014, пункт 1: раньше нулевой был крышей и верхним этажом сразу,
## и просвет у него выходил 20 px вместо 100.
const ROOF: int = -1

## Этажей в здании, не считая крыши. Нулевой — верхний, последний — с выходом.
@export var floors: int = 30

## Высота этажа и толщина перекрытия, px.
@export var floor_height: float = 120.0
@export var slab_height: float = 20.0

## Сколько открытого неба над настилом крыши, px.
##
## Больше, чем этаж: Otto прыгает на 80 px, и над макушкой в верхней точке
## должно оставаться небо, а не кромка кадра. При 120 px он проходил впритык —
## шесть пикселей до края, и прыжок читался как удар головой о край экрана.
@export var sky_height: float = 160.0

## Ширина здания и отступ от стен, px.
@export var width: float = 1280.0
@export var margin: float = 80.0

## Сколько мест по горизонтали на самом широком уровне. Всё, что стоит на этаже,
## занимает место целиком, поэтому шахта, эскалатор, дверь и лампа не могут
## оказаться друг на друге.
##
## Места нумеруются глобально и стоят по всей высоте на одних и тех же x. Иначе
## шахта, проходящая сквозь этажи разной ширины, оказывалась бы на каждом из них
## в своём столбце (ADR-0014, пункт 3).
@export var slots: int = 9

## Мест на самом узком уровне — наверху здания. Ступеней в силуэте — [member width_steps].
##
## Профиль задаётся местами, а ширина выводится из них, а не наоборот: от ширины
## получались этажи, куда не влезало обязательное — шахта, две двери и лампа.
@export var top_slots: int = 5
@export var width_steps: int = 3

## Сколько этажей обслуживает одна шахта. Шахты не сквозные: доехал до предела —
## переходи к следующей, и в этом весь спуск (ADR-0008).
@export var shaft_span: int = 6

## Ширина шахты, она же ширина кабины: по краям не должно остаться щелей.
@export var shaft_width: float = 40.0

## Проём под эскалатор: на сколько он отступает от площадки и какой он ширины, px.
## Лежит здесь, а не в уровне, потому что по нему раскладка узнаёт, где в полу дыра:
## иначе геометрия проёма была бы записана дважды и разъехалась бы.
@export var escalator_gap_offset: float = 16.0
@export var escalator_gap_width: float = 60.0

## На сколько эскалатор уводит в сторону, спускаясь на этаж, px.
@export var escalator_run: float = 96.0

## Красных дверей на здание. Пять — по Hardcore Gaming 101, единственному
## источнику, который называет число. Не сверено.
@export var documents: int = 5

## Дверей на этаже, считая красную, — на широких этажах внизу.
@export var doors_per_floor: int = 2

## Дверей на самых узких этажах, наверху здания.
##
## Источники описывают верх как редко заселённый, а низ — как тесный и злой.
## Раньше двери стояли поровну по всей высоте, и спуск начинался с той же
## плотности огня, какой он кончается (ADR-0014, пункт 3).
@export var top_doors: int = 1

## Ламп на этаже.
@export var lamps_per_floor: int = 1

## Насколько агенты злее обычного: множитель к дальности, скорострельности и
## скорости, с которой дверь выпускает следующего. Растёт от здания к зданию.
@export var agent_menace: float = 1.0


## Правила очередного здания: дальше — злее агенты. Остальные способы роста
## сложности из оригинала отложены, см. ADR-0009, пункт 2.
static func for_building(number: int) -> BuildingRules:
	var rules := BuildingRules.new()
	var grown := 1.0 + MENACE_PER_BUILDING * float(maxi(number, 1) - 1)
	rules.agent_menace = minf(grown, MENACE_BY_BUILDING_CAP)
	return rules


## Итоговая злость агентов прямо сейчас: рост от здания к зданию, помноженный
## на надбавку за тревогу ([param alarm_multiplier], 1.0 — сирены нет).
##
## Считается здесь, а не в уровне, чтобы потолок был один на оба источника
## и проверялся без сцены.
func menace_with(alarm_multiplier: float) -> float:
	# Нижняя граница та же, что у [method Enemy.set_menace]: на это число делится
	# задержка смены агента, и ноль из инспектора оставил бы дверь запертой навсегда.
	return minf(maxf(agent_menace, 0.1) * alarm_multiplier, MENACE_CAP)


## Координата места по горизонтали.
func slot_x(slot: int) -> float:
	if slots <= 1:
		return width * 0.5
	var usable := width - margin * 2.0
	return margin + usable * float(slot) / float(slots - 1)


## Поверхность уровня, на которой стоят: [constant ROOF] — настил крыши,
## нулевой — верхний этаж здания.
##
## Одна формула на крышу и на этажи: крыша — это [code]index = -1[/code], и
## отдельного счёта ей не нужно. Так просвет у всех уровней выходит одинаковым,
## чего не было, пока крышей работал нулевой этаж (ADR-0014, пункт 1).
func floor_surface(index: int) -> float:
	return sky_height + floor_height * float(index + 1)


## Высота здания целиком, px. Небо над крышей входит: это часть мира,
## по которой ходит камера.
func total_height() -> float:
	return floor_surface(floors - 1) + slab_height


## Ближайший уровень к точке по вертикали. Может вернуть [constant ROOF].
func floor_index_near(y: float) -> int:
	var raw := roundf((y - sky_height) / floor_height) - 1.0
	return clampi(int(raw), ROOF, floors - 1)


## Потолок уровня: низ перекрытия сверху. У крыши потолка нет — над ней небо,
## и полоса отмеряется от верха мира.
func story_top(index: int) -> float:
	return 0.0 if index <= ROOF else floor_surface(index - 1) + slab_height


## Все уровни сверху вниз, крышу включая. Один обход на весь проект: обойти
## [code]range(floors)[/code] и забыть крышу — ровно та ошибка, из-за которой
## на ней стояли двери.
func levels() -> Array[int]:
	var all: Array[int] = []
	for index in range(ROOF, floors):
		all.append(index)
	return all


## Ступень силуэта, на которой стоит уровень: 0 — самая узкая, наверху.
func width_step(index: int) -> int:
	var steps := maxi(width_steps, 1)
	if steps <= 1:
		return 0
	# Считается по порядковому номеру уровня, а не по номеру этажа: крыша идёт
	# нулевой, иначе она попадала бы на ступень ниже собственного верхнего этажа.
	var ordinal := index - ROOF
	var total := floors - ROOF
	return clampi(int(float(ordinal) * float(steps) / float(maxi(total, 1))), 0, steps - 1)


## Сколько мест вправо и влево от середины доступно на уровне.
##
## Счёт идёт полушириной, поэтому число мест всегда нечётное и они лежат
## симметрично: этаж с чётным числом мест был бы сдвинут относительно
## проходящей сквозь него шахты.
func slot_reach(index: int) -> int:
	var full := (slots - 1) / 2
	var narrow := clampi((top_slots - 1) / 2, 0, full)
	var steps := maxi(width_steps, 1)
	if steps <= 1:
		return full
	var grown := float(narrow) + float(full - narrow) * float(width_step(index)) / float(steps - 1)
	return clampi(int(roundf(grown)), narrow, full)


## Первое и последнее доступное место уровня, включительно.
func slot_range(index: int) -> Vector2i:
	var middle := (slots - 1) / 2
	var reach := slot_reach(index)
	return Vector2i(maxi(middle - reach, 0), mini(middle + reach, slots - 1))


## Стоит ли место на этом уровне. За границами силуэта места нет: там улица.
func slot_available(slot: int, index: int) -> bool:
	var span := slot_range(index)
	return slot >= span.x and slot <= span.y


## Границы уровня: внешние края стен, левый и правый.
##
## Выводятся из крайних доступных мест, а не из доли ширины: место должно
## отстоять от стены на [member margin], как и на здании во всю ширину.
func floor_span(index: int) -> Vector2:
	var span := slot_range(index)
	return Vector2(slot_x(span.x) - margin, slot_x(span.y) + margin)


## Сколько дверей на этаже. Наверху реже, внизу плотнее — той же ступенью,
## что и ширина: узкий этаж и заселён скупо.
func doors_on(index: int) -> int:
	var most := maxi(doors_per_floor, 0)
	var fewest := clampi(top_doors, 0, most)
	return clampi(fewest + width_step(index), fewest, most)


## Ширина уровня, px.
func floor_width(index: int) -> float:
	var span := floor_span(index)
	return span.y - span.x
