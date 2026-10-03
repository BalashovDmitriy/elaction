class_name ShaftHums
extends Node3D

## Shaft hum (ADR-0036): each shaft has its own source, and it moves along the shaft
## level with Otto, within its floors — the whole shaft hums, not one point at mid-height.

## How far a shaft's hum is heard, m, and where it stands in depth: behind the cab.
const REACH: float = 9.0
const Z: float = -0.4

var _holders: Array[Node3D] = []
## Height band of each shaft, plane m: top and bottom.
var _spans: Array[Vector2] = []


## Starts the hum of shaft [param shaft] from [param top] to [param bottom], m.
func add(shaft: BuildingPlan.ShaftSpot, top: float, bottom: float) -> void:
	var holder := Node3D.new()
	holder.name = "ShaftHum"
	holder.position = WorldSpace.to_scene(Vector2(shaft.x, top))
	holder.position.z = Z
	add_child(holder)
	Sounds.source(holder, Sounds.SHAFT_HUM, REACH, true)
	_holders.append(holder)
	_spans.append(Vector2(minf(top, bottom), maxf(top, bottom)))


## Places the sources at height [param height], plane m.
func follow(height: float) -> void:
	for index: int in _holders.size():
		var span := _spans[index]
		var holder := _holders[index]
		var at := WorldSpace.to_plane(holder.position)
		holder.position = WorldSpace.to_scene(Vector2(at.x, clampf(height, span.x, span.y)))
		holder.position.z = Z


## Source height of shaft number [param index], plane m. Needed for tests.
func height_of(index: int) -> float:
	return WorldSpace.to_plane(_holders[index].position).y
