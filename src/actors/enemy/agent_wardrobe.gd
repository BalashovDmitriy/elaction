class_name AgentWardrobe
extends RefCounted

## What an agent wears by building kind (ADR-0055, decision 7): a fedora in the hotel, a business
## suit without a hat in the office, a leather jacket and cap in the residential building.
##
## The mechanics are the same for all — the body model changes. The models are build profiles of
## `tools/build_actors.py`, one per kind.

## Agent models by building kind ([enum BuildingIdentity.Kind]), in its order.
const MODELS: Array[PackedScene] = [
	preload("res://assets/models/agent.glb"),
	preload("res://assets/models/agent_office.glb"),
	preload("res://assets/models/agent_residential.glb"),
]


## Dresses [param agent] by building [param building]; without a building — as in the hotel,
## with the scene model. Called before [method Node.add_child]: the body is assembled from the
## model on entering the tree.
static func dress(agent: Enemy, building: BuildingIdentity) -> void:
	if building == null:
		return
	var body := agent.get_node("Body") as FigureRig
	body.model = MODELS[building.kind]
