extends GutTest

## Music by building kind (ADR-0057, decision 7): each kind has its own set for
## each time of day and its own alarm; from the middle of the building the next track of
## the set plays, if there is one; the alarm does not change at the half.

const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func test_every_kind_and_time_has_its_music() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for time: TimeOfDay.Kind in TimeOfDay.Kind.values():
			var theme := Sounds.theme_for(time, kind)
			assert_not_null(Sounds.stream(theme), "%s: track present" % theme)
			# Without a loop the building track played once and fell silent (code review M24o).
			assert_true(Sounds.LOOPED.has(theme), "%s plays as a loop" % theme)
			assert_true(Sounds.MUSIC.has(theme), "%s is music" % theme)
		var alarm := Sounds.alarm_for(kind)
		assert_not_null(Sounds.stream(alarm), "%s: alarm present" % alarm)
		assert_true(Sounds.LOOPED.has(alarm), "%s plays as a loop" % alarm)
		assert_true(Sounds.MUSIC.has(alarm), "%s is music" % alarm)


func test_kinds_do_not_share_themes() -> void:
	for time: TimeOfDay.Kind in TimeOfDay.Kind.values():
		var names := {}
		for kind: BuildingIdentity.Kind in KINDS:
			names[Sounds.theme_for(time, kind)] = true
		assert_eq(names.size(), KINDS.size(), "time %d: each kind has its own theme" % time)
	var alarms := {}
	for kind: BuildingIdentity.Kind in KINDS:
		alarms[Sounds.alarm_for(kind)] = true
	assert_eq(alarms.size(), KINDS.size(), "each kind has its own alarm")


func test_hotel_keeps_its_old_names() -> void:
	assert_eq(Sounds.theme_for(TimeOfDay.Kind.NIGHT), Sounds.THEME)
	assert_eq(Sounds.theme_for(TimeOfDay.Kind.DAY), Sounds.THEME_DAY)
	assert_eq(Sounds.alarm_for(), Sounds.ALARM_THEME)


func test_lower_half_plays_the_next_track() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		var rules := BuildingRules.new()
		rules.kind = kind
		var music := BuildingMusic.new(rules, 7)
		var top: Array = music.track_at(0, false)
		var bottom: Array = music.track_at(rules.floors - 2, false)
		assert_eq(top[0], bottom[0], "the same set")
		var count := Sounds.variants(String(top[0])).size()
		if count > 1:
			assert_ne(
				posmod(int(top[1]), count), posmod(int(bottom[1]), count), "a different track below"
			)
		else:
			assert_eq(top[1], bottom[1], "one track — the same below")
		var alarm_top: Array = music.track_at(0, true)
		var alarm_bottom: Array = music.track_at(rules.floors - 2, true)
		assert_eq(alarm_top, alarm_bottom, "the alarm does not change with the half")
		assert_eq(String(alarm_top[0]), Sounds.alarm_for(kind))


## While the alarm, the intro or death holds, the theme does not change, but the half
## is not forgotten either: Otto, released already in the lower half, gets its track.
func test_a_hold_does_not_swallow_the_turn() -> void:
	var director := AudioDirector.instance()
	assert_not_null(director, "the sound autoload is up")
	if director == null:
		return
	var rules := BuildingRules.new()
	var music := BuildingMusic.new(rules, 7)
	var lower := rules.floors - 2
	var top: Array = music.track_at(0, false)
	var bottom: Array = music.track_at(lower, false)
	music.play(false, 0)
	var upper_stream := director.music_stream()
	music.follow(lower, true)
	assert_eq(director.music_stream(), upper_stream, "under the hold the theme is the same")
	music.follow(lower, false)
	assert_eq(
		director.music_stream(),
		Sounds.variant(String(bottom[0]), int(bottom[1])),
		"hold released — the lower theme plays"
	)
	assert_ne(top[1], bottom[1], "a night hotel has a different track below")
	director.stop_music()
	director.reset()
