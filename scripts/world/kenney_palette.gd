class_name KenneyPalette
extends RefCounted
## Maps Kenney Nature Kit material names onto KartWorld's palette.
##
## Kenney's kit ships teal leaves and pink-tan bark (its own house style). We
## keep the geometry and swap the colours so props match the island's grass
## and the rest of the placeholder art. Materials are shared between every
## instance of a model, so the recoloured copies are cached per name and
## applied as per-surface overrides — the imported resources are never edited.

const COLORS := {
	"leafsGreen": Color(0.30, 0.64, 0.30),
	"leafsDark": Color(0.18, 0.50, 0.28),
	"leafsFall": Color(0.85, 0.50, 0.20),
	"woodBark": Color(0.45, 0.30, 0.18),
	"woodBarkDark": Color(0.36, 0.24, 0.15),
	"wood": Color(0.62, 0.42, 0.24),
	"grass": Color(0.42, 0.66, 0.34),
	"dirt": Color(0.55, 0.40, 0.25),
	"stone": Color(0.64, 0.64, 0.68),
	"stoneDark": Color(0.48, 0.48, 0.52),
	"snow": Color(0.95, 0.96, 0.98),
}

static var _cache: Dictionary = {}


## Applies the palette to every mesh under `root`. Materials whose name is not
## in COLORS are left alone.
static func apply(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.mesh.surface_get_material(i) as StandardMaterial3D
			if material == null or not COLORS.has(material.resource_name):
				continue
			mesh_instance.set_surface_override_material(i, _recolored(material))


static func _recolored(material: StandardMaterial3D) -> StandardMaterial3D:
	var key := material.resource_name
	if not _cache.has(key):
		var copy := material.duplicate() as StandardMaterial3D
		copy.albedo_color = COLORS[key]
		copy.metallic_specular = 0.0
		copy.roughness = 1.0
		_cache[key] = copy
	return _cache[key]
