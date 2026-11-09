// A melee swipe: a crescent band that sweeps across the quad as `progress` goes 0 -> 1 and
// fades out behind its leading edge.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0);
uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float band = smoothstep(0.55, 0.7, radius) * (1.0 - smoothstep(0.85, 1.0, radius));
	float angle = (atan(p.y, p.x) / PI + 1.0) * 0.5;  // 0..1 around the circle
	float lead = progress;
	float tail = clamp(lead - angle, 0.0, 1.0);
	float swept = step(angle, lead) * (1.0 - smoothstep(0.0, 0.35, tail));
	float fade = 1.0 - smoothstep(0.7, 1.0, progress);
	ALBEDO = tint.rgb;
	ALPHA = band * swept * fade;
}
