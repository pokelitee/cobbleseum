#include "snowstorm_core.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace snowstorm {

namespace {

const float GROUND = 0.0f;

Vector3 safe_normalized(const Vector3 &v, const Vector3 &fallback) {
	float length = v.length();
	return length > 0.000001f ? v / length : fallback;
}

} // namespace

void SnowstormCore::start(const Ref<SnowstormProgram> &source, const Transform3D &at, int64_t seed, const Dictionary &vars,
		const Dictionary &queries, float entity_scale, float sizes) {
	program = source;
	plan = &program->plan;
	frame = at;
	size_scale = sizes;
	rng.seed((uint64_t)seed);
	v.assign(program->names.v.size() + 1, 0.0f);
	q.assign(program->names.q.size() + 1, 0.0f);
	for (const auto &entry : program->names.q) {
		Variant value = queries.get(String::utf8(entry.first.c_str()), 0.0);
		q[entry.second] = (float)double(value);
	}
	float randoms[4];
	for (int i = 0; i < 4; i++) {
		randoms[i] = rng.unit();
		v[EMITTER_RANDOM_1 + i] = randoms[i];
	}
	scale = plan->scale_with_entity ? entity_scale : 1.0f;
	if (plan->has_creation) {
		run(plan->creation);
	}
	for (const auto &entry : program->names.v) {
		String name = String::utf8(entry.first.c_str());
		if (vars.has(name)) {
			v[entry.second] = (float)double(vars[name]);
		}
	}
	for (int i = 0; i < 4; i++) {
		v[EMITTER_RANDOM_1 + i] = randoms[i];
	}
	active_time = plan->has_active_time ? run(plan->active_time) : max_age;
	sleep_time = plan->looping ? run(plan->sleep_time) : 0.0f;
	v[EMITTER_LIFETIME] = active_time;
	fire(plan->emitter_creation, frame.origin);
}

bool SnowstormCore::is_finished() const {
	return (stopped || expired || age >= max_age) && particles.empty();
}

Array SnowstormCore::take_spawns() {
	Array taken = spawns;
	spawns = Array();
	return taken;
}

float SnowstormCore::shared(const Program &p) {
	if (p.is_constant) {
		return p.constant;
	}
	if (p.per_particle) {
		return run(p);
	}
	for (size_t i = 0; i < shared_programs.size(); i++) {
		if (shared_programs[i] == &p) {
			return shared_values[i];
		}
	}
	float value = run(p);
	shared_programs.push_back(&p);
	shared_values.push_back(value);
	return value;
}

void SnowstormCore::step(float dt, const Basis &camera_basis, const Vector3 &camera_position, float cap_per_metre) {
	if (plan == nullptr) {
		return;
	}
	if (age >= max_age) {
		stopped = true;
	}
	v[EMITTER_AGE] = loop_age;
	if (plan->has_per_update) {
		run(plan->per_update);
	}
	if (!stopped && !expired && loop_age < active_time) {
		emit(dt);
	}
	while (timeline_index < plan->emitter_timeline.size() && plan->emitter_timeline[timeline_index].first <= loop_age + dt) {
		fire(plan->emitter_timeline[timeline_index].second, frame.origin);
		timeline_index++;
	}
	loop_age += dt;
	age += dt;
	if (loop_age >= active_time && !expired) {
		if (plan->looping && !stopped) {
			if (loop_age >= active_time + sleep_time) {
				loop_age = 0.0f;
				emitted = false;
				timeline_index = 0;
			}
		} else {
			expired = true;
			fire(plan->emitter_expiration, frame.origin);
		}
	}
	update_particles(dt, camera_basis, camera_position, cap_per_metre);
}

