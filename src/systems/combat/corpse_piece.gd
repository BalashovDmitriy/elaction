class_name CorpsePiece
extends Node3D

## A piece of a body torn off by a cab wall (ADR-0043, decisions 11 and 12).
##
## A copy of the figure in the same pose bone for bone, in which only the parts of
## this piece are physical and the rest of the body is hidden. The parts take the places
## they had in the body, with its velocities, and from then on it is an ordinary fallen
## body ([Corpse]): it rides on the cab floor, falls into the shaft, lands on corpses,
## gets under the cab bottom. It stays until the end of the building, like corpses
## (ADR-0037, decision 6).

var corpse: Corpse = null


## Tears the parts [param names] off the body [param from] with the figure
## [param figure] and puts them into [param host] as a separate piece in the same place.
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
