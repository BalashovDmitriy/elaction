class_name Hud
extends CanvasLayer

## Game HUD: only what you cannot play without (ADR-0012, point 8).
##
## Since M22 — neon noir (the user's decision): dark translucent panels with
## a neon edge in the building sign's colour, the narrow Exo 2 font, icons instead of
## words. Top left — score and documents as folders, centre — building name and the floor
## Otto is on, right — lives as silhouettes, bottom right — round, under the building name —
## a blinking alarm panel.
##
## The building bonus is a panel in the middle of the frame while the car with Otto drives off: a
## caption and a number counting up from zero (ADR-0038, decision 4). There is no separate results
## screen — as in the ROM, a line over the scene.
##
## There is no arcade-style high score line: the game is a remake, the interface is on the same side
## as picture and sound. Everything is built in code: panels are data, not markup.

## How often the alarm blinks, times per second, and how much it dims at the low point.
const ALARM_BLINKS: float = 1.6
const ALARM_DIM: float = 0.35

## How many document folders are created: more than a building ever has. Red
## doors are 5 to 10, by draw from the building seed ([method BuildingDocuments.count]),
## — as many folders are visible as there are documents in this building.
const DOCUMENT_ICONS: int = 10
## Beyond this many lives icons are not drawn — a number instead.
const LIFE_ICONS: int = 5

const MARGIN: float = 28.0

const INK := NeonStyle.INK
const INK_DIM := NeonStyle.INK_DIM
const ALARM := Color(1.0, 0.22, 0.2)
const PLATE := NeonStyle.PLATE

## The edge if the building did not give its colour: the neon of the first building, a hotel.
const DEFAULT_NEON := VerticalSign.NEON_HOTEL
## How often the frame counter is rewritten, s: every frame the digits would flicker.
const FPS_EVERY: float = 0.25
## How long the building bonus takes to count up, s: the car leaves the frame in about
## the same time.
const BONUS_COUNT_TIME: float = 1.2
## Margin on the sides of the bonus number on top of the panel padding, px: digits at size 72
## stick out beyond their width, and "1 000" came right up against the edge.
const BONUS_PAD: float = 18.0
## Font size of the bonus number.
const BONUS_SIZE: int = 72

## Whether to show the frame counter. Static, like [member Blood.enabled]: the
## settings set it, and the HUD reads it without knowing who holds them.
static var show_fps: bool = false

var _neon := DEFAULT_NEON
var _score_caption: Label = null
var _score: Label = null
var _documents: Array[HudIcon] = []
var _lives: Array[HudIcon] = []
var _lives_more: Label = null
var _building: Label = null
## Score gain: pops up above the spot and next to the score, the score counts up.
var _bursts: ScoreBursts = null
var _floor: Label = null
var _round: Label = null
var _alarm: PanelContainer = null
var _alarm_label: Label = null
var _plates: Array[PanelContainer] = []
var _level: GreyboxLevel = null
var _shown_floor: int = -2
var _fps_plate: PanelContainer = null
var _fps: Label = null
var _fps_next: float = 0.0
var _bonus_plate: PanelContainer = null
var _bonus_caption: Label = null
var _bonus: Label = null
var _bonus_count: Tween = null


func _ready() -> void:
	_build()
	var game := GameState.instance()
	game.score_changed.connect(_on_score_changed)
	game.documents_changed.connect(_on_documents_changed)
	game.lives_changed.connect(_on_lives_changed)
	game.building_changed.connect(_on_building_changed)
	game.alarm_raised.connect(_on_alarm_raised)
	refresh()


func _process(_delta: float) -> void:
	_follow_floor()
	_count_frames()
	if not _alarm.visible:
		return
	# Blinking is computed from time, not by an accumulator: the HUD lives on pause too,
	# and under pause delta does not come at all.
	var phase := sin(Time.get_ticks_msec() / 1000.0 * ALARM_BLINKS * TAU) * 0.5 + 0.5
	_alarm.modulate.a = ALARM_DIM + (1.0 - ALARM_DIM) * phase


## The language was changed in the menu mid-game: captions are built in code from the translation
## in upper case and will not re-translate themselves — the score caption would stay in the
## previous language until the game ends, and the floor — until the next one (code review M22).
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _score_caption == null:
		return
	_score_caption.text = tr("UI_SCORE").to_upper()
	_bonus_caption.text = tr("UI_BONUS").to_upper()
	_shown_floor = -2
	refresh()


## The building the HUD tracks: its name, sign colour and Otto's floor.
func follow(level: GreyboxLevel) -> void:
	_level = level
	_bursts.follow(level)
	_shown_floor = -2
	if level != null and level.identity != null:
		_neon = VerticalSign.neon_of(level.identity)
		_bursts.neon = _neon
		_building.text = " ".join(level.identity.sign_lines())
	_restyle()
	refresh()


