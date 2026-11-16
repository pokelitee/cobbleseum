class_name SnowstormEffect
extends RefCounted
## A Bedrock particle effect (the "Snowstorm" JSON format Cobblemon's move effects use),
## parsed once with every Molang field compiled. SnowstormEmitter runs it.
## Supported: point, sphere, disc and box shapes; once and looping emitters; instant and
## steady rates; dynamic and parametric motion; ground collision; billboards with flipbooks;
## tinting (fixed or gradient); linear, catmull-rom and bezier curves; emitter and particle
## events that spawn other effects or run expressions. Unsupported components are listed in
## `unsupported` and ignored.

const KNOWN := [
	"minecraft:emitter_initialization", "minecraft:emitter_lifetime_once", "minecraft:emitter_lifetime_looping",
	"minecraft:emitter_lifetime_events", "minecraft:emitter_rate_instant", "minecraft:emitter_rate_steady",
	"minecraft:emitter_shape_point", "minecraft:emitter_shape_sphere", "minecraft:emitter_shape_disc",
	"minecraft:emitter_shape_box", "minecraft:particle_appearance_billboard", "minecraft:particle_appearance_tinting",
	"minecraft:particle_appearance_lighting", "minecraft:particle_initial_speed", "minecraft:particle_initial_spin",
	"minecraft:particle_lifetime_expression", "minecraft:particle_lifetime_events", "minecraft:particle_motion_dynamic",
	"minecraft:particle_motion_parametric", "minecraft:particle_motion_collision", "minecraft:particle_initialization",
	"cobblemon:emitter_space",
]

var id := ""
var texture := ""
## "alpha" (cut out), "blend" or "add".
var material := "alpha"
var components: Dictionary = {}
var events: Dictionary = {}
## Curve name (without "variable.") -> {"type", "input", "range", "nodes"}.
var curves: Dictionary = {}
## Every v./q. name any expression uses, so emitters can start them at 0.
var names: Dictionary = {}
## Molang that failed to parse, and components ignored.
var errors: PackedStringArray = []
var unsupported: PackedStringArray = []

var _compiled: Dictionary = {}


static func parse(data: Dictionary) -> SnowstormEffect:
	var effect := SnowstormEffect.new()
	var body: Dictionary = data.get("particle_effect", {})
	var description: Dictionary = body.get("description", {})
	effect.id = description.get("identifier", "")
	var render: Dictionary = description.get("basic_render_parameters", {})
	effect.texture = render.get("texture", "")
	effect.material = {"particles_blend": "blend", "particles_add": "add"}.get(render.get("material", ""), "alpha")
	effect.components = body.get("components", {})
	effect.events = body.get("events", {})
	for key: String in effect.components:
		if not KNOWN.has(key):
			effect.unsupported.append(key)
	var raw_curves: Dictionary = body.get("curves", {})
	for key: String in raw_curves:
		var curve: Dictionary = raw_curves[key]
		var name := key.get_slice(".", 1) if key.contains(".") else key
		effect.curves[name] = {"type": curve.get("type", "linear"), "input": effect.molang(curve.get("input", 0)),
			"range": effect.molang(curve.get("horizontal_range", 1)), "nodes": curve.get("nodes", [])}
		effect.names["v." + name] = true
	return effect


func has(component: String) -> bool:
	return components.has(component)


func get_component(component: String) -> Dictionary:
	var value: Variant = components.get(component, {})
	return value if value is Dictionary else {}


## The compiled Molang for a JSON value, cached by its text.
func molang(source: Variant) -> ParticleMolang:
	var key := var_to_str(source)
	if _compiled.has(key):
		return _compiled[key]
	var program := ParticleMolang.compile(source)
	if not program.error.is_empty():
		errors.append(program.error)
	names.merge(program.names)
	_compiled[key] = program
	return program


## Three compiled values from a JSON triple (or one value repeated).
func molang3(source: Variant) -> Array[ParticleMolang]:
	var parts: Array[ParticleMolang] = []
	for i in 3:
		parts.append(molang(source[i] if source is Array and source.size() > i else (source if not source is Array else 0)))
	return parts


## Evaluates a curve for the variables in `v`.
func curve_value(curve: Dictionary, v: Dictionary, q: Dictionary, math: ParticleMath) -> float:
	var input := (curve.input as ParticleMolang).evaluate(v, q, math)
	var span := (curve.range as ParticleMolang).evaluate(v, q, math)
	var t := input / span if span != 0.0 else input
	var nodes: Variant = curve.nodes
	if nodes is Dictionary:
		return _bezier_chain(nodes, t)
	if not nodes is Array or (nodes as Array).is_empty():
		return 0.0
	var values: Array = nodes
	match curve.type:
		"catmull_rom":
			if values.size() < 4:
				return float(values[0])
			var segments := values.size() - 3
			var x := clampf(t, 0.0, 1.0) * segments
			var i := mini(int(x), segments - 1)
			var f := x - i
			return _catmull(float(values[i]), float(values[i + 1]), float(values[i + 2]), float(values[i + 3]), f)
		"bezier":
			if values.size() < 4:
				return float(values[0])
			var u := clampf(t, 0.0, 1.0)
			var a := 1.0 - u
			return a * a * a * float(values[0]) + 3.0 * a * a * u * float(values[1]) + 3.0 * a * u * u * float(values[2]) + u * u * u * float(values[3])
		_:
			if values.size() == 1:
				return float(values[0])
			var x := clampf(t, 0.0, 1.0) * (values.size() - 1)
			var i := mini(int(x), values.size() - 2)
			return lerpf(float(values[i]), float(values[i + 1]), x - i)


static func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


## Bezier chains are keyed by time with values and slopes; this evaluates them as Hermite
## segments, which is how Snowstorm defines them.
static func _bezier_chain(nodes: Dictionary, t: float) -> float:
	var keys: Array = nodes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.to_float() < b.to_float())
	if keys.is_empty():
		return 0.0
	var first: Dictionary = nodes[keys[0]]
	if t <= keys[0].to_float():
		return float(first.get("value", first.get("right_value", 0.0)))
	for i in keys.size() - 1:
		var t0: float = keys[i].to_float()
		var t1: float = keys[i + 1].to_float()
		if t <= t1:
			var a: Dictionary = nodes[keys[i]]
			var b: Dictionary = nodes[keys[i + 1]]
			var v0 := float(a.get("right_value", a.get("value", 0.0)))
			var v1 := float(b.get("left_value", b.get("value", 0.0)))
			var s0 := float(a.get("right_slope", a.get("slope", 0.0)))
			var s1 := float(b.get("left_slope", b.get("slope", 0.0)))
			var span := t1 - t0
			var u := (t - t0) / span if span > 0.0 else 0.0
			var u2 := u * u
			var u3 := u2 * u
			return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * s0 * span + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * s1 * span
	var last: Dictionary = nodes[keys[-1]]
	return float(last.get("value", last.get("left_value", 0.0)))
