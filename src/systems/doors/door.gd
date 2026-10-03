class_name Door
extends Node3D

## A floor door.
##
## A red one hides a document, an ordinary one an ambush. The leaf is driven by
## [DoorCycle], the rules of Otto's visit by [DoorVisit]; the node is responsible for the
## mat, the look and handing out the document.
##
## Two parties use a door, and differently. Otto knocks by himself, the leaf closes
## behind him and opens, letting him out, exactly after 70 ROM ticks (ADR-0038, decision
## 2). The door lets an agent out at the level's request, and opens before him noticeably
## longer: the leaf is a warning (ADR-0020, decision 2).
##
## The leaf hangs in the corridor back wall, the threshold in the play plane (ADR-0021,
## decision 1). The level itself cuts the opening in the wall behind the leaf.
##
## Above the leaf is an indicator board: red at a red door, warm at an ordinary one. This
## is what makes a door readable on an unlit floor: the leaf itself no longer glows
## (ADR-0023, decision 6).

## The document is taken, the door is no longer red. As in the ROM, on Otto's exit,
## not on entry (ADR-0038, decision 2).
signal document_taken

## Otto went inside and the leaf followed him. By this the level leads agents to the
## door ([DoorWatch]).
signal otto_hid

## Otto came outside.
signal otto_came_out

## Leaf size, m: 40% × 70% of the clearance, as in the original ([Proportions]).
## The level cuts the opening in the back wall by it, and the leaf box is built
## from it as well in [method Node._ready] instead of sitting in the scene as a second
## number.
const LEAF_SIZE := Proportions.DOOR

## Default leaf travel before an agent, s: [member agent_open_time].
const AGENT_OPEN_TIME: float = 0.7

## Leaf thickness, m.
const LEAF_THICKNESS: float = 0.08

## How far the leaf stands off the wall. Slightly more than zero: lying in the same
## plane as the wall, it would flicker with it every frame.
const LEAF_STANDOFF: float = 0.05

## How far the leaf can be heard, m. There are fifty doors in a building, and a slam of
## each across the whole building would turn into nonstop banging: only near ones are
## heard.
const DOOR_REACH: float = 14.4

## The indicator board above the leaf: size and how far its middle is above the top of
## the leaf, m.
const SIGN_SIZE := Vector3(0.4, 0.13, 0.04)

## Door details (ADR-0031, decision 3): panels on the leaf, a handle, a kick
## plate and a casing around the opening, m.
const PANEL_SIZE := Vector2(0.84, 0.78)
const PANEL_RELIEF: float = 0.02
const HANDLE := Vector3(0.15, 0.025, 0.04)
const ROSETTE := Vector3(0.06, 0.12, 0.02)
const HANDLE_RISE: float = 1.0
const KICK_PLATE := Vector2(1.08, 0.2)
const FRAME_WIDTH: float = 0.08
const FRAME_DEPTH: float = 0.05
const SIGN_RISE: float = 0.2
## While Otto is behind a red door, the closed leaf in the corridor shadow merged with
## the darkness (shot `door_02_inside_closed`). Now the leaf glows slightly by itself,
## red as it was, and the board above it slowly breathes: once every this many seconds,
## from its usual brightness up to this fraction on top. It adds no light sources.
const OCCUPIED_PULSE: float = 1.6
const OCCUPIED_GLOW: float = 1.8
## How much an occupied leaf glows by itself: a fraction of its color. The marker
## ([method GreyboxLook.marker]) burned as a flat pink spot brighter than all doors.
const OCCUPIED_LEAF_GLOW: float = 0.14

## The red door's sconce (ADR-0042, decision 8): a red door in the corridor shadow got
## lost, and it was easy to walk past. A shadowless cone, in front of the leaf at its
## top, looks down and toward the wall: the spot falls onto the leaf and the floor in
## front of it. It stays on with a knocked-down lamp and goes out with the document. It
## does not light beyond its own floor: from the sconce height to the floor is less than
## its range, to the slab under the floor more.
const RED_LIGHT_COLOR := Color(1.0, 0.32, 0.26)
const RED_LIGHT_ENERGY: float = 1.3
const RED_LIGHT_RANGE: float = 3.0
const RED_LIGHT_ANGLE: float = 42.0
## How far the sconce is in front of the wall, m, and how much it tilts toward it from
## plumb.
const RED_LIGHT_OUT: float = 0.7
const RED_LIGHT_TILT: float = 0.35

