// Arena blocks: each block's colour broken up the way Cobblemon's textures are, so nothing
// looks painted on (concepts_brief.md §12.7):
// - pixel grain at TEXEL pixels per metre, the density of Cobblemon's models (16 per block),
//   laid out on each face so the pixels line up with its edges;
// - grime toward the ground on upright faces, and moss in their lower part if MOSS > 0.
// - see-through: anything between the camera and a fighter (above that fighter's ground)
//   dissolves with a screen-door dither, so cover never hides the battle.
// - a surge (§9.11) on the field: upward faces inside SURGE_RADIUS take a light tint of its
//   colour, a stepped glowing band just inside the edge, and a pattern of its own in eighth-metre
//   pixels that moves with SURGE_PHASE (set per video frame, so renders repeat): pulses along a
//   grid of lines (electric), mown stripes of grass (grassy), drifting cloud patches (misty) or
//   rings rippling out from the centre (psychic).
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
// The surge's colour, and in alpha how far it's faded in (0 for none).
uniform vec4 SURGE = vec4(0.0);
uniform float SURGE_RADIUS = 14.5;
uniform float SURGE_PHASE = 0.0;
// 0 electric, 1 grassy, 2 misty, 3 psychic (ArenaSurge.COLOURS order).
uniform int SURGE_KIND = 0;

varying vec3 world_position;
varying vec3 world_normal;
varying vec2 face_metres;
varying float block_seed;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// A 4 x 4 ordered-dither threshold for the screen pixel.
float dither(vec2 pixel) {
	int x = int(mod(pixel.x, 4.0));
	int y = int(mod(pixel.y, 4.0));
	int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(bayer[y * 4 + x]) + 0.5) / 16.0;
}

// Smooth value noise on a grid, for the mist's patches.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 11.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 11.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 11.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 11.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// A surge's pattern at a pixel centre `p` (metres on the floor): how much the pixel takes the
// surge's colour (x), how brightly it glows (y) and how light a shade of the colour it takes (z).
vec3 surge_pattern(vec2 p, float phase) {
	if (SURGE_KIND == 0) {
		// Pulses running along a 1.5 m grid of lines, each line its own way and pace.
		vec2 grid = p / 1.5;
		vec2 to_line = abs(fract(grid) - 0.5);
		float glow = 0.0;
		for (int axis = 0; axis < 2; axis++) {
			float across = axis == 0 ? to_line.y : to_line.x;
			if (across > 0.5 - 0.09) {
				float line = axis == 0 ? floor(grid.y + 0.5) : floor(grid.x + 0.5);
				float along = axis == 0 ? p.x : p.y;
				float way = hash(vec3(line, float(axis), 5.0)) < 0.5 ? -1.0 : 1.0;
				float speed = 1.2 + hash(vec3(line, float(axis), 9.0));
				float dash = fract(along * 0.25 * way - phase * speed + hash(vec3(line, float(axis), 2.0)));
				glow = max(glow, max(0.25, step(0.78, dash) * (0.5 + dash)));
			}
		}
		return vec3(glow * 0.8, glow, 1.0);
	}
	if (SURGE_KIND == 1) {
		// Grass covering the ground in two greens, in broad mown stripes, with a sparse sway of
		// brighter tips. Darker shades of the colour, since mixing a bright green into pale
		// paving only washes it out.
		float stripe = step(0.5, fract(p.x / 2.0 + 0.15 * sin(p.y * 0.4)));
		float blade = hash(vec3(floor(p * 8.0), 4.0));
		float tip = step(0.93, fract(blade + phase * 0.15));
		return vec3(1.5, tip * 0.25, 0.5 + 0.18 * stripe + 0.12 * blade + 0.2 * tip);
	}
	if (SURGE_KIND == 2) {
		// Soft cloud patches drifting slowly across, their edges dithered pixel by pixel.
		float cloud = value_noise(p * 0.35 + vec2(phase * 0.25, phase * 0.1));
		float threshold = dither(floor(p * 8.0));
		float dense = step(threshold, smoothstep(0.45, 0.65, cloud)) * 0.45 + step(threshold, smoothstep(0.62, 0.8, cloud)) * 0.35;
		return vec3(0.15 + dense, 0.04 + dense * 0.35, 1.0);
	}
	// Rings rippling out from the centre, a pixel ring every 3 m.
	float ring = fract(length(p) / 3.0 - phase * 0.6);
	float lit = step(0.9, ring) + step(0.82, ring) * 0.35;
	return vec3(0.25 + lit * 0.6, lit * 0.9, 1.0);
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
	if (SURGE.a > 0.0) {
		float up = smoothstep(0.5, 0.9, world_normal.y);
		// Eighth-metre pixels, so the pattern sits on the arena's pixel grain.
		vec2 pixel = (floor(world_position.xz * 8.0) + 0.5) / 8.0;
		float from_centre = length(pixel);
		float inside = step(from_centre, SURGE_RADIUS - 0.25);
		float amount = SURGE.a * up * inside;
		// A stepped band just inside the edge, so the field's limit reads from low cameras.
		float edge = step(SURGE_RADIUS - 1.0, from_centre) * 0.6 + step(SURGE_RADIUS - 0.5, from_centre) * 0.4;
		vec3 pattern = surge_pattern(pixel, SURGE_PHASE);
		float tint = max(pattern.x, edge);
		float glow = max(pattern.y, edge * 0.9);
		vec3 shade = SURGE.rgb * mix(pattern.z, 1.0, edge) * (1.0 + grain * GRAIN);
		colour = mix(colour, shade, min(1.0, amount * (0.12 + 0.5 * tint)));
		EMISSION = SURGE.rgb * amount * glow * 0.9;
	}
	ALBEDO = colour;
	ROUGHNESS = 0.92;
}
