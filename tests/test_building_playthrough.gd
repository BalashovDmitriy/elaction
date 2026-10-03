extends GutTest

## The bot plays through the whole building.
##
## The most honest level check: a real scene with physics is assembled, and Otto actually goes down,
## takes the documents and leaves through the exit. It catches what neither the layout nor the smoke
## test sees — for example, a cab whose stops do not match the floors, or a door mat that cannot be
## reached.
##
## There are three kinds of building: a small one without guards, a real one without guards and a
## real one with agents. The first two check traversability, the third — combat: this is the DoD of
## milestone M11 (ADR-0016, items 7 and 8). Combat is measured by the number of deaths, not by
## whether the bot survived on three lives, — its lives are unlimited.
##
## The small one catches degenerate layouts and costs next to nothing, so it has many seeds. The
## real one is the very one the player plays: until nobody ran it, the building was assembled with a
## 20 px gap at the roof, and not a single test saw it (ADR-0014, item 5).

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 4, 5]

## Seeds of the real building. There are fewer of them: each is thirty floors and five documents,
## that is a minute and a half of game time per run.
const TALL_SEEDS: Array[int] = [1, 2]

## Cap for a playthrough, in physics frames. At 60 frames per second this is a minute of game time
## for four floors — with margin even for waiting for a cab.
const FRAME_BUDGET: int = 900

## Cap for the real building, in **bot loop steps** — the very ones the loop below counts. One step
## is two physics frames, guarded by [method test_a_tick_is_two_physics_frames].
##
## Measurement with `tools/playthrough.gd` on five seeds, 2026-09-22: **1992–3176 steps**, all five
## pass with five documents out of five. The cap is twice the worst seed, rounded.
##
## Measure in the same units the test counts in. The former comment promised "about 5500 frames" — a
## number from the tool, which then went one frame per step, whereas the test went two. The
## diverging units cost the milestone three investigation commits.
const TALL_BUDGET: int = 7000

## Seeds of the real building with guards. This is the most expensive run in the project: combat is
## added to thirty floors, and every duel adds more seconds.
const GUARDED_SEEDS: Array[int] = [1, 2, 3]

## Cap for the building with guards, in bot loop steps. The same as without them: combat adds tens
## of steps to a run, not thousands — a duel is decided in a second. Measurement with
## `tools/playthrough.gd --agents` on three seeds, 2026-09-22: **2756–3176 steps** against 1992–3176
## without combat.
##
## Twice the worst seed, but no more: this run is the most expensive in the project, and a failing
## seed must not burn minutes of CI before saying so.
const GUARDED_BUDGET: int = 7000

## How many lives the bot gets in a run with combat. Not three, but enough for the game to reach the
## end under any conceivable bad luck: the measure is the number of deaths, not the fact of
## "survived" (ADR-0016, item 8).
const ENDLESS_LIVES: int = 99

## How many deaths combat is allowed to cost the bot in one building.
##
## Measurement 2026-09-23, after the map-based building (ADR-0028), skill 0 — the first building at
## the easy level: **0, 1, 0** on seeds 1–3 (`tools/playthrough.gd --agents --endless`); this test
## counted 4 on seed 2. In M18d it was 0, 0, 0 with threshold 3: since M18e there are two and a half
## times more doors, and agents come out closer — the first building became more expensive by the
## milestone's decision, not by a breakage.
##
## Scale by skill (`--skill=N`, seeds 1–3): 3 — 4, 7, 0; 6 — 10, 36, 41 (on the third the bot
## collected everything but did not fit in 12000 steps); 10 — 22, 11, 21. The peak at six is a
## property of the bot, as in M18d: there agents are already fast but stand, while at ten three
## shots out of four are fired lying down, and the bot jumps over such a bullet better than it wins
## a duel.
##
## So the threshold has margin rather than sitting right at the worst: fitting it to an unstable
## number would lock noise into the check. It catches a regression of several times, not of one, and
## that is enough: the printed numbers of each seed track the ones, and they are visible on a green
## run too.
##
## This number is about the game's difficulty, and it is changed by measurement, not by fitting it
## to a green test (ADR-0016). If it grew, combat got meaner, and someone has to decide whether we
## wanted that or not.
##
## Measurement 2026-10-02, after the ROM rules (ADR-0053): return with no agents on the floor, the
## crowd leaves through doors, release no closer than 1.2 m — **1, 4, 6** on seeds 1–3. Seed 3 was
## at the threshold before too (5 of 5); combat by the ROM is a bit meaner, and the threshold was
## raised to six by the user's decision.
const DEATHS_ALLOWED: int = 6