## Glass of the office leaf: size, m, and tone: light frosted.
const VISION := Vector2(0.62, 0.5)
const FROSTED := Color(0.78, 0.84, 0.88)
## The "Do not disturb" sign on the handle: size, m, and color.
const HANGER := Vector3(0.09, 0.22, 0.008)
const HANGER_COLOR := Color(0.72, 0.1, 0.12)
## Salt of the draw for small items at the door: its own, so as not to move in step with
## the room.
const LITTLE_SALT: int = 0x7A_B1E5
## Life behind an apartment door (ADR-0055, decision 8): draw salt, where the sound comes
## from, how far it can be heard, m, and how much quieter than other sounds, dB: it is
## muffled, from behind the door.
const LIFE_SALT: int = 0x11FE
const LIFE_AT := Vector3(0.0, 1.2, -0.3)
const LIFE_REACH: float = 7.0
const LIFE_DB: float = -6.0
## The apartment peephole: size and height above the bottom of the leaf, m.
const PEEPHOLE := Vector3(0.035, 0.035, 0.02)
const PEEPHOLE_RISE: float = 1.55
## The mat at the apartment threshold, m, and its colors.
const DOORMAT := Vector3(0.9, 0.015, 0.5)
const DOORMAT_RIM := Color(0.12, 0.11, 0.1)
const DOORMAT_TONES: Array[Color] = [
	Color(0.36, 0.26, 0.16), Color(0.2, 0.26, 0.2), Color(0.34, 0.14, 0.12), Color(0.28, 0.28, 0.3)
]
## A grocery bag, m, and its contents.
const BAG := Vector3(0.3, 0.38, 0.2)
const BAG_COLOR := Color(0.62, 0.48, 0.3)
const LOAF_COLOR := Color(0.78, 0.6, 0.34)
const GREENS_COLOR := Color(0.24, 0.46, 0.18)

## Occupied leaf paints by tone: there are two for all doors (leaf and panels).
static var _occupied_paints: Dictionary = {}

## How long Otto stays inside, s: 70 ROM ticks, counting from the knock.
@export var hide_time: float = Arcade.seconds(Arcade.ROOM_TICKS)

## How long the leaf takes to open before a guest, s: 7 ROM ticks, as long as Otto
## walks into the door before vanishing (@3BDA–3C25, ADR-0043, decision 4).
@export var open_time: float = Arcade.seconds(7)

## How long the leaf takes to open before an agent, s.
##
## Longer than before Otto, on purpose: the player must manage to see the leaf and leave.
## Not confirmed by the check: ADR-0020, decision 2. The number is in [constant
## AGENT_OPEN_TIME]: by it the level knows in advance when to call the door so that
## the agent comes out by the end of the shift (ADR-0028, decision 7).
@export var agent_open_time: float = AGENT_OPEN_TIME

## A red door: a document is behind it.
@export var has_document: bool = false

## A special-floor door (ADR-0057, decision 3): behind it is a hall, not a room: the leaf
## opens into the hall, as at the office, and no room appears in it. Set by the level.
var opens_into_hall: bool = false

