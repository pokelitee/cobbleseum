// Arena blocks: each block's colour broken up the way Cobblemon's textures are, so nothing
// looks painted on (concepts_brief.md §12.7):
// - pixel grain at TEXEL pixels per metre, the density of Cobblemon's models (16 per block),
//   laid out on each face so the pixels line up with its edges;
// - grime toward the ground on upright faces, and moss in their lower part if MOSS > 0.
// - see-through: anything between the camera and a fighter (above that fighter's ground)
//   dissolves with a screen-door dither, so cover never hides the battle.
// Blocks come two ways: MultiMesh boxes (a unit cube scaled per instance; the face's metres
// come from the vertex and the instance's scale) and ring segments built as meshes (UV holds
// the face's metres; FACE_UV is set).
shader_type spatial;
render_mode diffuse_burley;

uniform float TEXEL = 16.0;
uniform float GRAIN = 0.14;
uniform float GRIME = 0.3;
uniform float MOSS = 0.0;
uniform vec3 MOSS_COLOUR : source_color = vec3(0.33, 0.42, 0.25);
uniform bool FACE_UV = false;
// The fighters' chest positions and ground heights, set every frame (Arena.set_sight).
uniform bool SIGHT_ON = false;
uniform vec3 SIGHT_A = vec3(0.0);
uniform vec3 SIGHT_B = vec3(0.0);
uniform float SIGHT_GROUND_A = 0.0;
uniform float SIGHT_GROUND_B = 0.0;
uniform float SIGHT_RADIUS = 1.3;

varying vec3 world_position;
varying vec3 world_normal;
varying vec2 face_metres;
varying float block_seed;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// How much of this fragment to dissolve for the line from the camera to `target`: fully on
// the line, nothing past SIGHT_RADIUS from it, behind the target, or at or below its ground.
float sight(vec3 camera, vec3 target, float ground, vec3 point) {
	vec3 line = target - camera;
	float along = dot(point - camera, line) / max(dot(line, line), 1e-4);
	if (along < 0.02 || along > 0.92 || point.y <= ground + 0.05) {
		return 0.0;
	}
	float off = length(camera + line * along - point);
	return 1.0 - smoothstep(SIGHT_RADIUS * 0.55, SIGHT_RADIUS, off);
}

// A 4 x 4 ordered-dither threshold for the screen pixel.
float dither(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(bayer[y * 4 + x]) + 0.5) / 16.0;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (FACE_UV) {
		face_metres = UV;
		block_seed = 0.0;
	} else {
		vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		// From the box's corner, so the pixel grid starts at its edges.
		vec3 metres = (VERTEX + 0.5) * scale;
		vec3 n = abs(NORMAL);
		face_metres = n.x > 0.5 ? metres.zy : (n.y > 0.5 ? metres.xz : metres.xy);
		block_seed = hash(MODEL_MATRIX[3].xyz);
	}
}

void fragment() {
	if (SIGHT_ON) {
		vec3 camera = CAMERA_POSITION_WORLD;
		float fade = max(sight(camera, SIGHT_A, SIGHT_GROUND_A, world_position),
			sight(camera, SIGHT_B, SIGHT_GROUND_B, world_position));
		if (fade > dither(FRAGCOORD.xy)) {
			discard;
		}
	}
	vec2 texel = floor(face_metres * TEXEL);
	float side = dot(round(world_normal), vec3(1.0, 2.0, 3.0));
	float grain = hash(vec3(texel, side + block_seed * 97.0)) - 0.5;
	vec3 colour = COLOR.rgb * (1.0 + grain * GRAIN);
	float upright = 1.0 - abs(world_normal.y);
	float low = 1.0 - smoothstep(0.0, 1.6, world_position.y);
	colour *= 1.0 - GRIME * upright * low;
	float moss = MOSS * upright * low * step(0.55, hash(vec3(floor(face_metres * 4.0), side)));
	colour = mix(colour, MOSS_COLOUR * (1.0 + grain * GRAIN), moss);
	ALBEDO = colour;
	ROUGHNESS = 0.92;
}
