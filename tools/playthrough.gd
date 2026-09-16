extends SceneTree

## Прогон настоящего здания ботом: 30 этажей, как в игре.
##
## Тест прохождения гоняет здание на четыре этажа с одной шахтой — этого хватает
## проверить, что бот вообще умеет спускаться, но не то, во что играет игрок.
## Здесь собирается ровно то здание, которое собирает игра, и по нему видно,
## где спуск встаёт.
##
## Запуск:
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1,2,3
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1 --agents

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Потолок на здание, физических кадров. Тридцать этажей и пять документов —
## это минуты игрового времени, поэтому бюджет крупный.
const FRAME_BUDGET: int = 24000


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = [1, 2, 3]
	var agents := false
	# Жизни не кончаются: так видно, проходится ли здание вообще, отдельно от
	# того, хватает ли на него трёх жизней.
	var endless := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds = []
			for piece in argument.trim_prefix("--seeds=").split(","):
				seeds.append(piece.to_int())
		elif argument == "--agents":
			agents = true
		elif argument == "--endless":
			endless = true

	Engine.time_scale = 4.0
	var failures := 0
	for building_seed in seeds:
		if not await _play(building_seed, agents, endless):
			failures += 1
	Engine.time_scale = 1.0

	print("\nПровалено зданий: %d из %d" % [failures, seeds.size()])
	quit(1 if failures > 0 else 0)


func _play(building_seed: int, agents: bool, endless: bool) -> bool:
	var game := GameState.instance()
	game.reset()
	game.start_game()

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = agents
	root.add_child(level)

	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)
	var over := [false]
	# [GameState] — синглтон и переживает здание, поэтому связь снимается в конце
	# прогона: иначе на третьем сиде по «партия окончена» срабатывали бы три
	# замыкания подряд, и каждое держало бы своё уже убранное здание.
	var on_game_over := func() -> void: over[0] = true
	game.game_over.connect(on_game_over)

	var bot := OttoBot.new(level)
	var rules := level.rules
	var deepest := 0
	var frames := 0
	var deaths := 0
	var continues := 0
	var was_dead := false
	# Сколько кадров этаж не менялся: по этому видно застревание, а не медленность.
	var stuck := 0
	var last_floor := -1

	print("\n=== Сид %d, агенты: %s ===" % [building_seed, "да" if agents else "нет"])

	while not cleared[0] and frames < FRAME_BUDGET:
		# Жизни подливаются до того, как кончатся, а не после: на нуле уровень
		# не назначает возвращение в игру вовсе, и Otto остался бы лежать.
		if endless and game.lives < 2:
			continues += 1
			game.lives = GameState.STARTING_LIVES
			game.lives_changed.emit(game.lives)
		bot.step()
		await physics_frame
		frames += 1

		var here := rules.floor_index_near(level.otto.global_position.y)
		deepest = maxi(deepest, here)
		if level.otto.is_dead() and not was_dead:
			deaths += 1
			print(
				(
					"  смерть #%d на этаже %d, кадр %d, Otto %s, в кабине %s%s"
					% [
						deaths,
						here,
						frames,
						level.otto.global_position,
						level.otto.is_riding(),
						_around(level)
					]
				)
			)
		was_dead = level.otto.is_dead()

		if here == last_floor:
			stuck += 1
		else:
			if stuck > 1800:
				print("  этаж %d держал бота %d кадров" % [last_floor, stuck])
			stuck = 0
			last_floor = here
		if over[0]:
			print("  партия окончена на этаже %d, кадр %d" % [here, frames])
			break

	bot.release()
	var ok: bool = cleared[0] and game.documents_collected == game.documents_total
	var verdict := "прошёл" if ok else "НЕ ПРОШЁЛ"
	print(
		(
			"  %s: кадров %d, ниже всего этаж %d/%d, документы %d/%d, смертей %d, партий %d, очки %d"
			% [
				verdict,
				frames,
				deepest,
				rules.floors - 1,
				game.documents_collected,
				game.documents_total,
				deaths,
				continues + 1,
				game.score
			]
		)
	)
	if not ok:
		print("  застрял на этаже %d, стоя там %d кадров" % [last_floor, stuck])

	game.game_over.disconnect(on_game_over)
	root.remove_child(level)
	level.free()
	return ok


## Кто стоит рядом с Otto: три ближайших агента с расстоянием до него.
##
## Всех подряд печатать нельзя: в настоящем здании их под шестьдесят, и строка
## смерти вырастает на весь экран. Интересны только те, кто до Otto достаёт.
func _around(level: GreyboxLevel) -> String:
	var here := level.otto.global_position
	var near := level.agents()
	near.sort_custom(
		func(a: Enemy, b: Enemy) -> bool:
			return here.distance_to(a.global_position) < here.distance_to(b.global_position)
	)

	var parts := PackedStringArray()
	for index in mini(3, near.size()):
		var agent := near[index]
		parts.append(
			"агент %s (%.0f px)" % [agent.global_position, here.distance_to(agent.global_position)]
		)
	if near.is_empty():
		return ""
	return " | агентов %d, ближайшие: %s" % [near.size(), ", ".join(parts)]
