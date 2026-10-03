class_name DoorRoom
extends Node3D

## The room behind a door (ADR-0047): a hotel room, an office or a residential
## building's flat (ADR-0055, decision 5).
##
## Visible while the leaf is open: the ortho camera looks into the opening almost head-on, and in it
## is the room's back wall with a window and what stands in front of it, and a strip of floor (the
## camera is tilted by [constant SideCamera.TILT_DEGREES]). The ceiling is not visible; the side
## walls are there for the light: it does not escape into the void behind the corridor.
##
## Its door assembles it when the leaf starts to move and removes it when it has closed:
## there are fifty doors in a building, and keeping fifty rooms with their own light is wasteful.
## The draw is per door: the same door opens into the same room.
##
## The window is an opening in the back wall with glass (ADR-0052, decision 5): behind it is the
## same city as behind the building ([CityBackdrop]) — it is drawn behind the whole scene, and in
## the opening it shows itself, with the pack's facades, sky, weather and time of day.
##
## Coordinates are the door's: X along the wall from the middle of the opening, Y from the floor, Z
## is the scene's, the room behind the corridor's back wall.

## Which flat is behind the door: a kitchen, a living room with a TV or a bedroom.
enum Home { KITCHEN, LIVING, BEDROOM }
## Room size, m: width along the wall and depth from the corridor wall.
const WIDTH: float = 4.2
const DEPTH: float = 3.6
## Room height: a floor without the slab.
const HEIGHT: float = Proportions.FLOOR - Proportions.SLAB
## Wall thickness, m.
const WALL: float = 0.08
## The leaf swings into the room by its own width: there is no furniture closer than this to the
## corridor wall.
const LEAF_CLEAR: float = Door.LEAF_SIZE.x + 0.1
## How far the room is shifted along the wall from the middle of the opening, m: a draw, so that
## the doors of one floor do not open onto the same picture.
const SHIFT: float = 0.6
## Window in the back wall: width, height and sill height above the floor, m.
const WINDOW := Vector2(1.2, 1.35)
const WINDOW_SILL: float = 0.9
const FRAME: float = 0.06
## Room light: under the ceiling, no shadow. Hotel — warm, office — cold
## white of fluorescent lamps, flat — an incandescent bulb.
const HOTEL_LIGHT := Color(1.0, 0.76, 0.5)
const OFFICE_LIGHT := Color(0.86, 0.93, 1.0)
const HOME_LIGHT := Color(1.0, 0.82, 0.6)
const LIGHT_ENERGY: float = 2.3
const LIGHT_RANGE: float = 4.6
## The lamp on the nightstand — its own warm glow next to the shade.
const LAMP_LIGHT := Color(1.0, 0.7, 0.4)
const LAMP_ENERGY: float = 1.2
const LAMP_RANGE: float = 1.8
## Finish: hotel wallpaper and floor, office paint and carpet, the ceiling.
const HOTEL_WALL := Color(0.62, 0.5, 0.4)
const HOTEL_FLOOR := Color(0.32, 0.1, 0.1)
const OFFICE_WALL := Color(0.66, 0.68, 0.7)
const OFFICE_FLOOR := Color(0.26, 0.28, 0.31)
const HOME_WALL := Color(0.6, 0.58, 0.46)
const HOME_FLOOR := Color(0.34, 0.22, 0.14)
## TV in darkness (ADR-0055, decision 5): the blue light of the screen flickers —
## brightness, radius, m, and how fast the picture changes, times per second.
const TV_LIGHT := Color(0.55, 0.7, 1.0)
const TV_ENERGY: float = 1.4
const TV_RANGE: float = 2.6
const TV_FLICKER: float = 7.0
## The TV is turned toward the sofa by this many degrees: the screen is visible through the opening
## too.
const TV_TURN: float = 25.0
## Living-room row gap, m: the turned TV sticks out with its front corner beyond its
## extent by 0.27 m toward the sofa, and with a narrow gap the corner went into the armrest.
const LIVING_GAP: float = 0.3
## Setback of the furniture row from the back wall, m: by it the row works out how much
## [method _put] will squash a deep item.
const ROW_FROM_WALL: float = 0.02
## Top of the kitchen worktop as a fraction of the sink's height: the tap is above the worktop.
const COUNTER_TOP: float = 0.85
## Furniture no closer than this to the room's side walls, m.
const INNER_MARGIN: float = 0.08
const CEILING := Color(0.85, 0.83, 0.8)
const WINDOW_FRAME := Color(0.9, 0.88, 0.84)
const WINDOW_SHADER := preload("res://src/levels/room_window.gdshader")
## Cloudy light from the window: in fog and rain the sun goes grey.
const WINDOW_OVERCAST := Color(0.5, 0.52, 0.56)
## Sun from the window by day (ADR-0052, decision 5): a patch on the floor and furniture. Its own
## source instead of the ceiling light — one or two rooms are open, the budget is the
## same. No shadow: a shadow from the frame costs more than it shows.
const SUN_ENERGY: float = 4.0
const SUN_RANGE: float = 5.5
const SUN_ANGLE: float = 21.0
## How steeply the sun falls from the window, degrees.
const SUN_PITCH: float = 44.0
## Pictures and boards on the room wall — the same as in the corridor.
const HOTEL_ART: PackedStringArray = ["painting", "wall_art_02", "wall_art_03", "wall_art_05"]
const OFFICE_ART: PackedStringArray = ["whiteboard", "calendar", "corkboard", "analog_clock"]
const HOME_ART: PackedStringArray = ["painting", "wall_art_03", "wall_art_06", "analog_clock"]

