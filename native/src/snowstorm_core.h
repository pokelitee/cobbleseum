// Runs one SnowstormProgram: spawns, moves and lays out its particles as a MultiMesh buffer
// (a 3x4 transform, a colour and custom data per particle, 20 floats), stepped by video frame
// with a seeded random stream so renders are identical. Coordinates: Bedrock blocks are metres;
// the emitter's frame has -Z toward its target, and shapes, directions and accelerations are
// in that frame. Effects an event spawns are queued for the caller (take_spawns()).
#pragma once

#include "snowstorm_program.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

#include <vector>

namespace snowstorm {

class SnowstormCore : public godot::RefCounted {
	GDCLASS(SnowstormCore, godot::RefCounted)

public:
	static const int STRIDE = 20;
	static const int MAX_PARTICLES = 400;

	// Starts the effect at `frame` with the given variables (set after its creation expression,
	// so Cobblemon's target variables win over an effect's defaults) and queries.
	void start(const godot::Ref<SnowstormProgram> &program, const godot::Transform3D &frame, int64_t seed,
			const godot::Dictionary &vars, const godot::Dictionary &queries, float entity_scale, float size_scale);
	// Advances by `delta` seconds of effect time. Camera-facing particles are capped at
	// `cap_per_metre` times their distance from the camera (0: no cap).
	void step(float delta, const godot::Basis &camera_basis, const godot::Vector3 &camera_position, float cap_per_metre);

	void set_frame(const godot::Transform3D &frame) { this->frame = frame; }
	godot::Transform3D get_frame() const { return frame; }
	void stop() { stopped = true; }
	bool is_stopped() const { return stopped; }
	void set_max_age(float value) { max_age = value; }
	float get_max_age() const { return max_age; }
	bool is_finished() const;
	int get_particle_count() const { return (int)particles.size(); }
	// Particles drawn by the last step, and their buffer (sized for at least that many).
	int get_drawn() const { return drawn; }
	godot::PackedFloat32Array get_buffer() const { return buffer; }
	// Effects to spawn since the last call: [[effect id, position, vars, bound], ...].
	godot::Array take_spawns();

protected:
	static void _bind_methods();

private:
	struct Particle {
		float age = 0.0f;
		float lifetime = 1.0f;
		float random[4] = { 0, 0, 0, 0 };
		godot::Vector3 position;
		godot::Vector3 velocity;
		godot::Vector3 direction = godot::Vector3(1, 0, 0);
		float rotation = 0.0f;
		float spin = 0.0f;
		size_t timeline = 0;
	};

	godot::Ref<SnowstormProgram> program;
	const Plan *plan = nullptr;
	Rng rng;
	std::vector<float> v;
	std::vector<float> q;
	std::vector<Particle> particles;
	godot::Transform3D frame;
	float max_age = 6.0f;
	float scale = 1.0f;
	float size_scale = 1.0f;
	bool stopped = false;
	bool expired = false;
	bool emitted = false;
	float age = 0.0f;
	float loop_age = 0.0f;
	float active_time = 1.0f;
	float sleep_time = 0.0f;
	float spawn_debt = 0.0f;
	size_t timeline_index = 0;
	int drawn = 0;
	godot::PackedFloat32Array buffer;
	godot::Array spawns;
	// Per-frame cache of programs that don't vary between particles.
	std::vector<const Program *> shared_programs;
	std::vector<float> shared_values;

	float run(const Program &p) { return p.run(v.data(), q.data(), rng); }
	float shared(const Program &p);
	godot::Vector3 run3(const Program3 &p) { return godot::Vector3(run(p.x), run(p.y), run(p.z)); }
	godot::Vector3 shared3(const Program3 &p) { return godot::Vector3(shared(p.x), shared(p.y), shared(p.z)); }
	void set_particle_vars(const Particle &p);
	void emit(float dt);
	void spawn_particle();
	void update_particles(float dt, const godot::Basis &camera_basis, const godot::Vector3 &camera_position, float cap_per_metre);
	void draw(const Particle &p, int index, const godot::Basis &camera_basis, const godot::Vector3 &camera_position, float cap_per_metre);
	godot::Color tint();
	godot::Color uv(const Particle &p);
	void fire(const EventRef &names, const godot::Vector3 &at);
	void run_event(const Event &event, const godot::Vector3 &at);
};

} // namespace snowstorm
