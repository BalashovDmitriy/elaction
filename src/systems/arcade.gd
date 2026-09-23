class_name Arcade
extends RefCounted

## Правила аркадного ROM — боя и здания — одной таблицей.
##
## Числа и формулы взяты из аннотированного дизассемблера ROM (jotd, перенос на
## Amiga); выводы с адресами — в `docs/reference/arcade-rom.md`, решения — в
## [ADR-0027](../../docs/adr/0027-rom-combat.md) и
## [ADR-0028](../../docs/adr/0028-building-by-the-map.md). Адрес рядом с числом — место
## в `src/elevator_z80.asm` того проекта: по нему число перепроверяется.
##
## Оригинал считает в тиках логики: кадр 59.19 Гц (драйвер MAME `taitosj`),
## логика раз в четыре кадра. Таблица отдаёт секунды и метры, а тики держит
## у себя: так формула читается рядом с ROM, а остальной код о тиках не знает.
##
## Здесь — правила, а не размеры: высоты стоек и пуль лежат в [Proportions].

## Поза, в которой агент стреляет.
enum Pose { STAND, CROUCH, PRONE, ON_THE_MOVE }

## Секунд в тике логики: 4 кадра по 1/59.19 с.
const TICK: float = 4.0 / 59.19

## Потолок сложности и злости (@592F, @5AFC).
const TOP: int = 15

## Тревога: 4096 тиков, ~277 с (@466E).
const ALARM_TICKS: int = 4096

## Шаг ходьбы Otto и агента, px за тик (@4450/@445F) — одна процедура на обоих.
const WALK_PX: float = 2.0

## Пуля Otto, px за тик (table_50D8).
const OTTO_BULLET_PX: float = 8.0

## Кабина, px за тик (@45D8).
const CAR_PX: float = 2.0

## Сколько тиков действует тревога агентов после выстрела Otto или посадки
## агента в кабину (@59C8, @1AED).
const ALERT_TICKS: int = 90

## Насколько близко пуля Otto должна подлететь, чтобы агент от неё уворачивался,
## px (@05F5).
const DODGE_REACH_PX: float = 20.0

## В какой полосе над полом пуля Otto заставляет агента уворачиваться, px
## (@05F5): выше и ниже она проходит мимо и так.
const DODGE_BAND_PX := Vector2(6.0, 24.0)

## Шанс увернуться за тик по злости, из 256 (odds_table_0659).
const DODGE_ODDS: Array[int] = [0, 0, 2, 2, 4, 8, 16, 16, 32, 32, 64, 64, 96, 128, 196, 255]

## Выбор позы выстрела по злости — пороги из 256 для пар злости (table_1D75 для
## агентов 1–2, table_1D95 для 3–4). Бросок ниже первого — стоя, ниже второго —
## присев, ниже третьего — лёжа, выше — выстрел на ходу.
const POSE_THRESHOLDS: Array[Vector3i] = [
	Vector3i(0xC4, 0xC4, 0xC4),
	Vector3i(0x80, 0xC4, 0xC4),
	Vector3i(0x40, 0xC4, 0xC4),
	Vector3i(0x20, 0x80, 0xC4),
	Vector3i(0x08, 0x40, 0xC4),
	Vector3i(0x08, 0x20, 0xC4),
	Vector3i(0x08, 0x10, 0xC4),
	Vector3i(0x00, 0x08, 0xC4),
]
const POSE_THRESHOLDS_LATE: Array[Vector3i] = [
	Vector3i(0x40, 0x40, 0x40),
	Vector3i(0x30, 0x40, 0x40),
	Vector3i(0x20, 0x40, 0x40),
	Vector3i(0x18, 0x30, 0x40),
	Vector3i(0x10, 0x20, 0x40),
	Vector3i(0x08, 0x10, 0x40),
	Vector3i(0x00, 0x08, 0x40),
	Vector3i(0x00, 0x00, 0x40),
]

