class_name BuildingMusic
extends RefCounted

## Building music (ADR-0057, decision 7): the theme — by building kind and time of day,
## with the siren — the kind's alarm motif. From the middle of the building down the next track
## of the set plays — a change of theme, like a mission turn in Elevator Action Returns; in
## a set of one track (office morning and day — the user's choice) it is the same one.
## The alarm does not change by half: it plays until the end of the building.
##
## Without nodes: which track on which floor is checked by a test.

var _rules: BuildingRules = null
var _seed: int = 0
var _lower: bool = false


func _init(rules: BuildingRules, building_seed: int) -> void:
	_rules = rules
	_seed = building_seed


## Whether floor [param index] is below the middle of the building: the second track plays from it.
func is_lower_half(index: int) -> bool:
	return index >= _rules.floors / 2


## What to play on floor [param index]: the set name and the variant in it.
func track_at(index: int, alarm: bool) -> Array:
	if alarm:
		return [Sounds.alarm_for(_rules.kind), _seed]
	var theme := Sounds.theme_for(_rules.time_of_day, _rules.kind)
	# In a set of one track there is nothing to change: the same one plays below.
	var turn := 1 if is_lower_half(index) and Sounds.variants(theme).size() > 1 else 0
	return [theme, _seed + turn]


## Turns on the music of floor [param index] or the alarm.
func play(alarm: bool, index: int) -> void:
	_lower = is_lower_half(index)
	var track := track_at(index, alarm)
	Sounds.play_music(String(track[0]), int(track[1]))


## Otto is on floor [param index]: crossed the middle of the building — changes the theme. While
## [param hold] — alarm, intro or death — it does not touch the track and does not remember the
## half: Otto respawned in the other half gets its theme.
func follow(index: int, hold: bool) -> void:
	if hold or is_lower_half(index) == _lower:
		return
	play(false, index)