void SnowstormCore::emit(float dt) {
	int count = 0;
	if (plan->instant) {
		if (!emitted) {
			count = (int)run(plan->num_particles);
		}
		emitted = true;
	} else if (plan->steady) {
		spawn_debt += run(plan->spawn_rate) * dt;
		count = (int)spawn_debt;
		spawn_debt -= count;
		count = std::min(count, (int)run(plan->max_particles) - (int)particles.size());
	}
	count = std::min(count, MAX_PARTICLES - (int)particles.size());
	for (int i = 0; i < count; i++) {
		spawn_particle();
	}
}

void SnowstormCore::set_particle_vars(const Particle &p) {
	v[PARTICLE_AGE] = p.age;
	v[PARTICLE_LIFETIME] = p.lifetime;
	for (int i = 0; i < 4; i++) {
		v[PARTICLE_RANDOM_1 + i] = p.random[i];
	}
}

void SnowstormCore::spawn_particle() {
	Particle p;
	for (int i = 0; i < 4; i++) {
		p.random[i] = rng.unit();
	}
	set_particle_vars(p);
	if (plan->has_max_lifetime) {
		p.lifetime = std::max(0.001f, run(plan->max_lifetime));
	}
	v[PARTICLE_LIFETIME] = p.lifetime;
	Vector3 local;
	Vector3 direction;
	if (plan->shape != Shape::NONE) {
		Vector3 centre = run3(plan->offset);
		switch (plan->shape) {
			case Shape::SPHERE: {
				float radius = run(plan->radius);
				Vector3 unit(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1));
				while (unit.length_squared() > 1.0f || unit.length_squared() < 0.0001f) {
					unit = Vector3(rng.range(-1, 1), rng.range(-1, 1), rng.range(-1, 1));
				}
				local = plan->surface_only ? unit.normalized() * radius : unit * radius;
				break;
			}
			case Shape::DISC: {
				float radius = run(plan->radius);
				float angle = rng.unit() * 6.28318530718f;
				float distance = plan->surface_only ? radius : radius * std::sqrt(rng.unit());
				Vector3 normal = safe_normalized(run3(plan->plane_normal), Vector3(0, 1, 0));
				Vector3 u = normal.cross(std::fabs(normal.y) < 0.99f ? Vector3(0, 1, 0) : Vector3(1, 0, 0)).normalized();
				Vector3 w = normal.cross(u);
				local = (u * std::cos(angle) + w * std::sin(angle)) * distance;
				break;
			}
			case Shape::BOX: {
				Vector3 half = run3(plan->half_dimensions);
				local = Vector3(rng.range(-half.x, half.x), rng.range(-half.y, half.y), rng.range(-half.z, half.z));
				if (plan->surface_only) {
					int axis = rng.integer(0, 2);
					local[axis] = half[axis] * (rng.unit() < 0.5f ? 1.0f : -1.0f);
				}
				break;
			}
			default:
				break;
		}
		switch (plan->direction_mode) {
			case Direction::OUTWARDS:
				direction = safe_normalized(local, Vector3());
				break;
			case Direction::INWARDS:
				direction = -safe_normalized(local, Vector3());
				break;
			default:
				direction = run3(plan->direction);
				break;
		}
		local += centre;
	}
	p.position = frame.origin + frame.basis.xform(local * scale);
	if (plan->speed_is_vector) {
		p.velocity = frame.basis.xform(run3(plan->speed_vector) * scale);
	} else {
		p.velocity = frame.basis.xform(safe_normalized(direction, Vector3()) * run(plan->speed) * scale);
	}
	p.rotation = run(plan->spin);
	p.spin = run(plan->spin_rate);
	p.direction = safe_normalized(p.velocity, p.direction);
	if (plan->has_particle_render) {
		run(plan->particle_render);
	}
	particles.push_back(p);
	fire(plan->particle_creation, p.position);
}

