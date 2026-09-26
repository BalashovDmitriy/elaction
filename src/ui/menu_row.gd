class_name MenuRow
extends Button

## Пункт меню — плашка в стиле HUD (ADR-0035, решение 4).
##
## Один класс на все виды пунктов: кнопка, переключатель «‹ значение ›», уровень
## громкости, флажок и назначение клавиши. Выпадающие списки заменены переключателем: влево-вправо
## листают, и с геймпада это одно нажатие, а не открытый поверх страницы список.
##
## Выбранный пункт загорается плавно: кромка шире, ореол ярче, текст чуть
## сдвигается вправо. Фокус идёт за мышью, поэтому состояние у пункта одно —
## выбран или нет, — и «наведён, но не выбран» не бывает.

## Значение сменилось: индекс варианта, уровень 0..1 или флажок.
signal changed(value: Variant)

enum Kind { ACTION, CHOICE, LEVEL, TOGGLE, BINDING }

## Сколько длится вспышка выбора, с.
const GLOW_TIME: float = 0.14
## Насколько выбранный пункт сдвигает текст вправо, px.
const INDENT: float = 14.0
## Шаг уровня громкости: двадцать делений на всю шкалу.
const LEVEL_STEP: float = 0.05
## Ширина полосы уровня, px.
const BAR_WIDTH: float = 220.0

const FILL_IDLE := Color(0.03, 0.035, 0.06, 0.38)
const FILL_LIT := Color(0.05, 0.05, 0.09, 0.78)

var kind: Kind = Kind.ACTION
var options: Array[String] = []
var index: int = 0
var level: float = 0.0
var on: bool = false
## Что написано справа у назначения: клавиша и кнопка или «нажмите клавишу».
var shown: String = ""
## Цвет кромки и ореола. Меню задаёт его уже собранному пункту, поэтому стиль
## пересобирается сразу, а не с первой вспышкой фокуса.
var neon: Color = VerticalSign.NEON_HOTEL:
	set(value):
		neon = value
		_restyle()

## 0 — не выбран, 1 — выбран; между ними — вспышка.
var glow: float = 0.0:
	set(value):
		glow = value
		_restyle()

var _box := StyleBoxFlat.new()
var _caption: Label = null
var _value: Label = null
var _tween: Tween = null


## Кнопка: подпись и действие по нажатию.
static func action(caption: String, font_size: int = 40) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.ACTION
	row._build(caption, font_size)
	return row


## Переключатель: подпись слева, «‹ вариант ›» справа.
static func choice(caption: String, variants: Array[String], selected: int) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.CHOICE
	row.options = variants
	row.index = clampi(selected, 0, maxi(variants.size() - 1, 0))
	row._build(caption, 30)
	return row


## Уровень 0..1 полосой и процентами — громкость.
static func slider(caption: String, value: float) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.LEVEL
	row.level = clampf(value, 0.0, 1.0)
	row._build(caption, 30)
	return row


## Флажок: «вкл» и «выкл».
static func toggle(caption: String, value: bool) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.TOGGLE
	row.on = value
	row._build(caption, 30)
	return row


## Назначение: подпись действия слева, его клавиша и кнопка справа. Нажатие
## не листает, а отдаётся меню — оно слушает следующую клавишу (ADR-0039).
static func binding(caption: String, value: String) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.BINDING
	row.shown = value
	row._build(caption, 30)
	return row


## Меняет то, что написано справа у назначения.
func show_text(value: String) -> void:
	shown = value
	_show_value()


## Что написано справа: вариант, проценты или «вкл/выкл». Нужно тестам.
func value_text() -> String:
	return _value.text if _value != null else ""


## Листает значение на [param step]: −1 — влево, +1 — вправо.
func step_value(step: int) -> void:
	match kind:
		Kind.CHOICE:
			if options.is_empty():
				return
			index = wrapi(index + step, 0, options.size())
			changed.emit(index)
		Kind.LEVEL:
			var next := clampf(snappedf(level + step * LEVEL_STEP, LEVEL_STEP), 0.0, 1.0)
			# Упёрлись в край — ничего не сменилось: ни щелчка, ни записи в шину.
			if is_equal_approx(next, level):
				return
			level = next
			changed.emit(level)
		Kind.TOGGLE:
			on = not on
			changed.emit(on)
		_:
			return
	_show_value()
	queue_redraw()


