extends GutTest

## When one can step from the cab onto a floor — [method ElevatorMotion.can_step_out].
## Without a scene, like [code]test_elevator_motion.gd[/code].

const TOP: float = 0.0
const MIDDLE: float = 100.0
const BOTTOM: float = 200.0


func _shaft(start_floor: int = 0) -> ElevatorMotion:
	var motion := ElevatorMotion.new()
	motion.setup(PackedFloat32Array([TOP, MIDDLE, BOTTOM]), start_floor)
	return motion


## One can step out while moving as long as the cab floor is no more than 18/48 of a floor
## above the storey floor, as in the ROM (@36F2, ADR-0044, decision 5).
func test_one_can_step_out_level_with_a_floor() -> void:
	assert_true(_shaft(1).can_step_out(), "вровень — можно")


func test_one_can_step_out_a_little_above_a_floor() -> void:
	var motion := _shaft()
	motion.position = MIDDLE - 30.0
	assert_true(motion.can_step_out(), "на 30 из 100 выше этажа — спрыгнуть можно")


func test_one_cannot_step_out_halfway_between_floors() -> void:
	var motion := _shaft()
	motion.position = MIDDLE - 50.0
	assert_false(motion.can_step_out(), "посреди пролёта — борт стеной")


func test_one_cannot_step_out_below_a_floor() -> void:
	var motion := _shaft()
	motion.position = MIDDLE + 5.0
	assert_false(motion.can_step_out(), "пол кабины ниже этажа — плита на пути")
