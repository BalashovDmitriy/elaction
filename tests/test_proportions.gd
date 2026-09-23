extends GutTest

## Пропорции мира: человек, дверь, проём, этаж.
##
## Игра, сыгранная руками, дала упрёк: «маленький человечек, маленькие двери
## и несуразно огромные окна». Числа развели в M13 (ADR-0018, решение 5), и
## держать их дальше должен тест, а не глаз: формы и константы живут в разных
## файлах и расходятся молча.
##
## Утверждения здесь — отношения, а не абсолютные числа: мир переезжал в другой
## масштаб дважды (M13 и M15), и оба раза тест обязан был остаться зелёным без
## правок в утверждениях — это и есть проверка того, что делились только
## константы (ADR-0021, «Как проверяем»). Окна вернутся в M19 вместе со своей
## проверкой.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")
const LAMP_SCENE := preload("res://src/systems/lighting/lamp.tscn")
const BULLET_SCENE := preload("res://src/systems/combat/bullet.tscn")

## Кадр оригинала, px: просвет этажа, шаг этажа и поле здания по высоте.
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


## Otto проходит в дверь, не пригибаясь: дверь выше него.
func test_otto_fits_through_a_door() -> void:
	var opening := Door.LEAF_SIZE.y
	var standing := _otto_shape("StandingShape").y
	assert_gt(opening, standing, "дверь выше Otto")
	# И не вдвое выше: дверь в два роста читается воротами, а не дверью.
	assert_lt(opening, standing * 1.8, "но не вдвое")


## Otto входит в шахту: проём шире его.
func test_otto_fits_into_a_shaft() -> void:
	var rules := BuildingRules.new()
	var width := _otto_shape("StandingShape").x
	assert_gt(rules.shaft_width, width, "проём шахты шире Otto")


## Otto помещается на этаже по высоте, и над ним остаётся место на прыжок.
func test_a_floor_has_room_for_otto_and_his_jump() -> void:
	var rules := BuildingRules.new()
	var clearance := rules.floor_height - rules.slab_height
	var standing := _otto_shape("StandingShape").y
	assert_gt(clearance, standing, "Otto стоит на этаже в полный рост")

	var otto := OTTO_SCENE.instantiate() as Otto
	var apex := otto.jump_height()
	otto.free()
	assert_gt(clearance, standing + apex * 0.5, "и прыжок не упирается в потолок сразу")


## Агент того же роста, что и Otto: они стоят рядом в одном кадре.
func test_agent_is_the_same_height_as_otto() -> void:
	assert_almost_eq(_agent_shape().y, _otto_shape("StandingShape").y, 0.12, "рост агента и Otto")


## Присев, Otto ниже пули агента — на этом держится всё уклонение (ADR-0006).
func test_crouching_otto_ducks_under_the_agent_bullet() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var bullet_height := absf(enemy.shot_height)
	enemy.free()
	assert_gt(bullet_height, _otto_shape("CrouchingShape").y, "пуля проходит над присевшим")


## Все игровые тела стоят в одной плоскости и одной толщины: иначе тени и
## коллизии сходились бы каждая в своей (ADR-0021, решение 1).
func test_every_actor_stands_in_the_play_plane() -> void:
	for name in ["StandingShape", "CrouchingShape"]:
		assert_almost_eq(_otto_shape(name).z, WorldSpace.BODY_DEPTH, 0.001, "%s Otto" % name)
	assert_almost_eq(_agent_shape().z, WorldSpace.BODY_DEPTH, 0.001, "агент")


## Доли предметов здания к просвету этажа — по кадру оригинала (ADR-0026).
##
## Замер: нативные снимки MAME 256×224 и спрайтшит аркады 1:1, просвет этажа
## 40 px. Доля оригинала — в пикселях, чтобы число можно было перепроверить по
## кадру, а не по памяти. Допуск — сколько расхождения принято; если оно
## сознательное, причина записана рядом.


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
	# [что, наше, доля оригинала, допуск]
	var table: Array = [
		["плита", rules.slab_height, _original(8.0), 0.01],
		["Otto в рост: 22–23 px над полом", _otto_shape("StandingShape").y, _original(22.5), 0.02],
		["Otto в ширину: 10 px", _otto_shape("StandingShape").x, _original(10.0), 0.02],
		["агент в рост — как Otto", _agent_shape().y, _original(22.5), 0.02],
		["дверь в высоту: 28 px", Door.LEAF_SIZE.y, _original(28.0), 0.01],
		["дверь в ширину: 16 px", Door.LEAF_SIZE.x, _original(16.0), 0.01],
		["шахта: 24 px", rules.shaft_width, _original(24.0), 0.01],
		["шаг места: 24 px", pitch, _original(24.0), 0.01],
		# Сознательное расхождение: 84% против 82%. Эти 5 см держат «лампу
		# не сбить из прыжка» — см. test_a_lamp_is_out_of_reach_from_the_floor.
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


## Присед и выстрелы — доли роста, а не просвета: это устройство тела.
func test_stances_and_shots_keep_the_shape_of_the_original() -> void:
	var otto := OTTO_SCENE.instantiate() as Otto
	var standing := _otto_shape("StandingShape").y
	var crouching := _otto_shape("CrouchingShape").y
	var shot := otto.shot_height_standing
	otto.free()
	# Присед 15–16 px из 24 спрайта, выстрел стоя — 15 px из 22–23 над полом.
	assert_almost_eq(crouching / standing, 15.5 / 24.0, 0.03, "присед к стойке")
	assert_almost_eq(shot / standing, 15.0 / 22.5, 0.03, "пуля стоящего Otto к его росту")

	var rules := BuildingRules.new()
	# Присевший агент — 14 px над полом из 22–23.
	assert_almost_eq(rules.agent_kneel_height / _agent_shape().y, 14.0 / 22.5, 0.04, "колено")


## Пуля и стойка расходятся краем пули, а не её осью: пуля — коробка.
##
## Порядок держит весь бой (ADR-0006, ADR-0016): от высокой пули уходят на
## колено, от низкой — ложатся, присевшего Otto пуля агента не берёт. Выросшие
## актёры сдвинули все пять чисел разом, и разойтись им нельзя ни на сантиметр.
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


## Лампу сбивают из кабины, как в оригинале: с пола — ни стоя, ни в прыжке.
##
## В прыжке Otto упирается головой в потолок, и выше этого его пуля не
## поднимается, сколько бы ни давал сам прыжок (ADR-0026, решение 5).
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
	# А из кабины — да: кабина проходит все высоты между этажами, и пол её
	# бывает на любой высоте от одного пола до другого.
	assert_lt(lamp_bottom - shot, rules.floor_height, "ствол из кабины проходит высоту лампы")


## В кадре столько этажей, сколько в поле здания оригинала: 176 px при шаге 48.
func test_the_frame_shows_as_many_floors_as_the_original() -> void:
	var rules := BuildingRules.new()
	# На плоскости игры, как считает сама камера: наклонённый кадр выше своего
	# размера в 1/cos(наклона) раз.
	var tilt := deg_to_rad(SideCamera.TILT_DEGREES)
	var floors := SideCamera.DEFAULT_HALF_HEIGHT * 2.0 / cos(tilt) / rules.floor_height
	assert_almost_eq(floors, ORIGINAL_FIELD_PX / ORIGINAL_FLOOR_PX, 0.01, "этажей в кадре")
