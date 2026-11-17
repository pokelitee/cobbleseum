class_name CobblemonMoveFX
extends Node3D
## Move visuals in Cobblemon's style (concepts_brief.md §12.5): plays each move's MoveSequence,
## whose pieces are Cobblemon's own particle effects, run by SnowstormEmitter. Presentation
## only. The effects stay in the git-ignored cache (the Cobblemon source's build copies them to
## move_fx/); only the sequences, which name pieces and time them, are committed.

const ROOT := "res://cache/build/cobblemon/1.8.4/move_fx"
const PARTICLES := ROOT + "/assets/cobblemon/bedrock/particles"
const TEXTURES := ROOT + "/assets/cobblemon/textures/particle"
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
## Phases whose pieces sit on a fighter's body (a wind-up's glow or a buff's aura on the user,
## a hit's sparks on the foe), so their fighter carries them for their life. Pieces outside
## them stay in the world: shots fired at the foe, blasts, and projectiles (which ride their
## projectile instead).
const CARRIED_PHASES: Array[String] = ["windup", "hit"]
## Pieces on the ground stay where they were put even in those phases: floor scorches, quake
## and ground rings, powder settling, dust.
const GROUND_PIECES := "floor|ground|quake|scorch|crater|dust|_land|bigring|actorring"

## Effects or textures that were missing, for previews and reports.
var problems: Dictionary = {}

## Move id -> MoveSequence, or null when the move has none.
var _sequences: Dictionary = {}

var _paths: Dictionary = {}
var _effects: Dictionary = {}
var _textures: Dictionary = {}
var _shaders: Dictionary = {}
var _emitters: Array[SnowstormEmitter] = []
## Spawns waiting for their delay: {"frames": int, "spawn": Dictionary, "user", "foe", "cut": int}.
var _pending: Array[Dictionary] = []
var _spawned := 0
var _ground := RegEx.create_from_string(GROUND_PIECES)


## Whether the extracted effects are in the cache.
static func available() -> bool:
	return ClassDB.class_exists("SnowstormCore") and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(PARTICLES))


## Indexes the cached effects. Returns "" or why they can't run.
func setup() -> String:
	if not ClassDB.class_exists("SnowstormCore"):
		return "the native move-effect runtime isn't built; run tools/native/build.sh"
	if not available():
		return "Cobblemon move effects are not in the cache; run tools/assets.gd"
	_index(ProjectSettings.globalize_path(PARTICLES))
	return ""


## The sequence a move plays: its own (move_sequences/<move>.gd), or else its style's
## (move_sequences/styles/<style>.gd); null when neither exists.
func sequence_for(move: BattleMove, style: String) -> MoveSequence:
	var own := _sequence(move.id, MoveSequence.DIR)
	return own if own != null else _sequence(style, MoveSequence.STYLES_DIR)


func _sequence(id: String, dir: String) -> MoveSequence:
	var key := dir.path_join(id)
	if not _sequences.has(key):
		_sequences[key] = MoveSequence.load_from(dir, id)
	return _sequences[key]


## Loads every effect and texture the moves' sequences can spawn, sub-effects included, so the
## first use of a piece in battle doesn't stall a frame on parsing and loading. `moves` holds
## [BattleMove, style] pairs; `pieces` names other effects to load (auras, dodges).
func prepare(moves: Array, pieces: Array[String] = []) -> void:
	var queue: Array[String] = pieces.duplicate()
	for entry: Array in moves:
		var move: BattleMove = entry[0]
		var sequence := sequence_for(move, entry[1])
		if sequence == null:
			continue
		for phase in MoveSequence.PHASES:
			for piece: Dictionary in sequence.steps_for(phase, move.type):
				queue.append(str(piece.effect))
	var seen := {}
	while not queue.is_empty():
		var effect_id: String = queue.pop_back()
		if seen.has(effect_id):
			continue
		seen[effect_id] = true
		var effect := _effect(effect_id)
		if effect == null:
			continue
		_texture(effect.get_texture())
		queue.append_array(Array(effect.get_spawned_effects()))


