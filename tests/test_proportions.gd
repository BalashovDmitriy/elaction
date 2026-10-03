extends GutTest

## World proportions: a man, a door, an opening, a floor.
##
## A hands-on playthrough produced a complaint: "a tiny little man, tiny doors
## and absurdly huge windows". The numbers were separated in M13 (ADR-0018, decision 5), and
## from then on a test must keep them, not the eye: shapes and constants live in different
## files and diverge silently.
##
## The assertions here are ratios, not absolute numbers: the world moved to a different
## scale twice (M13 and M15), and both times the test had to stay green without
## changes to the assertions — that is the very check that only the constants
## were divided (ADR-0021, "How we check"). There is no window check here: the building walls
## have no windows, and the city behind it is a separate scene.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Frame of the original, px: floor clearance, floor step and the building field height.
const ORIGINAL_CLEARANCE_PX: float = 40.0
const ORIGINAL_FLOOR_PX: float = 48.0
const ORIGINAL_FIELD_PX: float = 176.0


func _otto_shape(name: String) -> Vector3:
	var otto := OTTO_SCENE.instantiate() as Otto
	var shape := otto.get_node(name) as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size
	otto.free()
	return size


func _agent_shape() -> Vector3:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var shape := enemy.get_node("Shape") as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size
	enemy.free()
	return size


## Otto walks through a door without ducking: the door is taller than him.
func test_otto_fits_through_a_door() -> void:
	var opening := Door.LEAF_SIZE.y
	var standing := _otto_shape("StandingShape").y
	assert_gt(opening, standing, "дверь выше Otto")
	# But not twice as tall: a door two heights tall reads as a gate, not a door.
	assert_lt(opening, standing * 1.8, "но не вдвое")


## Otto fits into a shaft: the opening is wider than him.
func test_otto_fits_into_a_shaft() -> void:
	var rules := BuildingRules.new()
	var width := _otto_shape("StandingShape").x
	assert_gt(rules.shaft_width, width, "проём шахты шире Otto")


## Otto fits on a floor in height, with room left above him for a jump.
func test_a_floor_has_room_for_otto_and_his_jump() -> void:
	var rules := BuildingRules.new()
	var clearance := rules.floor_height - rules.slab_height
	var standing := _otto_shape("StandingShape").y
	assert_gt(clearance, standing, "Otto стоит на этаже в полный рост")

	var otto := OTTO_SCENE.instantiate() as Otto
	var apex := otto.jump_height()
	otto.free()
	assert_gt(clearance, standing + apex * 0.5, "и прыжок не упирается в потолок сразу")


## The agent is as tall as Otto: they stand side by side in one frame.
func test_agent_is_the_same_height_as_otto() -> void:
	assert_almost_eq(_agent_shape().y, _otto_shape("StandingShape").y, 0.12, "рост агента и Otto")


## Crouching, Otto is below the agent's bullet — all evasion rests on this (ADR-0006).
func test_crouching_otto_ducks_under_the_agent_bullet() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var bullet_height := absf(enemy.shot_height)
	enemy.free()
	assert_gt(bullet_height, _otto_shape("CrouchingShape").y, "пуля проходит над присевшим")


## All game bodies stand in one plane and have one thickness: otherwise shadows and
## collisions would each meet in their own (ADR-0021, decision 1).
func test_every_actor_stands_in_the_play_plane() -> void:
	for name: String in ["StandingShape", "CrouchingShape"]:
		assert_almost_eq(_otto_shape(name).z, WorldSpace.BODY_DEPTH, 0.001, "%s Otto" % name)
	assert_almost_eq(_agent_shape().z, WorldSpace.BODY_DEPTH, 0.001, "агент")


## Ratios of building items to the floor clearance — by the frame of the original (ADR-0026).
##
## Measurement: native MAME 256×224 screenshots and the arcade sprite sheet 1:1, floor
## clearance 40 px. The original's ratio is in pixels so the number can be rechecked against
## a frame, not memory. Tolerance — how much divergence is accepted; if it is
## deliberate, the reason is written next to it.


func _share_of_clearance(metres: float) -> float:
	var rules := BuildingRules.new()
	return metres / (rules.floor_height - rules.slab_height)


func _original(pixels: float) -> float:
	return pixels / ORIGINAL_CLEARANCE_PX


func _lamp_shape() -> Vector3:
	var lamp := LAMP_SCENE.instantiate() as Lamp
	var shape := lamp.get_node("Shape") as CollisionShape3D
	var size := (shape.shape as BoxShape3D).size
	lamp.free()
	return size