void SnowstormCore::update_particles(float dt, const Basis &camera_basis, const Vector3 &camera_position, float cap_per_metre) {
	shared_programs.clear();
	shared_values.clear();
	int shown = 0;
	size_t kept = 0;
	for (size_t index = 0; index < particles.size(); index++) {
		Particle p = particles[index];
		set_particle_vars(p);
		for (const Curve &curve : plan->curves) {
			v[curve.slot] = curve.at(run(curve.input), run(curve.range));
		}
		if (plan->has_particle_update) {
			run(plan->particle_update);
		}
		if (plan->has_expiration && shared(plan->expiration) != 0.0f) {
			fire(plan->particle_expiration, p.position);
			continue;
		}
		if (plan->dynamic) {
			Vector3 acceleration = frame.basis.xform(shared3(plan->acceleration) * scale);
			p.velocity += (acceleration - p.velocity * shared(plan->drag)) * dt;
			p.position += p.velocity * dt;
			p.spin += (shared(plan->spin_acceleration) - shared(plan->spin_drag) * p.spin) * dt;
			p.rotation += p.spin * dt;
		}
		if (plan->has_relative_position) {
			p.position = frame.origin + frame.basis.xform(shared3(plan->relative_position) * scale);
		}
		if (plan->has_parametric_direction) {
			Vector3 heading = frame.basis.xform(shared3(plan->parametric_direction));
			p.direction = safe_normalized(heading, p.direction);
		}
		if (plan->has_parametric_rotation) {
			p.rotation = shared(plan->parametric_rotation);
		}
		if (plan->collision && shared(plan->collision_enabled) != 0.0f) {
			float radius = shared(plan->collision_radius);
			if (p.position.y < GROUND + radius) {
				if (plan->expire_on_contact) {
					fire(plan->particle_expiration, p.position);
					continue;
				}
				p.position.y = GROUND + radius;
				if (p.velocity.y < 0.0f) {
					p.velocity.y = -p.velocity.y * shared(plan->restitution);
				}
				Vector2 flat(p.velocity.x, p.velocity.z);
				float slowed = std::max(0.0f, flat.length() - shared(plan->collision_drag) * dt);
				flat = flat.length() > 0.0f ? flat.normalized() * slowed : flat;
				p.velocity = Vector3(flat.x, p.velocity.y, flat.y);
			}
		}
		if (!plan->has_parametric_direction && !plan->has_relative_position && p.velocity.length_squared() > 0.0001f) {
			p.direction = p.velocity.normalized();
		}
		while (p.timeline < plan->particle_timeline.size() && plan->particle_timeline[p.timeline].first <= p.age + dt) {
			fire(plan->particle_timeline[p.timeline].second, p.position);
			p.timeline++;
		}
		if (shown < MAX_PARTICLES) {
			draw(p, shown, camera_basis, camera_position, cap_per_metre);
			shown++;
		}
		p.age += dt;
		if (p.age >= p.lifetime) {
			fire(plan->particle_expiration, p.position);
			continue;
		}
		particles[kept++] = p;
	}
	particles.resize(kept);
	drawn = shown;
}

