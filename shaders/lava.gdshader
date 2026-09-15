// Cartoon lava: dark crust drifting over a bright glowing core. No
// texture: two layers of sines make the cracks. Self-lit (unshaded).
shader_type spatial;
render_mode cull_back, unshaded;

uniform vec3 core_color : source_color = vec3(1.0, 0.55, 0.05);
uniform vec3 crust_color : source_color = vec3(0.35, 0.08, 0.02);
uniform vec3 hot_color : source_color = vec3(1.0, 0.95, 0.5);
uniform float scale = 0.35;
uniform float speed = 0.25;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cracks(vec2 p, float t) {
	float v = sin(p.x * 1.7 + t) * sin(p.y * 1.3 - t * 0.7);
	v += 0.5 * sin((p.x + p.y) * 2.9 + t * 1.3) * sin((p.x - p.y) * 2.3 - t);
	return v;
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float t = TIME * speed;
	float v = cracks(p, t) + 0.35 * cracks(p * 2.3 + 7.0, t * 1.7);
	float crust = smoothstep(0.15, 0.55, v);
	float hot = smoothstep(-0.9, -0.5, -v) * (1.0 - crust);
	vec3 col = mix(core_color, crust_color, crust);
	col = mix(col, hot_color, hot * 0.6);
	ALBEDO = col;
	EMISSION = col * 0.6;
}
