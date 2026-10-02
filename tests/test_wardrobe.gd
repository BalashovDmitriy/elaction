extends GutTest

## Агенты одеты по типу здания (ADR-0055, решение 7): федора в отеле, деловой
## костюм без шляпы в офисе, кожанка и кепка в жилом доме. Механика одна —
## меняется только модель тела, и каждая обязана собраться так же, как
## прежняя: скелет, клипы, шляпа отдельным мешем там, где она есть.

const ENEMY_SCENE := preload("res://src/actors/enemy/enemy.tscn")


func test_every_kind_of_building_has_its_agent() -> void:
	assert_eq(
		AgentWardrobe.MODELS.size(), BuildingIdentity.Kind.size(), "у каждого типа свой агент"
	)
	var paths := {}
	for model: PackedScene in AgentWardrobe.MODELS:
		paths[model.resource_path] = true
	assert_eq(paths.size(), AgentWardrobe.MODELS.size(), "модели разные")


## Шляпа — своим мешем `hat`: на добивании она слетает (ADR-0050). У офисного
## агента её нет, и добивание обходится без неё.
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
		assert_eq(hat != null, hatted[kind], "тип %d: шляпа" % kind)
		assert_not_null(model.find_child("*", true, false), "тип %d: модель не пустая" % kind)
		assert_eq(
			model.find_children("*", "Skeleton3D", true, false).size(), 1, "тип %d: скелет" % kind
		)


## Агент, одетый по типу, собирается целиком: тело из своей модели, клипы на
## месте — стойка и ходьба играют.
func test_a_dressed_agent_builds_its_body() -> void:
	for kind: BuildingIdentity.Kind in BuildingIdentity.Kind.values():
		var agent := ENEMY_SCENE.instantiate() as Enemy
		AgentWardrobe.dress(agent, BuildingIdentity.typed(kind))
		add_child_autofree(agent)
		await wait_physics_frames(2)
		var body := agent.get_node("Body") as FigureRig
		assert_eq(body.model, AgentWardrobe.MODELS[kind], "тип %d: модель своего здания" % kind)
		assert_not_null(body.skeleton(), "тип %d: скелет собран" % kind)
