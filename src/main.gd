extends Node

## Entry point: the menu, the game and the transitions between them.
##
## Holds three things and ties them together: [Menu] — the screens outside play, [Hud] — what
## is visible in play, and the building itself. The game lives in [GameState], the building
## does not: it is assembled anew for each one and thrown away whole.
##
## The root is a bare [Node], not a 2D or 3D node: under it live both the three-dimensional
## building and the flat interface, and neither of them needs a parent
## transform. 2D post-processing left with ADR-0002; its 3D successor is
## the business of the light milestone (M17).
##
## The game starts with the menu, not the building (M8b milestone DoD): before it, one landed
## straight in a game, because there was no menu yet.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
## The screenshot autoload script: the autoload name is not visible when parsing one file,
## yet the static question "is a capture running" must be asked.
const SCREENSHOTTER := preload("res://src/autoload/screenshotter.gd")
## How long the counted-up bonus hangs in frame before the frame fades to black, s:
## to finish reading the number.
const BONUS_HOLD: float = 0.8
## How long the game-over items do not accept presses, s (ADR-0042, decision 5).
const GAME_OVER_HOLD: float = 1.5

var _level: GreyboxLevel = null
## The city behind the main menu (ADR-0035). Lives while the menu is open, not the game.
var _stage: MenuStage = null
var _settings: GameSettings = null
var _records: Records = null
## Whether a game is running. On menu screens — no, even while the building hangs in the tree.
var _playing: bool = false
## What was held last frame: the press edge is computed from this.
var _held: Dictionary = {}
## The menu page as the last frame left it. Esc is both "pause" and the menu's "back":
## from settings over the pause the menu returns to the pause before the frame reaches
## [method _process], and judged by the current page alone the same press would immediately
## unpause (M22b code review).
var _page_before: Menu.Page = Menu.Page.MAIN
## Fade between buildings (ADR-0038, decision 4).
var _curtain: FadeCurtain = null
## The running demo (ADR-0041) or null. How long the main menu has stood without presses and
## from which point the next demo will start.
var _demo: DemoRun = null
var _idle: float = 0.0
var _demo_point: int = DemoPlan.Point.ROOF
## The demo is fading out: a second press no longer ends it.
var _demo_ending: bool = false

@onready var _menu: Menu = $Menu
@onready var _hud: Hud = $Hud


func _ready() -> void:
	# The first thing the game writes to the log: version and platform. Without them an "it does not
	# work for me" report has nothing to be matched against, and a build without this line
	# counts as not started — tools/smoke.py looks exactly for it.
	print(Release.banner())

	# Pause input must work while paused, otherwise there is no way out. The building itself
	# must freeze meanwhile — see _enter_building.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_settings = GameSettings.load_from()
	_settings.apply()
	# Vignette — under the HUD and menu, above the scene (ADR-0030, decision 3).
	add_child(Vignette.new())
	_curtain = FadeCurtain.new()
	add_child(_curtain)
	_records = Records.load_from()

	_menu.settings = _settings
	_menu.records = _records
	_menu.play_pressed.connect(_start_game)
	_menu.resume_pressed.connect(_resume)
	_menu.restart_pressed.connect(_start_game)
	_menu.to_menu_pressed.connect(_open_menu)
	_menu.quit_pressed.connect(_quit)

	var game := GameState.instance()
	game.game_over.connect(_on_game_over)
	game.extra_life_awarded.connect(_on_extra_life)

	# Auto-capture starts right with a game: it drives Otto with game actions,
	# but cannot press menu buttons.
	if SCREENSHOTTER.capturing():
		_start_game()
	else:
		_open_menu()


func _process(delta: float) -> void:
	_count_idle(delta)
	# The cursor is only in the menu: in a game and in the demo it hung over the frame, and full
	# screen read as a stretched window (ADR-0042, decision 4).
	var cursor := Input.MOUSE_MODE_VISIBLE if _menu.visible else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != cursor:
		Input.mouse_mode = cursor
	if _just_pressed(&"pause"):
		# Pause during the intro skips it rather than opening the menu (ADR-0038).
		if _playing and _level != null and _level.skip_the_intro():
			pass
		elif _playing:
			_pause()
		elif (
			_menu.visible
			and _page_before == Menu.Page.PAUSE
			and _menu.current_page() == Menu.Page.PAUSE
		):
			# Only an open pause: a closed menu remembers its last page, and
			# Esc during the last death would "continue" the game after a pause in
			# this game — the game over was never shown (M24f code review).
			_resume()
	_page_before = _menu.current_page()


