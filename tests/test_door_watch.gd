extends GutTest

## Тесты агента у двери, за которой спрятался Otto (ADR-0038, решение 2).
##
## Правило пользователя, в ROM его нет: агенты его этажа иногда подходят к двери и
## ждут. Стерегутся здесь границы «иногда»: не больше одного у двери, жребий раз
## на визит, вышел Otto — ждать некого. Проверка на здании — в
## [code]test_red_door.gd[/code].

const FLOOR: int = 7
const DOOR_X: float = 10.0
const NO_BLOCKS: Array[Vector2] = []


func _watch(seed_value: int) -> DoorWatch:
	var watch := DoorWatch.new()
	watch.rng.seed = seed_value
	watch.begin(FLOOR, DOOR_X)
	return watch


## Один кадр уровня: каждого агента спрашивают, где ему ждать. Возвращает ответы.
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
			assert_lte(waiting, 1, "у двери не больше одного, сид %d" % seed_value)
			if waiting > 0:
				somebody += 1
	assert_gt(somebody, 0, "никто ни разу не пошёл — проверять было нечего")


func test_the_roll_is_once_per_visit_not_per_frame() -> void:
	# Жребий за кадр дал бы «иногда» каждому за секунду: на шестидесяти сидах
	# одинокий агент пошёл бы всегда. Раз на визит — примерно в половине.
	var went := 0
	var ids: Array[int] = [5]
	var xs: Array[float] = [4.0]
	for seed_value: int in range(1, 201):
		var watch := _watch(seed_value)
		var first := _frame(watch, ids, xs)
		var steady := true
		for _frame_index: int in 60:
			steady = steady and is_nan(_frame(watch, ids, xs)[0]) == is_nan(first[0])
		assert_true(steady, "решение держится весь визит, сид %d" % seed_value)
		if not is_nan(first[0]):
			went += 1
	assert_between(went, 60, 140, "каждый второй, а не каждый")


func test_the_post_is_off_the_mat_on_the_agents_side() -> void:
	var watch := _watch(1)
	var left := watch.spot(3.0)
	var right := watch.spot(20.0)
	assert_lt(left, DOOR_X, "слева пришёл — слева и ждёт")
	assert_gt(right, DOOR_X)
	for post: float in [left, right]:
		var gap := absf(post - DOOR_X)
		assert_gt(gap - Proportions.BODY_WIDTH * 0.5, Proportions.DOOR_MAT * 0.5, "не на коврике")
		assert_lt(gap, Proportions.DOOR.x, "но у самой двери")


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
		assert_true(is_nan(watch.post_for(1, FLOOR, 3.0, blocks)), "проём между ним и дверью")


func test_the_watcher_lets_go_when_otto_comes_out() -> void:
	var ids: Array[int] = [21, 22, 23, 24]
	var xs: Array[float] = [4.0, 6.0, 14.0, 17.0]
	for seed_value: int in range(1, 30):
		var watch := _watch(seed_value)
		_frame(watch, ids, xs)
		watch.end()
		for _frame_index: int in 5:
			assert_eq(_waiting(_frame(watch, ids, xs)), 0, "вышел — ждать некого")


func test_a_gone_watcher_frees_the_door() -> void:
	# Ждущего убили: в следующем кадре о нём не спросят, и место у двери
	# свободно — но жребий уже брошенным не перебрасывается.
	var found := false
	for seed_value: int in range(1, 60):
		var watch := _watch(seed_value)
		watch.start_frame()
		if is_nan(watch.post_for(1, FLOOR, 4.0, NO_BLOCKS)):
			continue
		found = true
		watch.start_frame()
		watch.start_frame()
		assert_eq(watch.watcher(), 0, "пропал из кадра — пост свободен")
		break
	assert_true(found, "ни на одном сиде никто не пошёл")


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
	assert_gt(went, 0, "новый визит — новый жребий")
