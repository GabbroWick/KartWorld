// Flat vertex-coloured surface with a self-lit "ambient" term.
//
// The Compatibility renderer doubles the base pass whenever ambient light or
// a second light coexists with a shadowed sun (godot#90259), so scenes run
// with no ambient at all. To keep faces turned away from the sun readable,
// every material emits a fraction of its own albedo instead — this shader is
// the vertex-colour flavour used by the island terrain.
shader_type spatial;
render_mode cull_back;

uniform float fill : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	// COLOR already arrives linear (Godot converts vertex colours on import).
	vec3 albedo = COLOR.rgb;
	ALBEDO = albedo;
	EMISSION = albedo * fill;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