var _visit := DoorVisit.new()
var _cycle := DoorCycle.new()
var _guest: Otto = null
## Otto, already outside but still coming out: the leaf closes behind him.
var _stepping_out: Otto = null
## The door is open for an agent: occupied until he comes out.
var _expecting_agent: bool = false
var _voice: AudioStreamPlayer3D = null
## What is already shown: the leaf travel and whether the door is red. There are fifty
## doors in a building, and almost all the time they all stand closed: moving them every
## frame means touching the transform fifty times for nothing.
var _shown: float = -1.0
var _shown_red: bool = false
var _shown_occupied: bool = false
var _sign: MeshInstance3D = null
## The red door's sconce; on while the document is behind it and the floor is in frame.
var _red_light: SpotLight3D = null
## The door's floor is in the lit band: off-frame the sconce is off, like the lamps
## ([method set_light_in_view]). A door outside a level (in tests) counts as in frame.
var _in_view: bool = true
## Life behind an apartment door; other doors do not have it.
var _life: DoorLife = null
## Its own board while Otto is inside: the shared indicator light material would breathe
## at all red doors of the building at once. And the breathing clock follows physics: on
## pause it stands still.
var _pulse: StandardMaterial3D = null
var _pulse_clock: float = 0.0
## Leaf panels: their tone follows the leaf, red or ordinary.
var _panels: Array[MeshInstance3D] = []
## The room behind the door ([DoorRoom], ADR-0047): it is built when the leaf
## starts moving and removed when it has closed. The building and the door's draw come
## from the level ([method furnish]); without them (in tests) it is still dark behind
## the door.
var _room: DoorRoom = null
var _room_identity: BuildingIdentity = null
var _room_seed: int = 0
var _room_span := Vector2(-INF, INF)
var _furnished: bool = false
var _room_unlit: bool = false
var _room_time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT
var _room_weather: Weather.Kind = Weather.Kind.CLEAR
## Door look by building kind (ADR-0048): panels and wood at the hotel, glass and
## aluminum at the office. Without a building, the hotel, as before M24i.
var _style := BuildingStyle.new()

@onready var _mat: Area3D = $Mat
@onready var _leaf: MeshInstance3D = $Leaf
@onready var _mat_visual: MeshInstance3D = $MatVisual


## A mat by [Proportions], right after the scene is assembled, like the actors' shapes.
func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED:
		return
	var mat := Proportions.DOOR_MAT
	Proportions.fit_box($Mat/MatShape as CollisionShape3D, Vector3(mat, 0.3, 0.4))
	Proportions.fit_mesh($MatVisual as MeshInstance3D, Vector3(mat, 0.02, mat))


func _ready() -> void:
	if _furnished:
		_style = BuildingStyle.of(_room_identity)
	_visit.hide_time = hide_time
	_visit.leaf_time = open_time
	_mat_visual.material_override = GreyboxLook.surface(GreyboxLook.SLAB)
	var leaf := BoxMesh.new()
	leaf.size = Vector3(LEAF_SIZE.x, LEAF_SIZE.y, LEAF_THICKNESS)
	_leaf.mesh = leaf
	_leaf.position = Vector3(0.0, LEAF_SIZE.y * 0.5, WorldSpace.BACK_WALL_Z + LEAF_STANDOFF)
	_sign = GreyboxLook.box(SIGN_SIZE, GreyboxLook.light(GreyboxLook.SIGN_WARM))
	_sign.name = "Sign"
	_sign.position = Vector3(
		0.0, LEAF_SIZE.y + SIGN_RISE, WorldSpace.BACK_WALL_Z + SIGN_SIZE.z * 0.5
	)
	add_child(_sign)
	_red_light = _make_red_light()
	add_child(_red_light)
	_dress_leaf()
	_frame_the_opening()
	_refresh_look()


func _physics_process(delta: float) -> void:
	_cycle.tick(delta)
	_refresh_look()
	_breathe(delta)
	_listen(delta)

	if _stepping_out != null:
		# Comes out toward the camera while the leaf closes.
		_stepping_out.ride_progress = _cycle.openness()
		_see_out()
		return

	if _guest == null:
		_look_for_visitor()
		return
	if _guest.is_dead():
		_drop_the_guest()
		return
	if _guest.ride_look == Otto.LOOK_DOOR_IN:
		# Goes into the depth of the opening while the leaf opens.
		_guest.ride_progress = _cycle.openness()

	match _visit.tick(delta, _cycle.is_open()):
		DoorVisit.Cue.HIDE:
			_hide_the_guest()
		DoorVisit.Cue.LET_OUT:
			_cycle.open()
			Sounds.play(Sounds.DOOR_OPEN)
		DoorVisit.Cue.OUT:
			_release()


## Whether loot is left behind the door: whether it is still red. The document is
## obtained on exit (ADR-0038, decision 2), and until the exit the door stays red.
func is_pending() -> bool:
	return has_document


## The point where Otto stands in front of the door, in rules coordinates: he enters
## here and comes out from here.
func mat_position() -> Vector2:
	return WorldSpace.to_plane(_mat.global_position)


