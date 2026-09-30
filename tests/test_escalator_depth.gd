extends GutTest

## Эскалатор в глубине (ADR-0044, решение 10).
##
## До M24h пролёт резал плиту этажа во всю глубину от площадки до края, и там
## было не пройти. Теперь проём — только в задней полосе коридора, за
## плоскостью игры: пол перед ним цельный, мимо эскалатора ходят. Проверяется
## на любом здании, а не на одном: раскладка генерируется.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")
const SEEDS: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89]
## Сколько кадров дать поставленному над проёмом Otto, чтобы он провалился,
## будь там дыра.
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
						"сид %d, этаж %d: над проёмом эскалатора пол"
						% [building_seed, escalator.floor_index]
					)
				)


func test_the_hole_is_behind_the_play_plane() -> void:
	assert_lt(
		Escalator.HOLE_FRONT_Z,
		WorldSpace.PLAY_Z - WorldSpace.BODY_DEPTH * 0.5,
		"край цельной плиты — за телом идущего"
	)
	assert_lte(
		Escalator.BELT_Z + Escalator.BELT_DEPTH * 0.5,
		Escalator.HOLE_FRONT_Z,
		"полотно — в проёме, а не в цельной плите"
	)


## Дыра в перекрытии под пролётом — там, где он проходит плиту, и не дальше
## края этажа.
func test_the_hole_starts_at_the_bend_and_stays_on_the_floor() -> void:
	var rules := BuildingRules.new()
	for building_seed: int in SEEDS:
		var plan := BuildingPlan.generate(rules, building_seed)
		for escalator in plan.escalators:
			var hole := escalator.hole(rules)
			var gap := escalator.gap(rules)
			var where := "сид %d, этаж %d" % [building_seed, escalator.floor_index]
			assert_gte(hole.x, gap.x - 0.001, where + ": дыра в месте эскалатора")
			assert_lte(hole.y, gap.y + 0.001, where + ": дыра в месте эскалатора")
			assert_gt(hole.y - hole.x, Proportions.BODY, where + ": голова едущего проходит")


## Otto, поставленный над проёмом, стоит на полу: плита в плоскости игры цельная.
func test_otto_stands_over_the_escalator_hole() -> void:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = 2
	add_child_autofree(level)
	await level.wait_for_the_landing()
	var plan := level.plan()
	assert_false(plan.escalators.is_empty(), "в здании есть эскалатор")
	for escalator: EscalatorSpot in plan.escalators.slice(0, 3):
		var hole := escalator.hole(level.rules)
		var surface := level.rules.floor_surface(escalator.floor_index)
		level.otto.global_position = WorldSpace.to_scene(Vector2((hole.x + hole.y) * 0.5, surface))
		await wait_physics_frames(FALL_FRAMES)
		var y := WorldSpace.to_plane(level.otto.global_position).y
		assert_almost_eq(y, surface, 0.1, "этаж %d: Otto стоит над проёмом" % escalator.floor_index)
		assert_false(level.otto.is_dead(), "и жив")
