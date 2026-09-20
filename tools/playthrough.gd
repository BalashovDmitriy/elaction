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
##     godot --headless --script res://tools/playthrough.gd -- --agents --at-once=8
##     godot --headless --script res://tools/playthrough.gd -- --seeds=1 --trace --budget=3000
##
## С [code]--trace[/code] раз в [constant TRACE_EVERY] кадров печатается, где бот
## и что вокруг: этаж, положение, стоит ли, едет ли, где ближайшая кабина. Это
## инструмент на случай «застрял», когда итоговая строка говорит лишь этаж.
## [code]--budget=N[/code] укорачивает прогон под такую диагностику, а
## [code]--trace-every=N[/code] делает трассу мельче.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Потолок на здание, физических кадров. Тридцать этажей и пять документов —
## это минуты игрового времени, поэтому бюджет крупный.
const FRAME_BUDGET: int = 24000

## Как часто печатать трассу, кадров.
const TRACE_EVERY: int = 300


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var seeds: Array[int] = [1, 2, 3]
	var agents := false
	# Жизни не кончаются: так видно, проходится ли здание вообще, отдельно от
	# того, хватает ли на него трёх жизней.
	var endless := false
	# Потолок живых агентов: 0 — брать из правил. Подбор этого числа и есть
	# главный рычаг плотности боя, и крутить его надо не правкой файла.
	var at_once := 0
	var trace := false
	var trace_every := TRACE_EVERY
	var budget := FRAME_BUDGET
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			seeds = []
			for piece in argument.trim_prefix("--seeds=").split(","):
				seeds.append(piece.to_int())
		elif argument == "--agents":
			agents = true
		elif argument == "--endless":
			endless = true
		elif argument == "--trace":
			trace = true
		elif argument.begins_with("--at-once="):
			at_once = argument.trim_prefix("--at-once=").to_int()
		elif argument.begins_with("--budget="):
			budget = maxi(argument.trim_prefix("--budget=").to_int(), 1)
		elif argument.begins_with("--trace-every="):
			trace_every = maxi(argument.trim_prefix("--trace-every=").to_int(), 1)

	Engine.time_scale = 4.0
	var failures := 0
	for building_seed in seeds:
		if not await _play(building_seed, agents, endless, at_once, trace, budget, trace_every):
			failures += 1
	Engine.time_scale = 1.0

	print("\nПровалено зданий: %d из %d" % [failures, seeds.size()])
	quit(1 if failures > 0 else 0)


