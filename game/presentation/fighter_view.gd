class_name FighterView
extends Node3D
## Shows one fighter: its converted model at the roster's scale, facing and position from
## the simulation, and animations chosen by role (concepts_brief.md §7.4, §8). Roles the species
## has no animation for fall back to ProceduralMotion, applied to a node above the model.

const CROSSFADE := 0.15
## Hit flash: frames it lasts and its peak strength.
const FLASH_FRAMES := 6
const FLASH_STRENGTH := 0.6
## Head tracking: the bone that turns to watch the foe, at most HEAD_MAX either way, eased
## by HEAD_EASE per frame. Past HEAD_GIVE_UP off to the side the head turns back to centre,
## as a body that has turned away no longer watches.
const HEAD_BONE := "head"
const HEAD_MAX := deg_to_rad(60.0)
const HEAD_GIVE_UP := deg_to_rad(110.0)
const HEAD_EASE := 0.2
## Share of the way to a new ground height covered each frame.
const GROUND_EASE := 0.35
## Above this speed (m/s) a grounded fighter with a run animation runs instead of walking.
const RUN_SPEED := 3.5
## The overlay layer: frames between blinks or fidgets (picked at random within the range),
## and the share of them that are fidgets (quirks) when the species has any.
const OVERLAY_GAP := Vector2i(60, 180)
const QUIRK_SHARE := 0.25
## Shading (concepts_brief.md §12.7): models stay lit by the arena but matte, like Cobblemon in
## Minecraft, with a soft rim of the light's colour on edges seen side-on, so they stand out
## from busy ground. Godot narrows the rim with lower roughness, which otherwise barely shows
## once specular is off. Emissive layers (glowing eyes, flames) draw
## EMISSIVE_ENERGY brighter than their texture, so they bloom.
const RIM := 0.35
const RIM_TINT := 0.5
const RIM_ROUGHNESS := 0.6
const EMISSIVE_ENERGY := 2.0

## Rendered height in metres, from the roster.
var height := 1.0
var _player: AnimationPlayer
var _mesh: MeshInstance3D
var _flash_material: StandardMaterial3D
var _flash_frames := 0
var _flash_delay := 0
var _head: HeadTurn
## Undulates a serpent whose animations hold its body still; null for other models.
var _wave: BodyWave
## Shows the poser's ground or air parts (folded or open wings); null when nothing swaps.
var _parts: PartSwap
var _watched: FighterView
var _ground_shown := 0.0
var _placed := false
var _animations: Dictionary = {}
var _fainted := false
## The looping animation between one-off animations: "walk" while moving (if the species has
## one), else "idle".
var _base_role := "idle"
var _one_off := false
var _moving := false
var _asleep := false
var _time_scale := 1.0
var _motion: ProceduralMotion
var _motion_root: Node3D
## A second player for animations layered over the main one: blinks and idle fidgets. It only
## touches the bones those animations move (it isn't deterministic-blended).
var _overlay: AnimationPlayer
var _quirks: Array = []
## The blink animations: one for most species, one per head or eye where each blinks on its
## own (Doduo, Maushold).
var _blinks: Array = []
var _overlay_wait := 0.0
var _rng := RandomNumberGenerator.new()
var _celebrating := false
## A one-off role to play after a delay (the intro cry), in frames.
var _pending_role := ""
var _pending_frames := 0
## The looping roles a fighter returns to between one-off animations (see pad_base_animations).
const BASE_ROLES: Array[String] = ["idle", "walk", "run", "air_idle", "air_fly", "sleep", "air_sleep", "happy"]
## Roles played once between base loops. Cobblemon loops many of these (hurt, angry, sad,
## shocked) since its battles hold them as a state; here they'd never end. The faint is left as
## authored, since nothing follows it.
const ONE_OFF_ROLES: Array[String] = ["physical", "special", "status", "recoil", "cry", "shock", "angry", "sad"]
## Procedural stand-ins for one-off roles the species has no animation for.
const PROCEDURAL_ROLES := {"physical": "lunge", "special": "rear", "status": "spin", "recoil": "tilt"}


