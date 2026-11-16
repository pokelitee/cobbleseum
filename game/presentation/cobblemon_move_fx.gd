class_name CobblemonMoveFX
extends Node3D
## Prototype: Cobblemon's own move particle effects in place of our styles for the moves in
## game/data/cobblemon_move_fx.json (concepts_brief.md §12.5). Presentation only.
## The effects themselves stay in the git-ignored cache (tools/extract_move_fx.gd copies them
## out of the jar); the committed fit table only names them and says when each plays:
## - windup: on the user while it winds up (cut short by a feint, unless "keep");
## - fire: when the move is released, from the user, aimed at the foe when "aim" is set;
## - flight: riding the projectile until it lands;
## - hit: on the foe when the move connects (melee moves included);
## - blast: an area move going off around the user.
## Each spawn names an effect, whose fighter it plays on ("on": "user" or "foe"), where
## ("at": a Cobblemon locator name), an optional "delay" and "max" in seconds, "face":
## "camera" to turn the effect's front toward the camera instead of the other fighter (for
## effects that start metres in front of their fighter, which our closer melee spacing would
## bury inside the attacker), and the move's
## "speed" (effect seconds per real second) squeezes Cobblemon's slower timings into ours.

const ROOT := "res://cache/build/cobblemon/1.8.4/move_fx"
const PARTICLES := ROOT + "/assets/cobblemon/bedrock/particles"
const TEXTURES := ROOT + "/assets/cobblemon/textures/particle"
const FIT_FILE := "res://game/data/cobblemon_move_fx.json"
const FRAME_SECONDS := 1.0 / Rules.TICK_RATE
const MAX_EMITTERS := 160
## Locators on Cobblemon models we have no bone for, placed by share of the fighter's height;
## "front" ones sit ahead of the fighter, like a mouth or hands.
const LOCATORS := {
	"root": [0.0, false], "middle": [0.5, false], "target": [0.5, false], "top": [1.0, false],
	"special": [0.6, true], "special_attack": [0.6, true], "mouth": [0.7, true], "physical": [0.5, true],
	"hand": [0.45, true], "hand_primary": [0.45, true], "hand_secondary": [0.45, true],
	"eye": [0.8, true], "face": [0.75, true], "jaw_lower": [0.65, true],
}
const BLEND_MODES := {"alpha": "blend_mix, depth_prepass_alpha", "blend": "blend_mix", "add": "blend_add"}

## Move id -> fit (see the table file).
var fits: Dictionary = {}
## Effects or textures that were missing, and Molang that failed, for the prototype's report.
var problems: Dictionary = {}

var _paths: Dictionary = {}
var _effects: Dictionary = {}
var _textures: Dictionary = {}
var _shaders: Dictionary = {}
var _emitters: Array[SnowstormEmitter] = []
## Spawns waiting for their delay: {"frames": int, "spawn": Dictionary, "user", "foe", "cut": int}.
var _pending: Array[Dictionary] = []
var _spawned := 0


## Whether the extracted effects are in the cache.
static func available() -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PARTICLES))


## Loads the fit table and indexes the cached effects. Returns "" or why it can't run.
func setup() -> String:
	if not available():
		return "Cobblemon move effects are not extracted; run tools/extract_move_fx.gd"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIT_FILE))
	if not parsed is Dictionary:
		return "%s is not a JSON object" % FIT_FILE
	for key: String in parsed:
		if not key.begins_with("_"):
			fits[key] = parsed[key]
	_index(ProjectSettings.globalize_path(PARTICLES))
	return ""


func has_move(id: String) -> bool:
	return fits.has(id)


## Plays a phase of a move's fit. Returns the emitters started now (delayed spawns start
## later). `cut_frames` >= 0 ends windup effects after that many frames (a feint).
func play(id: String, phase: String, user: FighterView, foe: FighterView, cut_frames := -1) -> Array[SnowstormEmitter]:
	var started: Array[SnowstormEmitter] = []
	var fit: Dictionary = fits.get(id, {})
	for spawn: Dictionary in fit.get(phase, []):
		var delay := roundi(float(spawn.get("delay", 0.0)) / _speed(fit) / FRAME_SECONDS)
		var entry := {"frames": delay, "spawn": spawn, "id": id, "user": user, "foe": foe, "cut": cut_frames, "phase": phase}
		if delay <= 0:
			var emitter := _start(entry)
			if emitter != null:
				started.append(emitter)
		else:
			_pending.append(entry)
	return started


