// Cartoon sea: two blues mixed by drifting waves, a gentle vertex swell,
// and a white foam band that laps at the island's shore.
//
// No depth texture (Compatibility renderer, Web): the foam is drawn where
// the sea meets the analytic island — a ring at `shore_radius` around
// `island_centre` — wobbled over time so it reads as surf. Same lighting
// recipe as everything else: no ambient light, self-lit `fill` fraction.
shader_type spatial;
render_mode cull_back, depth_draw_always;

uniform vec3 deep_color : source_color = vec3(0.12, 0.42, 0.72);
uniform vec3 shallow_color : source_color = vec3(0.3, 0.7, 0.85);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 0.88;
uniform float fill : hint_range(0.0, 1.0) = 0.28;
uniform float wave_height = 0.18;
uniform float wave_scale = 0.06;
uniform float wave_speed = 0.9;
uniform vec2 island_centre = vec2(0.0, 0.0);
uniform float shore_radius = 600.0;
uniform float foam_width = 10.0;
uniform float shallow_width = 60.0;

varying vec2 world_xz;
varying float swell;

float waves(vec2 p, float t) {
	return sin(p.x * wave_scale + t) * 0.5
		+ sin((p.x * 0.7 + p.y * 0.9) * wave_scale * 1.3 - t * 1.3) * 0.3
		+ sin(p.y * wave_scale * 0.8 + t * 0.7) * 0.2;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	float t = TIME * wave_speed;
	swell = waves(world.xz, t);
	VERTEX.y += swell * wave_height;
}

void fragment() {
	float d = distance(world_xz, island_centre);
	float shallow = 1.0 - smoothstep(shore_radius, shore_radius + shallow_width, d);
	vec3 albedo = mix(deep_color, shallow_color, shallow);
	// Wave crests lighten the water a little.
	albedo = mix(albedo, shallow_color, clamp(swell * 0.25 + 0.1, 0.0, 0.35));
	// Surf: a band around the shore that breathes with the swell.
	float edge = shore_radius + 2.0 + swell * 3.0;
	float foam = 1.0 - smoothstep(0.0, foam_width, abs(d - edge));
	foam *= 0.55 + 0.45 * sin(d * 0.6 - TIME * 2.0 + swell * 2.0);
	albedo = mix(albedo, foam_color, clamp(foam, 0.0, 1.0));
	ALBEDO = albedo;
	ALPHA = mix(alpha, 1.0, foam);
	EMISSION = albedo * fill;
	ROUGHNESS = 0.35;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