## Whether the door is free for an agent: nobody inside, and the leaf stands closed.
##
## Asked before choosing a door, not after: the level releases one per frame and
## takes the nearest door. The nearest one, still closing behind the previous agent,
## would take this frame for itself and release nobody until the leaf finishes.
func can_summon() -> bool:
	return _guest == null and not _expecting_agent and _cycle.is_shut()


## Asks the door to open to let an agent out.
##
## Returns false if the door is occupied: a guest is inside or the leaf is still moving
## after the previous one. In this case the level will simply try next time.
func summon_agent() -> bool:
	if not can_summon():
		return false
	_expecting_agent = true
	_cycle.travel_time = agent_open_time
	_cycle.open()
	_say(Sounds.DOOR_OPEN)
	return true


## Leaf travel, 0..1. From outside it shows whether the door is open or not.
func openness() -> float:
	return _cycle.openness()


## Whether the leaf has opened enough for an agent to appear in the opening.
func agent_may_step_out() -> bool:
	return _expecting_agent and _cycle.is_open()


## The agent came out or the door changed its mind: the leaf goes back.
##
## Otto standing in front of an opening door does not stop it: the door does not
## change its mind (ADR-0020, decision 5). Only the level calls this: either the agent
## cleared the opening, or the floor left the release band.
func dismiss_agent() -> void:
	if not _expecting_agent:
		return
	_expecting_agent = false
	_cycle.close()
	_say(Sounds.DOOR_CLOSE)


func _look_for_visitor() -> void:
	if _expecting_agent:
		# The door is occupied by an agent coming out, and Otto is not let in. It is not about
		# politeness: the leaf behind the agent is closed by the level ([method
		# dismiss_agent]), and the guest's visit follows the leaf (he hides and comes out
		# only through an open one), so Otto let in here would get stuck in the opening.
		return
	if not has_document:
		# As in the ROM (@3BDA): only a red door lets the player in while the document
		# has not been taken. An ordinary one is an agent door, and it does not serve as cover
		# (ADR-0044, decision 3).
		return
	for body: Node3D in _mat.get_overlapping_bodies():
		var visitor := body as Otto
		if visitor == null or visitor.is_dead():
			continue
		if not _visit.knock(visitor.is_grounded(), visitor.vertical_intent()):
			continue
		_admit(visitor)
		return


## Lets Otto in: the leaf opens, and while it moves he steps into the opening.
##
## The step into the opening is a ride, like on an escalator: input is off and he cannot
## be hit already now (in the ROM he is invulnerable from the first step inside), but he
## is still in view. He hides when the leaf opens ([method _hide_the_guest]).
func _admit(visitor: Otto) -> void:
	_guest = visitor
	visitor.global_position = _mat.global_position
	visitor.ride_look = Otto.LOOK_DOOR_IN
	visitor.ride(true)
	_visit.admit()
	_cycle.travel_time = open_time
	_cycle.open()
	Sounds.play(Sounds.DOOR_OPEN)


## The leaf has opened: Otto is inside, and it closes behind him. From here the corridor
## is heard muffled: both the music and the steps with shots (ADR-0038, decision 2).
func _hide_the_guest() -> void:
	_guest.ride(false)
	_guest.stay_indoors(true)
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)
	_muffle(true)
	otto_hid.emit()


## Lets Otto out through the open leaf and closes it behind him. The document is
## obtained here, on exit, as in the ROM: while Otto is inside, the door is still red.
##
## The exit ends when the leaf has closed: until then Otto is in view, but input is
## off and he cannot be hit: in the ROM he is invulnerable "until fully out". Without
## this an agent who waited at the door would shoot at someone still standing in the
## opening.
func _release() -> void:
	_guest.global_position = _mat.global_position
	_guest.stay_indoors(false)
	_guest.ride_look = Otto.LOOK_DOOR_OUT
	_guest.ride_progress = 1.0
	_guest.ride(true)
	_stepping_out = _guest
	_guest = null
	_visit.release()
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)
	_muffle(false)
	otto_came_out.emit()

	if not has_document:
		return
	has_document = false
	Sounds.play(Sounds.DOCUMENT)
	document_taken.emit()