## How many rooms are open now: while at least one is, the city behind the building is drawn,
## even when the building covers the whole frame — it is visible in the window.
static var open_count: int = 0

## What stands in the room: the catalogue item name, where (X along the wall, Z from the room's
## back wall toward the corridor, m) and the rotation, degrees. For tests and shots.
var placed: Array[Dictionary] = []
var kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
## Which room of the flat: only in a residential building.
var home: Home = Home.LIVING
## The floor is dark by ROM rules: the room has no light of its own, only the
## window with the city glows — the floor's darkness is not broken (user's decision, M24i).
var dark: bool = false
## Time of day outside the window: by day the room light is off and the sun shines.
var time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
var weather: Weather.Kind = Weather.Kind.CLEAR

var _wall_look: StandardMaterial3D = null
var _shift: float = 0.0
var _tv_glow: OmniLight3D = null
var _tv_clock: float = 0.0


## Assembles the room: [param which] — building kind, [param seed] —
## the door's draw, [param identity] — the building, its finish. [param span] — the floor
## from wall to wall along the door's X: the room does not go beyond its outer walls.
## [param unlit] — the floor is dark: the room has no light of its own ([member dark]).
## [param when] and [param sky] — time of day and weather outside the window.
static func build(
	which: BuildingIdentity.Kind,
	seed: int,
	identity: BuildingIdentity = null,
	span: Vector2 = Vector2(-INF, INF),
	unlit: bool = false,
	when: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	sky: Weather.Kind = Weather.Kind.CLEAR
) -> DoorRoom:
	var room := DoorRoom.new()
	room.name = "Room"
	room.kind = which
	room.dark = unlit
	room.time = when
	room.weather = sky
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# At the outermost slot of a floor there are 2.4 m to the outer wall, and the room with its
	# shift goes 2.7 from the opening: without a stop it would stick out of the building silhouette
	# as a strip of wall, floor and ceiling (M24i code review). Same draw, the shift is clamped.
	var half := (WIDTH + WALL) * 0.5
	var shift := clampf(rng.randf_range(-SHIFT, SHIFT), span.x + half, span.y - half)
	if which == BuildingIdentity.Kind.RESIDENTIAL:
		room.home = rng.randi_range(0, Home.size() - 1) as Home
	room._shell(shift, identity)
	var window_x := shift + rng.randf_range(-0.3, 0.3)
	room._window(window_x, rng)
	match which:
		BuildingIdentity.Kind.HOTEL:
			room._furnish_hotel(rng)
		BuildingIdentity.Kind.OFFICE:
			room._furnish_office(rng)
		BuildingIdentity.Kind.RESIDENTIAL:
			room._furnish_home(rng, window_x)
	if room.is_sunlit():
		room._sun_in(window_x)
	elif not unlit:
		room._light(shift)
	# The frame is needed only for the TV flicker.
	room.set_process(room._tv_glow != null)
	return room


func _process(delta: float) -> void:
	if _tv_glow == null:
		return
	# The picture changes in jumps, not smoothly: that is how a screen flickers.
	_tv_clock += delta * TV_FLICKER
	var frame := floorf(_tv_clock)
	var shade := 0.55 + 0.45 * absf(sin(frame * 12.9898 + 0.3 * sin(frame * 3.1)))
	_tv_glow.light_energy = TV_ENERGY * shade


