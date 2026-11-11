// Arena blocks: each block's colour (the MultiMesh instance colour) broken up the way
// Cobblemon's textures are, so nothing looks painted on (concepts_brief.md §12.7):
// - pixel grain at TEXEL pixels per metre, the density of Cobblemon's models;
// - a slow change of tone over metres, so no wall is one flat colour;
// - grime toward the ground on upright faces, and moss in their lower part if MOSS > 0.
// Everything is from world position, so it holds still as the camera moves.
shader_type spatial;
render_mode diffuse_burley;

uniform float TEXEL = 16.0;
uniform float GRAIN = 0.09;
uniform float TONE = 0.1;
uniform float GRIME = 0.3;
uniform float MOSS = 0.0;
uniform vec3 MOSS_COLOUR : source_color = vec3(0.33, 0.42, 0.25);

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Step half a texel inward so a face's pixels never straddle a cell boundary.
	vec3 texel = floor(world_position * TEXEL - world_normal * 0.5);
	float grain = hash(texel) - 0.5;
	float tone = hash(floor(world_position * 0.35)) - 0.5;
	vec3 colour = COLOR.rgb * (1.0 + grain * GRAIN + tone * TONE);
	float upright = 1.0 - abs(world_normal.y);
	float low = 1.0 - smoothstep(0.0, 1.6, world_position.y);
	colour *= 1.0 - GRIME * upright * low;
	float moss = MOSS * upright * low * step(0.55, hash(floor(world_position * 4.0 - world_normal * 0.5)));
	colour = mix(colour, MOSS_COLOUR * (1.0 + grain * GRAIN), moss);
	ALBEDO = colour;
	ROUGHNESS = 0.92;
}