## Any press: in the menu resets the countdown to the demo, in the demo ends it
## (ADR-0041, decision 5). The press that ended the demo does not reach the game or the menu.
func _input(event: InputEvent) -> void:
	var pressed := (
		(event is InputEventKey and event.is_pressed() and not event.is_echo())
		or (event is InputEventJoypadButton and event.is_pressed())
		or (event is InputEventMouseButton and event.is_pressed())
	)
	if _demo != null:
		# The F12 shot is taken in the demo too: main hears input before the screenshot autoload,
		# and the press that ended the demo would no longer reach it (M24e code review).
		if pressed and not event.is_action(&"screenshot"):
			get_viewport().set_input_as_handled()
			_end_demo()
		return
	# The stick also moves through the menu: the menu is navigated by arrows and by it (M24e code
	# review).
	var stick := event as InputEventJoypadMotion
	if (
		pressed
		or event is InputEventMouseMotion
		or (stick != null and absf(stick.axis_value) > 0.5)
	):
		_idle = 0.0


## Main menu without presses for [constant DemoPlan.IDLE_TIME] seconds — demo. Only
## the main one: on pause, in settings and in a game there is no countdown.
func _count_idle(delta: float) -> void:
	var waiting := (
		_demo == null
		and not _playing
		and _menu.visible
		and _menu.current_page() == Menu.Page.MAIN
		and not SCREENSHOTTER.capturing()
	)
	if not waiting:
		_idle = 0.0
		return
	_idle += delta
	if _idle >= DemoPlan.IDLE_TIME:
		_start_demo()


## Demo (ADR-0041): a building with its own salt, a bot for Otto, the point is the next one round
## the circle.
func _start_demo() -> void:
	_idle = 0.0
	_demo_ending = false
	_drop_the_curtain()
	_drop_stage()
	_menu.close()
	_hud.visible = true
	GameState.instance().start_game(_new_salt())
	_enter_building(true)
	_demo = DemoRun.start(_level, _demo_point)
	_demo.finished.connect(_end_demo)
	_demo_point = DemoPlan.next(_demo_point)


## End of the demo: the building freezes, the frame fades to black, from black — the main menu.
func _end_demo() -> void:
	if _demo == null or _demo_ending:
		return
	_demo_ending = true
	_demo.stop()
	_level.process_mode = Node.PROCESS_MODE_DISABLED
	# The takedown scene holds its own PAUSABLE mode and under a disabled building would go
	# on: finishing the agent with sound, driving the camera and keeping the world slowed —
	# and the fade with it (M24e code review). Leaving the tree gives the world its pace back.
	var director := _level.otto.takedown
	if director != null:
		_level.otto.takedown = null
		director.get_parent().remove_child(director)
		director.queue_free()
	_curtain.cover(0.0, _open_menu.bind(true))


## Whether the action was pressed exactly this frame.
##
## Own edge tracking instead of [method Input.is_action_just_pressed]: that one
## is true only on the frame of the press itself, and the capture auto-script presses actions
## from its own frame — main's frame manages to pass earlier, and the press is lost.
func _just_pressed(action: StringName) -> bool:
	var pressed := Input.is_action_pressed(action)
	var was: bool = _held.get(action, false)
	_held[action] = pressed
	return pressed and not was


## Main menu: the building is thrown away, the city rises behind the menu, the music stays.
## [param from_demo] — from the end-of-demo fade: it will bring the frame out of black itself,
## and it must not be cleared here.
func _open_menu(from_demo: bool = false) -> void:
	_playing = false
	_demo = null
	_demo_ending = false
	_idle = 0.0
	_unpause()
	if from_demo:
		_hud.hide_bonus()
	else:
		_drop_the_curtain()
	# The game stops rather than just hides: without this the siren timer
	# would keep running under the main menu exited to from the pause.
	GameState.instance().stop_game()
	# The building goes away together with Otto behind a door — the door itself clears the door
	# muffling.
	_drop_level()
	_raise_stage()
	_hud.visible = false
	_menu.show_page(Menu.Page.MAIN)
	Sounds.play_music(Sounds.MENU_THEME)


