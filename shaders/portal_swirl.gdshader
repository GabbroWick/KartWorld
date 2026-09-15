// Portal surface: a slowly turning vortex of two tints with a bright
// rim, self-lit so it glows without a light (lighting recipe: one sun).
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix;

uniform vec3 color_a : source_color = vec3(0.45, 0.3, 1.0);
uniform vec3 color_b : source_color = vec3(0.2, 0.9, 1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.95, 0.8);
uniform float speed = 0.8;
uniform float arms = 3.0;
uniform float alpha : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// A CylinderMesh cap: UV.x is the angle, UV.y radial for the side
	// faces; use the object-space position projected on the cap instead.
	vec2 p = UV * 2.0 - 1.0;
	// Top/bottom caps of the cylinder map UVs across the disc.
	float r = length(p);
	float a = atan(p.y, p.x);
	float swirl = sin(a * arms + r * 6.0 - TIME * speed * 3.0) * 0.5 + 0.5;
	float pulse = 0.5 + 0.5 * sin(TIME * speed * 2.0);
	vec3 col = mix(color_a, color_b, swirl * (0.6 + 0.4 * pulse));
	float rim = smoothstep(0.75, 1.0, r);
	col = mix(col, rim_color, rim * 0.8);
	ALBEDO = col;
	ALPHA = clamp(alpha + rim * 0.15, 0.0, 1.0);
}