## Этажей в здании оригинала. Считаются снизу: первый — нижний, тридцатый —
## верхний; нулевой — подвал с машиной, его у нас нет (ADR-0028, решение 1).
const FLOORS: int = 30

## Двери этажа — маска восьми мест, этаж 0..30 (table_280E). Здание оригинала
## одно, и двери в нём стоят на одних и тех же местах в каждом раунде.
const DOOR_MASKS: Array[int] = [
	0x00,
	0x81,
	0x81,
	0x81,
	0x81,
	0x81,
	0x81,
	0x00,
	0x7E,
	0x7E,
	0x66,
	0x66,
	0xE6,
	0x7E,
	0x7F,
	0x67,
	0xE6,
	0x66,
	0x7E,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
	0x66,
]

## Тёмные этажи: ламп на них нет вовсе (@2719), убийство стоит как в темноте
## (@56A1).
const DARK_FLOORS := Vector2i(11, 15)

## Полосы красных дверей: этажи ROM включительно и сколько красных в полосе по
## навыку 0..8 (@27D2, таблицы @282D–@2874). На этаже не больше одной.
const RED_DOOR_BANDS: Array[Vector2i] = [
	Vector2i(1, 6),
	Vector2i(8, 8),
	Vector2i(9, 11),
	Vector2i(12, 14),
	Vector2i(15, 17),
	Vector2i(18, 20),
	Vector2i(21, 25),
	Vector2i(26, 30),
]