void SnowstormCore::draw(const Particle &p, int index, const Basis &camera_basis, const Vector3 &camera_position, float cap_per_metre) {
	if ((index + 1) * STRIDE > buffer.size()) {
		buffer.resize(std::max((int64_t)buffer.size() * 2, (int64_t)(index + 1) * STRIDE));
	}
	float width = shared(plan->width) * 2.0f * scale * size_scale;
	float height = shared(plan->height) * 2.0f * scale * size_scale;
	if (cap_per_metre > 0.0f && plan->camera_facing) {
		float cap = camera_position.distance_to(p.position) * cap_per_metre;
		float largest = std::max(std::fabs(width), std::fabs(height));
		if (largest > cap) {
			width *= cap / largest;
			height *= cap / largest;
		}
	}
	Vector3 right, up, normal;
	Vector3 toward_camera = safe_normalized(camera_position - p.position, camera_basis.get_column(2));
	switch (plan->facing) {
		case Facing::ROTATE_XYZ:
			right = camera_basis.get_column(0);
			up = camera_basis.get_column(1);
			normal = camera_basis.get_column(2);
			break;
		case Facing::ROTATE_Y:
		case Facing::LOOKAT_Y: {
			Vector3 flat = safe_normalized(Vector3(toward_camera.x, 0, toward_camera.z), Vector3(0, 0, 1));
			right = Vector3(0, 1, 0).cross(flat);
			up = Vector3(0, 1, 0);
			normal = flat;
			break;
		}
		case Facing::LOOKAT_XYZ:
			right = safe_normalized(Vector3(0, 1, 0).cross(toward_camera), camera_basis.get_column(0));
			up = toward_camera.cross(right);
			normal = toward_camera;
			break;
		case Facing::EMITTER_XY:
			right = frame.basis.get_column(0);
			up = frame.basis.get_column(1);
			normal = frame.basis.get_column(2);
			break;
		case Facing::EMITTER_XZ:
			right = frame.basis.get_column(0);
			up = frame.basis.get_column(2);
			normal = -frame.basis.get_column(1);
			break;
		case Facing::EMITTER_YZ:
			right = frame.basis.get_column(2);
			up = frame.basis.get_column(1);
			normal = frame.basis.get_column(0);
			break;
		default: {
			Vector3 direction = p.direction;
			if (plan->has_custom_direction) {
				direction = safe_normalized(frame.basis.xform(shared3(plan->custom_direction)), direction);
			}
			normal = safe_normalized(toward_camera - direction * toward_camera.dot(direction), camera_basis.get_column(2));
			if (plan->facing == Facing::DIRECTION_Y) {
				right = direction.cross(normal);
				up = direction;
			} else if (plan->facing == Facing::DIRECTION_Z) {
				right = safe_normalized(Vector3(0, 1, 0).cross(direction), Vector3(1, 0, 0));
				up = direction.cross(right);
				normal = direction;
			} else {
				right = direction;
				up = normal.cross(direction);
			}
			break;
		}
	}
	if (p.rotation != 0.0f) {
		float angle = p.rotation * 0.01745329252f;
		float c = std::cos(angle);
		float s = std::sin(angle);
		Vector3 turned = right * c + up * s;
		up = -right * s + up * c;
		right = turned;
	}
	right *= width;
	up *= height;
	Color colour = tint();
	Color rect = uv(p);
	float *b = buffer.ptrw() + index * STRIDE;
	b[0] = right.x;
	b[1] = up.x;
	b[2] = normal.x;
	b[3] = p.position.x;
	b[4] = right.y;
	b[5] = up.y;
	b[6] = normal.y;
	b[7] = p.position.y;
	b[8] = right.z;
	b[9] = up.z;
	b[10] = normal.z;
	b[11] = p.position.z;
	b[12] = colour.r;
	b[13] = colour.g;
	b[14] = colour.b;
	b[15] = colour.a;
	b[16] = rect.r;
	b[17] = rect.g;
	b[18] = rect.b;
	b[19] = rect.a;
}

Color SnowstormCore::tint() {
	switch (plan->tint) {
		case Tint::FIXED:
			return plan->tint_colour;
		case Tint::CHANNELS:
			return Color(shared(plan->tint_r), shared(plan->tint_g), shared(plan->tint_b), shared(plan->tint_a));
		case Tint::GRADIENT: {
			const auto &stops = plan->gradient;
			float at = shared(plan->interpolant);
			if (at <= stops.front().first) {
				return stops.front().second;
			}
			for (size_t i = 0; i + 1 < stops.size(); i++) {
				if (at <= stops[i + 1].first) {
					float span = stops[i + 1].first - stops[i].first;
					return stops[i].second.lerp(stops[i + 1].second, span > 0.0f ? (at - stops[i].first) / span : 1.0f);
				}
			}
			return stops.back().second;
		}
		default:
			return Color(1, 1, 1, 1);
	}
}

