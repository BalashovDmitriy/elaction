class_name CityPlan
extends RefCounted

## City blocks behind the building: where the houses stand and how tall they are
## (ADR-0029, decision 1). Which windows are lit is decided by the building shader
## ([CityLook]), not here.
##
## Numbers only, no nodes: [CityBackdrop] builds from them, and tests check that
## the city repeats by seed and covers the whole frame width. Coordinates are metres
## of the city scene: x along the building, y up from the ground, z into the depth, away
## from the camera.

## How a house ends at the top (M22, user remark — "more detail for the
## background"): flat roof, setback, spire, tank, antenna. The skyline silhouette
## reads as a city even when blurred, not as a row of boxes.
enum Crown { FLAT, SETBACK, SPIRE, TANK, ANTENNA }

## What kind of house (M24a): office, residential, glass tower, brick. This decides
## the facade styles and wall tone ([CityLook]).
enum Kind { OFFICE, HOMES, GLASS, BRICK }


## A house: a box on the ground and a grid of windows on the facade facing the camera.
class Block:
	extends RefCounted
	## Row in depth: 0 — the nearest.
	var row: int = 0
	var x: float = 0.0
	var width: float = 0.0
	var height: float = 0.0
	## Middle of the house in depth.
	var z: float = 0.0
	var depth: float = 0.0
	## Top of the house and whether a red light blinks on it.
	var crown: Crown = Crown.FLAT
	var beacon: bool = false
	## Neon sign on the facade: colour (transparent — no sign), width and
	## height, at what height its middle is.
	var sign_colour := Color(0.0, 0.0, 0.0, 0.0)
	var sign_size := Vector2.ZERO
	var sign_y: float = 0.0
	## Sign offset from the middle of the facade along x: a vertical one hangs at the corner.
	var sign_x: float = 0.0
	## What kind of house and what window mullions: 0 — none, 1 — a mullion, 2 — a cross.
	var kind: Kind = Kind.OFFICE
	var mullions: int = 0


## Rows in depth: how far a row is behind the play plane, m, and how tall the houses
## there are. The nearest row is sixty metres away: closer, the windows came out the size of
## a door, and the city read as a backdrop right behind the wall (first M19 shots).
## The near ones are lower than our tower — the sky and the far rows are seen above its
## roof — the far ones taller: a big city's skyline grows towards the centre.
const ROWS: Array[Vector3] = [
	# depth, height from, height to
	Vector3(60.0, 30.0, 85.0),
	Vector3(100.0, 45.0, 120.0),
	Vector3(150.0, 60.0, 160.0),
	Vector3(220.0, 80.0, 200.0),
]

## House width, m: from a narrow tower to a block.
const WIDTH := Vector2(10.0, 30.0)

## Gap between houses of a row, m.
const GAP := Vector2(1.0, 6.0)

## House depth, m.
const DEPTH: float = 12.0

## Window pitch on the facade, m: column and storey. The storey is as in our building — the
## city has the same scale.
const WINDOW_STEP := Vector2(2.4, Proportions.FLOOR)

## How many windows are lit at night.
const LIT_SHARE: float = 0.26

## With what chance a whole storey of a house is lit.
const LIT_FLOOR_CHANCE: float = 0.35

## Shares of house tops: flat ones the most, spires the fewest.
const CROWN_WEIGHTS: Array[float] = [0.4, 0.22, 0.1, 0.16, 0.12]

## With what chance a light blinks on a spire and an antenna, and on a tall flat house.
const BEACON_CHANCE: float = 0.8

## With what chance a house has a neon sign and what its colours are: not the colours
## of the game's indicator lights (ADR-0023, decision 6).
const SIGN_CHANCE: float = 0.4
const SIGN_COLOURS: Array[Color] = [
	Color(1.0, 0.25, 0.6),
	Color(0.3, 0.85, 1.0),
	Color(0.62, 0.35, 1.0),
	Color(0.75, 0.82, 1.0),
]

## Shares of house kinds ([enum Kind]) and the chance that a sign is vertical.
const KIND_WEIGHTS: Array[float] = [0.35, 0.3, 0.15, 0.2]
const VERTICAL_SIGN_CHANCE: float = 0.4

## Mixed with the seed so the city does not repeat the building layout draw.
const SALT: int = 0x0C17_7A11


