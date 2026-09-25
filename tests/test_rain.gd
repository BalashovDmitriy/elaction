extends GutTest

## Дождь над крышей и в городе (ADR-0037, решение 3): что капли гаснут о
## крышу, а не по таймеру, и что перед этажами дождя нет, — на любом здании
## с дождём.
##
## Как дождь выглядит, тест не видит: это видно на кадрах вехи. Он стережёт
## то, из-за чего M24a переделывала дождь, — капли под плитой крыши и перед
## ней, — по устройству частиц: откуда сыплются, обо что гаснут и укрыта ли
## картой высот вся полоса, куда они падают.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## Сколько зданий с дождём проверять.
const RAINY: int = 3


func after_all() -> void:
	GameState.instance().reset()


## Первые [param count] сидов, на которых идёт дождь.
func _rainy_seeds(count: int) -> Array[int]:
	var found: Array[int] = []
	var building_seed := 1
	while found.size() < count:
		if Weather.is_raining(Weather.of_seed(building_seed)):
			found.append(building_seed)
		building_seed += 1
	return found


func _level(building_seed: int) -> GreyboxLevel:
	GameState.instance().start_game()
	var level := LEVEL_SCENE.instantiate() as GreyboxLevel
	level.rules = BuildingRules.new()
	level.building_seed = building_seed
	level.spawn_agents = false
	add_child_autofree(level)
	return level


func _rain_of(level: GreyboxLevel) -> RoofRain:
	return (level.get_node("Scenery") as BuildingScenery).roof_rain()


## Капля гаснет, коснувшись крыши: коллизия, брызги в месте удара, карта высот
## с неподвижного на крыше.
func test_drops_die_on_the_roof_not_on_a_timer() -> void:
	for building_seed in _rainy_seeds(RAINY):
		var level := _level(building_seed)
		var rain := _rain_of(level)
		assert_not_null(rain, "сид %d: дождя над крышей нет" % building_seed)
		if rain == null:
			continue
		var drops := rain.drops()
		var process := drops.process_material as ParticleProcessMaterial
		assert_eq(
			process.collision_mode,
			ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
			"капля гаснет о крышу"
		)
		assert_eq(process.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION)
		assert_false(drops.sub_emitter.is_empty(), "брызг в месте удара нет")
		assert_eq(rain.catcher().heightfield_mask, RoofRain.LAYER, "карта высот не с одной крыши")
		remove_child(level)


## Всё, куда падают капли, укрыто картой высот: капля, сносимая вбок, не
## выходит за её край и не летит мимо крыши вниз по фасаду.
func test_the_heightfield_covers_every_drop_path() -> void:
	for building_seed in _rainy_seeds(RAINY):
		var level := _level(building_seed)
		var rain := _rain_of(level)
		var drops := rain.drops()
		var process := drops.process_material as ParticleProcessMaterial
		var box := process.emission_box_extents
		var catcher := rain.catcher()
		var cover := AABB(catcher.global_position - catcher.size * 0.5, catcher.size)
		var deck := WorldSpace.height_to_scene(level.rules.floor_surface(BuildingRules.ROOF))
		var fall := drops.global_position.y + box.y - deck
		# Снос — вправо, разброс — в обе стороны.
		var spread := fall * tan(deg_to_rad(process.spread))
		var from := drops.global_position.x - box.x - spread
		var to := drops.global_position.x + box.x + fall * RoofRain.SLANT + spread
		var where := "сид %d" % building_seed
		assert_gte(from, cover.position.x, where + ": капля слева мимо карты высот")
		assert_lte(to, cover.end.x, where + ": капля справа мимо карты высот")
		assert_gte(drops.global_position.z - box.z, cover.position.z, where)
		assert_lte(drops.global_position.z + box.z, cover.end.z, where)
		assert_lt(cover.position.y, deck, where + ": карта высот не доходит до настила")
		remove_child(level)


## Перед этажами дождя нет: здание в разрезе, и капли перед плитой крыши
## читались бы дождём в комнате этажа под ней.
func test_no_rain_in_front_of_the_floors() -> void:
	for building_seed in _rainy_seeds(RAINY):
		var level := _level(building_seed)
		var drops := _rain_of(level).drops()
		var box := (drops.process_material as ParticleProcessMaterial).emission_box_extents
		assert_lt(
			drops.global_position.z + box.z,
			WorldSpace.CORRIDOR_DEPTH * 0.5,
			"сид %d: капли перед передней гранью коридора" % building_seed
		)
		remove_child(level)


## Карта высот снимается с крыши, а не с людей: настил на слое дождя, Otto —
## нет. Иначе в дожде осталась бы дыра на месте, где Otto стоял при сборке.
func test_the_roof_catches_rain_and_otto_does_not() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var deck := WorldSpace.height_to_scene(level.rules.floor_surface(BuildingRules.ROOF))
	var caught := 0
	var shell := level.get_node("Shell")
	for node: Node in shell.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var top := (part.global_transform * part.get_aabb()).end.y
		if absf(top - deck) < 0.01 and part.layers & RoofRain.LAYER:
			caught += 1
	assert_gt(caught, 0, "плита крыши не на слое дождя")
	for node: Node in level.otto.find_children("*", "GeometryInstance3D", true, false):
		assert_eq(
			(node as GeometryInstance3D).layers & RoofRain.LAYER, 0, "Otto на слое дождя: %s" % node
		)
	remove_child(level)