func _start_game() -> void:
	_demo = null
	_playing = true
	_unpause()
	_drop_the_curtain()
	_drop_stage()
	_menu.close()
	_hud.visible = true
	GameState.instance().start_game(_new_salt())
	GameState.instance().building = SCREENSHOTTER.start_building()
	# The HUD need not be redrawn: start_game and start_building inside the building
	# emit all the signals it is subscribed to.
	_enter_building()
	# The first building of a launch opens from black: under it the shaders of rare effects
	# warm up once, and the first shot does not jerk the frame (ADR-0039).
	if ShaderWarmup.run(_level):
		_curtain.reveal(ShaderWarmup.HOLD)


## Salt of a new game: random, not zero — zero means "no salt" (ADR-0028,
## decision 6). The `-- --salt=N` argument sets it by hand: that way a game can be
## repeated and shots taken on a known building. A milestone auto-capture runs without salt:
## its script is built for a building by number, and on someone else's layout it would walk
## past the shaft.
func _new_salt() -> int:
	if SCREENSHOTTER.capturing():
		return 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--salt="):
			return argument.trim_prefix("--salt=").to_int()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 0x7FFFFFFF)


func _pause() -> void:
	_playing = false
	get_tree().paused = true
	Sounds.play(Sounds.UI_SELECT)
	_menu.show_page(Menu.Page.PAUSE)
	Sounds.muffle_music(Sounds.MUFFLE_PAUSE, true)


func _resume() -> void:
	_playing = true
	_unpause()
	_menu.close()


## Clears the pause, and with it the muffled pause music. The pause is left not only by
## "continue": "restart" and "to menu" left the music muffled for the whole new
## game (M23 code review).
func _unpause() -> void:
	get_tree().paused = false
	Sounds.muffle_music(Sounds.MUFFLE_PAUSE, false)


func _quit() -> void:
	_settings.save_to()
	get_tree().quit()


## Assembles the next building. The old one is thrown away whole together with Otto:
## the game lives in [GameState], the level does not. [param demo] — a demo building: it does not
## start a quality measurement (ADR-0041, decision 6).
func _enter_building(demo: bool = false) -> void:
	_drop_level()

	var game := GameState.instance()
	_level = LEVEL_SCENE.instantiate() as GreyboxLevel
	_level.rules = BuildingRules.for_building(game.building, _settings.difficulty)
	_level.building_seed = game.building_seed()
	# Time of day — a draw by seed, for the whole building (ADR-0051, decisions 3 and 4).
	_level.rules.time_of_day = TimeOfDay.of_seed(_level.building_seed)
	# The full intro is in the game's first building, short ones after (ADR-0052).
	_level.full_intro = game.building == 1 and not demo
	# The mode is inherited from the parent, and here it is ALWAYS: without this line the pause
	# would stop nothing — the game would go on with a "pause" caption.
	_level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_level)
	_level.car_started.connect(_on_car_started)
	_level.building_cleared.connect(_on_building_cleared)
	# The HUD takes the name, sign colour and Otto's floor from the building (M22).
	_hud.follow(_level)
	# First launch: the quality level is chosen by a measurement during the building intro
	# (ADR-0034, decision 3). A milestone auto-capture shoots at the level from settings. The
	# measurement is under the building, not under main: if the building is thrown away
	# mid-measurement (new game, exit to menu), the measurement goes with it, does not measure the
	# menu and does not write its level, and the next building starts its own, single one (M22 code
	# review).
	if QualityProbe.needed(_settings) and not SCREENSHOTTER.capturing() and not demo:
		var probe := QualityProbe.new()
		_level.add_child(probe)
		probe.start(_settings)
	# The theme is started per building, not per game: after an alarm it must be restored,
	# and the siren is cleared only by a building change (ADR-0009).
	# Building and alarm tracks — a draw by the building seed (ADR-0036, decision 3), the building
	# theme — by time of day (ADR-0052, decision 1).
	# Theme and alarm — by building kind (ADR-0057, decision 7); Otto starts from the
	# roof, and the upper-half track of the building plays ([method GreyboxLevel.music]).
	_level.music(game.alarm.raised)


