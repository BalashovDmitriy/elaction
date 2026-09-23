extends GutTest

## Формулы боя сверяются с числами аркадного ROM (ADR-0027).
##
## Каждое утверждение — крайнее значение, прочитанное в дизассемблере: адрес
## рядом, выводы — в `docs/reference/arcade-rom.md`. Разошлось — значит формулу
## переписали, а не перенесли.


## 14.8 тика в секунду: кадр 59.19 Гц, логика раз в четыре кадра (MAME taitosj).
func test_a_tick_is_four_frames_of_the_arcade() -> void:
	assert_almost_eq(Arcade.TICK, 0.0676, 0.0001)
	assert_almost_eq(Arcade.seconds(Arcade.ALARM_TICKS), 277.0, 0.5, "тревога — ~277 с")


## Шаг 2 px за тик — 2.2 м/с; пуля Otto 8 px — 8.9 м/с (table_50D8).
func test_speeds_in_metres() -> void:
	assert_almost_eq(Arcade.speed(Arcade.WALK_PX), 2.22, 0.01, "ходьба")
	assert_almost_eq(Arcade.speed(Arcade.OTTO_BULLET_PX), 8.88, 0.01, "пуля Otto")


## Сложность: +1 каждые 1024 тика до тревоги, каждые 256 после, потолок 15 (@592F).
func test_difficulty_grows_with_time_and_alarm() -> void:
	assert_eq(Arcade.difficulty(0, 0.0), 0)
	assert_eq(Arcade.difficulty(0, Arcade.seconds(1023)), 0, "до 1024 тиков — прежняя")
	assert_eq(Arcade.difficulty(0, Arcade.seconds(1024)), 1)
	assert_eq(Arcade.difficulty(0, Arcade.seconds(4096)), 4, "на тревоге — +4")
	assert_eq(Arcade.difficulty(0, Arcade.seconds(4096 + 256)), 5, "после — каждые 256")
	assert_eq(Arcade.difficulty(20, 0.0), Arcade.TOP, "потолок 15")


## Злость агента: при выходе — сложность, +1 каждые 256 тиков (@5AFC).
func test_aggression_grows_with_age() -> void:
	assert_eq(Arcade.aggression(3, 0.0), 3)
	assert_eq(Arcade.aggression(3, Arcade.seconds(512)), 5)
	assert_eq(Arcade.aggression(14, Arcade.seconds(10000)), Arcade.TOP)


## Замах max(0, 10 − злость), пауза max(0, 80 − 8·злость) тиков (@1BDF, @0055).
func test_wind_up_and_cooldown() -> void:
	assert_almost_eq(Arcade.wind_up(0), Arcade.seconds(10), 0.0001)
	assert_eq(Arcade.wind_up(12), 0.0, "злой стреляет без замаха")
	assert_almost_eq(Arcade.cooldown(0), 5.41, 0.01, "5.4 с у спокойного")
	assert_eq(Arcade.cooldown(10), 0.0, "и ноль у злого")


## Агентов разом 3, четыре — когда навык·4 + время ≥ 14 (@594D).
func test_four_agents_only_late_or_on_high_skill() -> void:
	assert_eq(Arcade.agents_at_once(0, 0.0), 3)
	assert_eq(Arcade.agents_at_once(4, 0.0), 4, "навык 4 — сразу четыре")
	assert_eq(Arcade.agents_at_once(0, Arcade.seconds(14 * 256)), 4, "или 14×256 тиков в здании")


## На этаже: 1, 2, 3 по времени — только под тревогой и пока Otto на ногах (@5905).
func test_agents_per_floor() -> void:
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(5000), true, false), 1, "без тревоги — один")
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(5000), false, true), 1, "Otto в кабине — один")
	assert_eq(Arcade.agents_per_floor(0.0, true, true), 1)
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(3 * 256), true, true), 2)
	assert_eq(Arcade.agents_per_floor(Arcade.seconds(12 * 256), true, true), 3)


## Пуля агента: min(8, навык/4 + 6) px за тик, в тревоге на шаг быстрее (@463D).
func test_agent_bullet_speed() -> void:
	assert_almost_eq(Arcade.agent_bullet_speed(0, false), Arcade.speed(6.0), 0.001)
	assert_almost_eq(Arcade.agent_bullet_speed(0, true), Arcade.speed(7.0), 0.001)
	assert_almost_eq(Arcade.agent_bullet_speed(40, true), Arcade.speed(8.0), 0.001, "не выше 8")


## Позы выстрела по злости (table_1D75): спокойный не ложится, злой ложится чаще всего.
func test_fire_pose_follows_the_table() -> void:
	var calm := _share(0, Arcade.Pose.PRONE)
	var mean := _share(14, Arcade.Pose.PRONE)
	assert_eq(calm, 0.0, "спокойный лёжа не стреляет")
	assert_almost_eq(_share(0, Arcade.Pose.STAND), 196.0 / 256.0, 0.001, "стоя 77%")
	assert_almost_eq(mean, 188.0 / 256.0, 0.001, "злой — лёжа 73%")


## Увёртка: шанс за тик по злости (odds_table_0659) — ноль у спокойного, почти
## наверняка у самого злого.
func test_dodge_chance() -> void:
	assert_eq(Arcade.dodge_chance(0), 0.0)
	assert_almost_eq(Arcade.dodge_chance(15), 255.0 / 256.0, 0.0001)


func _share(anger: int, pose: Arcade.Pose) -> float:
	var hits := 0
	for roll in 256:
		if Arcade.fire_pose(anger, roll) == pose:
			hits += 1
	return float(hits) / 256.0
