// Radial speed lines that leave the centre of the frame clear.
shader_type canvas_item;

uniform float intensity = 0.0;
uniform float seed = 0.0;
uniform float aspect = 1.0;

float hash(float n) {
	return fract(sin(n * 12.9898 + seed) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float angle = atan(p.y, p.x);
	float slot = floor((angle + PI) / TAU * 90.0);
	float line = step(0.78, hash(slot));
	float clear_centre = smoothstep(0.28, 0.55, length(p));
	COLOR = vec4(1.0, 1.0, 1.0, line * clear_centre * intensity * 0.55);
}
