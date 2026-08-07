shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 accent : source_color = vec4(0.35, 0.9, 0.85, 1.0);
uniform float intensity : hint_range(0.0, 1.0, 0.01) = 0.42;

void fragment() {
	vec2 p = UV * 2.0 - vec2(1.0);
	float radius = length(p);
	float wave = 0.5 + 0.5 * sin(TIME * 2.2 - radius * 16.0);
	float core = 1.0 - smoothstep(0.22, 0.96, radius);
	float ring = 1.0 - smoothstep(0.02, 0.08, abs(radius - (0.58 + wave * 0.05)));
	float alpha = (core * 0.18 + ring * 0.24) * intensity * (1.0 - smoothstep(0.88, 1.0, radius));
	COLOR = vec4(accent.rgb, alpha * accent.a);
}