## Blocks along the building from [param from_x] to [param to_x] by seed. A row
## goes past the edges with a margin: in perspective the far row is seen wider than the near.
static func generate(building_seed: int, from_x: float, to_x: float) -> Array[Block]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT])
	var blocks: Array[Block] = []
	for row in ROWS.size():
		var spec := ROWS[row]
		var reach := spec.x * 1.2
		var x := from_x - reach + rng.randf_range(0.0, WIDTH.x)
		while x < to_x + reach:
			var block := Block.new()
			block.row = row
			block.width = rng.randf_range(WIDTH.x, WIDTH.y)
			block.x = x + block.width * 0.5
			block.height = rng.randf_range(spec.y, spec.z)
			block.depth = DEPTH
			block.z = -spec.x - DEPTH * 0.5
			_skip_lit_windows(rng, block)
			blocks.append(block)
			x += block.width + rng.randf_range(GAP.x, GAP.y)
	_dress_crowns(blocks, building_seed)
	_dress_facades(blocks, building_seed)
	return blocks


## House kind, mullions and vertical signs — by their own draw, after the tops:
## the layout and tops by seed are the same as before M24a.
static func _dress_facades(blocks: Array[Block], building_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "facades"])
	for block in blocks:
		block.kind = _weighted(rng, KIND_WEIGHTS) as Kind
		block.mullions = rng.randi_range(0, 2)
		if block.kind == Kind.GLASS:
			block.mullions = 1
		# Some signs are vertical, at the corner of the house, as over a hotel entrance.
		if block.sign_colour.a > 0.0 and rng.randf() < VERTICAL_SIGN_CHANCE:
			var tall := minf(rng.randf_range(7.0, 14.0), block.height * 0.5)
			var wide := minf(rng.randf_range(1.8, 3.0), block.width * 0.3)
			block.sign_size = Vector2(wide, tall)
			block.sign_y = clampf(block.sign_y, tall * 0.5 + 3.0, block.height - tall * 0.5)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			block.sign_x = side * (block.width * 0.5 - wide * 0.5 - 0.6)


## Tops and signs — by their own draw, after the layout: the block layout by
## seed is the same as before M22, and its tests do not shift.
static func _dress_crowns(blocks: Array[Block], building_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, SALT, "crowns"])
	for block in blocks:
		block.crown = _weighted(rng, CROWN_WEIGHTS) as Crown
		var tall := block.height > ROWS[block.row].z * 0.8
		var pointed := block.crown == Crown.SPIRE or block.crown == Crown.ANTENNA
		block.beacon = (pointed or tall) and rng.randf() < BEACON_CHANCE
		if rng.randf() < SIGN_CHANCE:
			block.sign_colour = SIGN_COLOURS[rng.randi_range(0, SIGN_COLOURS.size() - 1)]
			block.sign_size = Vector2(
				block.width * rng.randf_range(0.35, 0.7), rng.randf_range(2.0, 4.0)
			)
			# Anywhere in height, not just under the roof: the city camera sees
			# a band of houses at its own height, and a sign right under the roof of a near
			# house is not visible from the floors at all.
			block.sign_y = block.height * rng.randf_range(0.12, 0.9)
		# The lit storey's draw is gone with the window quads (ADR-0060): the facade shader
		# lights windows itself. The draw is kept so the crowns and signs of the houses
		# after it stay the same by seed.
		if rng.randf() < LIT_FLOOR_CHANCE:
			rng.randi_range(0, window_grid(block).y - 1)


static func _weighted(rng: RandomNumberGenerator, weights: Array[float]) -> int:
	return pick_weighted(weights, rng.randf())


## Index by weights [param weights] and draw [param roll] from 0 to 1.
static func pick_weighted(weights: Array, roll: float) -> int:
	var total := 0.0
	for weight: float in weights:
		total += weight
	var left := roll * total
	for index in weights.size():
		left -= float(weights[index])
		if left <= 0.0:
			return index
	return weights.size() - 1


## How many columns and storeys of windows a house facade has.
static func window_grid(block: Block) -> Vector2i:
	return Vector2i(
		maxi(int(block.width / WINDOW_STEP.x) - 1, 1),
		maxi(int(block.height / WINDOW_STEP.y) - 1, 1)
	)


## The lit windows' draw, one per window: no longer used (the facade shader lights windows,
## ADR-0060), but drawn so the houses after it stay the same by seed.
static func _skip_lit_windows(rng: RandomNumberGenerator, block: Block) -> void:
	var grid := window_grid(block)
	for _window in grid.x * grid.y:
		rng.randf()