## Доля капель — по уровню качества; на низком нет кругов и капели.
func test_the_rain_follows_the_quality_level() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var drops := _rain_of(level).drops()
	Graphics.broadcast(Graphics.Quality.LOW)
	var low := drops.amount
	var ripples := _rain_of(level).get_node("Ripples") as GPUParticles3D
	var low_ripples := ripples.emitting
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_lt(low, drops.amount, "на низком капель не меньше")
	assert_false(low_ripples, "на низком круги на лужах остались")
	assert_true(ripples.emitting, "на высоком кругов нет")
	remove_child(level)


## В городе дождь слоями на разной глубине и завесами между рядами домов — и
## только в дождь.
func test_the_city_rains_in_layers_only_when_it_rains() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var city := level.get_node("Scenery/City/CityView") as SubViewport
	var layers := city.find_children("Layer*", "GPUParticles3D", true, false)
	assert_eq(layers.size(), RainLook.CITY_LAYERS.size(), "не все слои дождя в городе")
	var curtains := city.find_children("Curtain*", "MeshInstance3D", true, false)
	assert_eq(curtains.size(), RainLook.CURTAINS.size(), "не все завесы")
	remove_child(level)
	var dry := 1
	while Weather.is_raining(Weather.of_seed(dry)):
		dry += 1
	var clear := _level(dry)
	var clear_city := clear.get_node("Scenery/City/CityView") as SubViewport
	assert_eq(clear_city.find_children("Layer*", "GPUParticles3D", true, false).size(), 0)
	assert_null(_rain_of(clear), "дождь над крышей в сухую погоду")
	remove_child(clear)


## Режимы отрисовки шейдера: что стоит в его [code]render_mode[/code].
func _render_modes(look: ShaderMaterial) -> PackedStringArray:
	for line in look.shader.code.split("\n"):
		if line.begins_with("render_mode"):
			var modes := PackedStringArray()
			for mode in line.trim_prefix("render_mode").trim_suffix(";").split(","):
				modes.append(mode.strip_edges())
			return modes
	return PackedStringArray()


## Капли видны светом (решение 3, дополнение): шейдер со светом ламп, а не
## своего цвета, и без тумана — сложение с туманом высветляло город вдвое.
## Так у капель над крышей, у брызг, у капели и у струй города.
func test_drops_are_lit_and_fog_free() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var rain := _rain_of(level)
	var looks: Array[ShaderMaterial] = []
	for particles: GPUParticles3D in [
		rain.drops(), rain.get_node("Splashes"), rain.get_node("Drips")
	]:
		looks.append((particles.draw_pass_1 as QuadMesh).material as ShaderMaterial)
	var city := level.get_node("Scenery/City/CityView") as SubViewport
	for node: Node in city.find_children("Layer*", "GPUParticles3D", true, false):
		looks.append(((node as GPUParticles3D).draw_pass_1 as QuadMesh).material as ShaderMaterial)
	for look in looks:
		var modes := _render_modes(look)
		assert_false(modes.has("unshaded"), "капля своего цвета, а не светом ламп")
		assert_true(modes.has("fog_disabled"), "на каплю ложится туман")
		assert_true(modes.has("blend_add"), "капля не светится поверх фона")
	for node: Node in city.find_children("Curtain*", "MeshInstance3D", true, false):
		var curtain := ((node as MeshInstance3D).mesh as QuadMesh).material as ShaderMaterial
		assert_true(_render_modes(curtain).has("fog_disabled"), "на завесу ложится туман")
	remove_child(level)


## Дымка над крышей — объёмный туман, и её нет там, где тумана нет: на низком.
## Ореол у лампы над крышей и у неона — на любом уровне.
func test_mist_and_halos_follow_the_quality_level() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var rain := _rain_of(level)
	var sign_board := level.find_children("VerticalSign", "", true, false)
	assert_eq(sign_board.size(), 1, "вывески нет")
	for quality: Graphics.Quality in [
		Graphics.Quality.LOW, Graphics.Quality.MEDIUM, Graphics.Quality.HIGH, Graphics.Quality.ULTRA
	]:
		Graphics.broadcast(quality)
		assert_eq(rain.mist().visible, Graphics.volumetric_fog(), "дымка на уровне %d" % quality)
		assert_true(rain.halo().visible, "ореола лампы нет на уровне %d" % quality)
	assert_not_null((sign_board[0] as VerticalSign).halo(), "у неона в дожде нет ореола")
	var box := AABB(rain.mist().global_position - rain.mist().size * 0.5, rain.mist().size)
	var deck := WorldSpace.height_to_scene(level.rules.floor_surface(BuildingRules.ROOF))
	assert_gt(box.position.y, deck - 0.3, "дымка уходит в этажи под крышей")
	Graphics.broadcast(Graphics.Quality.HIGH)
	remove_child(level)


## В сухую погоду ни дымки, ни ореолов: воздух прозрачный.
func test_no_mist_or_halos_when_dry() -> void:
	var dry := 1
	while Weather.is_raining(Weather.of_seed(dry)):
		dry += 1
	var level := _level(dry)
	assert_eq(level.find_children("Mist", "FogVolume", true, false).size(), 0, "дымка в сухую")
	assert_eq(level.find_children("Halo", "MeshInstance3D", true, false).size(), 0, "ореол в сухую")
	remove_child(level)
