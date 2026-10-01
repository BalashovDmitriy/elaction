class_name DoorRoom
extends Node3D

## Комната за дверью (ADR-0047): номер отеля или кабинет офиса.
##
## Видна, пока створка открыта: ортокамера смотрит в проём почти в лоб, и в
## нём — задняя стена комнаты с окном и тем, что стоит перед ней, и полоса пола
## (камера наклонена на [constant SideCamera.TILT_DEGREES]).
## Потолка не видно, боковые стены — на случай света: он не уходит в пустоту
## за коридором.
##
## Собирает её дверь, когда створка трогается, и убирает, когда закрылась:
## дверей в здании полсотни, и держать полсотни комнат со своим светом — лишнее.
## Жребий — по двери: одна и та же дверь открывается в ту же комнату.
##
## Окно — проём в задней стене со стеклом (ADR-0052, решение 5): за ним тот же
## город, что за зданием ([CityBackdrop]), — он рисуется позади всей сцены, и в
## проёме виден он сам, с фасадами пака, небом, погодой и временем суток.
##
## Координаты — двери: X вдоль стены от середины проёма, Y — от пола, Z —
## сцены, комната за задней стеной коридора.

## Размер комнаты, м: ширина вдоль стены и глубина от стены коридора.
const WIDTH: float = 4.2
const DEPTH: float = 3.6
## Высота комнаты: этаж без перекрытия.
const HEIGHT: float = Proportions.FLOOR - Proportions.SLAB
## Толщина стен, м.
const WALL: float = 0.08
## Створка распахивается в комнату на свою ширину: ближе этого к стене
## коридора мебели нет.
const LEAF_CLEAR: float = Door.LEAF_SIZE.x + 0.1
## Насколько комната сдвинута вдоль стены от середины проёма, м: жребий, чтобы
## двери одного этажа не открывались в одну и ту же картинку.
const SHIFT: float = 0.6
## Окно в задней стене: ширина, высота и низ над полом, м.
const WINDOW := Vector2(1.2, 1.35)
const WINDOW_SILL: float = 0.9
const FRAME: float = 0.06
## Свет комнаты: под потолком, без тени. Отель — тёплый, офис — холодный
## белый ламп дневного света.
const HOTEL_LIGHT := Color(1.0, 0.76, 0.5)
const OFFICE_LIGHT := Color(0.86, 0.93, 1.0)
const LIGHT_ENERGY: float = 2.3
const LIGHT_RANGE: float = 4.6
## Лампа на тумбе — свой тёплый огонёк рядом с абажуром.
const LAMP_LIGHT := Color(1.0, 0.7, 0.4)
const LAMP_ENERGY: float = 1.2
const LAMP_RANGE: float = 1.8
## Отделка: обои и пол отеля, краска и ковролин офиса, потолок.
const HOTEL_WALL := Color(0.62, 0.5, 0.4)
const HOTEL_FLOOR := Color(0.32, 0.1, 0.1)
const OFFICE_WALL := Color(0.66, 0.68, 0.7)
const OFFICE_FLOOR := Color(0.26, 0.28, 0.31)
const CEILING := Color(0.85, 0.83, 0.8)
const WINDOW_FRAME := Color(0.9, 0.88, 0.84)
const WINDOW_SHADER := preload("res://src/levels/room_window.gdshader")
## Облачный свет из окна: в туман и дождь солнце уходит к серому.
const WINDOW_OVERCAST := Color(0.5, 0.52, 0.56)
## Солнце из окна днём (ADR-0052, решение 5): пятно на полу и мебели. Свой
## источник вместо света под потолком — комнат открыто одна-две, бюджет тот
## же. Без тени: тень от рамы дороже, чем видна.
const SUN_ENERGY: float = 4.0
const SUN_RANGE: float = 5.5
const SUN_ANGLE: float = 21.0
## Насколько солнце падает вниз из окна, градусы.
const SUN_PITCH: float = 44.0
## Картины и доски на стене комнаты — те же, что в коридоре.
const HOTEL_ART: PackedStringArray = ["painting", "wall_art_02", "wall_art_03", "wall_art_05"]
const OFFICE_ART: PackedStringArray = ["whiteboard", "calendar", "corkboard", "analog_clock"]

