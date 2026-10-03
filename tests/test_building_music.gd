extends GutTest

## Музыка по типу здания (ADR-0057, решение 7): у каждого типа свой набор на
## каждое время суток и своя тревога; с середины здания играет следующий трек
## набора, если он есть; тревога половиной не меняется.

const KINDS: Array[BuildingIdentity.Kind] = [
	BuildingIdentity.Kind.HOTEL, BuildingIdentity.Kind.OFFICE, BuildingIdentity.Kind.RESIDENTIAL
]


func test_every_kind_and_time_has_its_music() -> void:
	for kind: BuildingIdentity.Kind in KINDS:
		for time: TimeOfDay.Kind in TimeOfDay.Kind.values():
			var theme := Sounds.theme_for(time, kind)
			assert_not_null(Sounds.stream(theme), "%s: трек есть" % theme)
		var alarm := Sounds.alarm_for(kind)
		assert_not_null(Sounds.stream(alarm), "%s: тревога есть" % alarm)


func test_kinds_do_not_share_themes() -> void:
	for time: TimeOfDay.Kind in TimeOfDay.Kind.values():
		var names := {}
		for kind: BuildingIdentity.Kind in KINDS:
			names[Sounds.theme_for(time, kind)] = true
		assert_eq(names.size(), KINDS.size(), "время %d: у каждого типа своя тема" % time)
	var alarms := {}
	for kind: BuildingIdentity.Kind in KINDS:
		alarms[Sounds.alarm_for(kind)] = true
	assert_eq(alarms.size(), KINDS.size(), "у каждого типа своя тревога")


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
		assert_eq(top[0], bottom[0], "тот же набор")
		var count := Sounds.variants(String(top[0])).size()
		if count > 1:
			assert_ne(
				posmod(int(top[1]), count), posmod(int(bottom[1]), count), "внизу — другой трек"
			)
		else:
			assert_eq(top[1], bottom[1], "один трек — внизу тот же")
		var alarm_top: Array = music.track_at(0, true)
		var alarm_bottom: Array = music.track_at(rules.floors - 2, true)
		assert_eq(alarm_top, alarm_bottom, "тревога половиной не меняется")
		assert_eq(String(alarm_top[0]), Sounds.alarm_for(kind))