func _play(
	building_seed: int,
	agents: bool,
	endless: bool,
	at_once: int,
	trace: bool,
	budget: int,
	trace_every: int
) -> bool:
	var game := GameState.instance()
	game.reset()
	game.start_game()

	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	if at_once > 0:
		level.rules.agents_at_once = at_once
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
	# Убитые агенты: по ним видно, дрался бот или пробегал мимо. Считаются по
	# телам, а не по очкам: лампа убивает не хуже пули, а очки у них разные.
	var kills := 0
	var counted: Dictionary = {}
	var continues := 0
	var was_dead := false
	# Сколько кадров этаж не менялся: по этому видно застревание, а не медленность.
	var stuck := 0
	var last_floor := -1

	print(
		(
			"\n=== Сид %d, агенты: %s, разом не больше %d ==="
			% [building_seed, "да" if agents else "нет", level.rules.agents_at_once]
		)
	)

	while not cleared[0] and frames < budget:
		# Жизни подливаются до того, как кончатся, а не после: на нуле уровень
		# не назначает возвращение в игру вовсе, и Otto остался бы лежать.
		if endless and game.lives < 2:
			continues += 1
			game.lives = GameState.STARTING_LIVES
			game.lives_changed.emit(game.lives)
		bot.step()
		await physics_frame
		frames += 1

		var here := rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		deepest = maxi(deepest, here)
		if trace and frames % trace_every == 0:
			print(
				(
					"  [%5d] этаж %d, Otto %s, стоит %s, едет %s, жмёт %s%s"
					% [
						frames,
						here,
						_at(level.otto),
						level.otto.is_grounded(),
						level.otto.is_riding(),
						_held_keys(),
						_cars_near(level)
					]
				)
			)
		for agent in level.agents():
			if agent.is_dead() and not counted.has(agent.get_instance_id()):
				counted[agent.get_instance_id()] = true
				kills += 1
		if level.otto.is_dead() and not was_dead:
			deaths += 1
			print(
				(
					"  смерть #%d на этаже %d, кадр %d, Otto %s, в кабине %s%s"
					% [
						deaths,
						here,
						frames,
						WorldSpace.to_plane(level.otto.global_position),
						level.otto.is_riding(),
						_around(level) + _killer(level)
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
			"  %s: кадров %d, этаж %d/%d, документы %d/%d, смертей %d, убито %d, партий %d, очки %d"
			% [
				verdict,
				frames,
				deepest,
				rules.floors - 1,
				game.documents_collected,
				game.documents_total,
				deaths,
				kills,
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
	var here := _at(level.otto)
	var near := level.agents()
	near.sort_custom(
		func(a: Enemy, b: Enemy) -> bool: return here.distance_to(_at(a)) < here.distance_to(_at(b))
	)

	var parts := PackedStringArray()
	for index in mini(3, near.size()):
		var agent := near[index]
		parts.append("агент %s (%.2f м)" % [_at(agent), here.distance_to(_at(agent))])
	if near.is_empty():
		return ""
	return " | агентов %d, ближайшие: %s" % [near.size(), ", ".join(parts)]


## Чем его, скорее всего, достали: ближайшая вражеская пуля и ближайшая кабина.
##
## Без этого смерть «в кабине» неотличима от смерти под кабиной, а это разные
## беды: первая лечится балансом, вторая — правилами шахты.
func _killer(level: GreyboxLevel) -> String:
	var here := _at(level.otto)
	var parts := PackedStringArray()

	var closest := INF
	var aim := 0.0
	for node in level.get_tree().get_nodes_in_group(Bullet.GROUP):
		var bullet := node as Bullet
		if bullet == null or bullet.collision_mask != Bullet.FROM_ENEMY:
			continue
		var gap := here.distance_to(_at(bullet))
		if gap < closest:
			closest = gap
			aim = here.y - _at(bullet).y
	if closest < INF:
		parts.append("пуля в %.2f м, выше ног на %.2f" % [closest, aim])

	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var to_car := _at(car) - here
		if to_car.length() > 0.6:
			continue
		parts.append("кабина %s, выровнена: %s" % [to_car, car.is_aligned()])

	if parts.is_empty():
		return " | рядом ни пули, ни кабины"
	return " | " + ", ".join(parts)


## Где узел стоит в плоскости правил: прогон, как и бот, думает там же, где
## раскладка, и переводит из сцены в одном месте.
static func _at(node: Node3D) -> Vector2:
	return WorldSpace.to_plane(node.global_position)


## Кабины на этаже Otto и ближайшая к нему по вертикали: по ним видно, ждёт ли
## бот кабину, которая не приходит, или стоит рядом с той, что пришла.
func _cars_near(level: GreyboxLevel) -> String:
	var here := _at(level.otto)
	var nearest := ""
	var gap := INF
	for child in level.get_children():
		var car := child as ElevatorCar
		if car == null:
			continue
		var at := _at(car)
		var distance := here.distance_to(at)
		if distance < gap:
			gap = distance
			nearest = "кабина %s (%.2f м, выровнена %s)" % [at, distance, car.is_aligned()]
	return "" if nearest.is_empty() else " | ближайшая " + nearest


## Что бот держит нажатым после своего шага: по этому видно, решил ли он идти.
func _held_keys() -> String:
	var keys := PackedStringArray()
	for action: StringName in [
		&"move_left", &"move_right", &"move_up", &"move_down", &"jump", &"shoot"
	]:
		if Input.is_action_pressed(action):
			keys.append(String(action).trim_prefix("move_"))
	return "[%s]" % ",".join(keys)
