extends GutTest

## Пропорции мира: человек, дверь, проём, этаж.
##
## Игра, сыгранная руками, дала упрёк: «маленький человечек, маленькие двери
## и несуразно огромные окна». Числа развели в M13 (ADR-0018, решение 5), и
## держать их дальше должен тест, а не глаз: ассеты и константы живут в разных
## файлах и расходятся молча.

const OTTO_SCENE := preload("res://src/actors/otto/otto.tscn")
const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")


func _otto_shape(name: String) -> Vector2:
	var otto := OTTO_SCENE.instantiate() as Otto
	var shape := otto.get_node(name) as CollisionShape2D
	var size := (shape.shape as RectangleShape2D).size
	otto.free()
	return size


## Otto проходит в дверь, не пригибаясь: дверь выше него.
func test_otto_fits_through_a_door() -> void:
	var door := SpriteTextures.tile("door")
	assert_not_null(door, "ассет двери на месте")
	var opening := float(door.diffuse_texture.get_height())
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
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var shape := enemy.get_node("Shape") as CollisionShape2D
	var agent := (shape.shape as RectangleShape2D).size
	enemy.free()
	assert_almost_eq(agent.y, _otto_shape("StandingShape").y, 12.0, "рост агента и Otto")


## Присев, Otto ниже пули агента — на этом держится всё уклонение (ADR-0006).
func test_crouching_otto_ducks_under_the_agent_bullet() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	var bullet_height := absf(enemy.shot_height)
	enemy.free()
	assert_gt(bullet_height, _otto_shape("CrouchingShape").y, "пуля проходит над присевшим")


## Окно не больше человека втрое: «несуразно огромные окна» были ровно об этом.
func test_a_window_is_not_a_gate() -> void:
	var standing := _otto_shape("StandingShape").y
	assert_lt(BuildingBackdrop.WINDOW_SIZE.y, standing, "окно ниже Otto — это окно, а не витрина")
	assert_lt(BuildingBackdrop.WINDOW_SIZE.x, standing * 1.5, "и не втрое шире его")
