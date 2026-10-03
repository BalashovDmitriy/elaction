class_name GameState
extends Node

## Game state: score, lives and document progress.
##
## The project's first game state singleton. Doors, HUD and the exit do not know about each
## other and talk through it with signals — as the conventions prescribe.
## The whole game lives here too: building number and alarm.
##
## The `Game` autoload puts it into the tree, and code accesses it via [method instance].
## The autoload name by itself is not an identifier: `--check-only` parses
## each script separately and does not know such names, but it knows the class name. A side
## benefit — tests create their own instance and do not touch the global one.

signal score_changed(value: int)
## Points awarded: how many and where — the scene point above which the HUD shows
## the increment; [constant AT_OTTO] — above Otto (a document). [param popup] = false —
## no increment above the place: the building bonus has its own panel.
signal scored(points: int, at: Vector3, popup: bool)
signal documents_changed(collected: int, total: int)
signal lives_changed(value: int)

## An extra life for points was awarded. Separate from [signal lives_changed]:
## that one says how many lives there are now, and this one says one was just given,
## and it plays its own sound.
signal extra_life_awarded
## Lives are over. The game is over.
signal game_over

## Otto has entered a new building.
signal building_changed(number: int)

## Took too long: agents get angrier, the cab responds with a delay (ADR-0009).
signal alarm_raised

## The original's score table (ADR-0005, item 1 and ADR-0006, item 5).
## Where to show the score increment if there is no event in the scene: above Otto
## ([signal scored]).
const AT_OTTO := Vector3.INF
## The increment pops up above the killed agent's head, not at his feet.
const OVER_HEAD := Vector3(0.0, 1.9, 0.0)
const DOCUMENT_SCORE: int = 500
const ENEMY_SHOT_SCORE: int = 100
const LAMP_SCORE: int = 300
## An agent crushed by a cab is 300, as in the ROM (score table @577B).
const CRUSH_SCORE: int = 300

## Bonus for a kill on a dark floor. Flat, not a multiplier: the check against the original
## before M6 found the table — shot 100, shot in the dark 150, kick 150,
## kick in the dark 200 (ADR-0010, item 6). Before the check there was a doubling here.
const DARK_KILL_BONUS: int = 50

## Lives per game — three, as in the original (ADR-0006, item 4).
const STARTING_LIVES: int = 3

## Extra life for points. The threshold is the lowest of the four the
## Taito manual offers via DIP switches (ADR-0012, item 5): 10 000.
##
## Awarded once per game. A repeat every ten thousand is not confirmed by the
## manual, and on a dark floor with agent respawn it would turn into
## infinite lives — we already predicted this farm for ourselves in ADR-0010.
const EXTRA_LIFE_SCORE: int = 10000

static var _instance: GameState = null

var score: int = 0
var lives: int = STARTING_LIVES
var documents_collected: int = 0
var documents_total: int = 0

## Building number. Its layout seed is [method building_seed].
var building: int = 1

## Game salt: mixed with the building number into the seed so buildings differ from
## game to game and are not memorised (ADR-0028, decision 6). Zero — the seed equals
## the building number, as before M18e: tests and the bot play this way, otherwise the death
## scale would be noisy.
var salt: int = 0
var alarm := Alarm.new()

## Whether a game is running. On pause and after Game Over time does not tick.
var _running: bool = false

## Whether the extra life has already been awarded in this game.
var _extra_life_given: bool = false


## Game state. Null until the autoload enters the tree.
static func instance() -> GameState:
	return _instance


## Points for a killed agent, taking into account whether it is dark where he was hit.
static func kill_score(base: int, in_the_dark: bool) -> int:
	return base + DARK_KILL_BONUS if in_the_dark else base


func _enter_tree() -> void:
	# The autoload instance enters the tree first and becomes the shared one.
	if _instance == null:
		_instance = self
		# Game run log — by the `--log=path` flag or `ELACTION_LOG`.
		RunLog.open()


## The siren is counted in physics steps, not frames.
##
## Agent anger and cab delay depend on it, i.e. the outcome of the game — while
## frames go by the wall clock. While the count was per frame, the same seed gave
## now three deaths, now four with the same number of bot steps: the siren managed
## to switch on earlier or later. The M18b milestone rule — everything that decides the
## outcome lives in physics ([`testing.md`](../../docs/testing.md)).
func _physics_process(delta: float) -> void:
	if not _running:
		return
	if alarm.tick(delta):
		alarm_raised.emit()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


## Starts the game anew: score, lives, first building. [param new_salt] —
## game salt; zero if it was not passed.
func start_game(new_salt: int = 0) -> void:
	reset()
	salt = new_salt
	_running = true
	building_changed.emit(building)


## Stops the game without touching its result. Needed for exiting to the menu: the building
## is thrown away there, and without this the siren timer would keep running under the main
## menu.
func stop_game() -> void:
	_running = false


## The building is finished: its bonus and moving on to the next. The alarm is cleared
## only here — death did not and will not clear it. The bonus is by the ROM: 1000 × building
## number, but no more than for the tenth (`Arcade.building_bonus`).
func finish_building() -> void:
	add_score(Arcade.building_bonus(building), AT_OTTO, false)
	building += 1
	alarm.enter_building()
	building_changed.emit(building)


## Starts a game in a building with a known number of red doors.
func start_building(total_documents: int) -> void:
	documents_total = maxi(total_documents, 0)
	documents_collected = 0
	documents_changed.emit(documents_collected, documents_total)


## Resets everything: score, lives, documents, building number, salt and alarm.
func reset() -> void:
	score = 0
	lives = STARTING_LIVES
	documents_collected = 0
	documents_total = 0
	building = 1
	salt = 0
	_extra_life_given = false
	alarm.enter_building()
	score_changed.emit(score)
	lives_changed.emit(lives)
	documents_changed.emit(documents_collected, documents_total)


## Layout seed of the current building: its number mixed with the game salt. One
## and the same salt for the layout and for combat (ADR-0027, decision 2): the level seeds
## both with it.
func building_seed() -> int:
	return building if salt == 0 else hash([building, salt])


## Counts a picked-up document together with its points. [param scored] =
## false — without points: this is how the demo from below counts documents of floors above
## that the bot did not pick up (ADR-0041).
func collect_document(scored: bool = true) -> void:
	documents_collected += 1
	documents_changed.emit(documents_collected, documents_total)
	if scored:
		add_score(DOCUMENT_SCORE)


## Takes a life. Returns true if Otto can still return to play.
##
## After the game is over it does nothing: [signal game_over] reports the transition,
## not the state, and it does not come twice.
func lose_life() -> bool:
	if lives <= 0:
		return false
	lives -= 1
	lives_changed.emit(lives)
	if lives > 0:
		return true
	_running = false
	game_over.emit()
	return false


## Awards [param points] points for an event at scene point [param at].
func add_score(points: int, at: Vector3 = AT_OTTO, popup: bool = true) -> void:
	score += points
	score_changed.emit(score)
	scored.emit(points, at, popup)
	_check_extra_life()


## Extra life for points — once per game and only while it is running.
##
## After Game Over points are still awarded (the building bonus arrives with a delay),
## and without this check a dead player would get a life he cannot come back with.
func _check_extra_life() -> void:
	if _extra_life_given or score < EXTRA_LIFE_SCORE or lives <= 0:
		return
	_extra_life_given = true
	lives += 1
	lives_changed.emit(lives)
	extra_life_awarded.emit()


## Whether all documents of the building are collected. A building without red doors counts
## as collected.
func all_documents_collected() -> bool:
	return documents_collected >= documents_total
