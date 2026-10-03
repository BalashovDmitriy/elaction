class_name CityDetails
extends RefCounted

## Details of the night city behind the building (M22, user's remark — "more
## detail for the background"): house tops, blinking lights, neon, street glow,
## fog bands; stars and moon since M24j are on the sky panorama.
##
## The city is blurred by its camera's depth of field, so the details are ones that
## read even blurred: a silhouette, a light, a patch of colour. All by multimeshes and without
## light sources — lights and neon glow by themselves, like windows (ADR-0029).
##
## Builds the nodes; [CityPlan] holds the layout by seed.

## Top: setback — a fraction of house width and height, spire, tank and antenna, m.
const SETBACK := Vector2(0.62, 0.12)
const SPIRE := Vector2(0.6, 14.0)
const TANK := Vector2(2.2, 3.4)
const TANK_LEGS: float = 2.0
const ANTENNA := Vector2(0.35, 9.0)

## Light on a house top: size, colour, blink period, s.
const BEACON: float = 1.6
const BEACON_COLOUR := Color(1.0, 0.12, 0.08)
const BEACON_PERIOD: float = 1.8

## Street glow: height of the band above the ground and its colour at the ground.
const GLOW_HEIGHT: float = 26.0
const GLOW_COLOUR := Color(1.0, 0.55, 0.25, 0.55)

## Fog bands: how many, how tall and how dense.
const FOG_BANKS: int = 7
const FOG_BANK_HEIGHT: float = 22.0
const FOG_BANK_COLOUR := Color(0.55, 0.58, 0.66, 0.16)
const FOG_DRIFT: float = 1.4

