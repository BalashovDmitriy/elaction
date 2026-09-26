class_name FadeCurtain
extends CanvasLayer

## Затемнение между зданиями (ADR-0038, решение 4).
##
## Машина с Otto уехала, бонус досчитан — кадр уходит в чёрное, под чёрным
## собирается следующее здание, и кадр выходит из чёрного уже на нём. Раньше
## здание сменялось встык, одним кадром.
##
## Слой — над HUD и под меню: бонус уходит в чёрное вместе со сценой, а пауза,
## взятая посреди затемнения, видна поверх него. На паузе затемнение стоит.

## Слой холста: HUD — 3, меню — 5.
const LAYER: int = 4
## Сколько кадр уходит в чёрное и сколько выходит из него, с.
const FADE_OUT: float = 0.45
const FADE_IN: float = 0.45

var _veil: ColorRect = null
var _tween: Tween = null


func _init() -> void:
	name = "FadeCurtain"
	layer = LAYER
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.color = Color(0.0, 0.0, 0.0, 0.0)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)


## Выждав [param hold], уводит кадр в чёрное, зовёт [param swap] и выводит кадр
## обратно. Начатое прежде затемнение отменяется.
func cover(hold: float, swap: Callable) -> void:
	cancel()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	if hold > 0.0:
		_tween.tween_interval(hold)
	_tween.tween_property(_veil, "color:a", 1.0, FADE_OUT)
	_tween.tween_callback(swap)
	_tween.tween_property(_veil, "color:a", 0.0, FADE_IN)


## Начинает с чёрного: держит его [param hold] секунд и выводит кадр. Так
## открывается первое здание партии, пока под чёрным греются шейдеры
## ([ShaderWarmup]).
func reveal(hold: float) -> void:
	cancel()
	_veil.color.a = 1.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tween.tween_interval(hold)
	_tween.tween_property(_veil, "color:a", 0.0, FADE_IN)


## Снимает затемнение сразу: партию бросили в меню или начали заново посреди
## смены здания — менять здание уже незачем.
func cancel() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_veil.color.a = 0.0


## Идёт ли затемнение.
func is_running() -> bool:
	return _tween != null and _tween.is_running()


## Насколько кадр сейчас в чёрном: 0 — открыт, 1 — чёрный.
func opacity() -> float:
	return _veil.color.a
