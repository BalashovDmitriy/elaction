extends GutTest

## The escalator in depth (ADR-0044, decision 10).
##
## Until M24h the span cut the floor slab over the whole depth from the landing to the edge, and you
## could not walk there. Now the opening is only in the corridor's rear strip, behind the play
## plane: the floor in front of it is solid, people walk past the escalator. Checked on any
## building, not on one: the layout is generated.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
## How many frames to give an Otto placed over the opening to fall through, if there were a hole.
const FALL_FRAMES: int = 45


func after_all() -> void:
	GameState.instance().reset()


func test_escalators_do_not_cut_walking() -> void:
	var rules := BuildingRules.new()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var hole := escalator.hole(rules)
			var middle := (hole.x + hole.y) * 0.5
			for block: Vector2 in plan.blocks_on(rules, escalator.floor_index):
				assert_false(
					middle > block.x and middle < block.y,
					(
						"seed %d, floor %d: a floor above the escalator opening"
						% [building_seed, escalator.floor_index]
					)
				)


func test_the_hole_is_behind_the_play_plane() -> void:
	assert_lt(
		Escalator.HOLE_FRONT_Z,
		WorldSpace.PLAY_Z - WorldSpace.BODY_DEPTH * 0.5,
		"the edge of the solid slab is behind the walker's body"
	)
	assert_lte(
		Escalator.BELT_Z + Escalator.BELT_DEPTH * 0.5,
		Escalator.HOLE_FRONT_Z,
		"the belt is in the opening, not in the solid slab"
	)


## The hole in the slab under the span — where it passes through the slab, and no farther than the
## floor edge.
func test_the_hole_starts_at_the_bend_and_stays_on_the_floor() -> void:
	var rules := BuildingRules.new()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var hole := escalator.hole(rules)
			var gap := escalator.gap(rules)
			var where := "seed %d, floor %d" % [building_seed, escalator.floor_index]
			assert_gte(hole.x, gap.x - 0.001, where + ": a hole where the escalator is")
			assert_lte(hole.y, gap.y + 0.001, where + ": a hole where the escalator is")
			assert_gt(hole.y - hole.x, Proportions.BODY, where + ": the rider's head passes")


## An Otto placed over the opening stands on the floor: the slab in the play plane is solid.
func test_otto_stands_over_the_escalator_hole() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 2
	add_child_autofree(level)
	await level.wait_for_the_landing()
	var plan := level.plan()
	assert_false(plan.escalators.is_empty(), "the building has an escalator")
	for escalator: EscalatorSpot in plan.escalators.slice(0, 3):
		var hole := escalator.hole(level.rules)
		var surface := level.rules.floor_surface(escalator.floor_index)
		level.otto.global_position = WorldSpace.to_scene(Vector2((hole.x + hole.y) * 0.5, surface))
		await wait_physics_frames(FALL_FRAMES)
		var y := WorldSpace.to_plane(level.otto.global_position).y
		assert_almost_eq(
			y, surface, 0.1, "floor %d: Otto stands above the opening" % escalator.floor_index
		)
		assert_false(level.otto.is_dead(), "and alive")
