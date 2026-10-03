class_name BuildingMusic
extends RefCounted

## Музыка здания (ADR-0057, решение 7): тема — по типу здания и времени суток,
## при сирене — мотив тревоги типа. С середины здания вниз играет следующий трек
## набора — смена темы, как на повороте миссии в Elevator Action Returns; в
## наборе из одного трека (утро и день офиса — выбор пользователя) он тот же.
## Тревога половиной не меняется: она звучит до конца здания.
##
## Без узлов: какой трек на каком этаже, проверяется тестом.

var _rules: BuildingRules = null
var _seed: int = 0
var _lower: bool = false


func _init(rules: BuildingRules, building_seed: int) -> void:
	_rules = rules
	_seed = building_seed


## Ниже ли середины здания этаж [param index]: с него играет второй трек.
func is_lower_half(index: int) -> bool:
	return index >= _rules.floors / 2


## Что играть на этаже [param index]: имя набора и вариант в нём.
func track_at(index: int, alarm: bool) -> Array:
	if alarm:
		return [Sounds.alarm_for(_rules.kind), _seed]
	var theme := Sounds.theme_for(_rules.time_of_day, _rules.kind)
	# В наборе из одного трека меняться нечему: внизу играет тот же.
	var turn := 1 if is_lower_half(index) and Sounds.variants(theme).size() > 1 else 0
	return [theme, _seed + turn]


## Включает музыку этажа [param index] или тревогу.
func play(alarm: bool, index: int) -> void:
	_lower = is_lower_half(index)
	var track := track_at(index, alarm)
	Sounds.play_music(String(track[0]), int(track[1]))


## Otto на этаже [param index]: перешёл середину здания — меняет тему. Пока
## [param hold] — тревога или вступление, — трек не трогает.
func follow(index: int, hold: bool) -> void:
	var lower := is_lower_half(index)
	if lower == _lower:
		return
	_lower = lower
	if not hold:
		play(false, index)
