class_name HallLook
extends RefCounted

## Materials and furniture of special-floor halls ([FloorHall], ADR-0057, decision 5):
## chain-link mesh, pool water, server indicators, meeting room glass, boiler room steam
## and Kenney Furniture Kit furniture repainted for the building kind. All static — one
## instance per building.

## Pack furniture colour by Kenney Furniture Kit material name — by building kind: the
## hotel has walnut, burgundy velvet and brass, the office light ash, grey-blue fabric
## and steel, the residential building oak, mustard fabric and painted metal.
const HOTEL_TONES := {
	"wood": Color(0.3, 0.17, 0.1),
	"woodDark": Color(0.18, 0.1, 0.06),
	"carpet": Color(0.42, 0.07, 0.1),
	"metal": Color(0.74, 0.56, 0.28),
}
const OFFICE_TONES := {
	"wood": Color(0.6, 0.53, 0.43),
	"woodDark": Color(0.32, 0.29, 0.26),
	"carpet": Color(0.24, 0.29, 0.37),
	"metal": Color(0.62, 0.64, 0.67),
}
const RESIDENTIAL_TONES := {
	"wood": Color(0.44, 0.32, 0.19),
	"woodDark": Color(0.27, 0.19, 0.12),
	"carpet": Color(0.5, 0.37, 0.14),
	"metal": Color(0.5, 0.5, 0.46),
}
## Shared by all kinds: appliances, steel, linen, lampshade.
const COMMON_TONES := {
	"metalLight": Color(0.82, 0.83, 0.8),
	"metalMedium": Color(0.4, 0.42, 0.44),
	"metalDark": Color(0.22, 0.23, 0.25),
	"carpetWhite": Color(0.9, 0.88, 0.83),
	"_defaultMat": Color(0.78, 0.78, 0.76),
}
const LAMP_SHADE := Color(1.0, 0.86, 0.6)
## Server indicators each blink at their own beat: the beat comes from the world position.
const LED_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec4 first : source_color;
uniform vec4 second : source_color;
void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float cell = floor(world.x * 14.0) + floor(world.y * 14.0) * 7.0 + floor(world.z * 4.0) * 13.0;
	float rate = 0.6 + fract(sin(cell * 12.9898) * 43758.5453) * 3.0;
	float blink = step(0.45, fract(TIME * rate + fract(sin(cell) * 917.0)));
	vec3 colour = mix(first.rgb, second.rgb, step(0.75, fract(sin(cell * 3.3) * 777.0)));
	ALBEDO = colour * (0.25 + 0.75 * blink);
}
"""
## Pool water: ripple glints and light from the bottom, by world position.
const WATER_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color;
uniform vec4 shallow : source_color;
uniform float glow = 0.6;
void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple = sin(world.x * 3.1 + TIME * 1.7) * 0.5 + sin(world.z * 4.3 - TIME * 1.3) * 0.5
		+ sin((world.x + world.z) * 7.0 + TIME * 2.3) * 0.25;
	vec3 colour = mix(deep.rgb, shallow.rgb, 0.5 + 0.25 * ripple);
	ALBEDO = colour;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
	EMISSION = shallow.rgb * glow * (0.55 + 0.3 * ripple);
}
"""
const CHAIN_LINK := Color(0.55, 0.57, 0.58)
const LED_GREEN := Color(0.25, 1.0, 0.4)
const LED_AMBER := Color(1.0, 0.6, 0.15)
const WATER_DEEP := Color(0.03, 0.22, 0.32)
const WATER_SHALLOW := Color(0.25, 0.65, 0.75)

static var _chain_link: StandardMaterial3D = null
static var _led: ShaderMaterial = null
static var _water: ShaderMaterial = null
static var _glass_look: StandardMaterial3D = null
## Pack furniture meshes repainted for the kind: the key is "name:kind".
static var _templates: Dictionary = {}


## Chain-link mesh: wire in a diamond pattern, the hall is visible through it. The
## pattern is in world coordinates — the cell step is the same on any span.
static func chain_link() -> StandardMaterial3D:
	if _chain_link != null:
		return _chain_link
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for step: int in size:
		for wire: int in [step, size - 1 - step]:
			image.set_pixel(step, wire, Color(1.0, 1.0, 1.0, 1.0))
			image.set_pixel(mini(step + 1, size - 1), wire, Color(1.0, 1.0, 1.0, 1.0))
	_chain_link = StandardMaterial3D.new()
	_chain_link.albedo_texture = ImageTexture.create_from_image(image)
	_chain_link.albedo_color = CHAIN_LINK
	_chain_link.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_chain_link.alpha_scissor_threshold = 0.5
	_chain_link.metallic = 0.5
	_chain_link.roughness = 0.5
	_chain_link.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chain_link.uv1_triplanar = true
	_chain_link.uv1_world_triplanar = true
	_chain_link.uv1_scale = Vector3(6.0, 6.0, 6.0)
	_chain_link.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _chain_link


