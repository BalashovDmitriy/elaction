class_name TiledRect
extends RefCounted

## Прямоугольник, замощённый ассетом, — и его же заливка цветом.
##
## Здание собирается из плиток: перекрытия, стены, кладка, шахта, город за
## окнами. Правил у такой плитки набралось больше, чем кажется, и каждое из них
## однажды стоило бага — поэтому они живут в одном месте, а не переписываются
## у каждого, кому понадобился [TextureRect].


## Плитка из ассета: [CanvasTexture] повторяется по площади прямоугольника.
##
## Вместе с цветом приходят нормаль и блик, поэтому свет из M6 ложится на
## рельеф, а не на плоскость ([ADR-0011](../../../docs/adr/0011-asset-pipeline.md),
## пункт 7).
##
## [param tint] — тон раунда: ассеты, которые красит палитра, нарисованы серыми,
## и цвет им даётся умножением, не трогая ни нормаль, ни блик (ADR-0017).
static func make(
	size: Vector2, offset: Vector2, tile: CanvasTexture, tint := Color.WHITE
) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tile
	rect.modulate = tint
	rect.stretch_mode = TextureRect.STRETCH_TILE
	# Повтор включается на самом узле: по умолчанию холст зажимает текстуру
	# по краям, и плита в тридцать тайлов вышла бы одним растянутым.
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	# Размер задаёт место, а не тайл. По умолчанию [TextureRect] объявляет
	# минимальным размером размер текстуры, и [Control] поднимал до него всё,
	# что меньше: полоса стены над окном (42 px при тайле 96 px) растягивалась
	# до 96 px и закрывала город в верхней трети проёма.
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = size
	rect.position = offset
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Цветной прямоугольник без ассета.
##
## Остался ровно для окон города: они источник света, а не поверхность, и
## рельеф им ни к чему. Всё остальное в здании давно одето (ADR-0011).
static func fill(size: Vector2, offset: Vector2, color: Color) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = color
	panel.size = size
	panel.position = offset
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


## Ассет, растянутый на прямоугольник без повтора: надстройка на крыше, выход.
##
## Отличается от [method make] ровно повтором: у таких ассетов рисунок цельный,
## и замостить его значило бы порезать картинку на четыре четверти.
static func stretched(
	size: Vector2, offset: Vector2, tile: CanvasTexture, tint := Color.WHITE
) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tile
	rect.modulate = tint
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = size
	rect.position = offset
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