## Redraws everything at once. Called on entering a building and on a state change:
## the game has many signals and few fields, and sorting them out one by one is pointless.
func refresh() -> void:
	var game := GameState.instance()
	_bursts.show_score(game.score)
	for index in _documents.size():
		_documents[index].set_state(index < game.documents_collected, _neon)
	_documents_row_visible(game.documents_total)
	for index in _lives.size():
		_lives[index].visible = index < mini(game.lives, LIFE_ICONS)
		_lives[index].set_state(true, _neon)
	_lives_more.visible = game.lives > LIFE_ICONS
	_lives_more.text = "×%d" % game.lives
	# "Round", not "building": that is what the counter is called both in the arcade and in the port
	# (ADR-0017, decision 5).
	_round.text = "%s %d" % [tr("UI_ROUND").to_upper(), game.building]
	_alarm_label.text = tr("UI_ALARM")
	_alarm.visible = game.alarm.raised


## Shows the building bonus: the number counts up from zero to [param amount] over
## [constant BONUS_COUNT_TIME]. On pause the count stands still along with the game.
func count_bonus(amount: int) -> void:
	if _bonus_count != null:
		_bonus_count.kill()
	_bonus_plate.visible = true
	_show_bonus_value(0.0)
	# The counter ticks while the number counts up: the recording is as long as the count
	# (ADR-0052, decision 7).
	if amount > 0:
		Sounds.play(Sounds.BONUS_TICK)
	_bonus_count = create_tween()
	_bonus_count.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_bonus_count.tween_method(_show_bonus_value, 0.0, float(amount), BONUS_COUNT_TIME)


## How much longer the bonus counts up to full, s: 0 — counted out or there is none.
func bonus_time_left() -> float:
	if _bonus_count == null or not _bonus_count.is_valid() or not _bonus_count.is_running():
		return 0.0
	return maxf(BONUS_COUNT_TIME - _bonus_count.get_total_elapsed_time(), 0.0)


## Removes the bonus panel: the next building, the menu or a new game.
func hide_bonus() -> void:
	if _bonus_count != null:
		_bonus_count.kill()
		_bonus_count = null
	_bonus_plate.visible = false


## Whether the bonus panel is visible and what number is on it.
func bonus_shown() -> bool:
	return _bonus_plate.visible


func bonus_text() -> String:
	return _bonus.text


func _show_bonus_value(value: float) -> void:
	_bonus.text = format_score(roundi(value))


## Score with spaces every three digits: 12 400 reads at a glance, 12400 does not.
static func format_score(score: int) -> String:
	var digits := str(absi(score))
	var grouped := ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += " "
		grouped += digits[index]
	return ("-" if score < 0 else "") + grouped


## The floor Otto stands on, as the player sees it: the sign number, roof or
## garage — the bottom floor, "P" on the signs ([method FloorSigns.label_of]).
static func floor_text(rules: BuildingRules, index: int) -> String:
	if index == BuildingRules.ROOF:
		return TranslationServer.translate("UI_ROOF").to_upper()
	if FloorSigns.is_parking(rules, index):
		return TranslationServer.translate("UI_PARKING").to_upper()
	return (
		"%s %d"
		% [TranslationServer.translate("UI_FLOOR").to_upper(), FloorSigns.number_of(rules, index)]
	)


func _follow_floor() -> void:
	# Outside the tree — a building main has already removed and not yet freed (exit to
	# the menu): its Otto has no global position (code review M22).
	if _level == null or not is_instance_valid(_level) or not _level.is_inside_tree():
		return
	if _level.otto == null:
		return
	var rules := _level.rules
	var y := WorldSpace.to_plane(_level.otto.global_position).y
	var index := rules.floor_index_near(y)
	if index == _shown_floor:
		return
	_shown_floor = index
	_floor.text = floor_text(rules, index)


func _documents_row_visible(total: int) -> void:
	for index in _documents.size():
		_documents[index].visible = index < maxi(total, 0)