## The guest died at the door: the door lets go of him and closes. A dead one is not
## taken out again, put back on the mat, nor given the document (ADR-0060).
func _drop_the_guest() -> void:
	if _visit.is_hiding():
		_muffle(false)
	_guest = null
	_visit.release()
	_cycle.close()
	Sounds.play(Sounds.DOOR_CLOSE)


## The leaf has closed behind the one who came out: control is back with the player.
func _see_out() -> void:
	if not _cycle.is_shut():
		return
	if is_instance_valid(_stepping_out):
		_stepping_out.ride(false)
	_stepping_out = null


## Muffles the corridor behind the door or restores it: music and world sounds at once.
func _muffle(on: bool) -> void:
	Sounds.muffle_music(Sounds.MUFFLE_DOOR, on)
	Sounds.muffle_world(on)


## The building was thrown away while Otto is behind the door: a new game from the
## pause, exit to the menu. The door itself removes the muffled sound: otherwise everyone
## who throws a building away would have to remember it.
func _exit_tree() -> void:
	if _guest != null and _visit.is_hiding():
		_muffle(false)


## Drives the leaf by the [DoorCycle] travel.
##
## The leaf swings on hinges at its left edge into the room, a quarter turn at full
## travel. Before M18c it slid sideways along the wall by its full width, but with a
## 1.8 m spot step and a 1.2 m leaf an open door would overlap the neighboring spot, a
## shaft or another door. Swung, it does not go beyond its opening: the room behind the
## wall is 7 m deep (ADR-0026, decision 3).
##
## A standing leaf is not touched: this is called every frame and from every door of
## the building, and the position changes only while the door moves.
func _refresh_look() -> void:
	var along := _cycle.openness()
	var occupied := _occupied()
	if (
		is_equal_approx(along, _shown)
		and has_document == _shown_red
		and occupied == _shown_occupied
	):
		return
	_shown = along
	_shown_red = has_document
	_shown_occupied = occupied
	_open_the_room(along)
	var angle := along * PI * 0.5
	var half := LEAF_SIZE.x * 0.5
	# Rotation around Y by +angle takes the leaf's right edge to −Z, that is,
	# into the room; the middle moves along an arc around the hinge.
	_leaf.rotation.y = angle
	_leaf.position.x = -half + cos(angle) * half
	_leaf.position.z = WorldSpace.BACK_WALL_Z + LEAF_STANDOFF - sin(angle) * half
	var tone := GreyboxLook.DOOR_RED if has_document else _style.leaf_tone
	# An occupied leaf glows by itself, dimly: a marker, not paint.
	_leaf.material_override = _paint(tone, occupied)
	var relief := _paint(tone.darkened(0.14), occupied)
	for panel in _panels:
		panel.material_override = relief
	var glow := GreyboxLook.SIGN_RED if has_document else _style.sign_tone
	_sign.material_override = GreyboxLook.light(glow)
	_red_light.visible = has_document and _in_view
	_pulse_clock = 0.0


## Which room is behind the door: building [param identity] and the door's draw
## [param seed]. [param span] is the floor from outer wall to outer wall along X from
## the door's middle: the room does not go beyond it ([method DoorRoom.build]).
##
## [param unlit]: the door's floor is dark, and the room behind it has no light of its
## own. [param time] and [param weather] are what is outside the room window (ADR-0052,
## decision 5).
func furnish(
	identity: BuildingIdentity,
	seed: int,
	span: Vector2 = Vector2(-INF, INF),
	unlit: bool = false,
	time: TimeOfDay.Kind = TimeOfDay.Kind.NIGHT,
	weather: Weather.Kind = Weather.Kind.CLEAR
) -> void:
	_room_unlit = unlit
	_room_time = time
	_room_weather = weather
	_room_identity = identity
	_room_seed = seed
	_room_span = span
	_furnished = true
	if identity != null and identity.kind == BuildingIdentity.Kind.RESIDENTIAL:
		_life = DoorLife.of(hash([seed, LIFE_SALT]))


## Life behind a closed apartment door: an occasional muffled sound ([DoorLife]).
func _listen(delta: float) -> void:
	if _life == null:
		return
	var audible := _in_view and _cycle.is_shut() and not has_document
	var heard := _life.advance(delta, audible)
	if heard != "":
		Sounds.play_at(self, heard, global_position + LIFE_AT, LIFE_REACH, LIFE_DB)