## How many steps the bot gets to make at least some progress before the run is declared stuck in a
## loop.
##
## The bot has one legitimate reason to stand still — waiting for a cab, and it is bounded by the
## round trip of the longest shaft: fourteen floors, thirteen spans, 2 s of travel each plus [member
## ElevatorCar.floor_pause] of stop — about 91 s both ways, that is roughly 2730 steps. The
## threshold is taken slightly higher and is still half the run budget.
##
## It is needed not for speed, though for speed too. On M18a a looping seed burned the whole budget
## and reported "did not fit in N frames" — a wording that led the investigation toward the budget
## for three commits, whereas the bot had been standing on one floor since step 2900. The watchdog
## says "stuck at such-and-such place, deciding such-and-such", and those are exactly the two facts
## by which the cause was found.
const STALL_LIMIT: int = 3000


## Idle watchdog: checks that the bot makes progress and cuts off a looping run.
##
## Progress is any growth of the measure the run passes in — a floor deeper than before, a collected
## document, a spent life. Waiting for a cab does not count as progress, which is why the threshold
## is based on a shaft round trip.
class _Watchdog:
	extends RefCounted

	## Whether the watchdog fired: the run was cut off as looping.
	var tripped: bool = false

	var _best: int = -1
	var _idle: int = 0

	## Takes the progress measure and says whether it is time to cut off the run.
	func stalled(depth: int, done: int) -> bool:
		var measure := depth * 100 + done
		if measure > _best:
			_best = measure
			_idle = 0
			return false
		_idle += 1
		tripped = _idle > STALL_LIMIT
		return tripped

	## What exactly the bot is doing at the place where it stopped. The bot's decision matters more
	## here than coordinates: from "presses [] on the 21st floor" the cause is not visible, but from
	## "waits for the cab of shaft x=6.6 to ride to the 27th" it is visible at once.
	func report(level: GreyboxLevel, bot: OttoBot, depth: int) -> String:
		var at := WorldSpace.to_plane(level.otto.global_position)
		return (
			"bot is looping: %d steps without progress, floor %d, Otto %s, decision: %s"
			% [_idle, depth, at, bot.decision()]
		)


func _rules() -> BuildingRules:
	var rules := BuildingRules.new()
	rules.floors = 4
	rules.documents_cap = 1
	rules.shaft_span = 2
	return rules


func _build(building_seed: int, rules: BuildingRules = null, agents: bool = false) -> GreyboxLevel:
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = rules if rules != null else _rules()
	level.building_seed = building_seed
	level.spawn_agents = agents
	add_child_autofree(level)
	return level


## Removes the building from the tree at once, without waiting for the end of the test.
##
## [method GutTest.add_child_autofree] frees only after the whole test, and seeds are iterated
## inside one test: without this five buildings stand inside each other in one physics world. The
## bot presses actions globally, so all five Ottos walk at once, and the red doors of previous
## buildings still send documents to the shared [GameState] — the "documents collected" check would
## pass thanks to someone else's work. GUT will free them.
func _drop(level: GreyboxLevel) -> void:
	remove_child(level)


## A step of the bot control loop: **two physics frames, and this is on purpose**.
##
## [method GutTest.wait_physics_frames] waits until the counter becomes *greater* than requested
## ([code]addons/gut/awaiter.gd[/code]), so `wait_physics_frames(1)` skips two frames, not one. On
## M13 this was noticed and kept as a rule: the bot is the coarsest control loop the game will ever
## have, and a tolerance in the world must not be smaller than the distance covered in two frames
## under [member Engine.time_scale] (`docs/testing.md`, item 4). That rule caught a cab that froze
## 24 units from a floor.
##
## It must not be changed to one frame — that would cancel the rule. Changing it to two frames in
## one place and one in another is even worse: on M18a the test and
## [code]tools/playthrough.gd[/code] diverged exactly like that, and seed 2 "did not pass the
## building" in the test while passing in the tool in 6377 frames. The breakage was blamed first on
## the route length through the graph, then on combat balance. The tool and the test must drive Otto
## the same way, otherwise they measure different games.
func _tick() -> void:
	await wait_physics_frames(1)