# --- Assembly ----------------------------------------------------------------


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top left: score and documents.
	var left := _plate(root, Control.PRESET_TOP_LEFT)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 2)
	left.add_child(left_box)
	_score_caption = _caption("UI_SCORE")
	left_box.add_child(_score_caption)
	_score = _label(56, INK, 700)
	left_box.add_child(_score)
	_bursts = ScoreBursts.new()
	_bursts.name = "ScoreBursts"
	root.add_child(_bursts)
	_bursts.watch(_score)
	var docs := HBoxContainer.new()
	docs.add_theme_constant_override("separation", 6)
	left_box.add_child(docs)
	for _i in DOCUMENT_ICONS:
		var icon := HudIcon.make(HudIcon.Kind.DOCUMENT, 34.0)
		docs.add_child(icon)
		_documents.append(icon)

	# Top centre: round, building and floor. Round — on the first line: in the corner,
	# small and dim, nobody found it (user's remark, ADR-0037).
	var middle := _plate(root, Control.PRESET_CENTER_TOP)
	var middle_box := VBoxContainer.new()
	middle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(middle_box)
	_round = _label(24, INK, 700)
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle_box.add_child(_round)
	_building = _label(26, _neon, 600)
	_building.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle_box.add_child(_building)
	_floor = _label(44, INK, 700)
	_floor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle_box.add_child(_floor)

	# Alarm — under the building.
	_alarm = PanelContainer.new()
	_alarm.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alarm.position = Vector2(0.0, 150.0)
	_alarm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alarm.add_theme_stylebox_override(
		"panel", NeonStyle.plate(Color(0.3, 0.02, 0.02, 0.75), ALARM)
	)
	_alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_alarm)
	_alarm_label = _label(34, Color(1.0, 0.85, 0.82), 800)
	_alarm.add_child(_alarm_label)

	# Top right: lives.
	var right := _plate(root, Control.PRESET_TOP_RIGHT)
	var lives := HBoxContainer.new()
	lives.add_theme_constant_override("separation", 8)
	right.add_child(lives)
	for _i in LIFE_ICONS:
		var icon := HudIcon.make(HudIcon.Kind.LIFE, 40.0)
		lives.add_child(icon)
		_lives.append(icon)
	_lives_more = _label(34, INK, 700)
	lives.add_child(_lives_more)
	# Middle of the frame: the building bonus while the car drives off. Hidden until the exit.
	_bonus_plate = _plate(root, Control.PRESET_CENTER)
	_bonus_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bonus_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	var bonus_box := VBoxContainer.new()
	bonus_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_bonus_plate.add_child(bonus_box)
	_bonus_caption = _caption("UI_BONUS")
	_bonus_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus_box.add_child(_bonus_caption)
	_bonus = _label(BONUS_SIZE, INK, 800)
	_bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Room for the largest bonus right away: the panel does not grow while the number
	# counts up, and any number has the same air on its sides.
	var widest := format_score(Arcade.building_bonus(Arcade.BUILDING_BONUS_TOP))
	var width := (
		NeonStyle.font(800).get_string_size(widest, HORIZONTAL_ALIGNMENT_LEFT, -1, BONUS_SIZE).x
	)
	_bonus.custom_minimum_size.x = ceilf(width + BONUS_PAD * 2.0)
	bonus_box.add_child(_bonus)
	_bonus_plate.visible = false
	# Bottom right: frames per second, if asked to show them. Small and
	# muted — it is a reference, not part of the game.
	_fps_plate = _plate(root, Control.PRESET_BOTTOM_RIGHT)
	_fps = _label(22, INK_DIM, 600)
	_fps_plate.add_child(_fps)
	_fps_plate.visible = show_fps
	_restyle()


## Shows frames per second once per [constant FPS_EVERY]. By the wall clock,
## not by delta: the HUD lives on pause too.
func _count_frames() -> void:
	_fps_plate.visible = show_fps
	if not show_fps:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _fps_next:
		return
	_fps_next = now + FPS_EVERY
	_fps.text = "%d FPS" % roundi(Engine.get_frames_per_second())


## A panel at corner or edge [param preset] with margin [constant MARGIN].
func _plate(root: Control, preset: Control.LayoutPreset) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	plate.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, int(MARGIN))
	match preset:
		Control.PRESET_TOP_RIGHT:
			plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_BOTTOM_RIGHT:
			plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plates.append(plate)
	return plate


## Edge and glow of panels — in the building sign's colour.
func _restyle() -> void:
	for plate in _plates:
		plate.add_theme_stylebox_override("panel", NeonStyle.plate(PLATE, _neon))
	if _building != null:
		_building.add_theme_color_override("font_color", _neon)
	for icon in _documents + _lives:
		icon.set_state(icon.lit, _neon)


func _caption(key: String) -> Label:
	var label := _label(20, INK_DIM, 600)
	label.text = tr(key).to_upper()
	return label


func _label(font_size: int, colour: Color, weight: int) -> Label:
	return NeonStyle.label(font_size, colour, weight)


func _on_score_changed(_value: int) -> void:
	refresh()


func _on_documents_changed(_collected: int, _total: int) -> void:
	refresh()


func _on_lives_changed(_value: int) -> void:
	refresh()


func _on_building_changed(_number: int) -> void:
	refresh()


func _on_alarm_raised() -> void:
	refresh()
