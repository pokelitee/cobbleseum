class_name ArenaSurge
extends Node3D
## How a surge (concepts_brief.md §9.11) looks: the field's upward faces inside the arena wall
## take the surge's colour, with pixel cells glowing on and off (the arena's surface shader), and
## particles drift low over the ground: sparks, leaves, mist or a psychic shimmer. Like
## ArenaWeather it follows the battle's state every frame, fading in and out over FADE_FRAMES,
## and its particles have fixed seeds.

const FADE_FRAMES := 24
const COLOURS := {"electric": Color(1.0, 0.85, 0.2), "grassy": Color(0.35, 0.9, 0.35),
	"misty": Color(1.0, 0.6, 0.85), "psychic": Color(0.75, 0.4, 1.0)}
## Particles fill the arena from the ground up to this height.
const PARTICLE_HEIGHT := 2.5
## Glowing cells cycle at this rate (cycles a second at normal speed).
const TWINKLE_RATE := 0.6

var _arena: Arena
var _emitters := {}
var _materials := {}
var _seed := 0
var _shown := ""
var _target := ""
var _blend := 0.0
var _frames := 0


func setup(arena: Arena, seed: int) -> void:
	_arena = arena
	_seed = seed


## The surge the battle has now ("" for none).
func show_surge(surge: String) -> void:
	_target = surge if COLOURS.has(surge) else ""


## Jumps straight to `surge`, for a clip that starts mid-battle.
func snap(surge: String) -> void:
	show_surge(surge)
	_shown = _target
	_blend = 1.0 if not _shown.is_empty() else 0.0
	_apply()


func next_frame() -> void:
	_frames += 1
	if _target == _shown:
		if not _shown.is_empty():
			_blend = minf(1.0, _blend + 1.0 / FADE_FRAMES)
	else:
		_blend = maxf(0.0, _blend - 1.0 / FADE_FRAMES)
		if _blend <= 0.0:
			_shown = _target
	_apply()


func shown() -> Array:
	return [_shown, _blend]


func _apply() -> void:
	var colour: Color = COLOURS.get(_shown, Color.BLACK)
	var t := _blend if not _shown.is_empty() else 0.0
	var eased := t * t * (3.0 - 2.0 * t)
	_arena.set_surge(colour, eased, _frames * TWINKLE_RATE / Rules.TICK_RATE)
	for name: String in COLOURS:
		var here := eased if name == _shown else 0.0
		if here > 0.0 and not _emitters.has(name):
			_emitters[name] = _emitter(name)
		if _emitters.has(name):
			(_emitters[name] as CPUParticles3D).visible = here > 0.0
			(_materials[name] as StandardMaterial3D).albedo_color.a = here


func _emitter(name: String) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.use_fixed_seed = true
	particles.seed = hash("%d|%s" % [_seed, name])
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = Rules.ARENA_RADIUS
	particles.emission_ring_inner_radius = 0.0
	particles.emission_ring_height = PARTICLE_HEIGHT
	particles.position.y = PARTICLE_HEIGHT * 0.5
	particles.gravity = Vector3.ZERO
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 0)
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = ArenaWeather.NEAR_FADE.x
	material.distance_fade_max_distance = ArenaWeather.NEAR_FADE.y
	quad.material = material
	particles.mesh = quad
	_materials[name] = material
	var colour: Color = COLOURS[name]
	match name:
		"electric":
			# Quick bright sparks, brighter than white so they bloom.
			quad.size = Vector2(0.07, 0.07)
			_drift(particles, 160, 0.5, Vector3(0.0, 1.2, 0.0), 90.0)
			particles.color = Color(colour.r * 2.4, colour.g * 2.4, colour.b * 1.6, 1.0)
		"grassy":
			quad.size = Vector2(0.09, 0.06)
			_drift(particles, 120, 5.0, Vector3(0.4, 0.25, 0.2), 45.0)
			particles.color = Color(colour.r, colour.g, colour.b, 0.9)
		"misty":
			quad.size = Vector2(0.6, 0.6)
			_drift(particles, 90, 6.0, Vector3(0.2, 0.08, 0.1), 60.0)
			particles.color = Color(colour.r, colour.g, colour.b, 0.22)
		"psychic":
			quad.size = Vector2(0.07, 0.07)
			_drift(particles, 140, 3.0, Vector3(0.0, 0.6, 0.0), 30.0)
			particles.color = Color(colour.r * 1.8, colour.g * 1.8, colour.b * 1.8, 0.9)
	add_child(particles)
	return particles


static func _drift(particles: CPUParticles3D, amount: int, lifetime: float, drift: Vector3, spread: float) -> void:
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.direction = drift.normalized()
	particles.spread = spread
	particles.initial_velocity_min = drift.length() * 0.7
	particles.initial_velocity_max = drift.length() * 1.3
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
