class_name EscalatorSpot
extends RefCounted

## Эскалатор ведёт с [member floor_index] на следующий этаж вниз.
##
## Своим файлом с M24h: [BuildingPlan] упёрся в предел строк, а до того это
## был его внутренний класс.

## Насколько перегиб ломаной отступает внутрь проёма от его ближнего края, м.
##
## Сквозь дыру проходит не линия пути, а пассажир: он шире её на полкорпуса,
## и отступ обязан быть больше. Запас — 0.15 м, и его стережёт
## [code]test_escalator_carries_its_rider_through_the_gap[/code].
const BEND_CLEARANCE: float = Proportions.BODY_WIDTH * 0.5 + 0.15
## Запас над головой едущего, пока пролёт уходит под плиту, м.
const HEAD_CLEARANCE: float = 0.25

var x: float = 0.0
var floor_index: int = 0
## Куда спускается полотно: -1 влево, +1 вправо. С M24g — всегда к краю
## этажа (ADR-0043, решение 15).
var towards: float = -1.0
## Край этажа, к которому эскалатор спускается: там кончается проём.
var edge: float = 0.0


## Проём в перекрытии под полотном: пара «левый край, правый край».
##
## Дыра не под площадкой, а сбоку от неё, по ходу спуска, и тянется до края
## этажа: пролёт под 45° уходит под плиту на два с лишним метра, и остаток
## пола за ним был бы островом, куда не дойти. Считается здесь, чтобы
## уровень и [method BuildingPlan.safe_x] видели один и тот же проём.
func gap(rules: BuildingRules) -> Vector2:
	var near := x + towards * rules.escalator_gap_offset
	return Vector2(minf(near, edge), maxf(near, edge))


## Дыра в перекрытии, сквозь которую проходит пролёт: пара «левый край,
## правый край», в задней полосе коридора (ADR-0044, решение 10).
##
## Короче [method gap]: тот — место, которое раскладка держит под
## эскалатором, от площадки до края этажа, и по нему по-прежнему стоят
## двери, лампы и мебель. Пол с M24h цельный, и дыра нужна лишь там, где
## пролёт проходит сквозь плиту: пока голова едущего не ушла под неё.
##
## Голове надо уйти вниз на рост, плиту и запас; по горизонтали — это, делённое
## на уклон правил ([member BuildingRules.escalator_angle]), а не 45° молча
## (авторевью M24h). Пролёт от перегиба круче уклона правил — запас выходит сам.
func hole(rules: BuildingRules) -> Vector2:
	var near := x + towards * rules.escalator_gap_offset
	var drop := Proportions.BODY + rules.slab_height + HEAD_CLEARANCE
	var reach := BEND_CLEARANCE + drop * rules.escalator_run / rules.floor_height
	var far := near + towards * minf(reach, absf(edge - near))
	return Vector2(minf(near, far), maxf(near, far))


## Нижняя площадка — на этаже ниже, у края.
func landing(rules: BuildingRules) -> float:
	return x + towards * rules.escalator_run


## Перегиб ломаной в своих координатах: где площадка кончается и начинается
## пролёт.
##
## До M18b перегиб стоял посреди проёма и ниже перекрытия, и ломаная шла
## двумя пролётами разной крутизны — в кадре это читалось жёлобом, а не
## эскалатором (ADR-0025, решение 4). Теперь до проёма идёт площадка по
## этажу, а от его ближнего края — один прямой пролёт вниз.
##
## Считается здесь, рядом с проёмом, через который проходит: уровень ставит
## по этому числу конструкцию, тест по нему же проверяет, что пассажир идёт
## сквозь дыру, а не сквозь плиту.
func bend(rules: BuildingRules) -> Vector2:
	return Vector2(towards * (rules.escalator_gap_offset + BEND_CLEARANCE), 0.0)