## Сколько комнат сейчас открыто: пока хоть одна, город за зданием рисуется,
## даже когда здание закрыло весь кадр, — его видно в окне.
static var open_count: int = 0

## Что стоит в комнате: имя предмета каталога, где (X вдоль стены, Z от задней
## стены комнаты к коридору, м) и поворот, градусы. Тестам и кадрам.
var placed: Array[Dictionary] = []
var hotel: bool = true
## Этаж тёмный по правилам ROM: своего света у комнаты нет, светится только
## окно с городом — темнота этажа не нарушается (решение пользователя, M24i).
var dark: bool = false
## Время суток за окном: днём свет в комнате не горит, светит солнце.
var time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
var weather: Weather.Kind = Weather.Kind.CLEAR

var _wall_look: StandardMaterial3D = null
var _shift: float = 0.0


## Собирает комнату: [param is_hotel] — номер отеля или кабинет, [param seed] —
## жребий двери, [param identity] — здание, его отделка. [param span] — этаж
## от стены до стены по X двери: за его наружные стены комната не выходит.
## [param unlit] — этаж тёмный: комната без своего света ([member dark]).
## [param when] и [param sky] — время суток и погода за окном.
static func build(
	is_hotel: bool,
	seed: int,
	identity: BuildingIdentity = null,
	span: Vector2 = Vector2(-INF, INF),
	unlit: bool = false,
	when: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	sky: Weather.Kind = Weather.Kind.CLEAR
) -> DoorRoom:
	var room := DoorRoom.new()
	room.name = "Room"
	room.hotel = is_hotel
	room.dark = unlit
	room.time = when
	room.weather = sky
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# У крайнего места этажа до наружной стены 2.4 м, а комната со сдвигом
	# уходит от проёма на 2.7: без упора она торчала бы из силуэта здания полосой
	# стены, пола и потолка (авторевью M24i). Жребий тот же, сдвиг — в упор.
	var half := (WIDTH + WALL) * 0.5
	var shift := clampf(rng.randf_range(-SHIFT, SHIFT), span.x + half, span.y - half)
	room._shell(shift, identity)
	var window_x := shift + rng.randf_range(-0.3, 0.3)
	room._window(window_x, rng)
	if is_hotel:
		room._furnish_hotel(rng)
	else:
		room._furnish_office(rng)
	if room.is_sunlit():
		room._sun_in(window_x)
	elif not unlit:
		room._light(shift, is_hotel)
	return room


func _enter_tree() -> void:
	open_count += 1


func _exit_tree() -> void:
	open_count = maxi(open_count - 1, 0)


## Светло ли за окном: утро и день. Тогда свет в комнате не горит, а из окна
## падает солнце — или, в непогоду, просто дневной свет.
func is_sunlit() -> bool:
	return TimeOfDay.is_daytime(time)


## Где задняя стена комнаты, Z сцены.
static func back_z() -> float:
	return WorldSpace.BACK_WALL_Z - DEPTH


## Пол, потолок, задняя и боковые стены.
func _shell(shift: float, identity: BuildingIdentity) -> void:
	var wall_tone := HOTEL_WALL if hotel else OFFICE_WALL
	var wall := (
		BuildingFinish.wall(identity, wall_tone)
		if identity != null
		else GreyboxLook.surface(wall_tone)
	)
	var floor_look := GreyboxLook.surface(HOTEL_FLOOR if hotel else OFFICE_FLOOR)
	var middle := WorldSpace.BACK_WALL_Z - DEPTH * 0.5
	_box(Vector3(WIDTH, 0.02, DEPTH), Vector3(shift, 0.01, middle), floor_look)
	_box(
		Vector3(WIDTH, 0.02, DEPTH),
		Vector3(shift, HEIGHT - 0.01, middle),
		GreyboxLook.surface(CEILING)
	)
	_wall_look = wall
	_shift = shift
	for side: float in [-1.0, 1.0]:
		_box(
			Vector3(WALL, HEIGHT, DEPTH),
			Vector3(shift + side * WIDTH * 0.5, HEIGHT * 0.5, middle),
			wall
		)


