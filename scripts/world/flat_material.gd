class_name FlatMaterial
extends RefCounted
## One place that decides how surfaces are shaded.
##
## Flat cartoon look: no specular, full roughness, and a self-lit term
## (`FILL` x albedo as emission) that stands in for ambient light. The
## Compatibility renderer doubles the base pass whenever ambient light or a
## second light coexists with a shadowed sun (godot#90259), so scenes have no
## ambient at all; without this term any face turned away from the sun is
## black. The scenes' sun energy is calibrated so a sunlit face still renders
## exactly the authored colour (guarded by test_lighting).

## Fraction of the albedo a surface emits on its own.
const FILL := 0.28
## Meta flag on materials that already carry the fill term (imported PBR
## materials may have emission enabled with a black colour, so the flag is
## the only reliable marker).
const FILLED := &"kw_fill"

static var _vertex_shader: Shader
static var _fill_cache: Dictionary = {}


static func flat(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 0.0
	material.metallic = 0.0
	material.emission_enabled = true
	material.emission = color * FILL
	material.set_meta(FILLED, true)
	return material


static func flat_vertex_colored() -> Material:
	if _vertex_shader == null:
		_vertex_shader = load("res://shaders/flat_vertex_fill.gdshader")
	var material := ShaderMaterial.new()
	material.shader = _vertex_shader
	material.set_shader_parameter(&"fill", FILL)
	return material


## A copy of `material` with the fill term, cached so shared materials get
## one override each. Textured materials emit their own texture.
static func with_fill(material: StandardMaterial3D) -> StandardMaterial3D:
	if material.has_meta(FILLED):
		return material
	if _fill_cache.has(material):
		return _fill_cache[material]
	var copy := material.duplicate() as StandardMaterial3D
	copy.emission_enabled = true
	if copy.albedo_texture:
		# The default operator ADDs the texture to the colour (= full-strength
		# glow); MULTIPLY makes the colour scale the texture.
		copy.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		copy.emission_texture = copy.albedo_texture
		copy.emission = Color(FILL, FILL, FILL) * copy.albedo_color
	else:
		copy.emission = copy.albedo_color * FILL
	copy.emission_energy_multiplier = 1.0
	copy.metallic_specular = 0.0
	copy.set_meta(FILLED, true)
	_fill_cache[material] = copy
	return copy


## Gives every mesh surface under `root` the fill term (per-surface overrides;
## imported resources stay untouched).
static func apply_fill(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var current := mesh_instance.get_surface_override_material(i)
			var material := (current if current else mesh_instance.mesh.surface_get_material(i)) as StandardMaterial3D
			if material == null:
				continue
			mesh_instance.set_surface_override_material(i, with_fill(material))
