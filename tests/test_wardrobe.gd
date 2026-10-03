extends GutTest

## Agents are dressed by building kind (ADR-0055, decision 7): a fedora in the hotel, a
## business suit without a hat in the office, a leather jacket and a cap in the
## residential building. The mechanic is the same — only the body model changes, and
## each must assemble the same as the previous: skeleton, clips, the hat as a separate
## mesh where there is one.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")


func test_every_kind_of_building_has_its_agent() -> void:
	assert_eq(
		AgentWardrobe.MODELS.size(), BuildingIdentity.Kind.size(), "each kind has its own agent"
	)
	var paths := {}
	for model: PackedScene in AgentWardrobe.MODELS:
		paths[model.resource_path] = true
	assert_eq(paths.size(), AgentWardrobe.MODELS.size(), "models differ")


## The hat is its own `hat` mesh: it flies off on a takedown (ADR-0050). The office agent
## has none, and the takedown does without it.
func test_hats_are_where_the_wardrobe_says() -> void:
	var hatted := {
		BuildingIdentity.Kind.HOTEL: true,
		BuildingIdentity.Kind.OFFICE: false,
		BuildingIdentity.Kind.RESIDENTIAL: true,
	}
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var model := AgentWardrobe.MODELS[kind].instantiate()
		autofree(model)
		var hat := model.find_child("hat", true, false)
		assert_eq(hat != null, hatted[kind], "kind %d: hat" % kind)
		assert_not_null(model.find_child("*", true, false), "kind %d: model is not empty" % kind)
		assert_eq(
			model.find_children("*", "Skeleton3D", true, false).size(),
			1,
			"kind %d: skeleton" % kind
		)


## An agent dressed by kind assembles entirely: the body from its own model, clips in
## place — idle and walk play.
func test_a_dressed_agent_builds_its_body() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var agent := ENEMY_SCENE.instantiate() as Enemy
		AgentWardrobe.dress(agent, BuildingIdentity.typed(kind))
		add_child_autofree(agent)
		await wait_physics_frames(2)
		var body := agent.get_node("Body") as FigureRig
		assert_eq(
			body.model, AgentWardrobe.MODELS[kind], "kind %d: the model of its own building" % kind
		)
		assert_not_null(body.skeleton(), "kind %d: skeleton is built" % kind)
