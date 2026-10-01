class_name Outdoors
extends RefCounted

## Что стоит снаружи здания и ловит солнце (ADR-0051).
##
## Солнце — направленный свет, а он светит сквозь всё на любой глубине: здание
## показано в разрезе, и коридоры, на которые он лёг бы, освещаются лампами и
## общим светом здания. Поэтому солнцу отдан свой слой, и в него попадает только
## то, что снаружи: крыша и её техника, вывеска, вертолёт, улица у выезда.
##
## Слой ставится и ночью: солнца тогда нет, и лишний бит ничего не меняет, —
## зато здание не собирается по-разному в разное время суток.

## Слой отрисовки, который видит солнце. Рядом — обстановка ([constant
## PropCatalog.RENDER_LAYER]) и фигуры ([constant FigureRig.RENDER_LAYER]).
const LAYER: int = 1 << 12


## Отдаёт солнцу всё видимое под [param root].
static func mark(root: Node) -> void:
	for node in _visuals(root):
		node.layers |= LAYER


## Отдаёт солнцу всё видимое под [param root], что целиком выше
## [param bottom] — высоты сцены, м: так из строителей здания берётся крыша, а
## этажи под ней, собранные теми же строителями, остаются без солнца.
static func mark_above(root: Node, bottom: float) -> void:
	for node in _visuals(root):
		var box := node.global_transform * node.get_aabb()
		if box.position.y >= bottom:
			node.layers |= LAYER


static func _visuals(root: Node) -> Array[VisualInstance3D]:
	var found: Array[VisualInstance3D] = []
	var own := root as VisualInstance3D
	if own != null:
		found.append(own)
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		# Свет — тоже VisualInstance3D, но слоя отрисовки у него нет. Кабины и
		# актёры ходят по зданию: солнце, пойманное на крыше, ехало бы с ними
		# в коридоры.
		if visual != null and not (visual is Light3D) and not _moves(visual, root):
			found.append(visual)
	return found


static func _moves(node: Node, root: Node) -> bool:
	var up := node.get_parent()
	while up != null and up != root.get_parent():
		if up is AnimatableBody3D or up is CharacterBody3D:
			return true
		up = up.get_parent()
	return false