## Окно на город в задней стене с рамой и подоконником; у отеля — шторы.
func _window(x: float, rng: RandomNumberGenerator) -> void:
	_wall_around(x)
	var glass := QuadMesh.new()
	glass.size = WINDOW
	var look := ShaderMaterial.new()
	look.shader = WINDOW_SHADER
	look.set_shader_parameter(&"seed", rng.randf() * 100.0)
	look.set_shader_parameter(&"blinds", 0.0 if hotel else 1.0)
	glass.material = look
	var pane := MeshInstance3D.new()
	pane.name = "Window"
	pane.mesh = glass
	pane.position = Vector3(x, WINDOW_SILL + WINDOW.y * 0.5, back_z() + 0.005)
	add_child(pane)
	var frame := GreyboxLook.polished(WINDOW_FRAME)
	var z := back_z() + FRAME * 0.5
	var middle_y := WINDOW_SILL + WINDOW.y * 0.5
	for side: float in [-1.0, 1.0]:
		_box(
			Vector3(FRAME, WINDOW.y + FRAME * 2.0, FRAME),
			Vector3(x + side * (WINDOW.x + FRAME) * 0.5, middle_y, z),
			frame
		)
		_box(
			Vector3(WINDOW.x, FRAME, FRAME),
			Vector3(x, middle_y + side * (WINDOW.y + FRAME) * 0.5, z),
			frame
		)
	_box(Vector3(FRAME * 0.6, WINDOW.y, FRAME * 0.6), Vector3(x, middle_y, z), frame)
	_box(
		Vector3(WINDOW.x + 0.2, 0.04, 0.16), Vector3(x, WINDOW_SILL - 0.02, back_z() + 0.08), frame
	)
	if hotel:
		_put("curtains", x, 0.12, 0.0, WINDOW.x + 0.9)


## Задняя стена с проёмом под окно: слева, справа, над окном и под ним.
func _wall_around(x: float) -> void:
	var z := back_z() - WALL * 0.5
	var left := _shift - WIDTH * 0.5
	var right := _shift + WIDTH * 0.5
	var low := x - WINDOW.x * 0.5
	var high := x + WINDOW.x * 0.5
	var top := WINDOW_SILL + WINDOW.y
	_box(
		Vector3(low - left, HEIGHT, WALL), Vector3((left + low) * 0.5, HEIGHT * 0.5, z), _wall_look
	)
	_box(
		Vector3(right - high, HEIGHT, WALL),
		Vector3((high + right) * 0.5, HEIGHT * 0.5, z),
		_wall_look
	)
	_box(Vector3(WINDOW.x, HEIGHT - top, WALL), Vector3(x, (top + HEIGHT) * 0.5, z), _wall_look)
	_box(Vector3(WINDOW.x, WINDOW_SILL, WALL), Vector3(x, WINDOW_SILL * 0.5, z), _wall_look)


