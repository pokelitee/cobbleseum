class_name SnowstormEmitter
extends MultiMeshInstance3D
## Runs one SnowstormEffect (concepts_brief.md §12.5, Cobblemon's move effects): spawns,
## moves and draws its particles, one MultiMesh of camera-facing quads, stepped by video
## frame with a seeded random stream so renders are identical.
## Coordinates: Bedrock blocks are metres. Each emitter has a frame (`frame`) whose -Z points
## at its target; shapes, directions and accelerations are in that frame. Cobblemon's
## v.target_delta* variables hold the target's offset with X and Z negated, which is how its
## effects expect them (their beams aim along -target_deltax, target_deltay, -target_deltaz).

const MAX_AGE := 6.0
const CAPACITY := 64
const GROUND := 0.0
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, %s;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float cutout = 0.0;
uniform float brightness = 1.0;
varying vec4 rect;
void vertex() {
	rect = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 c = texture(tex, rect.xy + UV * rect.zw) * COLOR;
	if (c.a <= cutout) {
		discard;
	}
	ALBEDO = c.rgb * brightness;
	ALPHA = c.a;
}
"""

## Emits this many particles at most, whatever the effect asks.
const MAX_PARTICLES := 400

var effect: SnowstormEffect
## Spawns the effects that events name: an object with spawn_child(id, transform, vars, parent).
var library: Object
## Effect time per video-frame second; the move fit uses it to squeeze Cobblemon's slower
## timings into the real-time battle.
var speed := 1.0
## The emitter's position and frame in world space.
var frame := Transform3D.IDENTITY
## When valid, called each frame for the emitter's new frame (an emitter riding a projectile
## or bound to its parent).
var follow := Callable()
## Set to stop emitting; the emitter frees itself once its particles are gone.
var stopped := false
var max_age := MAX_AGE
## Multiplies sizes and offsets for effects with cobblemon:emitter_space scaling "entity".
var entity_scale := 1.0

var v: Dictionary = {}
var q: Dictionary = {}
var math := ParticleMath.new()

var _particles: Array[Dictionary] = []
var _age := 0.0
var _loop_age := 0.0
var _active_time := 1.0
var _sleep_time := 0.0
var _looping := false
var _emitted := false
var _expired := false
var _spawn_debt := 0.0
var _scale := 1.0
var _timeline: Array = []
var _timeline_index := 0
var _gradient: Array = []
var _camera_basis := Basis.IDENTITY
var _camera_position := Vector3.ZERO


## Starts the effect at `at` with the given variables (set after its creation expression, so
## Cobblemon's target variables win over an effect's defaults) and queries.
func start(source: SnowstormEffect, at: Transform3D, seed_value: int, vars: Dictionary, queries: Dictionary,
		shader_material: ShaderMaterial) -> void:
	effect = source
	frame = at
	math.rng.seed = seed_value
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for key: String in effect.names:
		var name := key.substr(2)
		if key.begins_with("v."):
			v[name] = 0.0
		else:
			q[name] = 0.0
	q.merge(queries, true)
	for i in 4:
		v["emitter_random_%d" % (i + 1)] = math.rng.randf()
	v.emitter_age = 0.0
	v.emitter_lifetime = 0.0
	var space := effect.get_component("cobblemon:emitter_space")
	_scale = entity_scale if space.get("scaling", "") == "entity" else 1.0
	var init := effect.get_component("minecraft:emitter_initialization")
	if init.has("creation_expression"):
		effect.molang(init.creation_expression).evaluate(v, q, math)
	var randoms := [v.emitter_random_1, v.emitter_random_2, v.emitter_random_3, v.emitter_random_4]
	v.merge(vars, true)
	for i in 4:
		v["emitter_random_%d" % (i + 1)] = randoms[i]
	if effect.has("minecraft:emitter_lifetime_looping"):
		var looping := effect.get_component("minecraft:emitter_lifetime_looping")
		_looping = true
		_active_time = _eval(looping.get("active_time", 10))
		_sleep_time = _eval(looping.get("sleep_time", 0))
	elif effect.has("minecraft:emitter_lifetime_once"):
		_active_time = _eval(effect.get_component("minecraft:emitter_lifetime_once").get("active_time", 10))
	else:
		_active_time = max_age
	v.emitter_lifetime = _active_time
	var events := effect.get_component("minecraft:emitter_lifetime_events")
	_timeline = _sorted_timeline(events.get("timeline", {}))
	_gradient = _gradient_stops()
	var mesh := QuadMesh.new()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	custom_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 80, 200))
	material_override = shader_material
	_fire(events.get("creation_event", null), frame.origin, null)


func is_finished() -> bool:
	return (stopped or _expired or _age >= max_age) and _particles.is_empty()


## Advances the effect by `delta` seconds of video and redraws it.
func step(delta: float) -> void:
	var dt := delta * speed
	if follow.is_valid():
		var moved: Variant = follow.call()
		if moved is Transform3D:
			frame = moved
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		_camera_basis = camera.global_transform.basis
		_camera_position = camera.global_position
	if _age >= max_age:
		stopped = true
	v.emitter_age = _loop_age
	var init := effect.get_component("minecraft:emitter_initialization")
	if init.has("per_update_expression"):
		effect.molang(init.per_update_expression).evaluate(v, q, math)
	var active := not stopped and not _expired and _loop_age < _active_time
	if active:
		_emit(dt)
	while _timeline_index < _timeline.size() and _timeline[_timeline_index][0] <= _loop_age + dt:
		_fire(_timeline[_timeline_index][1], frame.origin, null)
		_timeline_index += 1
	_loop_age += dt
	_age += dt
	if _loop_age >= _active_time and not _expired:
		if _looping and not stopped:
			if _loop_age >= _active_time + _sleep_time:
				_loop_age = 0.0
				_emitted = false
				_timeline_index = 0
		else:
			_expired = true
			_fire(effect.get_component("minecraft:emitter_lifetime_events").get("expiration_event", null), frame.origin, null)
	_update_particles(dt)


func _eval(source: Variant) -> float:
	return effect.molang(source).evaluate(v, q, math)


func _emit(dt: float) -> void:
	var count := 0
	if effect.has("minecraft:emitter_rate_instant"):
		if not _emitted:
			count = int(_eval(effect.get_component("minecraft:emitter_rate_instant").get("num_particles", 10)))
		_emitted = true
	elif effect.has("minecraft:emitter_rate_steady"):
		var rate := effect.get_component("minecraft:emitter_rate_steady")
		_spawn_debt += _eval(rate.get("spawn_rate", 1)) * dt
		count = int(_spawn_debt)
		_spawn_debt -= count
		count = mini(count, int(_eval(rate.get("max_particles", 50))) - _particles.size())
	count = mini(count, MAX_PARTICLES - _particles.size())
	for i in count:
		_spawn_particle()


func _set_particle_vars(p: Dictionary) -> void:
	v.particle_age = p.age
	v.particle_lifetime = p.lifetime
	var r: Array = p.random
	v.particle_random_1 = r[0]
	v.particle_random_2 = r[1]
	v.particle_random_3 = r[2]
	v.particle_random_4 = r[3]


func _spawn_particle() -> void:
	var rng := math.rng
	var p := {"age": 0.0, "lifetime": 1.0, "random": [rng.randf(), rng.randf(), rng.randf(), rng.randf()],
		"rotation": 0.0, "spin": 0.0, "direction": Vector3.RIGHT, "timeline": 0}
	_set_particle_vars(p)
	var lifetime := effect.get_component("minecraft:particle_lifetime_expression")
	if lifetime.has("max_lifetime"):
		p.lifetime = maxf(0.001, _eval(lifetime.max_lifetime))
	v.particle_lifetime = p.lifetime
	var placed := _shape_point()
	var offset: Vector3 = placed[0] * _scale
	var direction: Vector3 = placed[1]
	p.position = frame.origin + frame.basis * offset
	var speed_source: Variant = effect.components.get("minecraft:particle_initial_speed", 0)
	if speed_source is Array:
		var parts := effect.molang3(speed_source)
		p.velocity = frame.basis * Vector3(parts[0].evaluate(v, q, math), parts[1].evaluate(v, q, math), parts[2].evaluate(v, q, math)) * _scale
	else:
		p.velocity = frame.basis * (direction.normalized() * _eval(speed_source) * _scale)
	var spin := effect.get_component("minecraft:particle_initial_spin")
	p.rotation = _eval(spin.get("rotation", 0))
	p.spin = _eval(spin.get("rotation_rate", 0))
	if p.velocity.length_squared() > 0.000001:
		p.direction = p.velocity.normalized()
	var init := effect.get_component("minecraft:particle_initialization")
	if init.has("per_render_expression"):
		_eval(init.per_render_expression)
	_particles.append(p)
	var events := effect.get_component("minecraft:particle_lifetime_events")
	_fire(events.get("creation_event", null), p.position, p)


## A spawn point and direction in the emitter's frame: [offset, direction].
func _shape_point() -> Array:
	var rng := math.rng
	for kind in ["point", "sphere", "disc", "box"]:
		var key: String = "minecraft:emitter_shape_" + kind
		if not effect.has(key):
			continue
		var shape := effect.get_component(key)
		var centre := _vec3(shape.get("offset", [0, 0, 0]))
		var local := Vector3.ZERO
		match kind:
			"sphere":
				var radius := _eval(shape.get("radius", 1))
				var unit := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				while unit.length_squared() > 1.0 or unit.length_squared() < 0.0001:
					unit = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				local = unit.normalized() * radius if shape.get("surface_only", false) else unit * radius
			"disc":
				var radius := _eval(shape.get("radius", 1))
				var angle := rng.randf() * TAU
				var distance := radius if shape.get("surface_only", false) else radius * sqrt(rng.randf())
				var normal := _plane_normal(shape.get("plane_normal", "y"))
				var u := normal.cross(Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT).normalized()
				var w := normal.cross(u)
				local = (u * cos(angle) + w * sin(angle)) * distance
			"box":
				var half := _vec3(shape.get("half_dimensions", [1, 1, 1]))
				local = Vector3(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y), rng.randf_range(-half.z, half.z))
				if shape.get("surface_only", false):
					var axis := rng.randi_range(0, 2)
					local[axis] = half[axis] * (1.0 if rng.randf() < 0.5 else -1.0)
		var direction_source: Variant = shape.get("direction", "outwards" if kind != "point" else [0, 0, 0])
		var direction: Vector3
		if direction_source is String:
			direction = local.normalized() * (-1.0 if direction_source == "inwards" else 1.0)
		else:
			direction = _vec3(direction_source)
		return [centre + local, direction]
	return [Vector3.ZERO, Vector3.ZERO]


func _plane_normal(source: Variant) -> Vector3:
	if source is String:
		return {"x": Vector3.RIGHT, "z": Vector3.BACK}.get(source, Vector3.UP)
	var normal := _vec3(source)
	return normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP


func _vec3(source: Variant) -> Vector3:
	var parts := effect.molang3(source)
	return Vector3(parts[0].evaluate(v, q, math), parts[1].evaluate(v, q, math), parts[2].evaluate(v, q, math))


func _update_particles(dt: float) -> void:
	var dynamic := effect.get_component("minecraft:particle_motion_dynamic")
	var parametric := effect.get_component("minecraft:particle_motion_parametric")
	var collision := effect.get_component("minecraft:particle_motion_collision")
	var lifetime := effect.get_component("minecraft:particle_lifetime_expression")
	var events := effect.get_component("minecraft:particle_lifetime_events")
	var particle_timeline := _sorted_timeline(events.get("timeline", {}))
	var init := effect.get_component("minecraft:particle_initialization")
	var shown := 0
	var survivors: Array[Dictionary] = []
	for p in _particles:
		_set_particle_vars(p)
		for name: String in effect.curves:
			v[name] = effect.curve_value(effect.curves[name], v, q, math)
		if init.has("per_update_expression"):
			_eval(init.per_update_expression)
		if lifetime.has("expiration_expression") and _eval(lifetime.expiration_expression) != 0.0:
			_fire(events.get("expiration_event", null), p.position, p)
			continue
		if not dynamic.is_empty() or parametric.is_empty():
			var acceleration := frame.basis * _vec3(dynamic.get("linear_acceleration", [0, 0, 0])) * _scale
			var drag := _eval(dynamic.get("linear_drag_coefficient", 0))
			p.velocity += (acceleration - drag * (p.velocity as Vector3)) * dt
			p.position += p.velocity * dt
			var spin_acceleration := _eval(dynamic.get("rotation_acceleration", 0))
			var spin_drag := _eval(dynamic.get("rotation_drag_coefficient", 0))
			p.spin += (spin_acceleration - spin_drag * float(p.spin)) * dt
			p.rotation += p.spin * dt
		if not parametric.is_empty():
			if parametric.has("relative_position"):
				p.position = frame.origin + frame.basis * _vec3(parametric.relative_position) * _scale
			if parametric.has("direction"):
				var heading := frame.basis * _vec3(parametric.direction)
				if heading.length_squared() > 0.000001:
					p.direction = heading.normalized()
			if parametric.has("rotation"):
				p.rotation = _eval(parametric.rotation)
		if not collision.is_empty() and _eval(collision.get("enabled", 1)) != 0.0:
			var radius := _eval(collision.get("collision_radius", 0.1))
			if p.position.y < GROUND + radius:
				if collision.get("expire_on_contact", false):
					_fire(events.get("expiration_event", null), p.position, p)
					continue
				p.position.y = GROUND + radius
				if p.velocity.y < 0.0:
					p.velocity.y = -p.velocity.y * _eval(collision.get("coefficient_of_restitution", 0))
				var flat := Vector2(p.velocity.x, p.velocity.z)
				var slowed := maxf(0.0, flat.length() - _eval(collision.get("collision_drag", 0)) * dt)
				flat = flat.normalized() * slowed if flat.length() > 0.0 else flat
				p.velocity = Vector3(flat.x, p.velocity.y, flat.y)
		var velocity: Vector3 = p.velocity
		if velocity.length_squared() > 0.0001 and parametric.is_empty():
			p.direction = velocity.normalized()
		while int(p.timeline) < particle_timeline.size() and particle_timeline[p.timeline][0] <= p.age + dt:
			_fire(particle_timeline[p.timeline][1], p.position, p)
			p.timeline += 1
		if shown < MAX_PARTICLES:
			_draw(p, shown)
			shown += 1
		p.age += dt
		if p.age >= p.lifetime:
			_fire(events.get("expiration_event", null), p.position, p)
			continue
		survivors.append(p)
	_particles = survivors
	multimesh.visible_instance_count = shown


func _draw(p: Dictionary, index: int) -> void:
	if index >= multimesh.instance_count:
		var grown := multimesh.instance_count * 2
		var keep := multimesh.visible_instance_count
		multimesh.instance_count = grown
		multimesh.visible_instance_count = keep
	var billboard := effect.get_component("minecraft:particle_appearance_billboard")
	var size: Variant = billboard.get("size", [0.1, 0.1])
	var width := effect.molang(size[0] if size is Array else size).evaluate(v, q, math) * 2.0 * _scale
	var height := effect.molang(size[1] if size is Array and size.size() > 1 else size).evaluate(v, q, math) * 2.0 * _scale
	var axes := _facing(billboard, p)
	var right: Vector3 = axes[0]
	var up: Vector3 = axes[1]
	var normal: Vector3 = axes[2]
	var angle := deg_to_rad(float(p.rotation))
	if angle != 0.0:
		var c := cos(angle)
		var s := sin(angle)
		var turned := right * c + up * s
		up = -right * s + up * c
		right = turned
	var placed := Transform3D(Basis(right * width, up * height, normal), p.position)
	multimesh.set_instance_transform(index, placed)
	multimesh.set_instance_color(index, _tint())
	multimesh.set_instance_custom_data(index, _uv(billboard.get("uv", {}), p))


## [right, up, normal] for a billboard's facing mode.
func _facing(billboard: Dictionary, p: Dictionary) -> Array:
	var mode: String = billboard.get("facing_camera_mode", "rotate_xyz")
	var toward_camera := (_camera_position - (p.position as Vector3))
	toward_camera = toward_camera.normalized() if toward_camera.length_squared() > 0.0 else _camera_basis.z
	match mode:
		"rotate_y", "lookat_y":
			var flat := Vector3(toward_camera.x, 0, toward_camera.z)
			flat = flat.normalized() if flat.length_squared() > 0.0 else Vector3.BACK
			return [Vector3.UP.cross(flat), Vector3.UP, flat]
		"lookat_xyz":
			var right := Vector3.UP.cross(toward_camera)
			right = right.normalized() if right.length_squared() > 0.0001 else _camera_basis.x
			return [right, toward_camera.cross(right), toward_camera]
		"lookat_direction", "direction_x", "direction_y", "direction_z":
			var direction := _billboard_direction(billboard, p)
			var normal := toward_camera - direction * toward_camera.dot(direction)
			normal = normal.normalized() if normal.length_squared() > 0.0001 else _camera_basis.z
			match mode:
				"direction_y":
					return [direction.cross(normal), direction, normal]
				"direction_z":
					var right := Vector3.UP.cross(direction)
					right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
					return [right, direction.cross(right), direction]
				_:
					return [direction, normal.cross(direction), normal]
		"emitter_transform_xy":
			return [frame.basis.x, frame.basis.y, frame.basis.z]
		"emitter_transform_xz":
			return [frame.basis.x, frame.basis.z, -frame.basis.y]
		"emitter_transform_yz":
			return [frame.basis.z, frame.basis.y, frame.basis.x]
		_:
			return [_camera_basis.x, _camera_basis.y, _camera_basis.z]


func _billboard_direction(billboard: Dictionary, p: Dictionary) -> Vector3:
	var settings: Variant = billboard.get("direction", {})
	if settings is Dictionary and settings.get("mode", "") == "custom":
		var custom := frame.basis * _vec3(settings.get("custom_direction", [1, 0, 0]))
		if custom.length_squared() > 0.000001:
			return custom.normalized()
	return p.direction


func _tint() -> Color:
	var tinting := effect.get_component("minecraft:particle_appearance_tinting")
	var colour: Variant = tinting.get("color", null)
	if colour == null:
		return Color.WHITE
	if colour is String:
		return _hex(colour)
	if colour is Array:
		var parts: Array = colour
		var values: Array[float] = []
		for i in 4:
			values.append(effect.molang(parts[i]).evaluate(v, q, math) if i < parts.size() else 1.0)
		return Color(values[0], values[1], values[2], values[3])
	if _gradient.is_empty():
		return Color.WHITE
	var at := effect.molang((colour as Dictionary).get("interpolant", 0)).evaluate(v, q, math)
	if at <= _gradient[0][0]:
		return _gradient[0][1]
	for i in _gradient.size() - 1:
		if at <= _gradient[i + 1][0]:
			var span: float = _gradient[i + 1][0] - _gradient[i][0]
			return (_gradient[i][1] as Color).lerp(_gradient[i + 1][1], (at - _gradient[i][0]) / span if span > 0.0 else 1.0)
	return _gradient[-1][1]


func _gradient_stops() -> Array:
	var colour: Variant = effect.get_component("minecraft:particle_appearance_tinting").get("color", null)
	if not colour is Dictionary:
		return []
	var gradient: Variant = (colour as Dictionary).get("gradient", {})
	var stops: Array = []
	if gradient is Array:
		for i in gradient.size():
			stops.append([float(i) / maxf(1.0, gradient.size() - 1), _hex(gradient[i])])
	elif gradient is Dictionary:
		for key: String in gradient:
			stops.append([key.to_float(), _hex(gradient[key])])
	stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return stops


## "#AARRGGBB" or "#RRGGBB" (Bedrock order), or an array of 0-1 channels.
static func _hex(source: Variant) -> Color:
	if source is Array:
		var parts: Array = source
		return Color(float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3]) if parts.size() > 3 else 1.0)
	var text := str(source).trim_prefix("#")
	if text.length() == 8:
		return Color.html("#" + text.substr(2) + text.substr(0, 2))
	return Color.html("#" + text) if Color.html_is_valid("#" + text) else Color.WHITE


## The texture rectangle (x, y, w, h in 0-1) for a particle.
func _uv(uv: Dictionary, p: Dictionary) -> Color:
	if uv.is_empty():
		return Color(0, 0, 1, 1)
	var texture_width := float(uv.get("texture_width", 1))
	var texture_height := float(uv.get("texture_height", 1))
	var x := 0.0
	var y := 0.0
	var w := texture_width
	var h := texture_height
	if uv.has("flipbook"):
		var book: Dictionary = uv.flipbook
		var base := effect.molang3(book.get("base_UV", [0, 0]))
		var frame_size: Array = book.get("size_UV", [texture_width, texture_height])
		var step_size: Array = book.get("step_UV", [0, 0])
		var frames := maxi(1, int(_eval(book.get("max_frame", 1))))
		var index := 0
		if book.get("stretch_to_lifetime", false):
			index = int(float(p.age) / float(p.lifetime) * frames)
		else:
			index = int(float(p.age) * float(book.get("frames_per_second", 8)))
		index = posmod(index, frames) if book.get("loop", false) else mini(index, frames - 1)
		x = base[0].evaluate(v, q, math) + float(step_size[0]) * index
		y = base[1].evaluate(v, q, math) + float(step_size[1]) * index
		w = float(frame_size[0])
		h = float(frame_size[1])
	else:
		var corner := effect.molang3(uv.get("uv", [0, 0]))
		var extent := effect.molang3(uv.get("uv_size", [texture_width, texture_height]))
		x = corner[0].evaluate(v, q, math)
		y = corner[1].evaluate(v, q, math)
		w = extent[0].evaluate(v, q, math)
		h = extent[1].evaluate(v, q, math)
	return Color(x / texture_width, y / texture_height, w / texture_width, h / texture_height)


func _sorted_timeline(timeline: Variant) -> Array:
	var entries: Array = []
	if timeline is Dictionary:
		for key: String in timeline:
			entries.append([key.to_float(), timeline[key]])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return entries


## Runs an event (a name, a list of names, or null) at `at`; `particle` is the particle it
## belongs to, or null for emitter events.
func _fire(names: Variant, at: Vector3, particle: Variant) -> void:
	if names == null:
		return
	if names is Array:
		for name: Variant in names:
			_fire(name, at, particle)
		return
	var event: Variant = effect.events.get(str(names), null)
	if event is Dictionary:
		_run_event(event, at)


func _run_event(event: Dictionary, at: Vector3) -> void:
	if event.has("sequence"):
		for step: Variant in event.sequence:
			if step is Dictionary:
				_run_event(step, at)
	if event.has("randomize"):
		var options: Array = event.randomize
		var total := 0.0
		for option: Dictionary in options:
			total += float(option.get("weight", 1))
		var pick := math.rng.randf() * total
		for option: Dictionary in options:
			pick -= float(option.get("weight", 1))
			if pick <= 0.0:
				_run_event(option, at)
				break
	if event.has("expression"):
		_eval(event.expression)
	if event.has("particle_effect") and library != null:
		var spawn: Dictionary = event.particle_effect
		# Children inherit Cobblemon's context (target and entity variables) and whatever the
		# event's pre-effect expression sets, not this emitter's own state.
		var scratch := v.duplicate()
		if spawn.has("pre_effect_expression"):
			effect.molang(spawn.pre_effect_expression).evaluate(scratch, q, math)
		var vars := {}
		for key: String in scratch:
			if key.begins_with("target_") or key.begins_with("entity_") or not is_equal_approx(float(scratch[key]), float(v[key])):
				vars[key] = scratch[key]
		var bound: SnowstormEmitter = self if spawn.get("type", "emitter") == "emitter_bound" else null
		library.spawn_child(str(spawn.get("effect", "")), Transform3D(frame.basis, at), vars, q, bound, speed, entity_scale)