## Blinking lights by shader: each has its own phase, and no node per light is needed.
const BEACON_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec4 colour : source_color = vec4(1.0, 0.12, 0.08, 1.0);
uniform float period = 1.8;
varying float phase;
void vertex() {
	// The blink phase is each light's own; it does not reach the fragment shader
	// by itself, only through a varying.
	phase = INSTANCE_CUSTOM.x;
}
void fragment() {
	float on = step(0.62, fract(TIME / period + phase));
	vec2 centre = UV - vec2(0.5);
	float disc = smoothstep(0.5, 0.15, length(centre));
	ALBEDO = colour.rgb * (0.15 + on * 3.0);
	ALPHA = disc * (0.25 + on * 0.75);
}
"""

## The beacon shader, compiled once for all buildings: a new [Shader] per building was
## compiled anew each time (ADR-0060).
static var _beacon_shader: Shader = null


## House tops: setbacks, spires, tanks on legs, antennas.
static func crowns(blocks: Array[CityPlan.Block], ground: float, facade: Material) -> Node3D:
	var host := Node3D.new()
	host.name = "Crowns"
	var boxes: Array[Transform3D] = []
	var tanks: Array[Transform3D] = []
	for block in blocks:
		var top := ground + block.height
		var front := block.z
		match block.crown:
			CityPlan.Crown.SETBACK:
				var size := Vector3(
					block.width * SETBACK.x, block.height * SETBACK.y, block.depth * 0.7
				)
				boxes.append(_box(size, Vector3(block.x, top + size.y * 0.5, front)))
			CityPlan.Crown.SPIRE:
				var base := Vector3(block.width * 0.3, 3.0, block.depth * 0.4)
				boxes.append(_box(base, Vector3(block.x, top + 1.5, front)))
				var spire := Vector3(SPIRE.x, SPIRE.y, SPIRE.x)
				boxes.append(_box(spire, Vector3(block.x, top + 3.0 + SPIRE.y * 0.5, front)))
			CityPlan.Crown.TANK:
				var at := block.x + block.width * 0.22
				tanks.append(
					Transform3D(
						Basis.from_scale(Vector3(TANK.x, TANK.y, TANK.x)),
						Vector3(at, top + TANK_LEGS + TANK.y * 0.5, front)
					)
				)
				for leg: float in [-0.35, 0.35]:
					var post := Vector3(0.25, TANK_LEGS, 0.25)
					boxes.append(
						_box(post, Vector3(at + leg * TANK.x, top + TANK_LEGS * 0.5, front))
					)
			CityPlan.Crown.ANTENNA:
				var mast := Vector3(ANTENNA.x, ANTENNA.y, ANTENNA.x)
				var at := block.x - block.width * 0.25
				boxes.append(_box(mast, Vector3(at, top + ANTENNA.y * 0.5, front)))
	host.add_child(_many("CrownBoxes", BoxMesh.new(), boxes, facade))
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 1.0
	cylinder.radial_segments = 10
	host.add_child(_many("Tanks", cylinder, tanks, facade))
	return host


## Where a house's top is — for the light: above the spire and antenna, above a flat roof.
static func crown_top(block: CityPlan.Block, ground: float) -> Vector3:
	var top := ground + block.height
	match block.crown:
		CityPlan.Crown.SPIRE:
			return Vector3(block.x, top + 3.0 + SPIRE.y, block.z)
		CityPlan.Crown.ANTENNA:
			return Vector3(block.x - block.width * 0.25, top + ANTENNA.y, block.z)
		CityPlan.Crown.SETBACK:
			return Vector3(block.x, top + block.height * SETBACK.y, block.z)
		CityPlan.Crown.TANK:
			return Vector3(block.x + block.width * 0.22, top + TANK_LEGS + TANK.y, block.z)
	return Vector3(block.x, top, block.z)


## Red lights on house tops, each with its own blink phase.
static func beacons(blocks: Array[CityPlan.Block], ground: float) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var phases: Array[float] = []
	for block in blocks:
		if not block.beacon:
			continue
		var top := crown_top(block, ground)
		places.append(
			Transform3D(Basis.from_scale(Vector3.ONE * BEACON), top + Vector3(0, 0.6, 0.0))
		)
		phases.append(fposmod(block.x * 0.137, 1.0))
	var quad := QuadMesh.new()
	if _beacon_shader == null:
		_beacon_shader = Shader.new()
		_beacon_shader.code = BEACON_SHADER
	var look := ShaderMaterial.new()
	look.shader = _beacon_shader
	look.set_shader_parameter("colour", BEACON_COLOUR)
	look.set_shader_parameter("period", BEACON_PERIOD)
	quad.material = look
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_custom_data(index, Color(phases[index], 0.0, 0.0, 0.0))
	var node := MultiMeshInstance3D.new()
	node.name = "Beacons"
	node.multimesh = many
	return node


## Neon signs on facades: bands of their own colour, bypassing the haze — neon cuts through
## fog.
static func signs(blocks: Array[CityPlan.Block], ground: float) -> MultiMeshInstance3D:
	var places: Array[Transform3D] = []
	var colours: Array[Color] = []
	var customs: Array[Color] = []
	for block in blocks:
		if block.sign_colour.a <= 0.0:
			continue
		var front := block.z + block.depth * 0.5 + 0.12
		var size := Vector3(block.sign_size.x, block.sign_size.y, 1.0)
		var at := Vector3(block.x + block.sign_x, ground + block.sign_y, front)
		places.append(Transform3D(Basis.from_scale(size), at))
		var fade := CityBackdrop.WINDOW_FADE[mini(block.row, CityBackdrop.WINDOW_FADE.size() - 1)]
		colours.append(block.sign_colour * (0.9 * fade))
		customs.append(CityLook.sign_custom(block))
	var quad := QuadMesh.new()
	# Backing, tube and letters by shader (M24a): before that the sign was a flat
	# rectangle of colour.
	quad.material = CityLook.signs()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	many.mesh = quad
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
		many.set_instance_color(index, colours[index])
		many.set_instance_custom_data(index, customs[index])
	var node := MultiMeshInstance3D.new()
	node.name = "Signs"
	node.multimesh = many
	return node


## Street glow: a warm band at the ground behind the first row, fading upward. The city
## at night is lit from below, and without the glow the houses stood in darkness, as on a wasteland.
static func street_glow(ground: float, from_x: float, to_x: float) -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(GLOW_COLOUR, 0.0))
	gradient.set_color(1, GLOW_COLOUR)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	look.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(to_x - from_x + 600.0, GLOW_HEIGHT)
	quad.material = look
	var glow := MeshInstance3D.new()
	glow.name = "StreetGlow"
	glow.mesh = quad
	glow.position = Vector3((from_x + to_x) * 0.5, ground + GLOW_HEIGHT * 0.5, -58.0)
	return glow


## Fog bands between rows of houses; they drift sideways in [method drift].
static func fog_banks(building_seed: int, from_x: float, to_x: float, ground: float) -> Node3D:
	var host := Node3D.new()
	host.name = "FogBanks"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([building_seed, "fog"])
	var gradient := Gradient.new()
	gradient.set_color(0, Color(FOG_BANK_COLOUR, 0.0))
	gradient.add_point(0.5, FOG_BANK_COLOUR)
	gradient.set_color(1, Color(FOG_BANK_COLOUR, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	for index in FOG_BANKS:
		var look := StandardMaterial3D.new()
		look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		look.albedo_texture = texture
		var quad := QuadMesh.new()
		quad.size = Vector2(
			rng.randf_range(160.0, 320.0), FOG_BANK_HEIGHT * rng.randf_range(0.7, 1.4)
		)
		quad.material = look
		var bank := MeshInstance3D.new()
		bank.mesh = quad
		var row := CityPlan.ROWS[index % CityPlan.ROWS.size()]
		bank.position = Vector3(
			rng.randf_range(from_x - 100.0, to_x + 100.0),
			ground + rng.randf_range(8.0, row.y),
			-row.x + 6.0
		)
		bank.set_meta(
			&"drift", rng.randf_range(0.5, 1.0) * FOG_DRIFT * (1.0 if index % 2 == 0 else -1.0)
		)
		host.add_child(bank)
	return host


## Shifts the fog bands by [param delta] seconds: slowly, in different directions.
static func drift(banks: Node3D, delta: float, from_x: float, to_x: float) -> void:
	for child in banks.get_children():
		var bank := child as Node3D
		bank.position.x += float(bank.get_meta(&"drift", 0.0)) * delta
		# Gone past the edge — comes back from the other: the fog never ends.
		if bank.position.x > to_x + 300.0:
			bank.position.x = from_x - 300.0
		elif bank.position.x < from_x - 300.0:
			bank.position.x = to_x + 300.0


static func _box(size: Vector3, centre: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), centre)


static func _many(
	title: String, mesh: Mesh, places: Array[Transform3D], look: Material
) -> MultiMeshInstance3D:
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = mesh
	many.instance_count = places.size()
	for index in places.size():
		many.set_instance_transform(index, places[index])
	var node := MultiMeshInstance3D.new()
	node.name = title
	node.multimesh = many
	node.material_override = look
	return node
