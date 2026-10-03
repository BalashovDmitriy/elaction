class_name Gun
extends RefCounted

## The three-bullet rule.
##
## In the original Otto keeps no more than three shots on screen at once, and this is not
## a technical limitation but the basis of tactics: fire them all and you stand unarmed
## until the bullets fly off (ADR-0006, point 2).
##
## The class only counts: the bullets themselves live in the scene and report their end.

const MAX_LIVE_BULLETS: int = 3

var live: int = 0


func can_fire() -> bool:
	return live < MAX_LIVE_BULLETS


## A shot was fired.
func fired() -> void:
	live += 1


## A bullet ended: it hit, went out of range or was destroyed together with the scene.
func bullet_spent() -> void:
	live = maxi(live - 1, 0)
