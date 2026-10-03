extends GutTest

## Tests of the three-bullet rule.
##
## In the original Otto keeps no more than three shots on screen at once — fire them all
## and you stand unarmed until they fly off (ADR-0006, point 2).


func test_fresh_gun_is_ready() -> void:
	assert_true(Gun.new().can_fire())


func test_three_bullets_empty_the_gun() -> void:
	var gun := Gun.new()
	for _shot: int in Gun.MAX_LIVE_BULLETS:
		assert_true(gun.can_fire())
		gun.fired()
	assert_false(gun.can_fire(), "четвёртой пули на экране не бывает")


func test_spent_bullet_frees_a_shot() -> void:
	var gun := Gun.new()
	for _shot: int in Gun.MAX_LIVE_BULLETS:
		gun.fired()
	gun.bullet_spent()
	assert_true(gun.can_fire())


func test_counter_never_goes_negative() -> void:
	var gun := Gun.new()
	gun.bullet_spent()
	gun.bullet_spent()
	assert_eq(gun.live, 0)
