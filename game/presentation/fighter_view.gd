class_name FighterView
extends Node3D
## Shows one fighter: its converted model scaled into the agreed height band, facing and
## position from the simulation, and clips chosen by role (concepts_brief.md §7.4, §8).

const MIN_HEIGHT := 0.5
const MAX_HEIGHT := 3.0
const CROSSFADE := 0.15

## Rendered height in metres after scaling into the height band.
var height := 1.0
var _player: AnimationPlayer
var _clips: Dictionary = {}
var _fainted := false


## Instances a converted species scene from the cache. Returns null if it can't be loaded.
static func from_model(path: String) -> FighterView:
	var scene: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if scene == null:
		return null
	var view := FighterView.new()
	var model: Node3D = scene.instantiate()
	view.add_child(model)
	view._player = model.get_node("AnimationPlayer")
	view._clips = model.get_meta("clips", {})
	var mesh: MeshInstance3D = model.get_node("Skeleton/Mesh")
	var model_height := mesh.get_aabb().size.y if mesh.mesh != null else 1.0
	view.height = clampf(model_height, MIN_HEIGHT, MAX_HEIGHT)
	model.scale = Vector3.ONE * (view.height / model_height)
	view._player.animation_finished.connect(view._on_clip_finished)
	view.play_idle()
	return view


## Moves the view to a simulation position (x, z on the floor) facing a direction.
func place(position_2d: Vector2, facing: Vector2) -> void:
	position = Vector3(position_2d.x, 0, position_2d.y)
	if facing.length_squared() > 0.0:
		look_at(position + Vector3(facing.x, 0, facing.y), Vector3.UP)


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
