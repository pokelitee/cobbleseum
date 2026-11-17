class_name ArenaWeather
extends Node3D
## How the weather (concepts_brief.md §9.11) looks: the sky, sun, ambient light and fog ease
## from the arena's own look toward the weather's over FADE_FRAMES, the weather's particles fade
## in, and the arena's own particles give way. The view tells it the battle's weather every
## frame, so clips that start mid-battle and the instant replay show the weather as it was.
## A new weather fades the old one out first. Particles have fixed seeds, so every render of a
## battle is the same.

const FADE_FRAMES := 30
## Each weather's look: sky [top, horizon], the sun's energy factor and colour, ambient
## [colour, energy factor], fog [colour, density factor], and an exposure factor.
const LOOKS := {
	"rain": {"sky": [Color("3a4656"), Color("75808f")], "sun": 0.35, "sun_colour": Color("b4c4dc"),
		"ambient": [Color("8392a8"), 0.85], "fog": [Color("66748a"), 2.5], "exposure": 0.95},
	"sun": {"sky": [Color("4f9be6"), Color("ffd59a")], "sun": 1.45, "sun_colour": Color("ffd08a"),
		"ambient": [Color("ffd9b0"), 1.15], "fog": [Color("ffe2b8"), 0.6], "exposure": 1.05},
	"sand": {"sky": [Color("8c7450"), Color("d2b27a")], "sun": 0.55, "sun_colour": Color("f0c890"),
		"ambient": [Color("c8a878"), 0.95], "fog": [Color("b8996a"), 4.0], "exposure": 1.0},
	"snow": {"sky": [Color("9fb0c4"), Color("dfe8f0")], "sun": 0.6, "sun_colour": Color("dce8ff"),
		"ambient": [Color("c8d8ee"), 1.05], "fog": [Color("d4dfea"), 2.2], "exposure": 1.0},
}
## Fog density never drops below this, so a clear arena's weather still hazes the distance.
const MIN_FOG := 0.006

var _sun: DirectionalLight3D
var _environment: Environment
var _sky: ProceduralSkyMaterial
## The arena's own look, to blend from.
var _base := {}
## The arena's own particles' material, faded out under a weather (null if it has none).
var _own_particles: StandardMaterial3D
var _own_alpha := 1.0
var _emitters := {}
var _materials := {}
var _seed := 0
## The weather being shown, the one the battle has, and how far the shown one is blended in.
var _shown := ""
var _target := ""
var _blend := 0.0


func setup(sun: DirectionalLight3D, environment: Environment, own_particles: StandardMaterial3D, seed: int) -> void:
	_sun = sun
	_environment = environment
	_sky = environment.sky.sky_material as ProceduralSkyMaterial
	_own_particles = own_particles
	if own_particles != null:
		_own_alpha = own_particles.albedo_color.a
	_seed = seed
	_base = {
		"sky": [_sky.sky_top_color, _sky.sky_horizon_color],
		"sun": sun.light_energy, "sun_colour": sun.light_color,
		"ambient": [environment.ambient_light_color, environment.ambient_light_energy],
		"fog": [environment.fog_light_color, environment.fog_density],
		"exposure": environment.tonemap_exposure,
	}


## The weather the battle has now ("" for none); the look follows it over the next frames.
func show_weather(weather: String) -> void:
	_target = weather if LOOKS.has(weather) else ""


## Jumps straight to `weather`, for a clip that starts mid-battle.
func snap(weather: String) -> void:
	show_weather(weather)
	_shown = _target
	_blend = 1.0 if not _shown.is_empty() else 0.0
	_apply()


## Advances the fade by one video frame.
func next_frame() -> void:
	if _target == _shown:
		if _shown.is_empty() or _blend >= 1.0:
			return
		_blend = minf(1.0, _blend + 1.0 / FADE_FRAMES)
	else:
		_blend = maxf(0.0, _blend - 1.0 / FADE_FRAMES)
		if _blend <= 0.0:
			_shown = _target
	_apply()


## The weather shown and how far it's blended in, for tests and tools.
func shown() -> Array:
	return [_shown, _blend]


