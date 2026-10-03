class_name DoorLife
extends RefCounted

## Life behind an apartment door (ADR-0055, decision 8): now and then a TV, a dog or
## neighbours arguing are heard muffled from behind a closed door.
##
## Sound only, no mechanic: agents do not hide behind these doors, and the sound does
## not foretell an agent's exit — that has its own leaf telegraph (ADR-0020). So only a
## closed door without a document on a floor in the frame sounds, rarely and quietly.
## No nodes: the door asks every frame what has sounded.

## What is heard from behind the door.
const SOUNDS: PackedStringArray = [Sounds.DOOR_TV, Sounds.DOOR_DOG, Sounds.DOOR_ARGUE]
## Pause between sounds of one door, s: there are up to a dozen doors in the frame, and
## all together they produce a sound every ten or so seconds.
const PAUSE := Vector2(60.0, 150.0)
## The first pause is shorter: entering a floor, life is heard sooner than in a minute.
const FIRST_PAUSE := Vector2(4.0, 90.0)

var _rng := RandomNumberGenerator.new()
var _wait: float = 0.0


## Door life with draw [param seed]: one door sounds the same from time to time.
static func of(seed: int) -> DoorLife:
	var life := DoorLife.new()
	life._rng.seed = seed
	life._wait = life._rng.randf_range(FIRST_PAUSE.x, FIRST_PAUSE.y)
	return life


## [param delta] seconds have passed; [param audible] — the door is closed, without a
## document and on a floor in the frame. Returns the sound's name if it sounded now,
## otherwise an empty string. While the door cannot be heard, the clock stands: sound
## does not accumulate.
func advance(delta: float, audible: bool) -> String:
	if not audible:
		return ""
	_wait -= delta
	if _wait > 0.0:
		return ""
	_wait = _rng.randf_range(PAUSE.x, PAUSE.y)
	return SOUNDS[_rng.randi_range(0, SOUNDS.size() - 1)]
