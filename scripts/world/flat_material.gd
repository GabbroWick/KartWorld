class_name FlatMaterial
extends RefCounted
## One place that decides how placeholder art is shaded.
##
## Flat cartoon look: no specular, full roughness. With this, a surface lit by
## sun (0.9) + ambient (0.25) renders exactly the colour written in the scene,
## on every renderer. Specular highlights from the default StandardMaterial3D
## (specular 0.5) added a uniform ~20% brightness that washed the palette out.


static func flat(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic_specular = 0.0
	material.metallic = 0.0
	return material


static func flat_vertex_colored() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.metallic = 0.0
	return material