## The room behind the door while the leaf is open; otherwise null.
func room() -> DoorRoom:
	return _room


## Builds the room when the leaf starts moving and removes it when it has closed.
func _open_the_room(along: float) -> void:
	if not _furnished:
		return
	# An office door opens into the hall behind the glass ([OpenSpace], ADR-0056):
	# it has no separate room.
	if along > 0.0 and _room == null and not _style.glass_wall and not opens_into_hall:
		var kind := BuildingIdentity.Kind.HOTEL if _room_identity == null else _room_identity.kind
		_room = DoorRoom.build(
			kind, _room_seed, _room_identity, _room_span, _room_unlit, _room_time, _room_weather
		)
		add_child(_room)
	elif along <= 0.0 and _room != null:
		_room.queue_free()
		_room = null


## The door's floor has entered or left the lit band. Called by the level as it selects
## the visible floors, as for lamps (ADR-0010, item 8).
func set_light_in_view(on: bool) -> void:
	_in_view = on
	if _red_light != null:
		_red_light.visible = has_document and on


## Whether the red door's sconce is on. For tests.
func is_red_light_on() -> bool:
	return _red_light != null and _red_light.visible


func _make_red_light() -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = "RedLight"
	light.light_color = RED_LIGHT_COLOR
	light.light_energy = RED_LIGHT_ENERGY
	light.spot_range = RED_LIGHT_RANGE
	light.spot_angle = RED_LIGHT_ANGLE
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.5
	light.position = Vector3(0.0, LEAF_SIZE.y + SIGN_RISE, WorldSpace.BACK_WALL_Z + RED_LIGHT_OUT)
	# In Godot a light points along the node's −Z: plumb down and tilted toward the wall.
	light.rotation.x = -PI * 0.5 + RED_LIGHT_TILT
	light.visible = false
	return light


## Leaf paint: an occupied one glows by itself, dimly, staying red even in the shadow.
static func _paint(tone: Color, occupied: bool) -> StandardMaterial3D:
	var plain := GreyboxLook.surface(tone)
	if not occupied:
		return plain
	var found: Variant = _occupied_paints.get(tone)
	if found != null:
		return found as StandardMaterial3D
	var glowing := plain.duplicate() as StandardMaterial3D
	glowing.emission_enabled = true
	glowing.emission = tone
	glowing.emission_energy_multiplier = OCCUPIED_LEAF_GLOW
	_occupied_paints[tone] = glowing
	return glowing


## Otto is behind this door: he went in and has not come out yet.
func _occupied() -> bool:
	return _guest != null and _visit.is_hiding()


## The board above an occupied door slowly breathes while Otto is inside.
func _breathe(delta: float) -> void:
	if not _shown_occupied:
		return
	if _pulse == null:
		_pulse = GreyboxLook.light(GreyboxLook.SIGN_RED).duplicate() as StandardMaterial3D
	_pulse_clock += delta
	var phase := 0.5 - 0.5 * cos(_pulse_clock * TAU / OCCUPIED_PULSE)
	_pulse.emission_energy_multiplier = GreyboxLook.LIGHT_GLOW * lerpf(1.0, OCCUPIED_GLOW, phase)
	_sign.material_override = _pulse