## Spawns an effect that rides `node` (a projectile's visual, whose -Z is its heading).
func play_riding(id: String, phase: String, node: Node3D, user: FighterView, foe: FighterView) -> Array[SnowstormEmitter]:
	var started := play(id, phase, user, foe)
	var ref: WeakRef = weakref(node)
	var follow := func() -> Variant:
		var riding: Node3D = ref.get_ref()
		return riding.global_transform if riding != null and riding.is_inside_tree() else null
	for emitter in started:
		emitter.follow = follow
		var at: Variant = follow.call()
		if at is Transform3D:
			emitter.frame = at
	return started


## Advances every effect by one video frame.
func next_frame() -> void:
	for entry in _pending.duplicate():
		entry.frames -= 1
		if entry.frames <= 0:
			_pending.erase(entry)
			_start(entry)
	for emitter in _emitters.duplicate():
		emitter.step(FRAME_SECONDS)
		if emitter.is_finished():
			_emitters.erase(emitter)
			emitter.queue_free()


## The battle is over: nothing new starts, and running effects stop emitting and fade out.
func end_all() -> void:
	_pending.clear()
	for emitter in _emitters:
		emitter.stopped = true


func emitter_count() -> int:
	return _emitters.size()


## Molang that failed to compile in the effects played so far (compiled as they first run).
func molang_problems() -> Dictionary:
	var found := {}
	for id: String in _effects:
		var effect: SnowstormEffect = _effects[id]
		if effect != null:
			for error in effect.errors:
				found["%s: %s" % [id, error]] = true
	return found


## Called by emitters for their events.
func spawn_child(effect_id: String, at: Transform3D, vars: Dictionary, queries: Dictionary, bound: SnowstormEmitter,
		speed: float, entity_scale: float) -> SnowstormEmitter:
	var emitter := _spawn(effect_id, at, vars, queries, speed, entity_scale)
	if emitter != null and bound != null:
		var ref: WeakRef = weakref(bound)
		emitter.follow = func() -> Variant:
			var parent: SnowstormEmitter = ref.get_ref()
			return parent.frame if parent != null else null
	return emitter


func _speed(fit: Dictionary) -> float:
	return maxf(0.05, float(fit.get("speed", 1.0)))


func _start(entry: Dictionary) -> SnowstormEmitter:
	var spawn: Dictionary = entry.spawn
	var user: FighterView = entry.user
	var foe: FighterView = entry.foe
	if not is_instance_valid(user) or not is_instance_valid(foe):
		return null
	var on_foe: bool = spawn.get("on", "foe" if entry.phase == "hit" else "user") == "foe"
	var subject := foe if on_foe else user
	var other := user if on_foe else foe
	var at := locator(subject, other, str(spawn.get("at", "middle")))
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if spawn.get("face", "") == "camera" and camera != null:
		var toward := (camera.global_position - at.origin) * Vector3(1, 0, 1)
		if toward.length_squared() > 0.0001:
			at.basis = Basis.looking_at(toward.normalized(), Vector3.UP)
	var vars := entity_vars(subject)
	if spawn.get("aim", false):
		vars.merge(target_vars(at, locator(other, subject, str(spawn.get("aim_at", "target")))), true)
	var fit: Dictionary = fits.get(entry.id, {})
	var emitter := _spawn(str(spawn.effect), at, vars, entity_vars(subject), _speed(fit) * float(spawn.get("speed", 1.0)), 1.0)
	if emitter == null:
		return null
	if spawn.has("max"):
		emitter.max_age = float(spawn.max)
	if entry.cut >= 0 and entry.phase == "windup" and not spawn.get("keep", false):
		emitter.max_age = minf(emitter.max_age, entry.cut * FRAME_SECONDS * emitter.speed)
	return emitter


