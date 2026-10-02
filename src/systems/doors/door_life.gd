class_name DoorLife
extends RefCounted

## Жизнь за дверью квартиры (ADR-0055, решение 8): изредка из-за закрытой
## двери глухо слышно телевизор, собаку или ссору соседей.
##
## Только звук, механики нет: агенты за этими дверьми не прячутся, и звук не
## предвещает выхода агента — у того свой телеграф створки (ADR-0020). Поэтому
## звучит лишь закрытая дверь без документа и на этаже в кадре, редко и тихо.
## Без узлов: дверь спрашивает каждый кадр, что прозвучало.

## Что слышно из-за двери.
const SOUNDS: PackedStringArray = [Sounds.DOOR_TV, Sounds.DOOR_DOG, Sounds.DOOR_ARGUE]
## Пауза между звуками одной двери, с: дверей в кадре до десятка, и на всех
## вместе выходит звук раз в десяток секунд.
const PAUSE := Vector2(60.0, 150.0)
## Первая пауза короче: войдя на этаж, жизнь слышно не через минуту.
const FIRST_PAUSE := Vector2(4.0, 90.0)

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0


## Жизнь двери с жребием [param seed]: одна дверь звучит одинаково от раза к разу.
static func of(seed: int) -> DoorLife:
	var life := DoorLife.new()
	life._rng.seed = seed
	life._wait = life._rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
	return life


## Прошло [param delta] секунд; [param audible] — дверь закрыта, без документа
## и на этаже в кадре. Возвращает имя звука, если он прозвучал сейчас, иначе
## пустую строку. Пока дверь не слышно, часы стоят: звук не копится.
func advance(delta: float, audible: bool) -> String:
	if not audible:
		return ""
	_wait -= delta
	if _wait > 0.0:
		return ""
	_wait = _rng.randf_range(PAUSE.x, PAUSE.y)
	return SOUNDS[_rng.randi_range(0, SOUNDS.size() - 1)]
