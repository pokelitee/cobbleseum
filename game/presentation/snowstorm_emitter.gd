class_name SnowstormEmitter
extends MultiMeshInstance3D
## Draws one Bedrock particle effect (concepts_brief.md §12.5, Cobblemon's move effects): the
## native SnowstormCore (game/native, a GDExtension) runs the effect and lays out its particles
## as a MultiMesh buffer, stepped by video frame with a seeded random stream so renders are
## identical. This node follows what the effect rides, keeps the camera-facing size cap and
## hands the effects its events spawn to `library`.
## Textures are drawn with nearest filtering, like Cobblemon; camera-facing particles are
## capped at MAX_SCREEN_SHARE of the view's height, so pieces sized for Minecraft's distant
## camera don't fill our close-ups.

const MAX_AGE := 6.0
const MAX_SCREEN_SHARE := 0.25
## Floats per instance in the MultiMesh buffer: a 3x4 transform, a colour and custom data.
const STRIDE := 20
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, %s;
uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float cutout = 0.0;
uniform float brightness = 1.0;
// A palette swap for borrowed pieces: rgb is the new colour, a how much of it to use.
uniform vec4 swap = vec4(0.0);
varying vec4 rect;
void vertex() {
	rect = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 c = texture(tex, rect.xy + UV * rect.zw) * COLOR;
	if (c.a <= cutout) {
		discard;
	}
	if (swap.a > 0.0) {
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		// Keep the piece's shading as a ramp in the new colour: darks lift to a shade of it (so a
		// dark piece still reads as the type), lights run on to white.
		vec3 ramp = l < 0.5 ? mix(swap.rgb * 0.45, swap.rgb, l * 2.0) : mix(swap.rgb, vec3(1.0), (l - 0.5) * 2.0);
		c.rgb = mix(c.rgb, ramp, swap.a);
	}
	ALBEDO = c.rgb * brightness;
	ALPHA = c.a;
}
"""

## The effect (a native SnowstormProgram).
var effect: RefCounted
## Spawns the effects that events name: an object with spawn_child(id, transform, vars,
## queries, bound, parent).
var library: Object
## Effect time per video-frame second; sequences use it to squeeze Cobblemon's slower
## timings into the real-time battle.
var speed := 1.0
## When valid, called each frame for the emitter's new frame (an emitter riding a projectile
## or bound to its parent).
var follow := Callable()
## The node the effect rides (a WeakRef to a Node3D), or null; drawn with it between frames.
var anchor: WeakRef
## Multiplies sizes and offsets for effects with cobblemon:emitter_space scaling "entity".
var entity_scale := 1.0
## Multiplies particle sizes (a sequence's "scale").
var size_scale := 1.0
## The palette swap colour (alpha 0: none), passed on to effects this one spawns.
var swap := Color(0, 0, 0, 0)
## The queries the effect started with, passed on to effects this one spawns.
var queries: Dictionary = {}
## The emitter's position and frame in world space; -Z points at its target.
var frame: Transform3D:
	get:
		return _core.get_frame() if _core != null else _frame
	set(value):
		_frame = value
		if _core != null:
			_core.set_frame(value)
## Set to stop emitting; the emitter frees itself once its particles are gone.
var stopped: bool:
	get:
		return _core.is_stopped() if _core != null else false
	set(value):
		if value and _core != null:
			_core.stop()
var max_age: float:
	get:
		return _core.get_max_age() if _core != null else MAX_AGE
	set(value):
		if _core != null:
			_core.set_max_age(value)

var _core: RefCounted
var _frame := Transform3D.IDENTITY


## Starts `program` at `at` with the given variables and queries.
func start(program: RefCounted, at: Transform3D, seed_value: int, vars: Dictionary, start_queries: Dictionary,
		shader_material: ShaderMaterial) -> void:
	effect = program
	queries = start_queries
	_core = ClassDB.instantiate("SnowstormCore")
	_core.set_max_age(MAX_AGE)
	_core.start(program, at, seed_value, vars, start_queries, entity_scale, size_scale)
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	custom_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 80, 200))
	material_override = shader_material
	_hand_over_spawns()


func is_finished() -> bool:
	return _core == null or _core.is_finished()


func particle_count() -> int:
	return _core.get_particle_count() if _core != null else 0


## Advances the effect by `delta` seconds of video and redraws it.
func step(delta: float) -> void:
	if follow.is_valid():
		var moved: Variant = follow.call()
		if moved is Transform3D:
			_core.set_frame(moved)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var camera_basis := camera.global_transform.basis if camera != null else Basis.IDENTITY
	var camera_position := camera.global_position if camera != null else Vector3.ZERO
	var cap := 2.0 * tan(deg_to_rad(camera.fov) * 0.5) * MAX_SCREEN_SHARE if camera != null else 0.0
	_core.step(delta * speed, camera_basis, camera_position, cap)
	var buffer: PackedFloat32Array = _core.get_buffer()
	var capacity := buffer.size() / STRIDE
	if multimesh.instance_count != capacity:
		multimesh.instance_count = capacity
	if capacity > 0:
		multimesh.buffer = buffer
	multimesh.visible_instance_count = _core.get_drawn()
	_hand_over_spawns()


func _hand_over_spawns() -> void:
	if library == null:
		return
	for spawn: Array in _core.take_spawns():
		var bound: SnowstormEmitter = self if spawn[3] else null
		library.spawn_child(str(spawn[0]), Transform3D(_core.get_frame().basis, spawn[1]), spawn[2], queries, bound, self)