func _spawn(effect_id: String, at: Transform3D, vars: Dictionary, queries: Dictionary, speed: float,
		entity_scale: float) -> SnowstormEmitter:
	if _emitters.size() >= MAX_EMITTERS:
		return null
	var effect := _effect(effect_id)
	if effect == null:
		return null
	var emitter := SnowstormEmitter.new()
	emitter.library = self
	emitter.speed = speed
	emitter.entity_scale = entity_scale
	add_child(emitter)
	_spawned += 1
	emitter.start(effect, at, hash([_spawned, effect.id]), vars, queries, _material(effect))
	_emitters.append(emitter)
	return emitter


## A Cobblemon locator on `subject` as a transform whose -Z faces `other`.
static func locator(subject: FighterView, other: FighterView, name: String) -> Transform3D:
	var share: Array = LOCATORS.get(name, [0.5, false])
	var toward := (other.position - subject.position) * Vector3(1, 0, 1)
	toward = toward.normalized() if toward.length_squared() > 0.0001 else Vector3.FORWARD
	var origin := subject.position + Vector3.UP * subject.height * float(share[0])
	if share[1]:
		origin += toward * subject.height * 0.35
	return Transform3D(Basis.looking_at(toward, Vector3.UP), origin)


## Cobblemon's target variables for an effect at `from` aimed at the point `to`.
static func target_vars(from: Transform3D, to: Transform3D) -> Dictionary:
	var local := from.basis.inverse() * (to.origin - from.origin)
	return {"target_deltax": -local.x, "target_deltay": local.y, "target_deltaz": -local.z,
		"target_distance": local.length()}


static func entity_vars(view: FighterView) -> Dictionary:
	var width := maxf(0.5, view.height * 0.7)
	return {"entity_height": view.height, "entity_width": width, "entity_radius": width * 0.5,
		"entity_scale": 1.0, "entity_size": width}


func _effect(effect_id: String) -> SnowstormEffect:
	var id := effect_id if effect_id.contains(":") else "cobblemon:" + effect_id
	if _effects.has(id):
		return _effects[id]
	var path: String = _paths.get(id, "")
	var effect: SnowstormEffect = null
	if path.is_empty():
		problems["missing effect " + id] = true
	else:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			effect = SnowstormEffect.parse(data)
			for error in effect.errors:
				problems["%s: %s" % [id, error]] = true
			for key in effect.unsupported:
				problems["%s: unsupported %s" % [id, key]] = true
		else:
			problems["unreadable effect " + path] = true
	_effects[id] = effect
	return effect


func _material(effect: SnowstormEffect) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if not _shaders.has(effect.material):
		var shader := Shader.new()
		shader.code = SnowstormEmitter.SHADER_CODE % BLEND_MODES[effect.material]
		_shaders[effect.material] = shader
	material.shader = _shaders[effect.material]
	material.set_shader_parameter("tex", _texture(effect.texture))
	material.set_shader_parameter("cutout", 0.02)
	return material


func _texture(name: String) -> Texture2D:
	if _textures.has(name):
		return _textures[name]
	var relative := name.trim_prefix("cobblemon:")
	for prefix in ["textures/particles/", "textures/particle/"]:
		relative = relative.trim_prefix(prefix)
	var path := ProjectSettings.globalize_path(TEXTURES.path_join(relative + ".png"))
	var texture: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		problems["missing texture " + name] = true
		var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		blank.fill(Color(1, 1, 1, 0))
		texture = ImageTexture.create_from_image(blank)
	_textures[name] = texture
	return texture


## Maps each effect's identifier to its file by file name. That matches the identifier for
## every move effect but two (firespin_targetcinder and minimize, not fitted here).
func _index(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for sub in access.get_directories():
		_index(dir.path_join(sub))
	for file in access.get_files():
		if file.ends_with(".json"):
			var id := "cobblemon:" + file.get_slice(".", 0)
			if not _paths.has(id):
				_paths[id] = dir.path_join(file)