## Plays a phase of a move's sequence (its own, or its style's). Tinted pieces take the move's
## type colour. Returns the pieces started now (delayed ones start later). `cut_frames` >= 0
## ends windup pieces after that many frames (a feint).
func play(move: BattleMove, style: String, phase: String, user: FighterView, foe: FighterView, cut_frames := -1) -> Array[SnowstormEmitter]:
	var started: Array[SnowstormEmitter] = []
	var sequence := sequence_for(move, style)
	if sequence == null:
		return started
	var speed := maxf(0.05, sequence.speed())
	var colour := TypeColors.of(move.type)
	for spawn: Dictionary in sequence.steps_for(phase, move.type):
		var delay := roundi(float(spawn.get("delay", 0.0)) / speed / FRAME_SECONDS)
		var entry := {"frames": delay, "spawn": spawn, "speed": speed, "user": user, "foe": foe, "cut": cut_frames,
			"phase": phase, "colour": colour}
		if delay <= 0:
			var emitter := _start(entry)
			if emitter != null:
				started.append(emitter)
		else:
			_pending.append(entry)
	return started


## Plays one piece outside any sequence, with SequenceSteps' options (on, at, aim, tint, ...),
## for auras, dodges, previews and authoring. Its fighter carries it unless the options say
## "carried": false.
func play_piece(effect: String, user: FighterView, foe: FighterView, options := {}, colour := Color.WHITE) -> SnowstormEmitter:
	var spawn := {"effect": effect, "on": "foe", "at": "target"}
	spawn.merge(options, true)
	return _start({"frames": 0, "spawn": spawn, "speed": float(options.get("speed", 1.0)), "user": user, "foe": foe,
		"cut": -1, "phase": "hit", "colour": colour})


## Spawns an effect that rides `node` (a projectile's visual, whose -Z is its heading).
func play_riding(move: BattleMove, style: String, phase: String, node: Node3D, user: FighterView, foe: FighterView) -> Array[SnowstormEmitter]:
	var started := play(move, style, phase, user, foe)
	var ref: WeakRef = weakref(node)
	var follow := func() -> Variant:
		var riding: Node3D = ref.get_ref()
		return riding.global_transform if riding != null and riding.is_inside_tree() else null
	for emitter in started:
		emitter.follow = follow
		emitter.anchor = ref
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


## Draws each effect that rides a node with that node, as `smooth` has drawn it between video
## frames; the particles themselves stay where the last frame put them.
func shift_riders(smooth: SmoothMotion) -> void:
	for emitter in _emitters:
		var anchor: Variant = emitter.anchor.get_ref() if emitter.anchor != null else null
		emitter.position = smooth.offset_of(anchor) if anchor is Node3D else Vector3.ZERO
		emitter.carry()


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
		var effect: RefCounted = _effects[id]
		if effect != null:
			for error: String in effect.get_errors():
				found["%s: %s" % [id, error]] = true
	return found


## Called by emitters for their events.
func spawn_child(effect_id: String, at: Transform3D, vars: Dictionary, queries: Dictionary, bound: SnowstormEmitter,
		parent: SnowstormEmitter) -> SnowstormEmitter:
	var emitter := _spawn(effect_id, at, vars, queries, parent.speed, parent.swap, parent.size_scale)
	if emitter != null and bound != null:
		var ref: WeakRef = weakref(bound)
		emitter.follow = func() -> Variant:
			var holder: SnowstormEmitter = ref.get_ref()
			return holder.frame if holder != null else null
		emitter.anchor = parent.anchor
	if emitter != null:
		emitter.carrier = parent.carrier
		emitter.carried_from = parent.carried_from
	return emitter


