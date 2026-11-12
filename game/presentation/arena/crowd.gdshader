// The crowd (Crowd): one low-poly figure drawn many times, animated here so thousands cost
// one draw. Vertex colour says what a vertex is: red 1 the shirt, 0.5 the legs, 0 the skin;
// green 1 an arm (rotated about its shoulder when cheering). Each figure's custom data holds
// its shirt colour (rgb) and, packed in alpha, its skin tone and a random phase.
shader_type spatial;
render_mode diffuse_burley;

// Seconds of crowd time (advanced by Crowd, so hit-stop freezes it) and how excited the
// crowd is (0 to 1).
uniform float crowd_time = 0.0;
uniform float excitement = 0.0;
uniform vec3 LEGS : source_color = vec3(0.22, 0.24, 0.3);

const vec3 SKIN[4] = vec3[](vec3(0.96, 0.8, 0.66), vec3(0.85, 0.65, 0.48), vec3(0.62, 0.43, 0.3), vec3(0.4, 0.27, 0.19));
const float SHOULDER = 0.92;

varying vec3 tint;

void vertex() {
	float packed = INSTANCE_CUSTOM.a * 4.0;
	int skin = clamp(int(floor(packed)), 0, 3);
	float phase = fract(packed);
	// Each figure joins in once the excitement passes its own threshold, so small cheers
	// move part of the crowd and a knockout moves all of it.
	float eager = fract(phase * 7.31 + 0.13);
	float cheer = clamp((excitement - eager * 0.6) * 2.5, 0.0, 1.0);
	float t = crowd_time * (0.9 + phase * 0.3) + phase * TAU;
	if (COLOR.g > 0.5) {
		float side = sign(VERTEX.x);
		vec2 pivot = vec2(side * 0.24, SHOULDER);
		vec2 relative = VERTEX.xy - pivot;
		float angle = side * cheer * (2.3 + 0.4 * sin(t * 6.0));
		relative = vec2(relative.x * cos(angle) - relative.y * sin(angle), relative.x * sin(angle) + relative.y * cos(angle));
		VERTEX.xy = pivot + relative;
	}
	VERTEX.x += sin(t * 1.3) * 0.04 * VERTEX.y;
	VERTEX.y += cheer * abs(sin(t * 8.0)) * 0.22;
	if (COLOR.r > 0.75) {
		tint = INSTANCE_CUSTOM.rgb;
	} else if (COLOR.r > 0.25) {
		tint = LEGS;
	} else {
		tint = SKIN[skin];
	}
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
}