func _apply() -> void:
	var look: Dictionary = LOOKS.get(_shown, {})
	var t := _blend if not look.is_empty() else 0.0
	var eased := t * t * (3.0 - 2.0 * t)
	if look.is_empty():
		look = {"sky": _base.sky, "sun": 1.0, "sun_colour": _base.sun_colour, "ambient": [_base.ambient[0], 1.0],
			"fog": [_base.fog[0], 1.0], "exposure": 1.0}
	_sky.sky_top_color = (_base.sky[0] as Color).lerp(look.sky[0], eased)
	_sky.sky_horizon_color = (_base.sky[1] as Color).lerp(look.sky[1], eased)
	_sky.ground_horizon_color = _sky.sky_horizon_color
	_sun.light_energy = _base.sun * lerpf(1.0, look.sun, eased)
	_sun.light_color = (_base.sun_colour as Color).lerp(look.sun_colour, eased)
	_environment.ambient_light_color = (_base.ambient[0] as Color).lerp(look.ambient[0], eased)
	_environment.ambient_light_energy = _base.ambient[1] * lerpf(1.0, look.ambient[1], eased)
	_environment.fog_light_color = (_base.fog[0] as Color).lerp(look.fog[0], eased)
	_environment.fog_density = lerpf(_base.fog[1], maxf(_base.fog[1], MIN_FOG) * look.fog[1], eased)
	_environment.tonemap_exposure = _base.exposure * lerpf(1.0, look.exposure, eased)
	if _own_particles != null:
		_own_particles.albedo_color.a = _own_alpha * (1.0 - eased)
	for name: String in LOOKS:
		var shown_here := eased if name == _shown else 0.0
		if shown_here > 0.0 and not _emitters.has(name):
			_emitters[name] = _emitter(name)
		if _emitters.has(name):
			var emitter: CPUParticles3D = _emitters[name]
			emitter.visible = shown_here > 0.0
			(_materials[name] as StandardMaterial3D).albedo_color.a = shown_here


## The weather's particles over the arena: rain streaks, warm motes rising in the sun, blowing
## sand, falling snow.
func _emitter(name: String) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.use_fixed_seed = true
	particles.seed = hash("%d|%s" % [_seed, name])
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Arena.PARTICLE_AREA * 0.5
	particles.position.y = Arena.PARTICLE_AREA.y * 0.5
	particles.gravity = Vector3.ZERO
	particles.spread = 8.0
	var quad := QuadMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1, 1, 1, 0)
	quad.material = material
	particles.mesh = quad
	_materials[name] = material
	match name:
		"rain":
			# Streaks stay upright and face the camera around the vertical.
			material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			quad.size = Vector2(0.025, 0.7)
			_drift(particles, 1400, 0.6, Vector3(0.6, -16.0, 0.3))
			particles.color = Color(0.78, 0.86, 1.0, 0.55)
		"sun":
			quad.size = Vector2(0.06, 0.06)
			particles.position.y = 0.3
			_drift(particles, 90, 6.0, Vector3(0.1, 0.5, 0.05))
			particles.spread = 40.0
			# Brighter than white, so they bloom.
			particles.color = Color(2.2, 1.7, 0.9, 0.8)
		"sand":
			quad.size = Vector2(0.08, 0.08)
			_drift(particles, 700, 2.5, Vector3(7.0, -0.3, 1.5))
			particles.spread = 20.0
			particles.color = Color(0.9, 0.78, 0.55, 0.75)
		"snow":
			quad.size = Vector2(0.09, 0.09)
			_drift(particles, 500, 6.0, Vector3(0.4, -1.4, 0.1))
			particles.spread = 25.0
			particles.color = Color(1, 1, 1, 0.95)
	add_child(particles)
	return particles


## Particles drift at `drift` (m/s), preprocessed so the air is full from the first frame.
static func _drift(particles: CPUParticles3D, amount: int, lifetime: float, drift: Vector3) -> void:
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = lifetime
	particles.direction = drift.normalized()
	particles.initial_velocity_min = drift.length() * 0.85
	particles.initial_velocity_max = drift.length() * 1.15
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
