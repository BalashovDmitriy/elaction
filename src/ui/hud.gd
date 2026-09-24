class_name Hud
extends CanvasLayer

## Игровой HUD: только то, без чего не сыграть (ADR-0012, пункт 8).
##
## С M22 — неон-нуар (решение пользователя): тёмные полупрозрачные плашки с
## неоновой кромкой в цвет вывески здания, узкий шрифт Exo 2, значки вместо
## слов. Слева сверху — очки и документы папками, по центру — имя здания и этаж,
## где Otto, справа — жизни силуэтами, внизу справа — раунд, под именем здания —
## мигающая плашка тревоги.
##
## Строки автомата с рекордом нет: игра ремейк, интерфейс на той же стороне, что
## картинка и звук. Всё собирается кодом: плашки — данные, а не разметка.

## Как часто мигает тревога, раз в секунду, и насколько тускнеет в нижней точке.
const ALARM_BLINKS: float = 1.6
const ALARM_DIM: float = 0.35

## Сколько папок документов заведено: больше, чем бывает в здании. По ROM
## красных дверей от 5 до 10, по навыку ([method Arcade.red_doors]), — видно
## столько папок, сколько документов в этом здании.
const DOCUMENT_ICONS: int = 10
## Больше стольких жизней значками не рисуется — дальше число.
const LIFE_ICONS: int = 5

const FONT := preload("res://assets/fonts/Exo2.ttf")
const MARGIN: float = 28.0

const INK := Color(0.93, 0.94, 0.97)
const INK_DIM := Color(0.62, 0.66, 0.76)
const ALARM := Color(1.0, 0.22, 0.2)
const PLATE := Color(0.03, 0.035, 0.06, 0.62)

## Кромка, если здание не сказало своего цвета: неон первого здания — отеля.
const DEFAULT_NEON := VerticalSign.NEON_HOTEL

var _neon := DEFAULT_NEON
var _score_caption: Label = null
var _score: Label = null
var _documents: Array[HudIcon] = []
var _lives: Array[HudIcon] = []
var _lives_more: Label = null
var _building: Label = null
var _floor: Label = null
var _round: Label = null
var _alarm: PanelContainer = null
var _alarm_label: Label = null
var _plates: Array[PanelContainer] = []
var _level: GreyboxLevel = null
var _shown_floor: int = -2


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
	if not _alarm.visible:
		return
	# Мигание считается от времени, а не накопителем: HUD живёт и на паузе,
	# а под паузой delta не приходит вовсе.
	var phase := sin(Time.get_ticks_msec() / 1000.0 * ALARM_BLINKS * TAU) * 0.5 + 0.5
	_alarm.modulate.a = ALARM_DIM + (1.0 - ALARM_DIM) * phase


## Язык сменили в меню посреди партии: подписи собраны кодом из перевода в
## верхнем регистре и сами не переведутся — подпись очков так и осталась бы на
## прежнем языке до конца игры, а этаж — до следующего этажа (авторевью M22).
func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or _score_caption == null:
		return
	_score_caption.text = tr("UI_SCORE").to_upper()
	_shown_floor = -2
	refresh()


## Здание, за которым следит HUD: его имя, цвет вывески и этаж Otto.
func follow(level: GreyboxLevel) -> void:
	_level = level
	_shown_floor = -2
	if level != null and level.identity != null:
		_neon = VerticalSign.NEON_HOTEL if level.identity.is_hotel() else VerticalSign.NEON_OFFICE
		_building.text = " ".join(level.identity.sign_lines())
	_restyle()
	refresh()


## Перерисовывает всё разом. Зовётся на входе в здание и при смене состояния:
## сигналов у партии много, а полей мало, и разбирать их по одному незачем.
func refresh() -> void:
	var game := GameState.instance()
	_score.text = format_score(game.score)
	for index in _documents.size():
		_documents[index].set_state(index < game.documents_collected, _neon)
	_documents_row_visible(game.documents_total)
	for index in _lives.size():
		_lives[index].visible = index < mini(game.lives, LIFE_ICONS)
		_lives[index].set_state(true, _neon)
	_lives_more.visible = game.lives > LIFE_ICONS
	_lives_more.text = "×%d" % game.lives
	# «Раунд», а не «здание»: так счётчик называется и в аркаде, и в порте
	# (ADR-0017, решение 5).
	_round.text = "%s %d" % [tr("UI_ROUND").to_upper(), game.building]
	_alarm_label.text = tr("UI_ALARM")
	_alarm.visible = game.alarm.raised


