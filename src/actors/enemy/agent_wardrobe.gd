class_name AgentWardrobe
extends RefCounted

## Во что одет агент по типу здания (ADR-0055, решение 7): федора в отеле,
## деловой костюм без шляпы в офисе, кожанка и кепка в жилом доме.
##
## Механика у всех одна — меняется модель тела. Модели — профили сборки
## `tools/build_actors.py`, по одной на тип.

## Модели агента по типу здания ([enum BuildingIdentity.Kind]), в его порядке.
const MODELS: Array[PackedScene] = [
	preload("res://assets/models/agent.glb"),
	preload("res://assets/models/agent_office.glb"),
	preload("res://assets/models/agent_residential.glb"),
]


## Одевает [param agent] по зданию [param building]; без здания — как в отеле,
## моделью сцены. Зовётся до [method Node.add_child]: тело собирается из
## модели, входя в дерево.
static func dress(agent: Enemy, building: BuildingIdentity) -> void:
	if building == null:
		return
	var body := agent.get_node("Body") as FigureRig
	body.model = MODELS[building.kind]