## Leaf details: the hotel has two panels, the office frosted glass in the upper
## third; a handle with a rose at the free edge and a kick plate at the bottom. They are
## children of the leaf and swing together with it. Some hotel rooms have a "Do not
## disturb" sign on the handle and a newspaper or a tray at the threshold (ADR-0048).
func _dress_leaf() -> void:
	var front := LEAF_THICKNESS * 0.5
	var bottom := -LEAF_SIZE.y * 0.5
	if _style.panels:
		for rise: float in [0.35, 0.78]:
			var panel := GreyboxLook.box(
				Vector3(PANEL_SIZE.x, PANEL_SIZE.y, PANEL_RELIEF),
				GreyboxLook.surface(GreyboxLook.DOOR)
			)
			panel.position = Vector3(0.0, bottom + LEAF_SIZE.y * rise, front + PANEL_RELIEF * 0.5)
			_leaf.add_child(panel)
			_panels.append(panel)
	if _style.vision_glass:
		_leaf.add_child(_vision_glass(front, bottom))
	var chrome := GreyboxLook.metal(_style.handle_tone)
	if _style.peephole:
		var eye := GreyboxLook.box(PEEPHOLE, chrome)
		eye.name = "Peephole"
		eye.position = Vector3(0.0, bottom + PEEPHOLE_RISE, front + PEEPHOLE.z * 0.5)
		_leaf.add_child(eye)
	var handle_x := LEAF_SIZE.x * 0.5 - 0.14
	var rosette := GreyboxLook.box(ROSETTE, chrome)
	rosette.position = Vector3(handle_x, bottom + HANDLE_RISE, front + ROSETTE.z * 0.5)
	_leaf.add_child(rosette)
	var lever := GreyboxLook.box(HANDLE, chrome)
	lever.name = "Lever"
	lever.position = Vector3(
		handle_x - HANDLE.x * 0.4, bottom + HANDLE_RISE, front + ROSETTE.z + HANDLE.z * 0.5
	)
	_leaf.add_child(lever)
	var kick := GreyboxLook.box(Vector3(KICK_PLATE.x, KICK_PLATE.y, 0.01), chrome)
	kick.position = Vector3(0.0, bottom + KICK_PLATE.y * 0.5 + 0.02, front + 0.005)
	_leaf.add_child(kick)
	_little_things(lever)


## Frosted glass in the office leaf: a light band in the upper third, slightly
## glowing: an office room is behind it.
func _vision_glass(front: float, bottom: float) -> MeshInstance3D:
	var frosted := StandardMaterial3D.new()
	frosted.albedo_color = FROSTED
	frosted.roughness = 0.2
	frosted.emission_enabled = true
	frosted.emission = FROSTED
	frosted.emission_energy_multiplier = 0.25
	var glass := GreyboxLook.box(Vector3(VISION.x, VISION.y, 0.012), frosted)
	glass.name = "VisionGlass"
	glass.position = Vector3(0.0, bottom + LEAF_SIZE.y * 0.72, front + 0.006)
	return glass


## Small items at the door by the door's draw: a hotel room gets a sign on the handle and
## a newspaper or a tray at the threshold, an apartment a mat and a grocery bag
## (ADR-0055). A red door and the office have none.
func _little_things(lever: MeshInstance3D) -> void:
	if not _furnished or has_document:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_room_seed, LITTLE_SALT])
	if rng.randf() < _style.door_hanger_share:
		var card := GreyboxLook.box(HANGER, GreyboxLook.surface(HANGER_COLOR))
		card.name = "DoorHanger"
		card.position = Vector3(-HANGER.x * 0.3, -HANGER.y * 0.55, HANGER.z)
		lever.add_child(card)
	if rng.randf() < _style.door_tray_share:
		var tray := _tray() if rng.randf() < 0.5 else _newspaper()
		tray.position = Vector3(LEAF_SIZE.x * 0.5 + 0.28, 0.0, WorldSpace.BACK_WALL_Z + 0.3)
		add_child(tray)
	if rng.randf() < _style.door_mat_share:
		add_child(_doormat(rng))
	if rng.randf() < _style.door_bag_share:
		var bag := _grocery_bag()
		bag.position = Vector3(
			-(LEAF_SIZE.x * 0.5 + 0.3), 0.0, WorldSpace.BACK_WALL_Z + BAG.z * 0.5 + 0.08
		)
		add_child(bag)


## A tray with dishes after dinner in the room.
func _tray() -> Node3D:
	var tray := Node3D.new()
	tray.name = "Tray"
	var board := GreyboxLook.box(
		Vector3(0.42, 0.02, 0.3), GreyboxLook.metal(Color(0.72, 0.7, 0.66))
	)
	board.position.y = 0.01
	tray.add_child(board)
	var dish := GreyboxLook.box(Vector3(0.2, 0.03, 0.2), GreyboxLook.surface(Color(0.9, 0.9, 0.88)))
	dish.position = Vector3(-0.07, 0.035, 0.0)
	tray.add_child(dish)
	var cloche := GreyboxLook.box(
		Vector3(0.14, 0.09, 0.14), GreyboxLook.metal(Color(0.8, 0.8, 0.82))
	)
	cloche.position = Vector3(0.11, 0.065, 0.02)
	tray.add_child(cloche)
	return tray


