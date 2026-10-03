extends GutTest

## Rain above the roof and in the city (ADR-0037, decision 3): that drops die on the
## roof rather than by a timer, and that there is no rain in front of the floors, on any
## building with rain.
##
## The test cannot see how the rain looks: that is visible in the milestone shots. It
## guards against what made M24a redo the rain, drops under the roof slab and in front of
## it, through the particle setup: where they fall from, what they die on, and whether
## the height map covers the whole band they fall into.

const LEVEL_SCENE := preload("res://src/levels/greybox_level.tscn")

## How many buildings with rain to check.
const RAINY: int = 3


func after_all() -> void:
	GameState.instance().reset()


## The first [param count] seeds on which it rains.
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


## A drop dies when it touches the roof: collision, a splash at the impact point, a
## height map from what is stationary on the roof.
func test_drops_die_on_the_roof_not_on_a_timer() -> void:
	for building_seed in _rainy_seeds(RAINY):
		var level := _level(building_seed)
		var rain := _rain_of(level)
		assert_not_null(rain, "seed %d: no rain above the roof" % building_seed)
		if rain == null:
			continue
		var drops := rain.drops()
		var process := drops.process_material as ParticleProcessMaterial
		assert_eq(
			process.collision_mode,
			ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT,
			"the drop dies on the roof"
		)
		assert_eq(process.sub_emitter_mode, ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION)
		assert_false(drops.sub_emitter.is_empty(), "no splash at the impact point")
		assert_eq(
			rain.catcher().heightfield_mask,
			RoofRain.LAYER,
			"the heightfield is not from the roof alone"
		)
		remove_child(level)


## Everything drops fall onto is covered by the height map: a drop carried sideways does
## not go past its edge and does not fly past the roof down the facade.
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
		# Drift is to the right, spread is both ways.
		var spread := fall * tan(deg_to_rad(process.spread))
		var from := drops.global_position.x - box.x - spread
		var to := drops.global_position.x + box.x + fall * RoofRain.SLANT + spread
		var where := "seed %d" % building_seed
		assert_gte(from, cover.position.x, where + ": a drop on the left misses the heightfield")
		assert_lte(to, cover.end.x, where + ": a drop on the right misses the heightfield")
		assert_gte(drops.global_position.z - box.z, cover.position.z, where)
		assert_lte(drops.global_position.z + box.z, cover.end.z, where)
		assert_lt(cover.position.y, deck, where + ": the heightfield does not reach the deck")
		remove_child(level)


## There is no rain in front of the floors: the building is in section, and drops in
## front of the roof slab would read as rain in the room of the floor below it.
func test_no_rain_in_front_of_the_floors() -> void:
	for building_seed in _rainy_seeds(RAINY):
		var level := _level(building_seed)
		var drops := _rain_of(level).drops()
		var box := (drops.process_material as ParticleProcessMaterial).emission_box_extents
		assert_lt(
			drops.global_position.z + box.z,
			WorldSpace.CORRIDOR_DEPTH * 0.5,
			"seed %d: drops in front of the corridor's front face" % building_seed
		)
		remove_child(level)


## The height map is taken from the roof, not from people: the deck is on the rain
## layer, Otto is not. Otherwise the rain would keep a hole where Otto stood at assembly.
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
	assert_gt(caught, 0, "the roof slab is not on the rain layer")
	for node: Node in level.otto.find_children("*", "GeometryInstance3D", true, false):
		assert_eq(
			(node as GeometryInstance3D).layers & RoofRain.LAYER,
			0,
			"Otto is on the rain layer: %s" % node
		)
	remove_child(level)


## Share of drops follows the quality level; on low there are no rings and no dripping.
func test_the_rain_follows_the_quality_level() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var drops := _rain_of(level).drops()
	Graphics.broadcast(Graphics.Quality.LOW)
	var low := drops.amount
	var ripples := _rain_of(level).get_node("Ripples") as GPUParticles3D
	var low_ripples := ripples.emitting
	Graphics.broadcast(Graphics.Quality.HIGH)
	assert_lt(low, drops.amount, "on low there are not fewer drops")
	assert_false(low_ripples, "on low the puddle ripples remain")
	assert_true(ripples.emitting, "on high there are no ripples")
	remove_child(level)


## In the city the rain is in layers at different depths and in curtains between the
## rows of houses, and only when it rains.
func test_the_city_rains_in_layers_only_when_it_rains() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var city := level.get_node("Scenery/City/CityView") as SubViewport
	var layers := city.find_children("Layer*", "GPUParticles3D", true, false)
	assert_eq(layers.size(), RainLook.CITY_LAYERS.size(), "not all rain layers in the city")
	var curtains := city.find_children("Curtain*", "MeshInstance3D", true, false)
	assert_eq(curtains.size(), RainLook.CURTAINS.size(), "not all curtains")
	remove_child(level)
	var dry := 1
	while Weather.is_raining(Weather.of_seed(dry)):
		dry += 1
	var clear := _level(dry)
	var clear_city := clear.get_node("Scenery/City/CityView") as SubViewport
	assert_eq(clear_city.find_children("Layer*", "GPUParticles3D", true, false).size(), 0)
	assert_null(_rain_of(clear), "rain above the roof in dry weather")
	remove_child(clear)


