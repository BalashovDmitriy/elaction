extends GutTest

## Tests of an agent at the door Otto hid behind (ADR-0038, decision 2).
##
## The user's rule, not in the ROM: agents of his floor sometimes walk up to the door and
## wait. What is guarded here are the bounds of "sometimes": no more than one at the door,
## one draw per visit, Otto came out — nobody to wait for. The building check is in
## [code]test_red_door.gd[/code].

const FLOOR: int = 7
const DOOR_X: float = 10.0
const NO_BLOCKS: Array[Vector2] = []


func _watch(seed_value: int) -> DoorWatch:
	var watch := DoorWatch.new()
	watch.rng.seed = seed_value
	watch.begin(FLOOR, DOOR_X)
	return watch


## One level frame: each agent is asked where to wait. Returns the answers.
func _frame(watch: DoorWatch, ids: Array[int], xs: Array[float]) -> Array[float]:
	var posts: Array[float] = []
	watch.start_frame()
	for index: int in ids.size():
		posts.append(watch.post_for(ids[index], FLOOR, xs[index], NO_BLOCKS))
	return posts


static func _waiting(posts: Array[float]) -> int:
	var count := 0
	for post: float in posts:
		if not is_nan(post):
			count += 1
	return count


func test_never_more_than_one_agent_waits_at_the_door() -> void:
	var ids: Array[int] = [11, 12, 13, 14]
	var xs: Array[float] = [4.0, 6.0, 14.0, 17.0]
	var somebody := 0
	for seed_value: int in range(1, 60):
		var watch := _watch(seed_value)
		for _frame_index: int in 30:
			var waiting := _waiting(_frame(watch, ids, xs))
			assert_lte(waiting, 1, "no more than one at a door, seed %d" % seed_value)
			if waiting > 0:
				somebody += 1
	assert_gt(somebody, 0, "nobody ever went - nothing to check")


func test_the_roll_is_once_per_visit_not_per_frame() -> void:
	# A draw per frame would give "sometimes" to everyone within a second: on sixty seeds
	# a lone agent would always go. Once per visit — in about half.
	var went := 0
	var ids: Array[int] = [5]
	var xs: Array[float] = [4.0]
	for seed_value: int in range(1, 201):
		var watch := _watch(seed_value)
		var first := _frame(watch, ids, xs)
		var steady := true
		for _frame_index: int in 60:
			steady = steady and is_nan(_frame(watch, ids, xs)[0]) == is_nan(first[0])
		assert_true(steady, "the decision holds for the whole visit, seed %d" % seed_value)
		if not is_nan(first[0]):
			went += 1
	assert_between(went, 60, 140, "every second one, not every one")


func test_the_post_is_off_the_mat_on_the_agents_side() -> void:
	var watch := _watch(1)
	var left := watch.spot(3.0)
	var right := watch.spot(20.0)
	assert_lt(left, DOOR_X, "came from the left - waits on the left")
	assert_gt(right, DOOR_X)
	for post: float in [left, right]:
		var gap := absf(post - DOOR_X)
		assert_gt(gap - Proportions.BODY_WIDTH * 0.5, Proportions.DOOR_MAT * 0.5, "not on the mat")
		assert_lt(gap, Proportions.DOOR.x, "but right at the door")


func test_other_floors_do_not_wait() -> void:
	var watch := _watch(1)
	for agent: int in range(1, 50):
		watch.start_frame()
		assert_true(is_nan(watch.post_for(agent, FLOOR + 1, 4.0, NO_BLOCKS)))


func test_nobody_walks_through_a_hole_or_a_wall() -> void:
	var blocks: Array[Vector2] = [Vector2(6.0, 7.2)]
	for seed_value: int in range(1, 40):
		var watch := _watch(seed_value)
		watch.start_frame()
		assert_true(
			is_nan(watch.post_for(1, FLOOR, 3.0, blocks)), "an opening between him and the door"
		)


func test_the_watcher_lets_go_when_otto_comes_out() -> void:
	var ids: Array[int] = [21, 22, 23, 24]
	var xs: Array[float] = [4.0, 6.0, 14.0, 17.0]
	for seed_value: int in range(1, 30):
		var watch := _watch(seed_value)
		_frame(watch, ids, xs)
		watch.end()
		for _frame_index: int in 5:
			assert_eq(_waiting(_frame(watch, ids, xs)), 0, "left - nobody to wait for")


func test_a_gone_watcher_frees_the_door() -> void:
	# The waiting one was killed: next frame nobody asks about him, and the place at the door
	# is free — but a draw already cast is not recast.
	var found := false
	for seed_value: int in range(1, 60):
		var watch := _watch(seed_value)
		watch.start_frame()
		if is_nan(watch.post_for(1, FLOOR, 4.0, NO_BLOCKS)):
			continue
		found = true
		watch.start_frame()
		watch.start_frame()
		assert_eq(watch.watcher(), 0, "gone from the frame - the post is free")
		break
	assert_true(found, "on no seed did anyone go")


func test_a_new_visit_rolls_again() -> void:
	var went := 0
	for seed_value: int in range(1, 60):
		var watch := _watch(seed_value)
		watch.start_frame()
		watch.post_for(1, FLOOR, 4.0, NO_BLOCKS)
		watch.end()
		watch.begin(FLOOR, DOOR_X)
		watch.start_frame()
		if not is_nan(watch.post_for(1, FLOOR, 4.0, NO_BLOCKS)):
			went += 1
	assert_gt(went, 0, "a new visit - a new roll")
