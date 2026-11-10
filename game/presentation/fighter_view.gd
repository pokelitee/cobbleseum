class_name FighterView
extends Node3D
## Shows one fighter: its converted model at the roster's scale, facing and position from
## the simulation, and clips chosen by role (concepts_brief.md §7.4, §8).

const CROSSFADE := 0.15
## Hit flash: frames it lasts and its peak strength.
const FLASH_FRAMES := 6
const FLASH_STRENGTH := 0.6
## Visual knockback: peak distance in metres per HP share dealt, and frames to recover.
const KNOCKBACK_PER_SHARE := 3.0
const KNOCKBACK_MAX := 0.6
const KNOCKBACK_FRAMES := 10

## Rendered height in metres, from the roster.
var height := 1.0
var _player: AnimationPlayer
var _mesh: MeshInstance3D
var _flash_material: StandardMaterial3D
var _flash_frames := 0
var _flash_delay := 0
var _knockback := Vector3.ZERO
var _knockback_frames := 0
var _clips: Dictionary = {}
var _fainted := false


## Instances a converted species scene from the cache at the roster's scale and height.
## Returns null if it can't be loaded.
static func from_model(path: String, scale: float, model_height: float) -> FighterView:
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		return null
	var view := FighterView.new()
	var model: Node3D = scene.instantiate()
	view.add_child(model)
	view._player = model.get_node("AnimationPlayer")
	view._clips = model.get_meta("clips", {})
	var mesh: MeshInstance3D = model.get_node("Skeleton/Mesh")
	view._mesh = mesh
	view._flash_material = StandardMaterial3D.new()
	view._flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	view._flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	view._flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.height = model_height
	model.scale = Vector3.ONE * scale
	view._player.animation_finished.connect(view._on_clip_finished)
	view.play_idle()
	return view


## Moves the view to a simulation position (x, z on the floor) facing a direction, plus any
## visual knockback (presentation only; the simulation has no knockback yet).
func place(position_2d: Vector2, facing: Vector2) -> void:
	var recovery := float(_knockback_frames) / KNOCKBACK_FRAMES
	position = Vector3(position_2d.x, 0, position_2d.y) + _knockback * recovery * recovery
	if facing.length_squared() > 0.0:
		look_at(position + Vector3(facing.x, 0, facing.y), Vector3.UP)


## Flashes white and recoils away from `from` (a world position), scaled by HP share lost.
## `delay_frames` holds the flash back, e.g. until full-screen impact frames have passed,
## since a white model would vanish in the two-tone impact frame.
func take_hit(from: Vector3, damage_share: float, delay_frames := 0) -> void:
	_flash_frames = FLASH_FRAMES
	_flash_delay = delay_frames
	var away := (global_position - from) * Vector3(1, 0, 1)
	var distance := minf(KNOCKBACK_MAX, damage_share * KNOCKBACK_PER_SHARE)
	_knockback = away.normalized() * distance if away.length() > 0.01 else Vector3.ZERO
	_knockback_frames = KNOCKBACK_FRAMES


## Advances the hit flash and knockback by one video frame.
func next_frame() -> void:
	if _flash_delay > 0:
		_flash_delay -= 1
	elif _flash_frames > 0:
		_flash_frames -= 1
		var fade := float(_flash_frames) / FLASH_FRAMES
		_flash_material.albedo_color = Color(1, 1, 1, FLASH_STRENGTH * fade * fade)
		_mesh.material_overlay = _flash_material if _flash_frames > 0 else null
	if _knockback_frames > 0:
		_knockback_frames -= 1


## Animation speed relative to normal: 0 freezes (hit-stop), below 1 is slow motion.
func set_time_scale(scale: float) -> void:
	_player.speed_scale = scale


func play_idle() -> void:
	if not _fainted:
		_play("idle", true)


## Plays a one-off clip for a role (physical, special, recoil, faint); falls back silently
## when the species has no clip for it.
func play_role(role: String) -> void:
	if _fainted:
		return
	if role == "faint":
		_fainted = true
		if not _play("faint", false):
			_player.stop()
			create_tween().tween_property(self, "rotation:z", deg_to_rad(80), 0.5)
		return
	_play(role, false)


func _play(role: String, looping: bool) -> bool:
	if not _clips.has(role):
		return false
	var clip: String = _clips[role]
	if looping:
		_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_player.play(clip, CROSSFADE)
	return true


func _on_clip_finished(_clip: StringName) -> void:
	play_idle()