## Shader render modes: what its [code]render_mode[/code] contains.
func _render_modes(look: ShaderMaterial) -> PackedStringArray:
	for line in look.shader.code.split("\n"):
		if line.begins_with("render_mode"):
			var modes := PackedStringArray()
			for mode in line.trim_prefix("render_mode").trim_suffix(";").split(","):
				modes.append(mode.strip_edges())
			return modes
	return PackedStringArray()


## Drops are seen by light (decision 3, addendum): a shader lit by lamps rather than
## its own color, and without fog: blending with fog brightened the city twofold.
## This holds for drops above the roof, splashes, dripping and city streaks.
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
		assert_false(modes.has("unshaded"), "the drop has its own color, not lamp light")
		assert_true(modes.has("fog_disabled"), "fog lies on the drop")
		assert_true(modes.has("blend_add"), "the drop does not glow over the background")
	for node: Node in city.find_children("Curtain*", "MeshInstance3D", true, false):
		var curtain := ((node as MeshInstance3D).mesh as QuadMesh).material as ShaderMaterial
		assert_true(_render_modes(curtain).has("fog_disabled"), "fog lies on the curtain")
	remove_child(level)


## The haze above the roof is volumetric fog, and it is absent where there is no fog: on
## low. The halo at the lamp above the roof and at the neon is on any level.
func test_mist_and_halos_follow_the_quality_level() -> void:
	var level := _level(_rainy_seeds(1)[0])
	var rain := _rain_of(level)
	var sign_board := level.find_children("VerticalSign", "", true, false)
	assert_eq(sign_board.size(), 1, "no sign")
	for quality: Graphics.Quality in [
		Graphics.Quality.LOW, Graphics.Quality.MEDIUM, Graphics.Quality.HIGH, Graphics.Quality.ULTRA
	]:
		Graphics.broadcast(quality)
		assert_eq(rain.mist().visible, Graphics.volumetric_fog(), "mist at level %d" % quality)
		assert_true(rain.halo().visible, "no lamp halo at level %d" % quality)
	assert_not_null((sign_board[0] as VerticalSign).halo(), "the neon in rain has no halo")
	var box := AABB(rain.mist().global_position - rain.mist().size * 0.5, rain.mist().size)
	var deck := WorldSpace.height_to_scene(level.rules.floor_surface(BuildingRules.ROOF))
	assert_gt(box.position.y, deck - 0.3, "the mist goes into the floors under the roof")
	Graphics.broadcast(Graphics.Quality.HIGH)
	remove_child(level)


## In dry weather there is neither haze nor halos: the air is transparent.
func test_no_mist_or_halos_when_dry() -> void:
	var dry := 1
	while Weather.is_raining(Weather.of_seed(dry)):
		dry += 1
	var level := _level(dry)
	assert_eq(
		level.find_children("Mist", "FogVolume", true, false).size(), 0, "mist in dry weather"
	)
	assert_eq(
		level.find_children("Halo", "MeshInstance3D", true, false).size(), 0, "halo in dry weather"
	)
	remove_child(level)


## The rotor downwash scatters the rain (ADR-0053): while the helicopter hovers low, a
## particle repeller stands under the rotor axis, and the drops obey it; once the
## helicopter has gone up, the downwash dies down.
func test_the_rotor_wash_pushes_the_rain() -> void:
	var wash := Downwash.new()
	add_child_autofree(wash)
	wash.deck = 10.0
	wash.follow(3.0, 10.0 + 4.0, true)
	var gust := wash.gust()
	assert_lt(gust.strength, 0.0, "hangs low - the flow drives drops away")
	assert_between(
		gust.global_position.y, 10.0, 14.0, "the sphere is between the deck and the rotor"
	)
	wash.follow(3.0, 10.0 + Downwash.DUST_REACH + 1.0, true)
	assert_eq(gust.strength, 0.0, "high - no flow")
	wash.follow(3.0, 10.0 + 4.0, false)
	assert_eq(gust.strength, 0.0, "not hovering - no flow")
	var drops := RainLook.streaks(
		10, 1.0, Vector3.ONE, Vector2(8.0, 10.0), 0.1, Vector2(0.01, 0.4), null
	)
	add_child_autofree(drops)
	var process := drops.process_material as ParticleProcessMaterial
	assert_true(process.attractor_interaction_enabled, "the drops ignore the flow")