func _enter_tree() -> void:
	open_count += 1


func _exit_tree() -> void:
	open_count = maxi(open_count - 1, 0)


## Whether it is light outside: morning and day. Then the room light is off, and the sun
## falls in through the window — or, in bad weather, just daylight.
func is_sunlit() -> bool:
	return TimeOfDay.is_daytime(time)


## Where the room's back wall is, scene Z.
static func back_z() -> float:
	return WorldSpace.BACK_WALL_Z - DEPTH


## Floor, ceiling, back and side walls.
func _shell(shift: float, identity: BuildingIdentity) -> void:
	var wall_tone := HOTEL_WALL
	var floor_tone := HOTEL_FLOOR
	match kind:
		BuildingIdentity.Kind.OFFICE:
			wall_tone = OFFICE_WALL
			floor_tone = OFFICE_FLOOR
		BuildingIdentity.Kind.RESIDENTIAL:
			wall_tone = HOME_WALL
			floor_tone = HOME_FLOOR
	var wall := (
		BuildingFinish.wall(identity, wall_tone)
		if identity != null
		else GreyboxLook.surface(wall_tone)
	)
	var floor_look := GreyboxLook.surface(floor_tone)
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


## A window onto the city in the back wall with a frame and sill; the hotel and the flat's
## rooms have curtains, the office and kitchen have blinds.
func _window(x: float, rng: RandomNumberGenerator) -> void:
	_wall_around(x)
	var glass := QuadMesh.new()
	glass.size = WINDOW
	var look := ShaderMaterial.new()
	look.shader = WINDOW_SHADER
	look.set_shader_parameter(&"seed", rng.randf() * 100.0)
	look.set_shader_parameter(&"blinds", 1.0 if _blinds() else 0.0)
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
	if not _blinds():
		_put("curtains", x, 0.12, 0.0, WINDOW.x + 0.9)


## Blinds on the window instead of curtains: in the office and kitchen.
func _blinds() -> bool:
	if kind == BuildingIdentity.Kind.OFFICE:
		return true
	return kind == BuildingIdentity.Kind.RESIDENTIAL and home == Home.KITCHEN


## Back wall with an opening for the window: left, right, above the window and below it.
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


