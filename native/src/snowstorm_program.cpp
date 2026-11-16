#include "snowstorm_program.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

#include <algorithm>
#include <cmath>
#include <set>

using namespace godot;

namespace snowstorm {

namespace {

const char *KNOWN[] = {
	"minecraft:emitter_initialization", "minecraft:emitter_lifetime_once", "minecraft:emitter_lifetime_looping",
	"minecraft:emitter_lifetime_events", "minecraft:emitter_rate_instant", "minecraft:emitter_rate_steady",
	"minecraft:emitter_shape_point", "minecraft:emitter_shape_sphere", "minecraft:emitter_shape_disc",
	"minecraft:emitter_shape_box", "minecraft:particle_appearance_billboard", "minecraft:particle_appearance_tinting",
	"minecraft:particle_appearance_lighting", "minecraft:particle_initial_speed", "minecraft:particle_initial_spin",
	"minecraft:particle_lifetime_expression", "minecraft:particle_lifetime_events", "minecraft:particle_motion_dynamic",
	"minecraft:particle_motion_parametric", "minecraft:particle_motion_collision", "minecraft:particle_initialization",
	"cobblemon:emitter_space",
};

const char *BUILTIN_NAMES[] = {
	"particle_age", "particle_lifetime", "particle_random_1", "particle_random_2", "particle_random_3", "particle_random_4",
	"emitter_age", "emitter_lifetime", "emitter_random_1", "emitter_random_2", "emitter_random_3", "emitter_random_4",
};

std::string text(const Variant &value) {
	return std::string(String(value).utf8().get_data());
}

Dictionary part(const Dictionary &components, const char *key) {
	Variant value = components.get(key, Variant());
	return value.get_type() == Variant::DICTIONARY ? Dictionary(value) : Dictionary();
}

float number(const Variant &value, float fallback) {
	if (value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT) {
		return (float)double(value);
	}
	if (value.get_type() == Variant::BOOL) {
		return bool(value) ? 1.0f : 0.0f;
	}
	return fallback;
}

float catmull(float p0, float p1, float p2, float p3, float t) {
	return 0.5f * ((2.0f * p1) + (-p0 + p2) * t + (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t * t + (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t * t * t);
}

float clamp01(float x) {
	return std::min(std::max(x, 0.0f), 1.0f);
}

} // namespace

Color hex_colour(const Variant &source) {
	if (source.get_type() == Variant::ARRAY) {
		Array parts = source;
		return Color(number(parts[0], 1), number(parts[1], 1), number(parts[2], 1), parts.size() > 3 ? number(parts[3], 1) : 1.0f);
	}
	String raw = String(source).trim_prefix("#");
	if (raw.length() == 8) {
		return Color::html("#" + raw.substr(2) + raw.substr(0, 2));
	}
	return Color::html_is_valid("#" + raw) ? Color::html("#" + raw) : Color(1, 1, 1, 1);
}

float Curve::at(float input_value, float span) const {
	float t = span != 0.0f ? input_value / span : input_value;
	if (!chain.empty()) {
		if (t <= chain.front().time) {
			return chain.front().right_value;
		}
		for (size_t i = 0; i + 1 < chain.size(); i++) {
			const ChainKey &a = chain[i];
			const ChainKey &b = chain[i + 1];
			if (t <= b.time) {
				float width = b.time - a.time;
				float u = width > 0.0f ? (t - a.time) / width : 0.0f;
				float u2 = u * u;
				float u3 = u2 * u;
				return (2 * u3 - 3 * u2 + 1) * a.right_value + (u3 - 2 * u2 + u) * a.right_slope * width
						+ (-2 * u3 + 3 * u2) * b.left_value + (u3 - u2) * b.left_slope * width;
			}
		}
		return chain.back().left_value;
	}
	if (nodes.empty()) {
		return 0.0f;
	}
	if (type == "catmull_rom") {
		if (nodes.size() < 4) {
			return nodes[0];
		}
		int segments = (int)nodes.size() - 3;
		float x = clamp01(t) * segments;
		int i = std::min((int)x, segments - 1);
		return catmull(nodes[i], nodes[i + 1], nodes[i + 2], nodes[i + 3], x - i);
	}
	if (type == "bezier") {
		if (nodes.size() < 4) {
			return nodes[0];
		}
		float u = clamp01(t);
		float a = 1.0f - u;
		return a * a * a * nodes[0] + 3 * a * a * u * nodes[1] + 3 * a * u * u * nodes[2] + u * u * u * nodes[3];
	}
	if (nodes.size() == 1) {
		return nodes[0];
	}
	float x = clamp01(t) * (nodes.size() - 1);
	int i = std::min((int)x, (int)nodes.size() - 2);
	return nodes[i] + (nodes[i + 1] - nodes[i]) * (x - i);
}

Program SnowstormProgram::molang(const Variant &source) {
	switch (source.get_type()) {
		case Variant::NIL:
			return constant(0.0f);
		case Variant::FLOAT:
		case Variant::INT:
		case Variant::BOOL:
			return constant(number(source, 0.0f));
		case Variant::STRING: {
			Program program = compile(text(source), names);
			if (!program.error.empty()) {
				errors.push_back(String::utf8(program.error.c_str()));
			}
			return program;
		}
		default:
			errors.push_back("unsupported Molang value " + String(source));
			return constant(0.0f);
	}
}

Program3 SnowstormProgram::molang3(const Variant &source) {
	Program3 parts;
	Program *slots[3] = { &parts.x, &parts.y, &parts.z };
	for (int i = 0; i < 3; i++) {
		if (source.get_type() == Variant::ARRAY) {
			Array values = source;
			*slots[i] = i < values.size() ? molang(values[i]) : constant(0.0f);
		} else {
			*slots[i] = molang(source);
		}
	}
	return parts;
}

EventRef SnowstormProgram::event_ref(const Variant &source) const {
	EventRef names_out;
	if (source.get_type() == Variant::ARRAY) {
		Array values = source;
		for (int i = 0; i < values.size(); i++) {
			names_out.push_back(text(values[i]));
		}
	} else if (source.get_type() == Variant::STRING) {
		names_out.push_back(text(source));
	}
	return names_out;
}

std::vector<std::pair<float, EventRef>> SnowstormProgram::timeline(const Variant &source) const {
	std::vector<std::pair<float, EventRef>> entries;
	if (source.get_type() == Variant::DICTIONARY) {
		Dictionary keyed = source;
		Array keys = keyed.keys();
		for (int i = 0; i < keys.size(); i++) {
			entries.push_back({ String(keys[i]).to_float(), event_ref(keyed[keys[i]]) });
		}
	}
	std::sort(entries.begin(), entries.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
	return entries;
}

Event SnowstormProgram::parse_event(const Dictionary &data) {
	Event event;
	if (data.has("sequence") && data["sequence"].get_type() == Variant::ARRAY) {
		Array steps = data["sequence"];
		for (int i = 0; i < steps.size(); i++) {
			if (steps[i].get_type() == Variant::DICTIONARY) {
				event.sequence.push_back(parse_event(steps[i]));
			}
		}
	}
	if (data.has("randomize") && data["randomize"].get_type() == Variant::ARRAY) {
		Array options = data["randomize"];
		for (int i = 0; i < options.size(); i++) {
			if (options[i].get_type() == Variant::DICTIONARY) {
				Dictionary option = options[i];
				event.randomize.push_back({ number(option.get("weight", 1), 1.0f), parse_event(option) });
			}
		}
	}
	if (data.has("expression")) {
		event.has_expression = true;
		event.expression = molang(data["expression"]);
	}
	if (data.has("particle_effect") && data["particle_effect"].get_type() == Variant::DICTIONARY) {
		Dictionary spawn = data["particle_effect"];
		event.has_effect = true;
		event.effect = String(spawn.get("effect", ""));
		event.bound = String(spawn.get("type", "emitter")) == "emitter_bound";
		if (spawn.has("pre_effect_expression")) {
			event.has_pre_effect = true;
			event.pre_effect = molang(spawn["pre_effect_expression"]);
		}
	}
	return event;
}

String SnowstormProgram::parse(const Dictionary &data) {
	for (int i = 0; i < BUILTIN_COUNT; i++) {
		names.variable(BUILTIN_NAMES[i]);
	}
	Dictionary body = part(data, "particle_effect");
	if (body.is_empty()) {
		return "no particle_effect";
	}
	Dictionary description = part(body, "description");
	id = String(description.get("identifier", ""));
	Dictionary render = part(description, "basic_render_parameters");
	texture = String(render.get("texture", ""));
	String material_name = String(render.get("material", ""));
	material = material_name == "particles_blend" ? "blend" : (material_name == "particles_add" ? "add" : "alpha");
	Dictionary components = part(body, "components");
	Array keys = components.keys();
	for (int i = 0; i < keys.size(); i++) {
		bool known = false;
		for (const char *name : KNOWN) {
			known = known || String(keys[i]) == name;
		}
		if (!known) {
			unsupported.push_back(String(keys[i]));
		}
	}
	Dictionary raw_curves = part(body, "curves");
	Array curve_names = raw_curves.keys();
	for (int i = 0; i < curve_names.size(); i++) {
		Dictionary raw = raw_curves[curve_names[i]];
		String key = curve_names[i];
		Curve curve;
		curve.slot = names.variable(text(key.contains(".") ? key.get_slice(".", 1) : key));
		curve.type = text(raw.get("type", "linear"));
		curve.input = molang(raw.get("input", 0));
		curve.range = molang(raw.get("horizontal_range", 1));
		Variant nodes = raw.get("nodes", Array());
		if (nodes.get_type() == Variant::ARRAY) {
			Array values = nodes;
			for (int n = 0; n < values.size(); n++) {
				curve.nodes.push_back(number(values[n], 0.0f));
			}
		} else if (nodes.get_type() == Variant::DICTIONARY) {
			Dictionary keyed = nodes;
			Array times = keyed.keys();
			for (int n = 0; n < times.size(); n++) {
				Dictionary node = keyed[times[n]];
				ChainKey chain_key;
				chain_key.time = String(times[n]).to_float();
				float value = number(node.get("value", 0), 0.0f);
				float slope = number(node.get("slope", 0), 0.0f);
				chain_key.left_value = number(node.get("left_value", value), value);
				chain_key.right_value = number(node.get("right_value", value), value);
				chain_key.left_slope = number(node.get("left_slope", slope), slope);
				chain_key.right_slope = number(node.get("right_slope", slope), slope);
				curve.chain.push_back(chain_key);
			}
			std::sort(curve.chain.begin(), curve.chain.end(), [](const ChainKey &a, const ChainKey &b) { return a.time < b.time; });
		}
		plan.curves.push_back(curve);
	}
	build(components);
	Dictionary raw_events = part(body, "events");
	Array event_names = raw_events.keys();
	for (int i = 0; i < event_names.size(); i++) {
		if (raw_events[event_names[i]].get_type() == Variant::DICTIONARY) {
			events[text(event_names[i])] = parse_event(raw_events[event_names[i]]);
		}
	}
	for (const auto &entry : names.v) {
		if (entry.first.rfind("target_", 0) == 0 || entry.first.rfind("entity_", 0) == 0) {
			context_slots.push_back(entry.second);
		}
	}
	mark_per_particle();
	return "";
}

void SnowstormProgram::build(const Dictionary &components) {
	Plan &p = plan;
	Dictionary init = part(components, "minecraft:emitter_initialization");
	if (init.has("creation_expression")) {
		p.has_creation = true;
		p.creation = molang(init["creation_expression"]);
	}
	if (init.has("per_update_expression")) {
		p.has_per_update = true;
		p.per_update = molang(init["per_update_expression"]);
	}
	if (components.has("minecraft:emitter_lifetime_looping")) {
		Dictionary looping = part(components, "minecraft:emitter_lifetime_looping");
		p.looping = true;
		p.has_active_time = true;
		p.active_time = molang(looping.get("active_time", 10));
		p.sleep_time = molang(looping.get("sleep_time", 0));
	} else if (components.has("minecraft:emitter_lifetime_once")) {
		p.has_active_time = true;
		p.active_time = molang(part(components, "minecraft:emitter_lifetime_once").get("active_time", 10));
	}
	Dictionary emitter_events = part(components, "minecraft:emitter_lifetime_events");
	p.emitter_timeline = timeline(emitter_events.get("timeline", Variant()));
	p.emitter_creation = event_ref(emitter_events.get("creation_event", Variant()));
	p.emitter_expiration = event_ref(emitter_events.get("expiration_event", Variant()));
	if (components.has("minecraft:emitter_rate_instant")) {
		p.instant = true;
		p.num_particles = molang(part(components, "minecraft:emitter_rate_instant").get("num_particles", 10));
	} else if (components.has("minecraft:emitter_rate_steady")) {
		Dictionary rate = part(components, "minecraft:emitter_rate_steady");
		p.steady = true;
		p.spawn_rate = molang(rate.get("spawn_rate", 1));
		p.max_particles = molang(rate.get("max_particles", 50));
	}
	const std::pair<const char *, Shape> SHAPES[] = {
		{ "minecraft:emitter_shape_point", Shape::POINT }, { "minecraft:emitter_shape_sphere", Shape::SPHERE },
		{ "minecraft:emitter_shape_disc", Shape::DISC }, { "minecraft:emitter_shape_box", Shape::BOX },
	};
	for (const auto &entry : SHAPES) {
		if (!components.has(entry.first)) {
			continue;
		}
		Dictionary shape = part(components, entry.first);
		p.shape = entry.second;
		Array zero;
		zero.push_back(0);
		zero.push_back(0);
		zero.push_back(0);
		Array one;
		one.push_back(1);
		one.push_back(1);
		one.push_back(1);
		p.offset = molang3(shape.get("offset", zero));
		p.radius = molang(shape.get("radius", 1));
		p.surface_only = bool(shape.get("surface_only", false));
		p.half_dimensions = molang3(shape.get("half_dimensions", one));
		Variant normal = shape.get("plane_normal", "y");
		if (normal.get_type() == Variant::STRING) {
			String axis = normal;
			Array values;
			values.push_back(axis == "x" ? 1 : 0);
			values.push_back(axis == "x" || axis == "z" ? 0 : 1);
			values.push_back(axis == "z" ? 1 : 0);
			normal = values;
		}
		p.plane_normal = molang3(normal);
		Variant direction = shape.get("direction", entry.second == Shape::POINT ? Variant(zero) : Variant("outwards"));
		if (direction.get_type() == Variant::STRING) {
			p.direction_mode = String(direction) == "inwards" ? Direction::INWARDS : Direction::OUTWARDS;
		} else {
			p.direction = molang3(direction);
		}
		break;
	}
	Dictionary lifetime = part(components, "minecraft:particle_lifetime_expression");
	if (lifetime.has("max_lifetime")) {
		p.has_max_lifetime = true;
		p.max_lifetime = molang(lifetime["max_lifetime"]);
	}
	if (lifetime.has("expiration_expression")) {
		p.has_expiration = true;
		p.expiration = molang(lifetime["expiration_expression"]);
	}
	Variant speed = components.get("minecraft:particle_initial_speed", 0);
	if (speed.get_type() == Variant::ARRAY) {
		p.speed_is_vector = true;
		p.speed_vector = molang3(speed);
	} else {
		p.speed = molang(speed);
	}
	Dictionary spin = part(components, "minecraft:particle_initial_spin");
	p.spin = molang(spin.get("rotation", 0));
	p.spin_rate = molang(spin.get("rotation_rate", 0));
	Dictionary dynamic = part(components, "minecraft:particle_motion_dynamic");
	Dictionary parametric = part(components, "minecraft:particle_motion_parametric");
	p.dynamic = components.has("minecraft:particle_motion_dynamic") || parametric.is_empty();
	Array zero;
	zero.push_back(0);
	zero.push_back(0);
	zero.push_back(0);
	p.acceleration = molang3(dynamic.get("linear_acceleration", zero));
	p.drag = molang(dynamic.get("linear_drag_coefficient", 0));
	p.spin_acceleration = molang(dynamic.get("rotation_acceleration", 0));
	p.spin_drag = molang(dynamic.get("rotation_drag_coefficient", 0));
	if (parametric.has("relative_position")) {
		p.has_relative_position = true;
		p.relative_position = molang3(parametric["relative_position"]);
	}
	if (parametric.has("direction")) {
		p.has_parametric_direction = true;
		p.parametric_direction = molang3(parametric["direction"]);
	}
	if (parametric.has("rotation")) {
		p.has_parametric_rotation = true;
		p.parametric_rotation = molang(parametric["rotation"]);
	}
	Dictionary collision = part(components, "minecraft:particle_motion_collision");
	if (!collision.is_empty()) {
		p.collision = true;
		p.collision_enabled = molang(collision.get("enabled", 1));
		p.collision_radius = molang(collision.get("collision_radius", 0.1));
		p.collision_drag = molang(collision.get("collision_drag", 0));
		p.restitution = molang(collision.get("coefficient_of_restitution", 0));
		p.expire_on_contact = bool(collision.get("expire_on_contact", false));
	}
	Dictionary billboard = part(components, "minecraft:particle_appearance_billboard");
	Variant size = billboard.get("size", Variant());
	if (size.get_type() == Variant::ARRAY) {
		Array sizes = size;
		p.width = sizes.size() > 0 ? molang(sizes[0]) : constant(0.1f);
		p.height = sizes.size() > 1 ? molang(sizes[1]) : p.width;
	} else if (size.get_type() == Variant::NIL) {
		p.width = constant(0.1f);
		p.height = constant(0.1f);
	} else {
		p.width = molang(size);
		p.height = molang(size);
	}
	String facing = billboard.get("facing_camera_mode", "rotate_xyz");
	const std::pair<const char *, Facing> FACINGS[] = {
		{ "rotate_xyz", Facing::ROTATE_XYZ }, { "rotate_y", Facing::ROTATE_Y }, { "lookat_xyz", Facing::LOOKAT_XYZ },
		{ "lookat_y", Facing::LOOKAT_Y }, { "lookat_direction", Facing::LOOKAT_DIRECTION }, { "direction_x", Facing::DIRECTION_X },
		{ "direction_y", Facing::DIRECTION_Y }, { "direction_z", Facing::DIRECTION_Z }, { "emitter_transform_xy", Facing::EMITTER_XY },
		{ "emitter_transform_xz", Facing::EMITTER_XZ }, { "emitter_transform_yz", Facing::EMITTER_YZ },
	};
	for (const auto &entry : FACINGS) {
		if (facing == entry.first) {
			p.facing = entry.second;
		}
	}
	p.camera_facing = p.facing == Facing::ROTATE_XYZ || p.facing == Facing::ROTATE_Y || p.facing == Facing::LOOKAT_XYZ || p.facing == Facing::LOOKAT_Y;
	Variant direction_settings = billboard.get("direction", Variant());
	if (direction_settings.get_type() == Variant::DICTIONARY && String(Dictionary(direction_settings).get("mode", "")) == "custom") {
		Array forward;
		forward.push_back(1);
		forward.push_back(0);
		forward.push_back(0);
		p.has_custom_direction = true;
		p.custom_direction = molang3(Dictionary(direction_settings).get("custom_direction", forward));
	}
	Variant uv = billboard.get("uv", Variant());
	if (uv.get_type() == Variant::DICTIONARY && !Dictionary(uv).is_empty()) {
		Dictionary mapping = uv;
		p.texture_size = Vector2(number(mapping.get("texture_width", 1), 1), number(mapping.get("texture_height", 1), 1));
		if (mapping.has("flipbook")) {
			Dictionary book = mapping["flipbook"];
			p.uv = Uv::FLIPBOOK;
			Variant base = book.get("base_UV", Variant());
			Array corner = base.get_type() == Variant::ARRAY ? Array(base) : Array();
			p.uv_x = corner.size() > 0 ? molang(corner[0]) : constant(0);
			p.uv_y = corner.size() > 1 ? molang(corner[1]) : constant(0);
			Variant frame = book.get("size_UV", Variant());
			Variant step = book.get("step_UV", Variant());
			if (frame.get_type() == Variant::ARRAY && Array(frame).size() >= 2) {
				p.frame_size = Vector2(number(Array(frame)[0], 1), number(Array(frame)[1], 1));
			} else {
				p.frame_size = p.texture_size;
			}
			if (step.get_type() == Variant::ARRAY && Array(step).size() >= 2) {
				p.frame_step = Vector2(number(Array(step)[0], 0), number(Array(step)[1], 0));
			}
			p.frames_per_second = number(book.get("frames_per_second", 8), 8);
			p.max_frame = molang(book.get("max_frame", 1));
			p.stretch_to_lifetime = bool(book.get("stretch_to_lifetime", false));
			p.loop = bool(book.get("loop", false));
		} else {
			p.uv = Uv::FIXED;
			Variant corner = mapping.get("uv", Variant());
			Variant extent = mapping.get("uv_size", Variant());
			Array corners = corner.get_type() == Variant::ARRAY ? Array(corner) : Array();
			Array extents = extent.get_type() == Variant::ARRAY ? Array(extent) : Array();
			p.uv_x = corners.size() > 0 ? molang(corners[0]) : constant(0);
			p.uv_y = corners.size() > 1 ? molang(corners[1]) : constant(0);
			p.uv_w = extents.size() > 0 ? molang(extents[0]) : constant(p.texture_size.x);
			p.uv_h = extents.size() > 1 ? molang(extents[1]) : constant(p.texture_size.y);
		}
	}
	Variant colour = part(components, "minecraft:particle_appearance_tinting").get("color", Variant());
	if (colour.get_type() == Variant::STRING) {
		p.tint = Tint::FIXED;
		p.tint_colour = hex_colour(colour);
	} else if (colour.get_type() == Variant::ARRAY) {
		Array channels = colour;
		p.tint = Tint::CHANNELS;
		p.tint_r = channels.size() > 0 ? molang(channels[0]) : constant(1);
		p.tint_g = channels.size() > 1 ? molang(channels[1]) : constant(1);
		p.tint_b = channels.size() > 2 ? molang(channels[2]) : constant(1);
		p.tint_a = channels.size() > 3 ? molang(channels[3]) : constant(1);
	} else if (colour.get_type() == Variant::DICTIONARY) {
		Dictionary gradient_data = colour;
		Variant gradient = gradient_data.get("gradient", Variant());
		if (gradient.get_type() == Variant::ARRAY) {
			Array stops = gradient;
			for (int i = 0; i < stops.size(); i++) {
				p.gradient.push_back({ (float)i / std::max(1, (int)stops.size() - 1), hex_colour(stops[i]) });
			}
		} else if (gradient.get_type() == Variant::DICTIONARY) {
			Dictionary stops = gradient;
			Array keys = stops.keys();
			for (int i = 0; i < keys.size(); i++) {
				p.gradient.push_back({ String(keys[i]).to_float(), hex_colour(stops[keys[i]]) });
			}
		}
		std::sort(p.gradient.begin(), p.gradient.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
		p.interpolant = molang(gradient_data.get("interpolant", 0));
		p.tint = p.gradient.empty() ? Tint::NONE : Tint::GRADIENT;
	}
	Dictionary particle_events = part(components, "minecraft:particle_lifetime_events");
	p.particle_timeline = timeline(particle_events.get("timeline", Variant()));
	p.particle_creation = event_ref(particle_events.get("creation_event", Variant()));
	p.particle_expiration = event_ref(particle_events.get("expiration_event", Variant()));
	Dictionary particle_init = part(components, "minecraft:particle_initialization");
	if (particle_init.has("per_update_expression")) {
		p.has_particle_update = true;
		p.particle_update = molang(particle_init["per_update_expression"]);
	}
	if (particle_init.has("per_render_expression")) {
		p.has_particle_render = true;
		p.particle_render = molang(particle_init["per_render_expression"]);
	}
	p.scale_with_entity = String(part(components, "cobblemon:emitter_space").get("scaling", "")) == "entity";
}

void SnowstormProgram::collect_programs(std::vector<Program *> &out) {
	Plan &p = plan;
	Program *singles[] = {
		&p.creation, &p.per_update, &p.active_time, &p.sleep_time, &p.num_particles, &p.spawn_rate, &p.max_particles,
		&p.radius, &p.max_lifetime, &p.expiration, &p.speed, &p.spin, &p.spin_rate, &p.drag, &p.spin_acceleration,
		&p.spin_drag, &p.parametric_rotation, &p.collision_enabled, &p.collision_radius, &p.collision_drag,
		&p.restitution, &p.width, &p.height, &p.uv_x, &p.uv_y, &p.uv_w, &p.uv_h, &p.max_frame, &p.tint_r, &p.tint_g,
		&p.tint_b, &p.tint_a, &p.interpolant, &p.particle_update, &p.particle_render,
	};
	for (Program *program : singles) {
		out.push_back(program);
	}
	Program3 *triples[] = {
		&p.offset, &p.plane_normal, &p.half_dimensions, &p.direction, &p.speed_vector, &p.acceleration,
		&p.relative_position, &p.parametric_direction, &p.custom_direction,
	};
	for (Program3 *triple : triples) {
		out.push_back(&triple->x);
		out.push_back(&triple->y);
		out.push_back(&triple->z);
	}
	for (Curve &curve : p.curves) {
		out.push_back(&curve.input);
		out.push_back(&curve.range);
	}
}

// Programs whose value can't differ between particles in one frame are evaluated once per
// frame. Curves read particle variables, and per-particle expressions can assign variables,
// so anything reading a curve or such a variable varies too.
void SnowstormProgram::mark_per_particle() {
	std::set<int> varying = { PARTICLE_AGE, PARTICLE_LIFETIME, PARTICLE_RANDOM_1, PARTICLE_RANDOM_2, PARTICLE_RANDOM_3, PARTICLE_RANDOM_4 };
	for (const Curve &curve : plan.curves) {
		varying.insert(curve.slot);
	}
	for (Program *program : { &plan.particle_update, &plan.particle_render }) {
		varying.insert(program->writes.begin(), program->writes.end());
	}
	std::vector<Program *> programs;
	collect_programs(programs);
	for (Program *program : programs) {
		program->per_particle = program->uses_random;
		for (int slot : program->reads) {
			program->per_particle = program->per_particle || varying.count(slot) > 0;
		}
	}
}

PackedStringArray SnowstormProgram::get_spawned_effects() const {
	PackedStringArray found;
	std::vector<const Event *> pending;
	for (const auto &entry : events) {
		pending.push_back(&entry.second);
	}
	while (!pending.empty()) {
		const Event *event = pending.back();
		pending.pop_back();
		if (event->has_effect) {
			found.push_back(event->effect);
		}
		for (const Event &step : event->sequence) {
			pending.push_back(&step);
		}
		for (const auto &option : event->randomize) {
			pending.push_back(&option.second);
		}
	}
	return found;
}

Dictionary SnowstormProgram::evaluate(const String &source, const Dictionary &v, const Dictionary &q, int64_t seed) {
	Names names;
	Program program = compile(text(source), names);
	std::vector<float> variables(names.v.size(), 0.0f);
	std::vector<float> queries(names.q.size() + 1, 0.0f);
	for (const auto &entry : names.v) {
		variables[entry.second] = number(v.get(String::utf8(entry.first.c_str()), 0), 0.0f);
	}
	for (const auto &entry : names.q) {
		queries[entry.second] = number(q.get(String::utf8(entry.first.c_str()), 0), 0.0f);
	}
	Rng rng;
	rng.seed((uint64_t)seed);
	variables.push_back(0.0f);
	float value = program.run(variables.data(), queries.data(), rng);
	Dictionary written;
	for (const auto &entry : names.v) {
		written[String::utf8(entry.first.c_str())] = variables[entry.second];
	}
	Dictionary result;
	result["value"] = value;
	result["error"] = String::utf8(program.error.c_str());
	result["v"] = written;
	return result;
}

float SnowstormProgram::curve_at(float input, float span) const {
	return plan.curves.empty() ? 0.0f : plan.curves[0].at(input, span);
}

void SnowstormProgram::_bind_methods() {
	ClassDB::bind_method(D_METHOD("parse", "data"), &SnowstormProgram::parse);
	ClassDB::bind_method(D_METHOD("get_id"), &SnowstormProgram::get_id);
	ClassDB::bind_method(D_METHOD("get_texture"), &SnowstormProgram::get_texture);
	ClassDB::bind_method(D_METHOD("get_material"), &SnowstormProgram::get_material);
	ClassDB::bind_method(D_METHOD("get_errors"), &SnowstormProgram::get_errors);
	ClassDB::bind_method(D_METHOD("get_unsupported"), &SnowstormProgram::get_unsupported);
	ClassDB::bind_method(D_METHOD("get_spawned_effects"), &SnowstormProgram::get_spawned_effects);
	ClassDB::bind_method(D_METHOD("curve_at", "input", "span"), &SnowstormProgram::curve_at);
	ClassDB::bind_static_method("SnowstormProgram", D_METHOD("evaluate", "source", "v", "q", "seed"), &SnowstormProgram::evaluate);
	ClassDB::bind_static_method("SnowstormProgram", D_METHOD("parse_colour", "source"), &SnowstormProgram::parse_colour);
}

} // namespace snowstorm