## A bot loop step lasts two physics frames — both the budgets above and the M13 rule about
## tolerances rest on this (`docs/testing.md`, item 4).
##
## The check is cheap, but it guards something expensive: the unit in which the budgets are counted
## is set by the behaviour of someone else's code — [method GutTest.wait_physics_frames] waits until
## the counter becomes *greater* than requested. A GUT update may silently change that, and then the
## budgets will mean twice as much or half as much, and the bot will be twice as responsive or twice
## as coarse. On M18a such a divergence between the test and the measuring tool cost three
## investigation commits.
func test_a_tick_is_two_physics_frames() -> void:
	# The engine counts, not our own [signal SceneTree.physics_frame] handler: handlers run in
	# connection order, GUT's awaiter is connected earlier and wakes the coroutine right inside the
	# emission — before the count gets a chance to run. Such a counter undercounts by exactly one
	# frame.
	var before := Engine.get_physics_frames()
	await _tick()
	assert_eq(int(Engine.get_physics_frames() - before), 2, "шаг петли бота — два физических кадра")


func before_all() -> void:
	# The run has few frames, so game time runs faster than real time.
	Engine.time_scale = 4.0


func after_all() -> void:
	Engine.time_scale = 1.0
	# The autoload is one for the whole run: a game left "in play" would keep counting the alarm in
	# other tests. Return it to its initial state.
	GameState.instance().reset()


func test_bot_finishes_every_building() -> void:
	for building_seed: int in SEEDS:
		GameState.instance().start_game()
		var level := _build(building_seed)
		var cleared := [false]
		level.building_cleared.connect(func() -> void: cleared[0] = true)

		var bot := OttoBot.new(level)
		var frames := 0
		while not cleared[0] and frames < FRAME_BUDGET:
			bot.step()
			await _tick()
			frames += 1
		bot.release()

		var game := GameState.instance()
		assert_eq(
			game.documents_collected,
			game.documents_total,
			"сид %d: выход сработал, но документы не собраны" % building_seed
		)

		assert_true(
			cleared[0],
			(
				"сид %d: бот не прошёл за %d кадров. Этаж %d, жизней %d, мёртв: %s"
				% [
					building_seed,
					FRAME_BUDGET,
					level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y),
					GameState.instance().lives,
					level.otto.is_dead()
				]
			)
		)

		_drop(level)


## The bot plays through the very building the player plays: thirty floors, five documents, a roof
## on top and a stepped silhouette.
##
## A four-floor building catches none of this: it has one strip of shafts, one document and a width
## that does not change.
func test_bot_finishes_the_real_building_seed_1() -> void:
	await _play_tall(TALL_SEEDS[0])


func test_bot_finishes_the_real_building_seed_2() -> void:
	await _play_tall(TALL_SEEDS[1])


## One run of the real building without guards.
##
## The seed comes from outside rather than being iterated in a loop: a run takes a minute and a
## half, and seeds can be spread across processes only if each has its own test
## (`tools/run_tests.py`, shard layout).
func _play_tall(building_seed: int) -> void:
	GameState.instance().start_game()
	var level := _build(building_seed, BuildingRules.new())
	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var bot := OttoBot.new(level)
	var game := GameState.instance()
	var frames := 0
	var deepest := 0
	var watchdog := _Watchdog.new()
	var lamps_before := level.lamps().size()
	while not cleared[0] and frames < TALL_BUDGET:
		bot.step()
		await _tick()
		frames += 1
		deepest = maxi(
			deepest, level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		)
		if watchdog.stalled(deepest, game.documents_collected):
			break
	bot.release()

	assert_false(
		watchdog.tripped, "сид %d: %s" % [building_seed, watchdog.report(level, bot, deepest)]
	)
	assert_true(
		cleared[0],
		(
			"сид %d: бот не прошёл за %d кадров, ниже всего этаж %d из %d"
			% [building_seed, TALL_BUDGET, deepest, level.rules.floors - 1]
		)
	)
	assert_eq(
		game.documents_collected,
		game.documents_total,
		"сид %d: документы собраны не все" % building_seed
	)
	# The bot shoots down lamps from a cab (ADR-0053, decision 4): without this the run would not check
	# darkness at all.
	assert_gt(bot.lamp_shots, 0, "сид %d: бот ни разу не выстрелил по лампе" % building_seed)
	assert_lt(level.lamps().size(), lamps_before, "сид %d: ни одна лампа не упала" % building_seed)
	_drop(level)