func _build(caption: String, font_size: int) -> void:
	focus_mode = Control.FOCUS_ALL
	flat = false
	text = ""
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(0.0, font_size * 1.7)
	for state: String in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, _box)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 24)
	add_child(line)

	var weight := 700 if kind == Kind.ACTION else 600
	_caption = NeonStyle.label(font_size, NeonStyle.INK_DIM, weight)
	_caption.text = caption
	_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(_caption)

	if kind != Kind.ACTION:
		_value = NeonStyle.label(font_size, NeonStyle.INK, 700)
		_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if kind == Kind.LEVEL:
			# Место под полосу слева от процентов: её рисует [method _draw].
			_value.custom_minimum_size = Vector2(BAR_WIDTH + 110.0, 0.0)
		line.add_child(_value)
		_show_value()

	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	mouse_entered.connect(grab_focus)
	pressed.connect(_on_pressed)
	_restyle()


func _gui_input(event: InputEvent) -> void:
	if kind == Kind.ACTION or kind == Kind.BINDING:
		return
	# Громкость листается с повтором, как фокус вверх-вниз: двадцать делений
	# по одному нажатию — это двадцать нажатий. Варианты — без повтора: смена
	# языка пересобирает страницу на каждый шаг.
	var repeat := kind == Kind.LEVEL
	if event.is_action_pressed(&"ui_left", repeat):
		step_value(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", repeat):
		step_value(1)
		accept_event()


func _on_pressed() -> void:
	# Нажатие листает вперёд: мышью по переключателю, как по кнопке.
	if kind != Kind.ACTION and kind != Kind.BINDING:
		step_value(1)


func _on_focus_changed(focused: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	# Меню живёт и на паузе, и вспышка обязана идти вместе с ним.
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "glow", 1.0 if focused else 0.0, GLOW_TIME)


func _show_value() -> void:
	if _value == null:
		return
	match kind:
		Kind.CHOICE:
			var shown := options[index] if index < options.size() else ""
			_value.text = "‹  %s  ›" % shown
		Kind.LEVEL:
			_value.text = "%d%%" % roundi(level * 100.0)
		Kind.TOGGLE:
			_value.text = "‹  %s  ›" % tr("UI_ON" if on else "UI_OFF")
		Kind.BINDING:
			_value.text = shown


func _restyle() -> void:
	_box.bg_color = FILL_IDLE.lerp(FILL_LIT, glow)
	_box.set_corner_radius_all(8)
	_box.border_width_left = roundi(lerpf(NeonStyle.EDGE, NeonStyle.EDGE_LIT, glow))
	_box.border_color = Color(neon, lerpf(0.35, 1.0, glow))
	_box.shadow_color = Color(neon, lerpf(0.0, 0.34, glow))
	_box.shadow_size = roundi(lerpf(0.0, 18.0, glow))
	_box.content_margin_left = 24.0 + INDENT * glow
	_box.content_margin_right = 24.0
	if _caption != null:
		_caption.add_theme_color_override("font_color", NeonStyle.INK_DIM.lerp(NeonStyle.INK, glow))
		# Подпись сдвигается вместе с полем: оно у HBox, а не у стиля.
		_caption.get_parent().set("offset_left", _box.content_margin_left)
		_caption.get_parent().set("offset_right", -_box.content_margin_right)
	queue_redraw()


func _draw() -> void:
	if kind != Kind.LEVEL or _value == null:
		return
	# Полоса уровня — перед процентами: тусклая дорожка и неоновая заливка.
	var right := size.x - _box.content_margin_right - 96.0
	var track := Rect2(right - BAR_WIDTH, size.y * 0.5 - 3.0, BAR_WIDTH, 6.0)
	draw_rect(track, Color(NeonStyle.INK_DIM, 0.25))
	var fill := Rect2(track.position, Vector2(BAR_WIDTH * level, track.size.y))
	draw_rect(fill, Color(neon, lerpf(0.7, 1.0, glow)))