## Instances a converted species scene from the cache at the roster's scale and height, wearing
## the material at `skin` (a shiny skin, Appearance) when one is given. Returns null if the model
## can't be loaded; a skin that can't be is left off, with a warning.
static func from_model(path: String, scale: float, model_height: float, skin := "") -> FighterView:
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		return null
	var view := FighterView.new()
	var model: Node3D = scene.instantiate()
	view._motion_root = Node3D.new()
	view.add_child(view._motion_root)
	view._motion_root.add_child(model)
	view._motion = ProceduralMotion.new(model_height, false)
	view._player = model.get_node("AnimationPlayer")
	view._animations = model.get_meta("animations", {})
	var mesh: MeshInstance3D = model.get_node("Skeleton/Mesh")
	view._mesh = mesh
	if mesh.mesh != null:
		shade(mesh.mesh)
		if not skin.is_empty():
			var material: Material = load(skin) if ResourceLoader.exists(skin) else null
			if material == null:
				push_warning("cannot load the skin %s; the model keeps its own colours" % skin)
			else:
				shade_material(material)
				mesh.set_surface_override_material(0, material)
	view._flash_material = StandardMaterial3D.new()
	view._flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view._flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	view._flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.height = model_height
	model.scale = Vector3.ONE * scale
	var skeleton: Skeleton3D = model.get_node("Skeleton")
	var parts: Dictionary = model.get_meta("parts", {})
	if not parts.is_empty():
		view._parts = PartSwap.new()
		view._parts.setup(skeleton, parts)
		skeleton.add_child(view._parts)
	if skeleton.find_bone(HEAD_BONE) >= 0:
		view._head = HeadTurn.new()
		view._head.bone = skeleton.find_bone(HEAD_BONE)
		skeleton.add_child(view._head)
	view._add_body_wave(skeleton)
	pad_base_animations(view._player.get_animation_library(""), view._animations, skeleton)
	play_one_offs_once(view._player.get_animation_library(""), view._animations)
	view._player.animation_finished.connect(view._on_animation_finished)
	view._quirks = model.get_meta("quirks", [])
	view._blinks = model.get_meta("blinks", [view._animations.blink] if view._animations.has("blink") else [])
	if view._animations.has("blink") or not view._quirks.is_empty():
		view._overlay = AnimationPlayer.new()
		view._overlay.deterministic = false
		view._overlay.add_animation_library("", view._player.get_animation_library(""))
		model.add_child(view._overlay)
	# Seeded by the model, so renders of the same battle are identical.
	view._rng.seed = hash(path)
	view._overlay_wait = view._rng.randi_range(OVERLAY_GAP.x, OVERLAY_GAP.y)
	view.play_idle()
	return view


## Gives a serpent whose base animations hold its body segments still a BodyWave, so it
## undulates and slithers instead of hopping and gliding about rigidly.
func _add_body_wave(skeleton: Skeleton3D) -> void:
	var segments := BodyWave.find_segments(skeleton)
	if segments.is_empty():
		return
	var base: Array[Animation] = []
	for role in ["idle", "walk", "run", "air_idle", "air_fly"]:
		if _animations.has(role):
			base.append(_player.get_animation(_animations[role]))
	if BodyWave.animated(base, skeleton, segments):
		return
	_wave = BodyWave.new()
	_wave.segments = segments
	skeleton.add_child(_wave)
	_motion.slithers = true


## Gives each base animation (BASE_ROLES in `roles`) a rest-pose track for every bone channel
## another animation in `library` moves and it doesn't, so the fighter comes back to its own
## pose after a one-off, a blink or a fidget. Godot's mixer leaves a bone no playing animation
## tracks where it was last put, which left eyelids closed after an attack or recoil that
## closes them. Animations are shared by every instance of the model; padding again adds nothing.
static func pad_base_animations(library: AnimationLibrary, roles: Dictionary, skeleton: Skeleton3D) -> void:
	var moved := {}
	for animation_name in library.get_animation_list():
		var animation := library.get_animation(animation_name)
		for track in animation.get_track_count():
			moved[[animation.track_get_path(track), animation.track_get_type(track)]] = true
	for role in BASE_ROLES:
		if not roles.has(role) or not library.has_animation(roles[role]):
			continue
		var animation := library.get_animation(roles[role])
		for key: Array in moved:
			var path: NodePath = key[0]
			var type: Animation.TrackType = key[1]
			if animation.find_track(path, type) >= 0:
				continue
			var bone := skeleton.find_bone(String(path.get_concatenated_subnames()))
			if bone < 0:
				continue
			var rest := skeleton.get_bone_rest(bone)
			var track := animation.add_track(type)
			animation.track_set_path(track, path)
			match type:
				Animation.TYPE_POSITION_3D:
					animation.position_track_insert_key(track, 0.0, rest.origin)
				Animation.TYPE_ROTATION_3D:
					animation.rotation_track_insert_key(track, 0.0, rest.basis.get_rotation_quaternion())
				Animation.TYPE_SCALE_3D:
					animation.scale_track_insert_key(track, 0.0, rest.basis.get_scale())