## A newspaper at the threshold.
func _newspaper() -> Node3D:
	var paper := GreyboxLook.box(
		Vector3(0.36, 0.025, 0.26), GreyboxLook.surface(Color(0.82, 0.8, 0.74))
	)
	paper.name = "Newspaper"
	paper.position.y = 0.0125
	paper.rotation.y = 0.25
	var holder := Node3D.new()
	holder.add_child(paper)
	return holder


## A mat at the apartment threshold: a dark border, the middle in a color by draw.
## It lies in front of the opening, not in it: the leaf moves above it.
func _doormat(rng: RandomNumberGenerator) -> Node3D:
	var mat := Node3D.new()
	mat.name = "Doormat"
	mat.position = Vector3(0.0, 0.0, WorldSpace.BACK_WALL_Z + DOORMAT.z * 0.5 + 0.06)
	var rim := GreyboxLook.box(DOORMAT, GreyboxLook.surface(DOORMAT_RIM))
	rim.position.y = DOORMAT.y * 0.5
	mat.add_child(rim)
	var tone := DOORMAT_TONES[rng.randi_range(0, DOORMAT_TONES.size() - 1)]
	var middle := GreyboxLook.box(
		Vector3(DOORMAT.x - 0.08, DOORMAT.y, DOORMAT.z - 0.08), GreyboxLook.surface(tone)
	)
	middle.position.y = DOORMAT.y * 0.5 + 0.002
	mat.add_child(middle)
	return mat


## A paper grocery bag at the door: a loaf and greens stick out of the top.
func _grocery_bag() -> Node3D:
	var bag := Node3D.new()
	bag.name = "GroceryBag"
	var paper := GreyboxLook.box(BAG, GreyboxLook.surface(BAG_COLOR))
	paper.position.y = BAG.y * 0.5
	bag.add_child(paper)
	var loaf := GreyboxLook.box(Vector3(0.07, 0.16, 0.07), GreyboxLook.surface(LOAF_COLOR))
	loaf.position = Vector3(-0.06, BAG.y + 0.03, 0.0)
	loaf.rotation.z = 0.25
	bag.add_child(loaf)
	var greens := GreyboxLook.box(Vector3(0.1, 0.08, 0.08), GreyboxLook.surface(GREENS_COLOR))
	greens.position = Vector3(0.06, BAG.y + 0.02, 0.01)
	bag.add_child(greens)
	return bag


## A casing around the opening on the back wall: jambs and a lintel.
func _frame_the_opening() -> void:
	var trim := GreyboxLook.metal(GreyboxLook.TRIM.darkened(0.35))
	if _furnished:
		trim = (
			GreyboxLook.surface(_style.frame_tone)
			if _style.panels
			else GreyboxLook.metal(_style.frame_tone)
		)
	var half := LEAF_SIZE.x * 0.5
	var z := WorldSpace.BACK_WALL_Z + FRAME_DEPTH * 0.5
	for side: float in [-1.0, 1.0]:
		var jamb := GreyboxLook.box(Vector3(FRAME_WIDTH, LEAF_SIZE.y, FRAME_DEPTH), trim)
		jamb.position = Vector3(side * (half + FRAME_WIDTH * 0.5), LEAF_SIZE.y * 0.5, z)
		add_child(jamb)
	var head := GreyboxLook.box(
		Vector3(LEAF_SIZE.x + FRAME_WIDTH * 2.0, FRAME_WIDTH, FRAME_DEPTH), trim
	)
	head.position = Vector3(0.0, LEAF_SIZE.y + FRAME_WIDTH * 0.5, z)
	add_child(head)


## Gives the door a voice. The source is positional and one per door: the stream is
## swapped, because the door cannot open and close at once anyway.
##
## The sound is called [param effect], not `name`: [Node] has its own field with that
## name, and the parameter would shadow it.
func _say(effect: String) -> void:
	if _voice == null:
		_voice = Sounds.source(self, effect, DOOR_REACH)
	else:
		_voice.stream = Sounds.stream(effect)
	_voice.play()