## Hotel room: bed with its headboard to the wall, a nightstand with a lamp, a rug, a picture above
## the bed; the bed left or right of the window — a draw.
func _furnish_hotel(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var bed := "bed_hotel" if rng.randf() < 0.6 else "bed_double"
	# The bed is half in line with the door: it is what is seen through the opening, and the
	# nightstand with the lamp is next to it. The room is shifted by a draw, the bed — from the
	# opening.
	var bed_x := side * rng.randf_range(0.35, 0.6)
	var bed_size := _put(bed, bed_x, 0.02, 0.0)
	var stand_x := bed_x - side * (bed_size.x * 0.5 + 0.35)
	_put("night_stand" if rng.randf() < 0.5 else "night_stand_b", stand_x, 0.05, 0.0)
	# By day the nightstand lamp is off, like the ceiling light.
	if not dark and not is_sunlit():
		_lamp_glow(stand_x)
	_put("rug", bed_x * 0.5, bed_size.z * 0.55, 0.0, 1.8)
	_hang(HOTEL_ART[rng.randi_range(0, HOTEL_ART.size() - 1)], bed_x, 1.75)


## Office: a workplace at the wall, a shelf or filing cabinet to the side, a board or
## a calendar on the wall.
func _furnish_office(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# The desk is in line with the door: it and the chair are what is seen through the opening.
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


## A flat by the door's draw: kitchen, living room or bedroom. [param window] — where
## the window is along the door's X: in the kitchen the sink is under it.
func _furnish_home(rng: RandomNumberGenerator, window: float) -> void:
	match home:
		Home.KITCHEN:
			_furnish_kitchen(rng, window)
		Home.LIVING:
			_furnish_living(rng)
		Home.BEDROOM:
			_furnish_bedroom(rng)


## Kitchen: units along the wall — the sink under the window in line with the door, on one
## side a stove with a kettle, on the other a fridge; at the edge of the worktop —
## a microwave or a shopping bag, a calendar above the stove.
func _furnish_kitchen(rng: RandomNumberGenerator, window: float) -> void:
	var stove_first := rng.randf() < 0.5
	var names: Array[String] = ["stove", "counter_sink", "fridge"]
	if not stove_first:
		names.reverse()
	var at := _row(names, 1, clampf(window, -0.45, 0.45))
	for index: int in names.size():
		_put(names[index], at[index], 0.02, 0.0)
	var stove := PropCatalog.footprint("stove")
	var stove_x := at[names.find("stove")]
	_put_on("kettle", stove_x - stove.x * 0.15, stove.y, 0.04)
	var sink := PropCatalog.footprint("counter_sink")
	var sink_x := at[1]
	var counter_top := sink.y * COUNTER_TOP
	var edge := 1.0 if stove_first else -1.0
	var on_counter := "microwave" if rng.randf() < 0.5 else "paper_bag"
	_put_on(on_counter, sink_x + edge * sink.x * 0.32, counter_top, 0.06)
	_hang("calendar", stove_x, 1.65)


## Living room: a sofa at the wall in line with the door, a TV stand to the side with its screen
## toward the sofa, a floor lamp on the other side, a rug, a picture above the sofa. In darkness
## the screen shines blue.
func _furnish_living(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# The row spans almost the whole room: the TV goes to the side the room is shifted to,
	# otherwise the wall pushed the sofa out of line with the door.
	if absf(_shift) > 0.2:
		side = signf(_shift)
	var names: Array[String] = ["tv_old", "sofa", "floor_lamp"]
	if side > 0.0:
		names.reverse()
	var sofa_index := names.find("sofa")
	var at := _row(names, sofa_index, side * rng.randf_range(0.0, 0.15), LIVING_GAP)
	var sofa := _put("sofa", at[sofa_index], 0.02, 0.0)
	var tv_x := at[names.find("tv_old")]
	# Rotating by +angle turns the item's face toward +X: the TV at the `side` edge
	# looks back, toward the sofa — not into the side wall.
	var tv := _put("tv_old", tv_x, 0.3, -side * TV_TURN)
	_put("floor_lamp", at[names.find("floor_lamp")], 0.08, 0.0)
	_put("rug", at[sofa_index], sofa.z * 0.6, 0.0, 1.9)
	_hang(HOME_ART[rng.randi_range(0, HOME_ART.size() - 1)], at[sofa_index], 1.6)
	if not dark and not is_sunlit():
		_tv_light(tv_x, tv.y)


## Bedroom: a double bed in line with the door, nightstands on both sides — a lamp on one,
## a rug and a picture above the headboard. A chest of drawers did not fit in the row: the bed with
## nightstands is already three metres.
func _furnish_bedroom(rng: RandomNumberGenerator) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var names: Array[String] = ["night_stand", "bed_double", "night_stand_b"]
	if side < 0.0:
		names.reverse()
	var at := _row(names, 1, side * rng.randf_range(0.0, 0.3), 0.12)
	var bed := _put("bed_double", at[1], 0.02, 0.0)
	var stand_x := at[names.find("night_stand")]
	_put("night_stand", stand_x, 0.05, 0.0)
	if not dark and not is_sunlit():
		_lamp_glow(stand_x)
	_put("night_stand_b", at[names.find("night_stand_b")], 0.05, 0.0)
	_put("rug", at[1], bed.z * 0.55, 0.0, 1.8)
	_hang(HOME_ART[rng.randi_range(0, HOME_ART.size() - 1)], at[1], 1.75)


## A row of items along the back wall, close together, [param gap] m apart: the middle of
## item [param hero] goes at [param hero_x], the whole row shifts into the
## room if it hits a wall. Returns the middles in order.
##
## The width is the one the item will stand at: [method _put] squashes a deep one
## (a double bed — to three quarters), and by the catalogue extent the nightstands
## stood forty centimetres away from the bed.
func _row(names: Array[String], hero: int, hero_x: float, gap: float = 0.03) -> PackedFloat64Array:
	var centres := PackedFloat64Array()
	var cursor := 0.0
	for name: String in names:
		var size := PropCatalog.footprint(name)
		var width := size.x * _depth_fit(size, ROW_FROM_WALL)
		centres.append(cursor + width * 0.5)
		cursor += width + gap
	var span := cursor - gap
	var offset := hero_x - centres[hero]
	var inner := WIDTH * 0.5 - INNER_MARGIN
	offset = maxf(offset, _shift - inner)
	offset = minf(offset, _shift + inner - span)
	for index: int in centres.size():
		centres[index] += offset
	return centres


## Places a catalogue item with its back to the room's back wall: [param x] — the middle
## along the wall, [param from_wall] — setback from the wall, m, [param yaw] —
## extra rotation, degrees. [param width] — scale to the width instead of the catalogue height.
## Returns the extent of what was placed. The item does not go closer than [constant LEAF_CLEAR]
## to the corridor wall: the leaf swings there.
func _put(prop: String, x: float, from_wall: float, yaw: float, width: float = 0.0) -> Vector3:
	var node := PropCatalog.make(prop, true)
	if node == null:
		return Vector3.ZERO
	var size := PropCatalog.bounds_of(node).size
	if width > 0.0 and size.x > 0.001:
		node.scale = Vector3.ONE * (width / size.x)
		size *= width / size.x
	var fit := _depth_fit(size, from_wall)
	node.scale *= fit
	size *= fit
	node.rotation.y = deg_to_rad(yaw)
	x = _between_walls(x, size.x)
	# A catalogue item has its zero at the back face: it is placed against the wall with one
	# shift. One turned to face the wall (a chair at a desk) goes from zero toward the
	# wall — its zero is further by its own depth.
	var turned := absf(yaw) > 90.0
	node.position = Vector3(x, 0.02, back_z() + from_wall + (size.z if turned else 0.0))
	add_child(node)
	placed.append({"prop": prop, "x": x, "size": size, "from_wall": from_wall, "yaw": yaw})
	return size


## By what factor [method _put] squashes an item of extent [param size] at setback
## [param from_wall]: deeper than the room up to the leaf — it is squashed whole.
static func _depth_fit(size: Vector3, from_wall: float) -> float:
	var room_for := DEPTH - LEAF_CLEAR - from_wall
	if size.z > room_for and size.z > 0.001:
		return room_for / size.z
	return 1.0


## The middle of an item of width [param width], pushed from the side walls into the
## room: the draw places furniture from the opening, while the room is shifted by its own draw, and
## at the edge the office plant went behind the wall (M24m test).
func _between_walls(x: float, width: float) -> float:
	var inner := WIDTH * 0.5 - INNER_MARGIN - width * 0.5
	if inner <= 0.0:
		return _shift
	return clampf(x, _shift - inner, _shift + inner)


## Places small items on top of furniture: [param top] — the height of its top, m,
## [param from_wall] — setback from the back wall.
func _put_on(prop: String, x: float, top: float, from_wall: float) -> void:
	var node := PropCatalog.make(prop, true)
	if node == null:
		return
	var size := PropCatalog.bounds_of(node).size
	node.position = Vector3(x, top, back_z() + from_wall)
	add_child(node)
	placed.append({"prop": prop, "x": x, "size": size, "from_wall": from_wall, "yaw": 0.0})


## Hangs a picture or a board on the back wall: the middle at height [param y].
func _hang(prop: String, x: float, y: float) -> void:
	var node := PropCatalog.make(prop, true)
	if node == null:
		return
	var size := PropCatalog.bounds_of(node).size
	node.position = Vector3(x, y - size.y * 0.5, back_z() + 0.01)
	add_child(node)
	placed.append({"prop": prop, "x": x, "size": size, "from_wall": 0.0, "yaw": 0.0})


## Room light under the ceiling.
func _light(shift: float) -> void:
	var light := OmniLight3D.new()
	light.name = "RoomLight"
	match kind:
		BuildingIdentity.Kind.OFFICE:
			light.light_color = OFFICE_LIGHT
		BuildingIdentity.Kind.RESIDENTIAL:
			light.light_color = HOME_LIGHT
		_:
			light.light_color = HOTEL_LIGHT
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	light.position = Vector3(shift, HEIGHT - 0.35, WorldSpace.BACK_WALL_Z - DEPTH * 0.55)
	add_child(light)


## Sun from the window: a spotlight behind the glass shines into the room downward, toward the
## corridor. In bad weather — the same light, but diffuse and cold.
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
	# The spotlight shines along −Z; turning by 180° — into the room, tilt — downward.
	sun.rotation = Vector3(-deg_to_rad(SUN_PITCH), PI, 0.0)
	add_child(sun)


## The blue light of the TV screen in front of it: flickers in [method _process].
func _tv_light(x: float, height: float) -> void:
	_tv_glow = OmniLight3D.new()
	_tv_glow.name = "TvGlow"
	_tv_glow.light_color = TV_LIGHT
	_tv_glow.light_energy = TV_ENERGY
	_tv_glow.omni_range = TV_RANGE
	_tv_glow.shadow_enabled = false
	_tv_glow.position = Vector3(x, height * 0.6, back_z() + 0.9)
	add_child(_tv_glow)


## The warm glow of the nightstand lamp.
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