## Makes the animations of ONE_OFF_ROLES in `roles` play once, so the fighter returns to its
## base loop after them. No species uses one of them for a base role too.
static func play_one_offs_once(library: AnimationLibrary, roles: Dictionary) -> void:
	for role in ONE_OFF_ROLES:
		if roles.has(role) and library.has_animation(roles[role]):
			library.get_animation(roles[role]).loop_mode = Animation.LOOP_NONE


## Sets the shading of a converted model's materials (each surface's and its layer passes).
## The materials are shared by every instance of the model, and setting them again is harmless.
static func shade(mesh: Mesh) -> void:
	for surface in mesh.get_surface_count():
		shade_material(mesh.surface_get_material(surface))


## Sets the shading of one material and its layer passes, as shade() does.
static func shade_material(first: Material) -> void:
	var material := first as BaseMaterial3D
	while material != null:
		if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			material.albedo_color = Color(EMISSIVE_ENERGY, EMISSIVE_ENERGY, EMISSIVE_ENERGY, material.albedo_color.a)
		else:
			material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			material.roughness = RIM_ROUGHNESS
			material.rim_enabled = true
			material.rim = RIM
			material.rim_tint = RIM_TINT
		material = material.next_pass as BaseMaterial3D


## Hovering fighters float above the ground (§9.2), play their air animations when the species
## has them, and show their air parts (open wings).
func set_hovering(hovering: bool) -> void:
	_motion.hovers = hovering
	if _parts != null:
		_parts.air = hovering
	_motion.moving = _moving and not _animations.has(_walk_role())
	_update_base()


## Whether the species only idles in the air (its idle animation is its air idle), so it hovers
## whatever its types. Many species have air animations just for being ridden in flight
## (Blastoise, Garchomp) and stay grounded.
func floats() -> bool:
	return _animations.has("air_idle") and _animations.get("idle") == _animations.air_idle


func _idle_role() -> String:
	return "air_idle" if _motion.hovers and _animations.has("air_idle") else "idle"


func _walk_role() -> String:
	if _motion.hovers and _animations.has("air_fly"):
		return "air_fly"
	if _motion.hovers and _animations.has("air_idle"):
		return "air_idle"
	return "run" if _animations.has("run") and _motion.velocity.length() > RUN_SPEED else "walk"


func has_animation(role: String) -> bool:
	return _animations.has(role)


## Plays `role` once after `delay_frames` (the cry when the fighter is sent out).
func play_role_after(role: String, delay_frames: int) -> void:
	_pending_role = role
	_pending_frames = delay_frames


## The winner's loop: its happy animation, when it has one.
func celebrate() -> void:
	_celebrating = true
	_update_base()


## Back on its feet and idling, with no celebration, faint or pending animation: how the
## instant replay picks the fighter up again before replaying the knockout.
func rewind() -> void:
	_fainted = false
	_celebrating = false
	_one_off = false
	_pending_role = ""
	_motion.revive()
	_base_role = ""
	_update_base()


## Moves the view to a simulation position (x, z on the floor) facing a direction. The
## simulation does knockback itself.
func place(position_2d: Vector2, facing: Vector2, ground := 0.0) -> void:
	# Steps up and down ease over a few frames rather than snapping a whole block.
	_ground_shown = ground if not _placed else lerpf(_ground_shown, ground, GROUND_EASE)
	_placed = true
	position = Vector3(position_2d.x, _ground_shown, position_2d.y)
	if facing.length_squared() > 0.0:
		look_at(position + Vector3(facing.x, 0, facing.y), Vector3.UP)
		_motion.facing = facing
	if _head != null and _watched != null and not _fainted and facing.length_squared() > 0.0:
		var to_foe := Vector2(_watched.position.x - position.x, _watched.position.z - position.z)
		var off := facing.angle_to(to_foe) if to_foe.length_squared() > 1e-6 else 0.0
		# Floor angles run from x toward z, the opposite way to turning about +Y.
		_motion.head_target = 0.0 if absf(off) > HEAD_GIVE_UP else clampf(-off, -HEAD_MAX, HEAD_MAX)