## Счёт с пробелами по три цифры: 12 400 читается с одного взгляда, 12400 — нет.
static func format_score(score: int) -> String:
	var digits := str(absi(score))
	var grouped := ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			grouped += " "
		grouped += digits[index]
	return ("-" if score < 0 else "") + grouped


## Этаж, где стоит Otto, так, как его видит игрок: номер таблички или крыша.
static func floor_text(rules: BuildingRules, index: int) -> String:
	if index == BuildingRules.ROOF:
		return TranslationServer.translate("UI_ROOF").to_upper()
	return (
		"%s %d"
		% [TranslationServer.translate("UI_FLOOR").to_upper(), FloorSigns.number_of(rules, index)]
	)


func _follow_floor() -> void:
	# Вне дерева — здание, которое main уже снял и ещё не освободил (выход в
	# меню): у его Otto нет глобального положения (авторевью M22).
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


# --- Сборка ------------------------------------------------------------------


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Слева сверху: очки и документы.
	var left := _plate(root, Control.PRESET_TOP_LEFT)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 2)
	left.add_child(left_box)
	_score_caption = _caption("UI_SCORE")
	left_box.add_child(_score_caption)
	_score = _label(56, INK, 700)
	left_box.add_child(_score)
	var docs := HBoxContainer.new()
	docs.add_theme_constant_override("separation", 6)
	left_box.add_child(docs)
	for _i in DOCUMENT_ICONS:
		var icon := HudIcon.make(HudIcon.Kind.DOCUMENT, 34.0)
		docs.add_child(icon)
		_documents.append(icon)

	# По центру сверху: здание и этаж.
	var middle := _plate(root, Control.PRESET_CENTER_TOP)
	var middle_box := VBoxContainer.new()
	middle_box.alignment = BoxContainer.ALIGNMENT_CENTER
	middle.add_child(middle_box)
	_building = _label(26, _neon, 600)
	_building.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle_box.add_child(_building)
	_floor = _label(44, INK, 700)
	_floor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle_box.add_child(_floor)

	# Тревога — под зданием.
	_alarm = PanelContainer.new()
	_alarm.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_alarm.position = Vector2(0.0, 150.0)
	_alarm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alarm.add_theme_stylebox_override("panel", _style(Color(0.3, 0.02, 0.02, 0.75), ALARM))
	_alarm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_alarm)
	_alarm_label = _label(34, Color(1.0, 0.85, 0.82), 800)
	_alarm.add_child(_alarm_label)

	# Справа сверху: жизни.
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

	# Справа снизу: раунд.
	var corner := _plate(root, Control.PRESET_BOTTOM_RIGHT)
	_round = _label(30, INK_DIM, 600)
	corner.add_child(_round)
	_restyle()


## Плашка у угла или края [param preset] с отступом [constant MARGIN].
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


## Кромка и ореол плашек — в цвет вывески здания.
func _restyle() -> void:
	for plate in _plates:
		plate.add_theme_stylebox_override("panel", _style(PLATE, _neon))
	if _building != null:
		_building.add_theme_color_override("font_color", _neon)
	for icon in _documents + _lives:
		icon.set_state(icon.lit, _neon)


static func _style(background: Color, neon: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(8)
	box.border_width_left = 3
	box.border_color = Color(neon, 0.9)
	box.shadow_color = Color(neon, 0.18)
	box.shadow_size = 14
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	return box


func _caption(key: String) -> Label:
	var label := _label(20, INK_DIM, 600)
	label.text = tr(key).to_upper()
	return label


func _label(font_size: int, colour: Color, weight: int) -> Label:
	var label := Label.new()
	var variation := FontVariation.new()
	variation.base_font = FONT
	variation.variation_opentype = {"wght": weight}
	label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


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