## DoD of milestone M11: a building with agents is traversable, and combat costs the bot no more
## than [constant DEATHS_ALLOWED] deaths.
##
## The most expensive test of the project and the only one that measures combat balance rather than
## geometry (ADR-0016, items 7 and 8).
##
## **The bot's lives are unlimited on purpose.** The former check — "passed on three lives" — stood
## on a cliff edge: a seed with one death and a seed with three gave the same answer, and the whole
## difference in difficulty lies between them. A live player plays differently from the bot anyway,
## and carrying exactly three lives over to it is pointless. So the run always reaches the end, and
## the measure is the **number of deaths** — a continuous quantity that shows direction, not just a
## fact. Future difficulty levels will rest on it too.
##
## The bot plays worse than a human — it does not retreat, does not use doors as cover and does not
## think ahead. So this is the lower bar of playability: a building it cannot pass is all the more
## beyond a live player.
func test_bot_survives_the_real_building_with_agents_seed_1() -> void:
	await _play_guarded(GUARDED_SEEDS[0])


func test_bot_survives_the_real_building_with_agents_seed_2() -> void:
	await _play_guarded(GUARDED_SEEDS[1])


func test_bot_survives_the_real_building_with_agents_seed_3() -> void:
	await _play_guarded(GUARDED_SEEDS[2])


## One run of a building with guards. The seed comes from outside for the same reason as in [method
## _play_tall]: three seeds in a row take 328 s — forty percent of the whole suite and its floor,
## below which no layout goes.
func _play_guarded(building_seed: int) -> void:
	GameState.instance().start_game()
	# The run log — always: a failure of this test is investigated from it, without reruns with debug
	# printing (`tools/run_log.py`).
	RunLog.open(
		ProjectSettings.globalize_path("res://logs/playthrough_seed%d.jsonl" % building_seed)
	)
	var level := _build(building_seed, BuildingRules.new(), true)
	var cleared := [false]
	level.building_cleared.connect(func() -> void: cleared[0] = true)

	var bot := OttoBot.new(level)
	var game := GameState.instance()
	# Lives are given all at once and with margin, not topped up at zero: topping up would change the
	# course of the game at its sharpest moment, and the measurement would measure a different game. At
	# zero the level does not schedule a return to the game at all, and Otto would stay lying.
	game.lives = ENDLESS_LIVES
	game.lives_changed.emit(game.lives)
	var frames := 0
	var deepest := 0
	var deaths := 0
	var was_dead := false
	var watchdog := _Watchdog.new()
	while not cleared[0] and frames < GUARDED_BUDGET and game.lives > 0:
		bot.step()
		await _tick()
		frames += 1
		deepest = maxi(
			deepest, level.rules.floor_index_near(WorldSpace.to_plane(level.otto.global_position).y)
		)
		if level.otto.is_dead() and not was_dead:
			deaths += 1
		was_dead = level.otto.is_dead()
		# Death also counts as movement: a respawned Otto starts over and is no longer allowed to stand
		# still.
		if watchdog.stalled(deepest, game.documents_collected + deaths):
			break
	bot.release()
	RunLog.close()

	assert_false(
		watchdog.tripped, "сид %d: %s" % [building_seed, watchdog.report(level, bot, deepest)]
	)

	# The numbers are always printed, not only on failure: they show where the difficulty creeps from
	# milestone to milestone, — and that is exactly why the run with combat is kept. A green test
	# without numbers would only tell that the threshold has not been crossed yet.
	gut.p(
		(
			"сид %d: смертей %d, шагов %d, документы %d/%d"
			% [building_seed, deaths, frames, game.documents_collected, game.documents_total]
		)
	)

	assert_true(
		cleared[0],
		(
			"сид %d: бой не пройден за %d шагов. Этаж %d из %d, смертей %d"
			% [building_seed, frames, deepest, level.rules.floors - 1, deaths]
		)
	)
	assert_eq(
		game.documents_collected,
		game.documents_total,
		"сид %d: документы собраны не все" % building_seed
	)
	assert_lte(
		deaths,
		DEATHS_ALLOWED,
		"сид %d: бой стоил %d смертей при пороге %d" % [building_seed, deaths, DEATHS_ALLOWED]
	)
	_drop(level)
