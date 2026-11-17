class_name BodyWave
extends SkeletonModifier3D
## Sends a travelling wave down a serpent's body segments, on top of whatever animation is
## playing, for Cobblemon serpents whose animations hold the body still (Rayquaza's only
## animation is a held pose). They undulate as they idle and slither or swim through the air
## when they move, rather than gliding about as a rigid statue. ProceduralMotion drives
## `phase` and `strength`.

## Cobblemon names a serpent's body bones segment, segment1, segment2, ...
const SEGMENT_PATTERN := "^segment\\d*$"
## Radians each segment turns at full strength, and the phase step from one segment to the
## next (about ten segments to a wavelength).
const AMPLITUDE := deg_to_rad(9.0)
const PHASE_STEP := 0.6

## Segment bones from the head end to the tail.
var segments: Array[int] = []
var phase := 0.0
var strength := 0.0


## The segment bones a wave would move on `skeleton`, from the head end to the tail. None
## means the model isn't a serpent.
static func find_segments(skeleton: Skeleton3D) -> Array[int]:
	var regex := RegEx.create_from_string(SEGMENT_PATTERN)
	var found: Array[int] = []
	for bone in skeleton.get_bone_count():
		if regex.search(skeleton.get_bone_name(bone)) != null:
			found.append(bone)
	found.sort_custom(func(a: int, b: int) -> bool: return _depth(skeleton, a) < _depth(skeleton, b))
	return found


## Whether any of `animations` turns one of `bones` (more than a held pose). Serpents whose
## animations already undulate are left to them.
static func animated(animations: Array[Animation], skeleton: Skeleton3D, bones: Array[int]) -> bool:
	for animation in animations:
		for track in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			if not skeleton.find_bone(String(animation.track_get_path(track).get_concatenated_subnames())) in bones:
				continue
			var first: Quaternion = animation.track_get_key_value(track, 0)
			for key in animation.track_get_key_count(track):
				if not (animation.track_get_key_value(track, key) as Quaternion).is_equal_approx(first):
					return true
	return false


static func _depth(skeleton: Skeleton3D, bone: int) -> int:
	var depth := 0
	while skeleton.get_bone_parent(bone) >= 0:
		bone = skeleton.get_bone_parent(bone)
		depth += 1
	return depth


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or is_zero_approx(strength):
		return
	for i in segments.size():
		var bone := segments[i]
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		# Some Cobblemon animations scale a bone to zero to hide it; its basis then can't be inverted.
		if is_zero_approx(parent_basis.determinant()):
			continue
		var up := (parent_basis.inverse() * Vector3.UP).normalized()
		var angle := AMPLITUDE * strength * sin(phase - PHASE_STEP * i)
		skeleton.set_bone_pose_rotation(bone, Quaternion(up, angle) * skeleton.get_bone_pose_rotation(bone))