## Номер отеля: кровать изголовьем к стене, тумба с лампой, ковёр, картина над
## кроватью; кровать слева или справа от окна — жребий.
func _furnish_hotel(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var bed := "bed_hotel" if rng.randf() < 0.6 else "bed_double"
	# Кровать — в створе двери наполовину: её и видно в проём, а тумба с
	# лампой — рядом. Комната сдвинута жребием, кровать — от проёма.
	var bed_x := side * rng.randf_range(0.35, 0.6)
	var bed_size := _put(bed, bed_x, 0.02, 0.0)
	var stand_x := bed_x - side * (bed_size.x * 0.5 + 0.35)
	_put("night_stand" if rng.randf() < 0.5 else "night_stand_b", stand_x, 0.05, 0.0)
	# Днём лампа на тумбе погашена, как и свет под потолком.
	if not dark and not is_sunlit():
		_lamp_glow(stand_x)
	_put("rug", bed_x * 0.5, bed_size.z * 0.55, 0.0, 1.8)
	_hang(HOTEL_ART[rng.randi_range(0, HOTEL_ART.size() - 1)], bed_x, 1.75)


## Кабинет: рабочее место у стены, стеллаж или картотека в стороне, доска или
## календарь на стене.
func _furnish_office(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# Стол — в створе двери: его с креслом и видно в проём.
	var desk_x := side * rng.randf_range(0.0, 0.3)
	var roll := rng.randf()
	if roll < 0.35:
		_put("workstation_a", desk_x, 0.05, 0.0)
	elif roll < 0.7:
		_put("workstation_b", desk_x, 0.05, 0.0)
	else:
		var desk := _put("desk", desk_x, 0.05, 0.0)
		_put("office_chair", desk_x, desk.z + 0.1, 180.0)
	var aside := desk_x - side * 1.35
	_put("bookshelf" if rng.randf() < 0.5 else "file_cabinet", aside, 0.05, 0.0)
	_put("potted_plant", desk_x + side * 1.2, 0.15, 0.0)
	_hang(OFFICE_ART[rng.randi_range(0, OFFICE_ART.size() - 1)], desk_x, 1.7)


## Ставит предмет каталога задом к задней стене комнаты: [param x] — середина
## вдоль стены, [param from_wall] — отступ от стены, м, [param yaw] —
## доповорот, градусы. [param width] — привести к ширине вместо роста каталога.
## Возвращает габарит поставленного. Ближе [constant LEAF_CLEAR] к стене
## коридора предмет не заходит: там ходит створка.
func _put(prop: String, x: float, from_wall: float, yaw: float, width: float = 0.0) -> Vector3:
	var node := PropCatalog.make(prop, true)
	if node == null:
		return Vector3.ZERO
	var size := PropCatalog.bounds_of(node).size
	if width > 0.0 and size.x > 0.001:
		node.scale = Vector3.ONE * (width / size.x)
		size *= width / size.x
	var room_for := DEPTH - LEAF_CLEAR - from_wall
	if size.z > room_for and size.z > 0.001:
		var fit := room_for / size.z
		node.scale *= fit
		size *= fit
	node.rotation.y = deg_to_rad(yaw)
	# У предмета каталога нуль — у задней грани: к стене он ставится одним
	# сдвигом. Развёрнутый лицом к стене (кресло у стола) уходит от нуля к
	# стене — его нуль на свою глубину дальше.
	var turned := absf(yaw) > 90.0
	node.position = Vector3(x, 0.02, back_z() + from_wall + (size.z if turned else 0.0))
	add_child(node)
	placed.append({"prop": prop, "x": x, "size": size, "from_wall": from_wall, "yaw": yaw})
	return size


## Вешает картину или доску на заднюю стену: середина на высоте [param y].
func _hang(prop: String, x: float, y: float) -> void:
	var node := PropCatalog.make(prop, true)
	if node == null:
		return
	var size := PropCatalog.bounds_of(node).size
	node.position = Vector3(x, y - size.y * 0.5, back_z() + 0.01)
	add_child(node)
	placed.append({"prop": prop, "x": x, "size": size, "from_wall": 0.0, "yaw": 0.0})


## Свет комнаты под потолком.
func _light(shift: float, is_hotel: bool) -> void:
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	light.light_color = HOTEL_LIGHT if is_hotel else OFFICE_LIGHT
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.position = Vector3(shift, HEIGHT - 0.35, WorldSpace.BACK_WALL_Z - DEPTH * 0.55)
	add_child(light)


## Солнце из окна: прожектор за стеклом светит в комнату вниз, к коридору.
## В непогоду — тот же свет, но рассеянный и холодный.
func _sun_in(x: float) -> void:
	var sun := SpotLight3D.new()
	sun.name = "WindowSun"
	var colour := TimeOfDay.sun_colour(time)
	var energy := SUN_ENERGY
	if weather != Weather.Kind.CLEAR:
		colour = colour.lerp(WINDOW_OVERCAST.lightened(0.4), 0.7)
		energy *= 0.55
	sun.light_color = colour
	sun.light_energy = energy
	sun.spot_range = SUN_RANGE
	sun.spot_angle = SUN_ANGLE
	sun.shadow_enabled = false
	sun.position = Vector3(x, WINDOW_SILL + WINDOW.y * 0.7, back_z() + 0.05)
	# Прожектор светит по −Z; разворот на 180° — в комнату, наклон — вниз.
	sun.rotation = Vector3(-deg_to_rad(SUN_PITCH), PI, 0.0)
	add_child(sun)


## Тёплый огонёк лампы на тумбе.
func _lamp_glow(x: float) -> void:
	var glow := OmniLight3D.new()
	glow.name = "LampGlow"
	glow.light_color = LAMP_LIGHT
	glow.light_energy = LAMP_ENERGY
	glow.omni_range = LAMP_RANGE
	glow.shadow_enabled = false
	glow.position = Vector3(x, 1.05, back_z() + 0.35)
	add_child(glow)


func _box(size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var box := GreyboxLook.box(size, material)
	box.position = at
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(box)