## Квоты красных дверей по полосам [constant RED_DOOR_BANDS] и навыку 0..8.
##
## Строки — [Array], а не [PackedInt32Array]: константа из литералов под типом
## упакованного массива читается по индексу мусором (Godot 4.7).
const RED_DOOR_QUOTAS: Array[Array] = [
	[0, 1, 2, 2, 2, 2, 3, 4, 5],
	[0, 0, 0, 1, 1, 1, 1, 1, 1],
	[2, 2, 2, 1, 1, 2, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[1, 1, 1, 1, 1, 1, 1, 1, 1],
	[0, 0, 0, 1, 1, 1, 1, 1, 0],
	[0, 0, 0, 0, 1, 1, 1, 0, 0],
]

## Выше этого навыка квоты красных дверей не растут (@27D6).
const RED_DOOR_SKILL_TOP: int = 8


## Тики в секунды.
static func seconds(ticks: float) -> float:
	return ticks * TICK


## Секунды в тики.
static func ticks(time: float) -> float:
	return time / TICK


## Скорость в метрах в секунду по шагу в пикселях за тик.
static func speed(px_per_tick: float) -> float:
	return px_per_tick * Proportions.PX / TICK


## Навык партии: уровень сложности (DIP 0–3) плюс пройденные здания (@2EAD, @0A0A).
static func skill(level: int, building: int) -> int:
	return maxi(level, 0) + maxi(building - 1, 0)


## Сложность сейчас: навык плюс время в здании (compute_difficulty_592F).
##
## До тревоги +1 каждые 1024 тика (~69 с), после — каждые 256 (~17 с).
static func difficulty(skill_level: int, time: float) -> int:
	var msb := int(ticks(time) / 256.0)
	var grown := msb - 12 if msb >= 16 else msb / 4
	return mini(TOP, skill_level + grown)


## Злость агента: при выходе — сложность, потом +1 каждые 256 тиков (@5AA4, @5AFC).
static func aggression(at_spawn: int, age: float) -> int:
	return mini(TOP, at_spawn + int(ticks(age) / 256.0))


## Сколько агентов в здании разом: 3, а 4 — когда навык·4 + время ≥ 14 (@594D).
static func agents_at_once(skill_level: int, time: float) -> int:
	var msb := int(ticks(time) / 256.0)
	return 4 if skill_level * 4 + msb >= 14 else 3


## Сколько агентов разом на этаже возле Otto: 1 первые ~51 с, 2 до ~3.4 мин,
## потом 3 (@5905). Пока Otto не на полу и тревоги агентов нет — 1 (@59F4).
static func agents_per_floor(time: float, otto_on_foot: bool, alert: bool) -> int:
	if not otto_on_foot or not alert:
		return 1
	var msb := int(ticks(time) / 256.0)
	if msb < 3:
		return 1
	return 2 if msb < 12 else 3


## Шанс, что агент выйдет именно на этаже Otto, из 1 (@5A4C).
static func own_floor_chance(level: int) -> float:
	return float(level * 4) / 256.0


## Сколько дверь ждёт смены после агента, с: max(0, 80 − 6·сложность) (@3866).
static func respawn_wait(level: int) -> float:
	return seconds(maxi(0, 0x50 - 6 * level))


## Замах перед выстрелом, с: max(0, 10 − злость) тиков (@1BDF).
static func wind_up(anger: int) -> float:
	return seconds(maxi(0, 10 - anger))


## Пауза после выстрела, с: max(0, 80 − 8·злость) тиков (@0055).
static func cooldown(anger: int) -> float:
	return seconds(maxi(0, 80 - 8 * anger))


## Сколько длится действие агента — выстрел или увёртка, с: max(7, замах + 2)
## тиков (@1C7A).
static func action_time(anger: int) -> float:
	return seconds(maxi(7, maxi(0, 10 - anger) + 2))


## Скорость пули агента, м/с: min(8, навык/4 + 6) px за тик, в тревоге на шаг
## быстрее, но не выше 8 (@463D).
static func agent_bullet_speed(skill_level: int, alarmed: bool) -> float:
	var step := mini(8, skill_level / 4 + 6)
	if alarmed:
		step = mini(8, step + 1)
	return speed(float(step))


## Поза выстрела по злости и броску 0..255. [param late] — агенты 3–4, у них
## своя таблица: они чаще стреляют на ходу.
static func fire_pose(anger: int, roll: int, late: bool = false) -> Pose:
	var table := POSE_THRESHOLDS_LATE if late else POSE_THRESHOLDS
	var limits: Vector3i = table[clampi(anger, 0, TOP) / 2]
	if roll < limits.x:
		return Pose.STAND
	if roll < limits.y:
		return Pose.CROUCH
	if roll < limits.z:
		return Pose.PRONE
	return Pose.ON_THE_MOVE


## Шанс увернуться от пули за один тик по злости, из 1.
static func dodge_chance(anger: int) -> float:
	return float(DODGE_ODDS[clampi(anger, 0, TOP)]) / 256.0


## Этаж ROM для нашего этажа: наш счёт идёт сверху, ROM — снизу (ADR-0028,
## решение 1). Здание другой высоты растягивает карту по доле высоты, а не
## обрывает её: тесты собирают и шестиэтажные.
static func rom_floor(index: int, floors: int) -> int:
	var from_bottom := float(floors - index) * float(FLOORS) / float(maxi(floors, 1))
	return clampi(roundi(from_bottom), 1, FLOORS)


## Сколько дверей на этаже ROM — мест в его маске (table_280E).
static func doors_on_floor(rom: int) -> int:
	var mask := DOOR_MASKS[clampi(rom, 0, FLOORS)]
	var count := 0
	while mask > 0:
		count += mask & 1
		mask >>= 1
	return count


## Тёмный ли этаж ROM: без ламп и с ценой убийства как в темноте (@2719, @56A1).
static func is_dark_floor(rom: int) -> bool:
	return rom >= DARK_FLOORS.x and rom <= DARK_FLOORS.y


## Сколько красных дверей в полосе [param band] на этом навыке (@27D2).
static func red_doors_in_band(band: int, skill_level: int) -> int:
	var quotas: Array = RED_DOOR_QUOTAS[band]
	return int(quotas[clampi(skill_level, 0, RED_DOOR_SKILL_TOP)])


## Сколько красных дверей в здании на этом навыке: 5, 6 … 10.
static func red_doors(skill_level: int) -> int:
	var total := 0
	for band in RED_DOOR_BANDS.size():
		total += red_doors_in_band(band, skill_level)
	return total
