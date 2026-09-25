class_name VerticalSign
extends Node3D

## Неоновая вывеска здания на углу фасада, буквами столбиком (ADR-0033,
## решение 2).
##
## До M21b неон HOTEL стоял на крыше, за техникой, и при спуске уходил за верх
## кадра и под HUD. Вывеска на углу висит вдоль верхних этажей снаружи здания
## лицом к камере: её не закрывает техника, и её видно всю дорогу вниз по
## башне. У отеля — имя и HOTEL, у офиса — имя корпорации.
##
## Свет — эмиссия букв и один источник отсвета, тот же, что был у неона на
## крыше: бюджет источников окружения не растёт. Одна буква изредка мигает —
## как у настоящего неона, у которого вот-вот сдохнет трубка.

## Шаг букв по высоте и их кегль, м; щит шире буквы на поля.
const LETTER_STEP: float = 0.82
const LETTER_SIZE: float = 0.7
const MARGIN: float = 0.3
## Докуда слышно гудение неона, м.
const BUZZ_REACH: float = 9.0
const PANEL_WIDTH: float = 1.1
const PANEL_DEPTH: float = 0.18
## Пробел между строками (имя и HOTEL), в шагах буквы.
const LINE_GAP: float = 0.6

## Насколько вывеска отстоит от боковой стены здания и где по глубине, м.
const STANDOFF: float = 0.75
const Z: float = -0.25
## Верх вывески над настилом крыши, м.
const RISE: float = 0.4

## Неон: отель — розовый, офис — холодный голубой. Не цвета огоньков игры
## (ADR-0023, решение 6).
const NEON_HOTEL := Color(1.0, 0.25, 0.55)
const NEON_OFFICE := Color(0.3, 0.85, 1.0)
const PANEL := Color(0.07, 0.07, 0.09)

## Отсвет: яркость и радиус, м.
const GLOW_ENERGY: float = 1.6
const GLOW_RANGE: float = 9.0

## Ореол неона в дожде: насколько шире щита и выше его, м, яркость и
## насколько позади щита — за задней стеной здания, чтобы ореол не лёг в
## коридоры.
const HALO_MARGIN := Vector2(2.4, 2.0)
const HALO_STRENGTH: float = 0.25
const HALO_BEHIND: float = 1.6

## Мигание: раз в сколько секунд буква гаснет и на сколько.
const FLICKER_EVERY: float = 3.7
const FLICKER_FOR: float = 0.18

var _letters: Array[Label3D] = []
var _glow: OmniLight3D = null
var _halo: MeshInstance3D = null
## Высота щита, м: по ней ореол в дожде.
var _height: float = 0.0
var _flicker: Label3D = null
var _clock: float = 0.0


## Вешает вывеску здания [param identity] у правой стены верхнего этажа.
func hang(rules: BuildingRules, identity: BuildingIdentity) -> void:
	name = "VerticalSign"
	var lines := identity.sign_lines()
	var neon := NEON_HOTEL if identity.is_hotel() else NEON_OFFICE
	var count := 0
	for line in lines:
		count += line.length()
	var height := (count + LINE_GAP * (lines.size() - 1)) * LETTER_STEP + MARGIN * 2.0
	_height = height
	var top := rules.floor_surface(BuildingRules.ROOF) - RISE
	var x := rules.floor_span(0).y + STANDOFF

	var panel := GreyboxLook.box(
		Vector3(PANEL_WIDTH, height, PANEL_DEPTH), GreyboxLook.metal(PANEL)
	)
	panel.position = WorldSpace.to_scene(Vector2(x, top + height * 0.5))
	panel.position.z = Z
	add_child(panel)
	# Неон гудит там, где висит (ADR-0036): слышно на крыше и верхних этажах.
	Sounds.source(panel, Sounds.NEON_BUZZ, BUZZ_REACH, true)
	# Кронштейны к стене: сверху и снизу.
	for share: float in [0.12, 0.88]:
		var arm := GreyboxLook.box(
			Vector3(STANDOFF, 0.08, 0.08), GreyboxLook.metal(PANEL.lightened(0.2))
		)
		arm.position = WorldSpace.to_scene(Vector2(x - STANDOFF * 0.5, top + height * share))
		arm.position.z = Z
		add_child(arm)

	var y := top + MARGIN + LETTER_STEP * 0.5
	for line in lines:
		for letter in line:
			var label := Label3D.new()
			label.text = letter
			label.font = NeonStyle.font(700)
			label.font_size = 96
			label.pixel_size = LETTER_SIZE / 96.0
			label.modulate = neon
			label.outline_modulate = neon.darkened(0.4)
			label.outline_size = 8
			label.shaded = false
			label.position = WorldSpace.to_scene(Vector2(x, y))
			label.position.z = Z + PANEL_DEPTH * 0.5 + 0.01
			add_child(label)
			_letters.append(label)
			y += LETTER_STEP
		y += LETTER_STEP * LINE_GAP
	# Мигает одна буква, по имени здания — всегда та же у этого здания.
	_flicker = (
		_letters[posmod(hash(identity.name), _letters.size())] if not _letters.is_empty() else null
	)

	var glow := OmniLight3D.new()
	_glow = glow
	glow.name = "NeonGlow"
	glow.light_color = neon
	glow.light_energy = GLOW_ENERGY
	glow.omni_range = GLOW_RANGE
	glow.shadow_enabled = false
	glow.position = WorldSpace.to_scene(Vector2(x, top + height * 0.5))
	glow.position.z = Z + 1.2
	add_child(glow)
	add_to_group(Graphics.GROUP)
	apply_graphics()


## Ореол неона в дожде (ADR-0037, решение 3, дополнение): дождь у вывески
## светится её цветом. Только в дождь — в ясную ночь воздух прозрачный.
func glow_in_rain() -> void:
	if _glow == null or _halo != null:
		return
	_halo = RainLook.halo(
		Vector3(_glow.position.x, _glow.position.y, Z - HALO_BEHIND),
		_glow.light_color,
		HALO_STRENGTH,
		Vector2(PANEL_WIDTH, _height) + HALO_MARGIN
	)
	add_child(_halo)


## Ореол неона в дожде — для теста; вне дождя его нет.
func halo() -> MeshInstance3D:
	return _halo


## Отсвет неона в объёмном тумане — по уровню качества (ADR-0034, решение 1):
## на «Ультра» вокруг вывески светится воздух.
func apply_graphics() -> void:
	if _glow != null:
		_glow.light_volumetric_fog_energy = Graphics.light_in_fog()


## Мигает буквой. Картинка, а не правило: по настенным часам.
func _process(delta: float) -> void:
	if _flicker == null:
		return
	_clock = fmod(_clock + delta, FLICKER_EVERY)
	_flicker.visible = _clock > FLICKER_FOR


## Текст вывески сверху вниз, буквами без пробелов: для тестов.
func text() -> String:
	var joined := ""
	for label in _letters:
		joined += label.text
	return joined
