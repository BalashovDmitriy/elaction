class_name SnowTracks
extends Node3D

## Tracks in the roof snow and a slippery deck (ADR-0054, decisions 2 and 4).
##
## Every physics step checks who stands on the snowy deck: Otto and
## the agents. They slide ([member Otto.icy], [member Enemy.icy] — grip in
## [Footing]) and leave prints — a sole with a heel, pressed into the snow,
## left and right foot in turn. The tracks stay until the end of the building; when
## [constant LIMIT] of them accumulate, new ones take the place of the oldest.
##
## A print is a decal on the roof layer [constant RoofCatch.LAYER], on top of the
## cover: equipment and parapets do not get tracks — nobody walks on them.

## Stride: this many metres between prints of one chain, and how far apart the left
## and right foot are in depth.
const STRIDE: float = 0.55
const GAIT: float = 0.07
## Print: length, width, m; colour of the pressed snow — darker and colder than the
## cover, it is in the shadow of its edges.
const PRINT := Vector2(0.3, 0.14)
const PRESSED := Color(0.36, 0.41, 0.5, 0.9)
## How many prints lie at once.
const LIMIT: int = 240
## How far the feet may be above or below the deck, m, to stand on it.
const ON_DECK: float = 0.2

## The sole texture — one for all prints.
static var _sole: ImageTexture = null

var _deck: float = 0.0
var _span := Vector2.ZERO
## Shaft openings in the deck, by x: above them underfoot is the cab — its floor or roof
## flush with the deck — metal, not snow.
var _shafts: Array[Vector2] = []
var _prints: Array[Decal] = []
var _next: int = 0
## Where each one left the last print and with which foot: by body id. Only walkers on
## the deck are here: whoever leaves it is forgotten.
var _last: Dictionary = {}
var _left_foot: Dictionary = {}
## Otto and the agents, re-read from their groups only when the groups change: reading
## them every physics step allocated two arrays for the whole building (ADR-0060).
var _walkers: Array[Node] = []
var _counts := Vector2i(-1, -1)


## Watches the roof deck at scene height [param deck], from [param from] to
## [param to] along x. [param shafts] — shaft openings in the deck: whoever stands above an
## opening stands on a cab — does not slide and leaves no tracks.
func watch(deck: float, from: float, to: float, shafts: Array[Vector2] = []) -> void:
	name = "Tracks"
	_deck = deck
	_span = Vector2(from, to)
	_shafts = shafts


## How many prints already lie — for a test.
func count() -> int:
	return _prints.size()


## How many walkers the tracks remember the stride of — for a test: only those on the deck.
func remembered() -> int:
	return maxi(_last.size(), _left_foot.size())


func _physics_process(_delta: float) -> void:
	_read_walkers()
	for index: int in _walkers.size():
		var node: Variant = _walkers[index]
		if not is_instance_valid(node) or not (node as Node).is_inside_tree():
			# Left the building between group reads: read them anew on the next step.
			_counts = Vector2i(-1, -1)
			continue
		var body := node as CharacterBody3D
		if body == null:
			continue
		var feet := body.global_position
		var id := body.get_instance_id()
		# Far from the deck and not on it a step ago: nothing to stamp, nothing to thaw.
		# This is the whole building below the roof, so it is checked first and cheaply.
		if absf(feet.y - _deck) >= ON_DECK and not _last.has(id):
			continue
		var dead: bool = body.call(&"is_dead")
		var on_deck := (
			not dead
			and body.is_on_floor()
			and absf(feet.y - _deck) < ON_DECK
			and feet.x >= _span.x
			and feet.x <= _span.y
			and not _over_a_shaft(feet.x)
		)
		body.set(&"icy", on_deck)
		if not on_deck:
			_last.erase(id)
			_left_foot.erase(id)
			continue
		if not _last.has(id):
			_last[id] = feet
			continue
		var from: Vector3 = _last[id]
		if absf(feet.x - from.x) < STRIDE:
			continue
		var left: bool = not bool(_left_foot.get(id, false))
		_left_foot[id] = left
		_last[id] = feet
		_stamp(feet, signf(feet.x - from.x), left)


## Re-reads Otto and the agents when their groups have changed.
func _read_walkers() -> void:
	var tree := get_tree()
	var counts := Vector2i(
		tree.get_node_count_in_group(Footing.OTTO_GROUP), tree.get_node_count_in_group(Enemy.GROUP)
	)
	if counts == _counts:
		return
	_counts = counts
	_walkers = tree.get_nodes_in_group(Footing.OTTO_GROUP)
	_walkers.append_array(tree.get_nodes_in_group(Enemy.GROUP))
	# Whoever left the groups is forgotten with the prints of their stride.
	var present: Dictionary = {}
	for walker: Node in _walkers:
		present[walker.get_instance_id()] = true
	for id: int in _last.keys():
		if not present.has(id):
			_last.erase(id)
			_left_foot.erase(id)


## Whether [param x] is above a shaft opening: underfoot there is a cab, not the deck.
func _over_a_shaft(x: float) -> bool:
	for gap in _shafts:
		if x > gap.x and x < gap.y:
			return true
	return false


func _stamp(at: Vector3, heading: float, left: bool) -> void:
	var print_here: Decal = null
	if _prints.size() < LIMIT:
		print_here = Decal.new()
		print_here.name = "Print"
		print_here.size = Vector3(PRINT.x, 0.3, PRINT.y)
		print_here.texture_albedo = sole()
		print_here.cull_mask = RoofCatch.LAYER
		print_here.upper_fade = 0.05
		print_here.lower_fade = 0.05
		add_child(print_here)
		_prints.append(print_here)
	else:
		print_here = _prints[_next]
		_next = (_next + 1) % LIMIT
	var side := GAIT if left else -GAIT
	print_here.global_position = Vector3(at.x, _deck, at.z + side)
	# Toe along the direction of travel: the texture has the toe towards +X, going left — a flip.
	print_here.rotation = Vector3(0.0, 0.0 if heading >= 0.0 else PI, 0.0)


## A sole with a heel, toe towards +X: pressed snow with a soft edge.
static func sole() -> ImageTexture:
	if _sole != null:
		return _sole
	var size := Vector2i(64, 26)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var u := (float(x) + 0.5) / float(size.x)
			var v := ((float(y) + 0.5) / float(size.y)) * 2.0 - 1.0
			# The sole is an oval from the middle to the toe, the heel an oval at the heel.
			var toe := Vector2((u - 0.66) / 0.33, v / 0.95).length()
			var heel := Vector2((u - 0.17) / 0.15, v / 0.8).length()
			var shape := maxf(1.0 - smoothstep(0.75, 1.0, toe), 1.0 - smoothstep(0.7, 1.0, heel))
			image.set_pixel(x, y, Color(PRESSED, PRESSED.a * shape))
	_sole = ImageTexture.create_from_image(image)
	return _sole