func _start(entry: Dictionary) -> SnowstormEmitter:
	var spawn: Dictionary = entry.spawn
	var user: FighterView = entry.user
	var foe: FighterView = entry.foe
	if not is_instance_valid(user) or not is_instance_valid(foe):
		return null
	var on_foe: bool = spawn.get("on", "user") == "foe"
	var subject := foe if on_foe else user
	var other := user if on_foe else foe
	var at := locator(subject, other, str(spawn.get("at", "middle")))
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if spawn.get("face_camera", false) and camera != null:
		var toward := (camera.global_position - at.origin) * Vector3(1, 0, 1)
		if toward.length_squared() > 0.0001:
			at.basis = Basis.looking_at(toward.normalized(), Vector3.UP)
	if spawn.has("nudge") and camera != null:
		var to_camera := camera.global_position - at.origin
		if to_camera.length_squared() > 0.0001:
			at.origin += to_camera.normalized() * float(spawn.nudge) * subject.height
	var vars := entity_vars(subject)
	if spawn.get("aim", false):
		vars.merge(target_vars(at, locator(other, subject, str(spawn.get("aim_at", "target")))), true)
	var swap: Color = entry.colour if spawn.get("tint", false) else Color(0, 0, 0, 0)
	var emitter := _spawn(str(spawn.effect), at, vars, entity_vars(subject), float(entry.speed) * float(spawn.get("speed", 1.0)),
		swap, float(spawn.get("scale", 1.0)))
	if emitter == null:
		return null
	if spawn.get("carried", entry.phase in CARRIED_PHASES) and _ground.search(str(spawn.effect)) == null:
		emitter.carrier = weakref(subject)
		emitter.carried_from = subject.position
	if spawn.has("max"):
		emitter.max_age = float(spawn.max)
	if entry.cut >= 0 and entry.phase == "windup" and not spawn.get("keep", false):
		emitter.max_age = minf(emitter.max_age, entry.cut * FRAME_SECONDS * emitter.speed)
	return emitter


func _spawn(effect_id: String, at: Transform3D, vars: Dictionary, queries: Dictionary, speed: float, swap: Color,
		size_scale: float) -> SnowstormEmitter:
	if _emitters.size() >= MAX_EMITTERS:
		return null
	var effect := _effect(effect_id)
	if effect == null:
		return null
	var emitter := SnowstormEmitter.new()
	emitter.library = self
	emitter.speed = speed
	emitter.swap = swap
	emitter.size_scale = size_scale
	add_child(emitter)
	_spawned += 1
	emitter.start(effect, at, hash([_spawned, effect.get_id()]), vars, queries, _material(effect, swap))
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


## The parsed effect (a native SnowstormProgram), or null when it's missing.
func _effect(effect_id: String) -> RefCounted:
	var id := effect_id if effect_id.contains(":") else "cobblemon:" + effect_id
	if _effects.has(id):
		return _effects[id]
	var path: String = _paths.get(id, "")
	var effect: RefCounted = null
	if path.is_empty():
		problems["missing effect " + id] = true
	else:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var program: RefCounted = ClassDB.instantiate("SnowstormProgram") if data is Dictionary else null
		var error: String = program.parse(data) if program != null else "unreadable"
		if error.is_empty():
			effect = program
			for problem: String in effect.get_errors():
				problems["%s: %s" % [id, problem]] = true
			for key: String in effect.get_unsupported():
				problems["%s: unsupported %s" % [id, key]] = true
		else:
			problems["unreadable effect " + path] = true
	_effects[id] = effect
	return effect


func _material(effect: RefCounted, swap: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if not _shaders.has(effect.get_material()):
		var shader := Shader.new()
		shader.code = SnowstormEmitter.SHADER_CODE % BLEND_MODES[effect.get_material()]
		_shaders[effect.get_material()] = shader
	material.shader = _shaders[effect.get_material()]
	material.set_shader_parameter("tex", _texture(effect.get_texture()))
	material.set_shader_parameter("cutout", 0.02)
	# Pieces that glow (blend and add) bloom like our other effects; cut-out pieces such as
	# rocks and debris stay flat.
	material.set_shader_parameter("brightness", 1.0 if effect.get_material() == "alpha" else MoveFX.GLOW)
	material.set_shader_parameter("swap", swap)
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