func _bullet_half_height() -> float:
	var bullet := BULLET_SCENE.instantiate()
	var shape := (bullet.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	bullet.free()
	return shape.size.y * 0.5


func test_things_on_the_floor_take_the_share_of_the_original() -> void:
	var rules := BuildingRules.new()
	var pitch := rules.slot_x(1) - rules.slot_x(0)
	# [what, ours, original ratio, tolerance]
	var table: Array = [
		["плита", rules.slab_height, _original(8.0), 0.01],
		["Otto в рост: 22–23 px над полом", _otto_shape("StandingShape").y, _original(22.5), 0.02],
		["Otto в ширину: 10 px", _otto_shape("StandingShape").x, _original(10.0), 0.02],
		["агент в рост — как Otto", _agent_shape().y, _original(22.5), 0.02],
		["дверь в высоту: 28 px", Door.LEAF_SIZE.y, _original(28.0), 0.01],
		["дверь в ширину: 16 px", Door.LEAF_SIZE.x, _original(16.0), 0.01],
		["шахта: 24 px", rules.shaft_width, _original(24.0), 0.01],
		["шаг места: 24 px", pitch, _original(24.0), 0.01],
		# Deliberate divergence: 84% against 82%. These 5 cm keep "the lamp
		# cannot be shot down from a jump" — see test_a_lamp_is_out_of_reach_from_the_floor.
		[
			"низ лампы: 33 px",
			GreyboxLevel.lamp_height(rules) - _lamp_shape().y * 0.5,
			_original(33.0),
			0.02
		],
	]
	for row: Array in table:
		var ours := _share_of_clearance(row[1] as float)
		assert_almost_eq(
			ours,
			row[2] as float,
			row[3] as float,
			"%s: у нас %.0f%% просвета, у оригинала %.0f%%" % [row[0], ours * 100.0, row[2] * 100.0]
		)


## Crouch and shots are fractions of height, not of clearance: this is how the body works.
func test_stances_and_shots_keep_the_shape_of_the_original() -> void:
	var otto := OTTO_SCENE.instantiate() as Otto
	var standing := _otto_shape("StandingShape").y
	var crouching := _otto_shape("CrouchingShape").y
	var shot := otto.shot_height_standing
	otto.free()
	# Crouch 15–16 px of the 24 sprite, standing shot 15 px of 22–23 above the floor.
	assert_almost_eq(crouching / standing, 15.5 / 24.0, 0.03, "присед к стойке")
	assert_almost_eq(shot / standing, 15.0 / 22.5, 0.03, "пуля стоящего Otto к его росту")

	var rules := BuildingRules.new()
	# A crouching agent is 14 px above the floor out of 22–23.
	assert_almost_eq(rules.agent_kneel_height / _agent_shape().y, 14.0 / 22.5, 0.04, "колено")


## Bullet and stance are separated by the bullet's edge, not its axis: a bullet is a box.
##
## The order holds the whole combat (ADR-0006, ADR-0016): from a high bullet one drops to
## a knee, from a low one one lies down, a crouching Otto is not hit by the agent's bullet.
## The grown actors shifted all five numbers at once, and they must not drift by a centimetre.
func test_bullets_and_stances_keep_their_order() -> void:
	var rules := BuildingRules.new()
	var half := _bullet_half_height()
	var otto := OTTO_SCENE.instantiate() as Otto
	var high := otto.shot_height_standing
	var low := otto.shot_height_crouching
	otto.free()
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var agent_shot := enemy.shot_height
	enemy.free()

	assert_lt(rules.agent_kneel_height, high - half, "колено ниже высокой пули Otto")
	assert_gt(rules.agent_kneel_height, low + half, "и выше низкой: от неё ложатся")
	assert_lt(rules.agent_prone_height, low - half, "лежащий ниже низкой")
	assert_gt(agent_shot - half, _otto_shape("CrouchingShape").y, "пуля агента над присевшим")
	assert_lt(agent_shot + half, _otto_shape("StandingShape").y, "и в стоящего")


## A lamp is shot down from a cab, as in the original: from the floor — neither standing nor
## jumping.
##
## In a jump Otto hits the ceiling with his head, and his bullet does not
## rise above that, however much the jump itself gives (ADR-0026, decision 5).
func test_a_lamp_is_out_of_reach_from_the_floor() -> void:
	var rules := BuildingRules.new()
	var clearance := rules.floor_height - rules.slab_height
	var standing := _otto_shape("StandingShape").y
	var otto := OTTO_SCENE.instantiate() as Otto
	var feet := minf(otto.jump_height(), clearance - standing)
	var shot := otto.shot_height_standing
	otto.free()

	var lamp_bottom := GreyboxLevel.lamp_height(rules) - _lamp_shape().y * 0.5
	var highest := feet + shot + _bullet_half_height()
	assert_lt(highest, lamp_bottom, "пуля из прыжка проходит под лампой")
	# But from a cab — yes: the cab passes all heights between floors, and its floor
	# can be at any height from one floor to the next.
	assert_lt(lamp_bottom - shot, rules.floor_height, "ствол из кабины проходит высоту лампы")


## The frame holds as many floors as the original's building field: 176 px at a step of 48.
func test_the_frame_shows_as_many_floors_as_the_original() -> void:
	var rules := BuildingRules.new()
	# On the play plane, as the camera itself computes: a tilted frame is taller than its
	# size by 1/cos(tilt).
	var tilt := deg_to_rad(SideCamera.TILT_DEGREES)
	var floors := SideCamera.DEFAULT_HALF_HEIGHT * 2.0 / cos(tilt) / rules.floor_height
	assert_almost_eq(floors, ORIGINAL_FIELD_PX / ORIGINAL_FLOOR_PX, 0.01, "этажей в кадре")