## Resets materials and meshes: for tests, like [method GreyboxLook.forget].
static func forget() -> void:
	_chain_link = null
	_led = null
	_water = null
	_glass_look = null
	_templates.clear()


## Meshes of a pack item with the base's middle at zero, repainted for the building kind.
static func template(prop_name: String, kind: BuildingIdentity.Kind) -> Array:
	var key := "%s:%d" % [prop_name, kind]
	if _templates.has(key):
		return _templates[key]
	var made := PropCatalog.make(prop_name, true)
	var parts: Array = []
	if made != null:
		var box := PropCatalog.bounds_of(made)
		var centre := Transform3D(
			Basis.IDENTITY, -Vector3(box.get_center().x, box.position.y, box.get_center().z)
		)
		var stack: Array = [[made, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var pair: Array = stack.pop_back()
			var current := pair[0] as Node3D
			var placed := pair[1] as Transform3D
			var visual := current as MeshInstance3D
			if visual != null and visual.mesh != null:
				parts.append([_recolour(visual.mesh, kind), centre * placed])
			for child: Node in current.get_children():
				var node_3d := child as Node3D
				if node_3d != null:
					stack.append([node_3d, placed * node_3d.transform])
		made.free()
	_templates[key] = parts
	return parts


## A copy of the mesh with Kenney materials replaced by the building kind's colours.
static func _recolour(source: Mesh, kind: BuildingIdentity.Kind) -> Mesh:
	var tones: Dictionary = HOTEL_TONES
	match kind:
		BuildingIdentity.Kind.OFFICE:
			tones = OFFICE_TONES
		BuildingIdentity.Kind.RESIDENTIAL:
			tones = RESIDENTIAL_TONES
	var copy := source.duplicate() as Mesh
	for surface: int in copy.get_surface_count():
		var material := copy.surface_get_material(surface)
		if material == null:
			continue
		var tone := material.resource_name
		if tone == "lamp":
			copy.surface_set_material(surface, GreyboxLook.light(LAMP_SHADE))
		elif tones.has(tone):
			var colour: Color = tones[tone]
			var metal := tone.begins_with("metal")
			copy.surface_set_material(
				surface, GreyboxLook.metal(colour) if metal else GreyboxLook.surface(colour)
			)
		elif COMMON_TONES.has(tone):
			copy.surface_set_material(surface, GreyboxLook.metal(COMMON_TONES[tone] as Color))
	return copy


## Glass of meeting rooms and turnstiles — the same as the office wall's
## ([BuildingShell]): one material per building.
static func glass() -> StandardMaterial3D:
	if _glass_look == null:
		_glass_look = StandardMaterial3D.new()
		_glass_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_look.albedo_color = BuildingShell.GLASS
		_glass_look.roughness = 0.04
		_glass_look.metallic = 0.1
		_glass_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_look


## Server indicators: each blinks at its own beat ([constant LED_SHADER]).
static func led() -> ShaderMaterial:
	if _led == null:
		var shader := Shader.new()
		shader.code = LED_SHADER
		_led = ShaderMaterial.new()
		_led.shader = shader
		_led.set_shader_parameter("first", LED_GREEN)
		_led.set_shader_parameter("second", LED_AMBER)
	return _led


## Rippling pool water ([constant WATER_SHADER]).
static func water() -> ShaderMaterial:
	if _water == null:
		var shader := Shader.new()
		shader.code = WATER_SHADER
		_water = ShaderMaterial.new()
		_water.shader = shader
		_water.set_shader_parameter("deep", WATER_DEEP)
		_water.set_shader_parameter("shallow", WATER_SHALLOW)
	return _water


## Steam over the boiler: sparse puffs up and to the sides, without shadows.
static func steam_plume(at: Vector3) -> GPUParticles3D:
	var steam := GPUParticles3D.new()
	steam.name = "Steam"
	steam.position = at
	steam.amount = 12
	steam.lifetime = 3.0
	steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.35
	process.gravity = Vector3(0.0, 0.05, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.2, Color(1.0, 1.0, 1.0, 0.35))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	steam.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(0.5, 0.5)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(0.85, 0.85, 0.85)
	puff.material = look
	steam.draw_pass_1 = puff
	return steam
