class_name BuildingPalette
extends Resource

## Палитра раунда: чем красится здание и каким светом оно горит.
##
## В оригинале планировка почти не меняется, а цвета меняются с каждым раундом
## («colors change with new levels»). Поэтому цвет — не константа уровня, а
## правило здания: [method BuildingRules.for_building] берёт палитру по номеру
## раунда, и набор зацикливается, как зацикливаются сами раунды
## ([ADR-0017](../../docs/adr/0017-spectrum-palette-and-shafts.md), решение 2).
##
## Тон раунда ложится на материалы здания: с M21b — множителем на фактуру
## стены ([BuildingFinish]), так что рисунок обоев и штукатурки остаётся, а
## цвет даёт раунд.
##
## Первый раунд — кадр порта: бирюзовые этажи, красная кладка, синяя шахта.

## Наборы палитр по типу здания ([enum BuildingIdentity.Kind]), собранные по
## первому требованию. Пустой — значит ещё не собраны.
static var _families: Array = []

## Тон внутренностей этажа: задняя стена, откосы окон.
@export var story := Color(0.0, 0.78, 0.78)

## Тон боковой кладки и надстройки на крыше.
@export var masonry := Color(0.85, 0.16, 0.16)

## Тон направляющих и створок шахты.
@export var shaft := Color(0.22, 0.32, 0.95)

## Общий тон здания — и он же тон погашенного этажа (ADR-0010, пункт 3).
##
## Отличается от света ламп своего типа здания ([constant BuildingAir.LAMP_LIGHT])
## не только яркостью, а оттенком: в темноте агенты продолжают стрелять, и
## «просто темнее» означало бы смерть ни за что.
## Разрыв между парой проверяется тестом на каждой палитре каждого набора.
@export var dark := Color(0.34, 0.42, 0.72)


## Сколько палитр в наборе. Набор конечный и идёт по кругу; у всех типов
## палитр поровну.
static func count() -> int:
	return _all(BuildingIdentity.Kind.HOTEL).size()


## Палитра раунда здания типа [param kind]. Нумерация с единицы, дальше по
## кругу.
static func of_round(
	number: int, kind: BuildingIdentity.Kind = BuildingIdentity.Kind.HOTEL
) -> BuildingPalette:
	var all := _all(kind)
	return all[posmod(maxi(number, 1) - 1, all.size())]


## Та же палитра раунда — из набора типа [param kind] (ADR-0056, решение 2):
## правила знают номер раунда, а тип здания узнаёт уровень. Чужая палитра —
## не из наборов — остаётся как есть: её поставили руками.
static func of_kind(palette: BuildingPalette, kind: BuildingIdentity.Kind) -> BuildingPalette:
	for family: int in BuildingIdentity.Kind.size():
		var index := _all(family as BuildingIdentity.Kind).find(palette)
		if index >= 0:
			return _all(kind)[index]
	return palette


## Набор типа [param kind]. Строится один раз: палитра — ресурс, и раздавать
## всем зданиям одну и ту же копию дешевле, чем собирать её заново на каждое.
##
## Отель держит набор порта Spectrum — первый кадр игры как в оригинале, —
## остальные типы — свои гаммы (ADR-0056, решение 2): офис холодный, жилой дом
## выцветший и землистый. Тон погашенной зоны у всех один по яркости —
## темнота одинаково тёмная (решение 3).
static func _all(kind: BuildingIdentity.Kind) -> Array:
	if _families.is_empty():
		_families = [_hotel(), _office(), _residential()]
	return _families[kind]


## Отель: набор порта Spectrum. Цвета взяты из атрибутной палитры, но не
## буквально: у порта они в полную силу и без света, а у нас поверх лягут
## заливка этажа и блик.
static func _hotel() -> Array[BuildingPalette]:
	return [
		# Кадр порта: бирюзовые этажи, красная кладка, синяя шахта.
		_make(
			Color(0.0, 0.78, 0.78),
			Color(0.85, 0.16, 0.16),
			Color(0.22, 0.32, 0.95),
			Color(0.34, 0.42, 0.72)
		),
		# Зелёный раунд: кладка уходит в пурпур, шахта остаётся холодной.
		_make(
			Color(0.22, 0.80, 0.30),
			Color(0.78, 0.20, 0.72),
			Color(0.20, 0.36, 0.92),
			Color(0.30, 0.40, 0.70)
		),
		# Пурпурный раунд: шахта бирюзовая, иначе она слилась бы со стеной.
		_make(
			Color(0.80, 0.26, 0.80),
			Color(0.26, 0.34, 0.86),
			Color(0.16, 0.78, 0.78),
			Color(0.32, 0.38, 0.74)
		),
		# Жёлтый раунд: самый тёплый этаж в наборе, и погашенный отделяется
		# от него сильнее всего.
		_make(
			Color(0.82, 0.76, 0.18),
			Color(0.80, 0.22, 0.20),
			Color(0.22, 0.34, 0.90),
			Color(0.28, 0.40, 0.76)
		),
	]


## Офис: холодная гамма — сталь, лёд, морская волна, графит с сиреневым.
static func _office() -> Array[BuildingPalette]:
	return [
		_make(
			Color(0.42, 0.62, 0.84),
			Color(0.30, 0.33, 0.40),
			Color(0.86, 0.56, 0.16),
			Color(0.30, 0.38, 0.72)
		),
		_make(
			Color(0.28, 0.70, 0.66),
			Color(0.24, 0.26, 0.34),
			Color(0.26, 0.30, 0.86),
			Color(0.30, 0.40, 0.70)
		),
		_make(
			Color(0.72, 0.78, 0.88),
			Color(0.20, 0.34, 0.62),
			Color(0.82, 0.30, 0.26),
			Color(0.32, 0.38, 0.74)
		),
		_make(
			Color(0.54, 0.50, 0.80),
			Color(0.22, 0.22, 0.30),
			Color(0.10, 0.80, 0.50),
			Color(0.30, 0.38, 0.72)
		),
	]


## Жилой дом: выцветшая краска подъездов — мята, горчица, бирюза
## учреждения, терракота.
static func _residential() -> Array[BuildingPalette]:
	return [
		_make(
			Color(0.44, 0.68, 0.48),
			Color(0.64, 0.28, 0.18),
			Color(0.30, 0.36, 0.70),
			Color(0.30, 0.38, 0.68)
		),
		_make(
			Color(0.76, 0.62, 0.28),
			Color(0.40, 0.30, 0.24),
			Color(0.22, 0.46, 0.72),
			Color(0.30, 0.38, 0.72)
		),
		_make(
			Color(0.26, 0.60, 0.62),
			Color(0.72, 0.36, 0.22),
			Color(0.66, 0.62, 0.20),
			Color(0.30, 0.38, 0.70)
		),
		_make(
			Color(0.70, 0.46, 0.36),
			Color(0.18, 0.30, 0.20),
			Color(0.24, 0.40, 0.82),
			Color(0.30, 0.38, 0.72)
		),
	]


static func _make(
	story_tone: Color, masonry_tone: Color, shaft_tone: Color, dark_tone: Color
) -> BuildingPalette:
	var palette := BuildingPalette.new()
	palette.story = story_tone
	palette.masonry = masonry_tone
	palette.shaft = shaft_tone
	palette.dark = dark_tone
	return palette
