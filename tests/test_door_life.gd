extends GutTest

## Life behind an apartment door (ADR-0055, decision 8): the sound is rare, only at
## a closed door on a floor in the frame, and the door draw repeats.


func test_a_door_sounds_now_and_then() -> void:
	var life := DoorLife.of(7)
	var heard: Array[String] = []
	for _step: int in 600 * 60:
		var sound := life.advance(1.0 / 60.0, true)
		if sound != "":
			heard.append(sound)
	# In ten minutes — from four to ten times: a pause of one to two and a half minutes.
	assert_between(heard.size(), 4, 11, "the sound is rare")
	for sound: String in heard:
		assert_has(DoorLife.SOUNDS, sound, "a sound from its own set")


func test_a_silent_door_keeps_its_clock() -> void:
	var life := DoorLife.of(3)
	for _step: int in 600 * 60:
		assert_eq(life.advance(1.0 / 60.0, false), "", "an inaudible door is silent")
	var first := ""
	for _step: int in 200 * 60:
		first = life.advance(1.0 / 60.0, true)
		if first != "":
			break
	assert_ne(
		first, "", "once audible, it sounds on its own schedule, without an accumulated burst"
	)


func test_the_same_door_lives_the_same_life() -> void:
	var one := DoorLife.of(11)
	var two := DoorLife.of(11)
	for _step: int in 300 * 60:
		assert_eq(one.advance(1.0 / 60.0, true), two.advance(1.0 / 60.0, true))


func test_the_step_sounds_the_floor_of_each_kind() -> void:
	var steps := {
		BuildingIdentity.Kind.HOTEL: Sounds.STEP_CARPET,
		BuildingIdentity.Kind.OFFICE: Sounds.STEP_CONCRETE,
		BuildingIdentity.Kind.RESIDENTIAL: Sounds.STEP_LINO,
	}
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var building := BuildingIdentity.typed(kind)
		assert_eq(
			PlaceSound.step_at(false, building), steps[kind], "kind %d: step on the floor" % kind
		)
		assert_eq(
			PlaceSound.step_at(true, building), Sounds.STEP_CONCRETE, "on the roof — concrete"
		)


func test_each_kind_has_its_own_room_tone() -> void:
	var tones := {}
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var loops := Sounds.weather_loops(Weather.Kind.CLEAR, false, TimeOfDay.Kind.NIGHT, kind)
		assert_eq(loops.size(), 1, "inside — one loop")
		tones[loops[0]] = true
		var outdoors := Sounds.weather_loops(Weather.Kind.CLEAR, true, TimeOfDay.Kind.NIGHT, kind)
		assert_false(outdoors.has(Sounds.room_tone_of(kind)), "outside there is no corridor tone")
	assert_eq(tones.size(), BuildingIdentity.Kind.size(), "each kind has its own corridor tone")
