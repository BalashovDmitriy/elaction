class_name CorpsePiece
extends Node3D

## Кусок тела, оторванный стенкой кабины (ADR-0043, решения 11 и 12).
##
## Копия фигуры в той же позе кость в кость, у которой физические только части
## этого куска, а остальное тело спрятано. Части встают туда, где были в теле,
## с его скоростями, и дальше это обычное упавшее тело ([Corpse]): едет на полу
## кабины, падает в шахту, ложится на трупы, попадает под днище. Лежит до конца
## здания, как и трупы (ADR-0037, решение 6).

var corpse: Corpse = null


## Отрывает от тела [param from] с фигурой [param figure] части [param names] и
## кладёт их в [param host] отдельным куском на том же месте.
static func tear_off(
	from: Corpse, figure: FigureRig, host: Node, names: PackedStringArray
) -> CorpsePiece:
	var piece := CorpsePiece.new()
	piece.name = "CorpsePiece"
	var copy := FigureRig.new()
	copy.model = figure.model
	piece.add_child(copy)
	host.add_child(piece)
	piece.global_transform = (figure.get_parent() as Node3D).global_transform
	copy.transform = figure.transform
	copy.copy_pose_of(figure)
	piece.corpse = Corpse.new(piece, copy, names)
	piece.corpse.torn = true
	piece.corpse.ragdoll.hide_all_but(names)
	piece.corpse.fall(Vector3.ZERO)
	piece.corpse.ragdoll.follow(from.ragdoll)
	return piece
