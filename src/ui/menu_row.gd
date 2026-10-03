class_name MenuRow
extends Button

## A menu item — a panel in the HUD style (ADR-0035, decision 4).
##
## One class for all item kinds: a button, a "‹ value ›" switch, a volume
## level, a flag and a key binding. Drop-down lists are replaced by a switch: left-right
## pages through values, and on a gamepad it is one press, not a list opened over the page.
##
## The selected item lights up smoothly: the edge widens, the glow brightens, the text shifts
## slightly to the right. Focus follows the mouse, so an item has one state —
## selected or not — and "hovered but not selected" does not happen.

## The value changed: variant index, level 0..1 or flag.
signal changed(value: Variant)

enum Kind { ACTION, CHOICE, LEVEL, TOGGLE, BINDING }

## How long the selection flash lasts, s.
const GLOW_TIME: float = 0.14
## How far the selected item shifts the text to the right, px.
const INDENT: float = 14.0
## Volume level step: twenty divisions over the whole scale.
const LEVEL_STEP: float = 0.05
## Width of the level bar, px.
const BAR_WIDTH: float = 220.0

const FILL_IDLE := Color(0.03, 0.035, 0.06, 0.38)
const FILL_LIT := Color(0.05, 0.05, 0.09, 0.78)

var kind: Kind = Kind.ACTION
var options: Array[String] = []
var index: int = 0
var level: float = 0.0
var on: bool = false
## What is written on the right of a binding: key and button, or "press a key".
var shown: String = ""
## Edge and glow colour. The menu sets it on an already built item, so the style
## is rebuilt immediately, not with the first focus flash.
var neon: Color = VerticalSign.NEON_HOTEL:
	set(value):
		neon = value
		_restyle()

## 0 — not selected, 1 — selected; in between — the flash.
var glow: float = 0.0:
	set(value):
		glow = value
		_restyle()

var _box := StyleBoxFlat.new()
var _caption: Label = null
var _value: Label = null
var _tween: Tween = null


## Button: caption and action on press.
static func action(caption: String, font_size: int = 40) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.ACTION
	row._build(caption, font_size)
	return row


## Switch: caption on the left, "‹ variant ›" on the right.
static func choice(caption: String, variants: Array[String], selected: int) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.CHOICE
	row.options = variants
	row.index = clampi(selected, 0, maxi(variants.size() - 1, 0))
	row._build(caption, 30)
	return row


## Level 0..1 as a bar and percent — volume.
static func slider(caption: String, value: float) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.LEVEL
	row.level = clampf(value, 0.0, 1.0)
	row._build(caption, 30)
	return row


## Flag: "on" and "off".
static func toggle(caption: String, value: bool) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.TOGGLE
	row.on = value
	row._build(caption, 30)
	return row


## Binding: the action caption on the left, its key and button on the right. A press
## does not page through values but goes to the menu — it listens for the next key (ADR-0039).
static func binding(caption: String, value: String) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.BINDING
	row.shown = value
	row._build(caption, 30)
	return row


## Changes what is written on the right of a binding.
func show_text(value: String) -> void:
	shown = value
	_show_value()


## What is written on the right: variant, percent or "on/off". Needed by tests.
func value_text() -> String:
	return _value.text if _value != null else ""


## Pages the value by [param step]: −1 — left, +1 — right.
func step_value(step: int) -> void:
	match kind:
		Kind.CHOICE:
			if options.is_empty():
				return
			index = wrapi(index + step, 0, options.size())
			changed.emit(index)
		Kind.LEVEL:
			var next := clampf(snappedf(level + step * LEVEL_STEP, LEVEL_STEP), 0.0, 1.0)
			# Hit the edge — nothing changed: no click, no write to the bus.
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
			# Room for the bar to the left of the percent: [method _draw] draws it.
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
	# Volume pages with repeat, like focus up-down: twenty divisions
	# one press at a time is twenty presses. Variants — without repeat: changing
	# the language rebuilds the page on every step.
	var repeat := kind == Kind.LEVEL
	if event.is_action_pressed(&"ui_left", repeat):
		step_value(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", repeat):
		step_value(1)
		accept_event()


func _on_pressed() -> void:
	# A press pages forward: with the mouse on a switch, as on a button.
	if kind != Kind.ACTION and kind != Kind.BINDING:
		step_value(1)


func _on_focus_changed(focused: bool) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	# The menu lives on pause too, and the flash must run together with it.
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
		# The caption shifts together with the margin: it belongs to the HBox, not the style.
		_caption.get_parent().set("offset_left", _box.content_margin_left)
		_caption.get_parent().set("offset_right", -_box.content_margin_right)
	queue_redraw()


func _draw() -> void:
	if kind != Kind.LEVEL or _value == null:
		return
	# The level bar — before the percent: a dim track and a neon fill.
	var right := size.x - _box.content_margin_right - 96.0
	var track := Rect2(right - BAR_WIDTH, size.y * 0.5 - 3.0, BAR_WIDTH, 6.0)
	draw_rect(track, Color(NeonStyle.INK_DIM, 0.25))
	var fill := Rect2(track.position, Vector2(BAR_WIDTH * level, track.size.y))
	draw_rect(fill, Color(neon, lerpf(0.7, 1.0, glow)))
