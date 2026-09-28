extends GutTest

## Последняя смерть Otto — замедление и наезд (ADR-0042, решение 5).
##
## Сцена сама уходит из дерева, когда кончилась, — поэтому конец ловится своим
## флажком, а не слежкой GUT за сигналами освобождённого узла.

var _finished: bool = false


func before_each() -> void:
	_finished = false


func after_each() -> void:
	Engine.time_scale = 1.0


func _play() -> LastDeath:
	var body := Node3D.new()
	add_child_autofree(body)
	var scene := LastDeath.play(self, body)
	scene.finished.connect(func() -> void: _finished = true)
	return scene


func test_the_world_slows_down_and_comes_back() -> void:
	var scene := _play()
	assert_almost_eq(Engine.time_scale, LastDeath.SLOW, 0.001, "мир замедлен")
	scene.advance(LastDeath.DURATION * 0.5)
	assert_false(_finished, "на середине сцена ещё идёт")
	scene.advance(LastDeath.DURATION)
	assert_true(_finished, "потом — конец партии")
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "и мир в своём темпе")


## Тесты гоняют мир ускоренным: замедление — от того темпа, а не от единицы.
func test_the_slowdown_is_relative() -> void:
	Engine.time_scale = 4.0
	var scene := _play()
	assert_almost_eq(Engine.time_scale, 4.0 * LastDeath.SLOW, 0.001, "втрое медленнее прежнего")
	scene.advance(LastDeath.DURATION)
	assert_almost_eq(Engine.time_scale, 4.0, 0.001, "и прежний темп вернулся")


func test_a_dropped_scene_does_not_leave_the_world_slow() -> void:
	var scene := _play()
	scene.free()
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "выброшенная сцена темп вернула")


## Сцена идёт по настоящим часам: в замедленном мире она не растягивается.
func test_the_scene_runs_on_real_time() -> void:
	_play()
	await wait_seconds(LastDeath.DURATION + 0.5, "сцена по настоящим часам")
	assert_true(_finished, "кончилась в свой срок")