## The nodes SmoothMotion draws between video frames: the view's place and facing, and the
## procedural motion of the model inside it.
func smoothed_nodes() -> Array[Node3D]:
	return [self, _motion_root]


## The fighter's movement over the last tick (m/s on the floor), for leaning and swooping.
func set_velocity(velocity: Vector2) -> void:
	_motion.velocity = velocity
	if _moving:
		_update_base()


## Squashes briefly on landing (the end of a dodge).
func land() -> void:
	if not _fainted:
		_motion.start("land")


## Turns this fighter's head (if its model has one) to follow `foe`.
func watch(foe: FighterView) -> void:
	_watched = foe


## Flashes white. `delay_frames` holds the flash back, e.g. until full-screen impact frames
## have passed, since a white model would vanish in the two-tone impact frame.
func take_hit(delay_frames := 0) -> void:
	_flash_frames = FLASH_FRAMES
	_flash_delay = delay_frames


## Advances the hit flash and procedural motion by one video frame.
func next_frame() -> void:
	if _flash_delay > 0:
		_flash_delay -= 1
	elif _flash_frames > 0:
		_flash_frames -= 1
		var fade := float(_flash_frames) / FLASH_FRAMES
		_flash_material.albedo_color = Color(1, 1, 1, FLASH_STRENGTH * fade * fade)
		_mesh.material_overlay = _flash_material if _flash_frames > 0 else null
	if not _pending_role.is_empty():
		_pending_frames -= 1
		if _pending_frames <= 0:
			play_role(_pending_role)
			_pending_role = ""
	_next_overlay()
	_motion.ground_lift = _faint_lift() if _fainted else 0.0
	_motion.next_frame(_time_scale)
	if _head != null:
		_head.yaw = _motion.head_yaw
	if _wave != null:
		_wave.phase = _motion.wave_phase
		_wave.strength = _motion.wave_strength
	_motion_root.transform = _motion.transform()


## Counts down to the next blink or fidget and starts it. Fidgets only play while idling,
## since they move the head and limbs; blinks only touch the eyes.
func _next_overlay() -> void:
	if _overlay == null or _fainted:
		return
	_overlay_wait -= _time_scale
	if _overlay_wait > 0.0:
		return
	_overlay_wait = _rng.randi_range(OVERLAY_GAP.x, OVERLAY_GAP.y)
	var fidget := not _quirks.is_empty() and not _one_off and not _moving and not _asleep and _rng.randf() < QUIRK_SHARE
	var animation := ""
	if fidget:
		animation = _quirks[_rng.randi() % _quirks.size()]
	elif _blinks.size() == 1:
		animation = _blinks[0]
	elif not _blinks.is_empty():
		animation = _blinks[_rng.randi() % _blinks.size()]
	if not animation.is_empty() and not _asleep:
		_overlay.play(animation)


## Animation speed relative to normal: 0 freezes (hit-stop), below 1 is slow motion.
func set_time_scale(scale: float) -> void:
	_time_scale = scale
	_player.speed_scale = scale
	if _overlay != null:
		_overlay.speed_scale = scale


func play_idle() -> void:
	if not _fainted:
		_play(_base_role, true)


## Holds the first frame of the idle animation and stops animating (for a still portrait).
func pose_still() -> void:
	_player.advance(0.0)
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if _overlay != null:
		_overlay.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL


## The mesh's vertices as currently posed, in this view's space, skinned on the CPU (the GPU's
## skinned positions can't be read back). Each vertex follows its heaviest bone, which is exact
## for Cobblemon's rigid cuboids.
func posed_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var skeleton: Skeleton3D = _mesh.get_parent()
	var skin := _mesh.skin
	if _mesh.mesh == null or skin == null:
		return points
	var to_view := _to_view(skeleton)
	var binds: Array[Transform3D] = []
	for i in skin.get_bind_count():
		var bone := skin.get_bind_bone(i)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(i))
		binds.append(to_view * skeleton.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(i))
	for surface in _mesh.mesh.get_surface_count():
		var arrays := _mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones.is_empty():
			continue
		var per_vertex := bones.size() / vertices.size()
		for v in vertices.size():
			var heaviest := v * per_vertex
			for k in range(v * per_vertex + 1, (v + 1) * per_vertex):
				if weights[k] > weights[heaviest]:
					heaviest = k
			points.append(binds[bones[heaviest]] * vertices[v])
	return points


## The posed model seen from the front, in the space ProceduralMotion moves (below its own
## offset): x and y of every vertex, for tipping over onto the ground.
func _faint_outline() -> PackedVector2Array:
	var to_model := _motion_root.transform.affine_inverse()
	var outline := PackedVector2Array()
	for point in posed_points():
		var local := to_model * point
		outline.append(Vector2(local.x, local.y))
	return outline


## How far the faint animation sinks the model below the ground as currently posed (all but
## ProceduralMotion's FAINT_REST_SHARE of it), measured while it plays and then held.
func _faint_lift() -> float:
	if not _animations.has("faint") or _player.current_animation != _animations.faint:
		return _motion.ground_lift
	var to_model := _motion_root.transform.affine_inverse()
	var heights := PackedFloat32Array()
	for point in posed_points():
		heights.append((to_model * point).y)
	if heights.is_empty():
		return 0.0
	heights.sort()
	return maxf(0.0, -heights[int(heights.size() * ProceduralMotion.FAINT_REST_SHARE)])


## The head bone's position in this view's space, as currently posed, or null without one.
func head_position() -> Variant:
	var skeleton: Skeleton3D = _mesh.get_parent()
	var bone := skeleton.find_bone(HEAD_BONE)
	if bone < 0:
		return null
	return _to_view(skeleton) * skeleton.get_bone_global_pose(bone).origin


## The transform from `node`'s space to this view's, without needing the tree.
func _to_view(node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	while node != self:
		transform = node.transform * transform
		node = node.get_parent()
	return transform


## Switches the looping animation between walking and idling; one-off animations play out first.
func set_moving(moving: bool) -> void:
	_moving = moving
	_motion.moving = moving and not _animations.has(_walk_role())
	_update_base()


## Asleep fighters loop their sleep animation, when the species has one.
func set_asleep(asleep: bool) -> void:
	_asleep = asleep
	_motion.asleep = asleep and not (_animations.has("sleep") or (_motion.hovers and _animations.has("air_sleep")))
	_update_base()


func _update_base() -> void:
	var role := _idle_role()
	if _asleep and _motion.hovers and _animations.has("air_sleep"):
		role = "air_sleep"
	elif _asleep and _animations.has("sleep"):
		role = "sleep"
	elif _celebrating and _animations.has("happy"):
		role = "happy"
	elif _moving and _animations.has(_walk_role()):
		role = _walk_role()
	if role == _base_role:
		return
	_base_role = role
	if not _one_off:
		play_idle()


## Plays a one-off animation for a role (physical, special, status, recoil, faint, cry, shock,
## angry, sad), or its procedural stand-in when the species has no animation for it.
func play_role(role: String) -> void:
	if _fainted:
		return
	if role == "faint":
		_fainted = true
		if _animations.has("faint"):
			_play("faint", false)
			_motion.fall()
		else:
			_player.pause()
			_motion.faint(_faint_outline())
		return
	_one_off = _play(role, false)
	if not _one_off and PROCEDURAL_ROLES.has(role):
		_motion.start(PROCEDURAL_ROLES[role])


## Breaks off a one-off animation (a feint's wind-up), blending back to the idle or walk.
func break_off() -> void:
	if _one_off and not _fainted:
		_one_off = false
		play_idle()


func _play(role: String, looping: bool) -> bool:
	if not _animations.has(role):
		return false
	var animation: String = _animations[role]
	if looping:
		_player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	_player.play(animation, CROSSFADE)
	return true


func _on_animation_finished(_animation: StringName) -> void:
	_one_off = false
	play_idle()