Color SnowstormCore::uv(const Particle &p) {
	const Vector2 &size = plan->texture_size;
	switch (plan->uv) {
		case Uv::FLIPBOOK: {
			int frames = std::max(1, (int)shared(plan->max_frame));
			int index = plan->stretch_to_lifetime ? (int)(p.age / p.lifetime * frames) : (int)(p.age * plan->frames_per_second);
			index = plan->loop ? ((index % frames) + frames) % frames : std::min(index, frames - 1);
			float x = shared(plan->uv_x) + plan->frame_step.x * index;
			float y = shared(plan->uv_y) + plan->frame_step.y * index;
			return Color(x / size.x, y / size.y, plan->frame_size.x / size.x, plan->frame_size.y / size.y);
		}
		case Uv::FIXED:
			return Color(shared(plan->uv_x) / size.x, shared(plan->uv_y) / size.y, shared(plan->uv_w) / size.x, shared(plan->uv_h) / size.y);
		default:
			return Color(0, 0, 1, 1);
	}
}

void SnowstormCore::fire(const EventRef &names, const Vector3 &at) {
	for (const std::string &name : names) {
		auto found = program->events.find(name);
		if (found != program->events.end()) {
			run_event(found->second, at);
		}
	}
}

void SnowstormCore::run_event(const Event &event, const Vector3 &at) {
	for (const Event &step : event.sequence) {
		run_event(step, at);
	}
	if (!event.randomize.empty()) {
		float total = 0.0f;
		for (const auto &option : event.randomize) {
			total += option.first;
		}
		float pick = rng.unit() * total;
		for (const auto &option : event.randomize) {
			pick -= option.first;
			if (pick <= 0.0f) {
				run_event(option.second, at);
				break;
			}
		}
	}
	if (event.has_expression) {
		run(event.expression);
	}
	if (event.has_effect) {
		// Children inherit Cobblemon's context (target and entity variables) and whatever the
		// event's pre-effect expression sets, not this emitter's own state.
		std::vector<float> scratch = v;
		if (event.has_pre_effect) {
			event.pre_effect.run(scratch.data(), q.data(), rng);
		}
		Dictionary vars;
		for (const auto &entry : program->names.v) {
			int slot = entry.second;
			bool context = std::find(program->context_slots.begin(), program->context_slots.end(), slot) != program->context_slots.end();
			if (context || scratch[slot] != v[slot]) {
				vars[String::utf8(entry.first.c_str())] = scratch[slot];
			}
		}
		Array spawn;
		spawn.push_back(event.effect);
		spawn.push_back(at);
		spawn.push_back(vars);
		spawn.push_back(event.bound);
		spawns.push_back(spawn);
	}
}

void SnowstormCore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start", "program", "frame", "seed", "vars", "queries", "entity_scale", "size_scale"), &SnowstormCore::start);
	ClassDB::bind_method(D_METHOD("step", "delta", "camera_basis", "camera_position", "cap_per_metre"), &SnowstormCore::step);
	ClassDB::bind_method(D_METHOD("set_frame", "frame"), &SnowstormCore::set_frame);
	ClassDB::bind_method(D_METHOD("get_frame"), &SnowstormCore::get_frame);
	ClassDB::bind_method(D_METHOD("stop"), &SnowstormCore::stop);
	ClassDB::bind_method(D_METHOD("is_stopped"), &SnowstormCore::is_stopped);
	ClassDB::bind_method(D_METHOD("set_max_age", "value"), &SnowstormCore::set_max_age);
	ClassDB::bind_method(D_METHOD("get_max_age"), &SnowstormCore::get_max_age);
	ClassDB::bind_method(D_METHOD("is_finished"), &SnowstormCore::is_finished);
	ClassDB::bind_method(D_METHOD("get_particle_count"), &SnowstormCore::get_particle_count);
	ClassDB::bind_method(D_METHOD("get_drawn"), &SnowstormCore::get_drawn);
	ClassDB::bind_method(D_METHOD("get_buffer"), &SnowstormCore::get_buffer);
	ClassDB::bind_method(D_METHOD("take_spawns"), &SnowstormCore::take_spawns);
}

} // namespace snowstorm
