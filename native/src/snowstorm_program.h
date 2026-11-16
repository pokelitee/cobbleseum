// A Bedrock particle effect (the "Snowstorm" JSON format Cobblemon's move effects use), parsed
// once into a plan of compiled Molang that every SnowstormCore running it shares.
#pragma once

#include "molang.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <map>
#include <string>
#include <vector>

namespace snowstorm {

godot::Color hex_colour(const godot::Variant &source);

// Variable slots every effect has, in this order.
enum Builtin {
	PARTICLE_AGE, PARTICLE_LIFETIME, PARTICLE_RANDOM_1, PARTICLE_RANDOM_2, PARTICLE_RANDOM_3, PARTICLE_RANDOM_4,
	EMITTER_AGE, EMITTER_LIFETIME, EMITTER_RANDOM_1, EMITTER_RANDOM_2, EMITTER_RANDOM_3, EMITTER_RANDOM_4,
	BUILTIN_COUNT,
};

struct Event {
	std::vector<Event> sequence;
	std::vector<std::pair<float, Event>> randomize;
	bool has_expression = false;
	Program expression;
	bool has_effect = false;
	godot::String effect;
	bool bound = false;
	bool has_pre_effect = false;
	Program pre_effect;
};

// Event names to run: one name, a list, or none.
using EventRef = std::vector<std::string>;

struct ChainKey {
	float time = 0.0f;
	float left_value = 0.0f, right_value = 0.0f, left_slope = 0.0f, right_slope = 0.0f;
};

struct Curve {
	int slot = 0;
	std::string type;
	Program input;
	Program range;
	std::vector<float> nodes;
	std::vector<ChainKey> chain;

	float at(float input_value, float span) const;
};

enum class Shape { NONE, POINT, SPHERE, DISC, BOX };
enum class Direction { VECTOR, OUTWARDS, INWARDS };
enum class Facing {
	ROTATE_XYZ, ROTATE_Y, LOOKAT_XYZ, LOOKAT_Y, LOOKAT_DIRECTION, DIRECTION_X, DIRECTION_Y, DIRECTION_Z,
	EMITTER_XY, EMITTER_XZ, EMITTER_YZ,
};
enum class Uv { FULL, FLIPBOOK, FIXED };
enum class Tint { NONE, FIXED, CHANNELS, GRADIENT };

struct Program3 {
	Program x, y, z;
};

struct Plan {
	bool has_creation = false, has_per_update = false;
	Program creation, per_update;
	bool looping = false, has_active_time = false;
	Program active_time, sleep_time;
	bool instant = false, steady = false;
	Program num_particles, spawn_rate, max_particles;
	Shape shape = Shape::NONE;
	Program3 offset, plane_normal, half_dimensions, direction;
	Program radius;
	bool surface_only = false;
	Direction direction_mode = Direction::VECTOR;
	bool has_max_lifetime = false, has_expiration = false;
	Program max_lifetime, expiration;
	bool speed_is_vector = false;
	Program speed;
	Program3 speed_vector;
	Program spin, spin_rate;
	bool dynamic = false;
	Program3 acceleration;
	Program drag, spin_acceleration, spin_drag;
	bool has_relative_position = false, has_parametric_direction = false, has_parametric_rotation = false;
	Program3 relative_position, parametric_direction;
	Program parametric_rotation;
	bool collision = false, expire_on_contact = false;
	Program collision_enabled, collision_radius, collision_drag, restitution;
	Program width, height;
	Facing facing = Facing::ROTATE_XYZ;
	bool camera_facing = true;
	bool has_custom_direction = false;
	Program3 custom_direction;
	Uv uv = Uv::FULL;
	godot::Vector2 texture_size = godot::Vector2(1, 1);
	Program uv_x, uv_y, uv_w, uv_h, max_frame;
	godot::Vector2 frame_size = godot::Vector2(1, 1), frame_step;
	float frames_per_second = 8.0f;
	bool stretch_to_lifetime = false, loop = false;
	Tint tint = Tint::NONE;
	godot::Color tint_colour = godot::Color(1, 1, 1, 1);
	Program tint_r, tint_g, tint_b, tint_a, interpolant;
	std::vector<std::pair<float, godot::Color>> gradient;
	std::vector<Curve> curves;
	std::vector<std::pair<float, EventRef>> emitter_timeline, particle_timeline;
	EventRef emitter_creation, emitter_expiration, particle_creation, particle_expiration;
	bool has_particle_update = false, has_particle_render = false;
	Program particle_update, particle_render;
	bool scale_with_entity = false;
};

class SnowstormProgram : public godot::RefCounted {
	GDCLASS(SnowstormProgram, godot::RefCounted)

public:
	Names names;
	Plan plan;
	std::map<std::string, Event> events;
	// Variable slots children inherit (Cobblemon's target and entity variables).
	std::vector<int> context_slots;

	// Parses an effect's JSON (as parsed by Godot). Returns "" or why it can't be used.
	godot::String parse(const godot::Dictionary &data);
	godot::String get_id() const { return id; }
	godot::String get_texture() const { return texture; }
	godot::String get_material() const { return material; }
	godot::PackedStringArray get_errors() const { return errors; }
	godot::PackedStringArray get_unsupported() const { return unsupported; }
	// Every effect id this effect's events can spawn.
	godot::PackedStringArray get_spawned_effects() const;

	// Compiles and runs one Molang text against `v` and `q`, for tests: {"value", "error", "v"}.
	static godot::Dictionary evaluate(const godot::String &source, const godot::Dictionary &v, const godot::Dictionary &q, int64_t seed);
	// A Bedrock colour ("#AARRGGBB", "#RRGGBB" or channels), for tests.
	static godot::Color parse_colour(const godot::Variant &source) { return hex_colour(source); }
	// Hermite and linear curve maths, for tests: the effect's first curve at an input.
	float curve_at(float input, float span) const;

protected:
	static void _bind_methods();

private:
	godot::String id, texture, material = "alpha";
	godot::PackedStringArray errors, unsupported;

	Program molang(const godot::Variant &source);
	Program3 molang3(const godot::Variant &source);
	Event parse_event(const godot::Dictionary &data);
	EventRef event_ref(const godot::Variant &source) const;
	std::vector<std::pair<float, EventRef>> timeline(const godot::Variant &source) const;
	void build(const godot::Dictionary &components);
	void mark_per_particle();
	void collect_programs(std::vector<Program *> &out);
};

} // namespace snowstorm