## The city behind the menu. Weather — a draw on each exit to the menu: a clear night, fog
## or rain with lightning.
func _raise_stage() -> void:
	if _stage != null:
		return
	_stage = MenuStage.new()
	_stage.name = "Stage"
	add_child(_stage)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_stage.build(rng.randi())


func _drop_stage() -> void:
	if _stage == null:
		return
	remove_child(_stage)
	_stage.queue_free()
	_stage = null


func _drop_level() -> void:
	if _level == null:
		return
	# First out of the tree, then to the bin: [method Node.queue_free] removes the node
	# only at the end of the frame, and the old building would keep simulating next to the new one —
	# two Ottos, two cabs and all the geometry twice in one physics world.
	remove_child(_level)
	_level.queue_free()
	_level = null


## Otto got into the car, it pulled away: the building bonus counts up over the scene.
func _on_car_started() -> void:
	Sounds.play(Sounds.BUILDING_BONUS)
	_hud.count_bonus(Arcade.building_bonus(GameState.instance().building))


## The car left the frame: the bonus finishes counting on the plate, hangs for [constant
## BONUS_HOLD], the frame fades to black, and only under black does the bonus go into the score,
## the round advances and the next building is assembled.
##
## Before, the score and round changed on the same frame the car left: the old building
## still on screen, and the HUD already shows "ROUND 2" and the score with bonus, while the bonus
## plate is only counting up.
func _on_building_cleared() -> void:
	# A demo that drove to the exit ends rather than assembling the next building.
	if _demo != null:
		_end_demo()
		return
	if not _hud.bonus_shown():
		_on_car_started()
	# The building changes under black, from the fade tween — not from a physics step
	# of the departing building in which the signal arrived.
	_curtain.cover(_hud.bonus_time_left() + BONUS_HOLD, _next_building)


## Under black: bonus into the score, the next round and its building.
func _next_building() -> void:
	_hud.hide_bonus()
	GameState.instance().finish_building()
	_enter_building()


## Abandons the building change halfway: menu, new game, game over.
func _drop_the_curtain() -> void:
	_curtain.cancel()
	_hud.hide_bonus()


func _on_extra_life() -> void:
	Sounds.play(Sounds.EXTRA_LIFE)


func _on_game_over() -> void:
	# A demo writes no records and shows no game over (ADR-0041, decision 6).
	if _demo != null:
		_end_demo()
		return
	_playing = false
	_drop_the_curtain()
	# The jingle ducks the track while it plays, and the game-over track comes in
	# from under it (ADR-0036, decision 6).
	Sounds.play(Sounds.GAME_OVER)
	Sounds.play_music(Sounds.GAME_OVER_THEME)

	var score := GameState.instance().score
	var place := _records.submit(score)
	if place >= 0:
		_records.save_to()
		# A new record — its own jingle over the game over (ADR-0052, decision 7).
		Sounds.play(Sounds.RECORD)
	_menu.remember(score, place)
	# First the last death — slow-down and zoom-in (ADR-0042, decision 5). Not on
	# this frame: an Otto who died mid takedown scene cuts it short, and the scene,
	# restoring the world's tempo, would also clear the scene slow-down.
	_play_the_last_death.call_deferred()


func _play_the_last_death() -> void:
	if _level == null or not is_instance_valid(_level.otto):
		_show_game_over()
		return
	LastDeath.play(self, _level.otto).finished.connect(_show_game_over)


func _show_game_over() -> void:
	# Exited to the menu while the scene ran — there is nothing to show anymore.
	if _level == null or _playing:
		return
	# The game is over — the building freezes, as on pause. Otherwise agents keep
	# arriving and shooting under the "game over" caption.
	get_tree().paused = true
	_menu.show_page(Menu.Page.GAME_OVER)
	# Items not at once: otherwise a player mashing jump would press "Restart" with the same space.
	_menu.hold_rows(GAME_OVER_HOLD)
