class_name BodyWave
extends SkeletonModifier3D
## Sends a travelling wave down a serpent's body segments, on top of whatever animation is
## playing, for Cobblemon serpents whose animations hold the body still (Rayquaza's only
## animation is a held pose). They undulate as they idle and slither or swim through the air
## when they move, rather than gliding about as a rigid statue. On a knockout they slump: each
## segment turns toward level, so a body reared up in its only pose (Rayquaza's) lies down
## instead of staying raised. ProceduralMotion drives `phase`, `strength` and `slump`.

## Cobblemon names a serpent's body bones segment, segment1, segment2, ...
const SEGMENT_PATTERN := "^segment\\d*$"
## A body of this many segments or more is a serpent's (Orthworm's 5 to Rayquaza's 15); fewer
## are something else, such as Burmy's cloak or Golisopod's back.
const SERPENT_SEGMENTS := 5
## Radians each segment turns at full strength, and the phase step from one segment to the
## next (about ten segments to a wavelength).
const AMPLITUDE := deg_to_rad(9.0)
const PHASE_STEP := 0.6

## Segment bones from the head end to the tail.
var segments: Array[int] = []
## The chains of bones a slump levels (spine()).
var spine_bones: Array[PackedInt32Array] = []
var phase := 0.0
var strength := 0.0
## How far the body has slumped, from its own pose (0) to every segment level (1).
var slump := 0.0


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
	if skeleton == null or (is_zero_approx(strength) and slump <= 0.0):
		return
	if slump > 0.0:
		var rotations := lie_down(skeleton, spine_bones, slump)
		for bone: int in rotations:
			skeleton.set_bone_pose_rotation(bone, rotations[bone])
	if is_zero_approx(strength):
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


## The chains of bones a slump levels, each from the skeleton's root: one through the segments
## and on down the tail (the longest line of descendants), and one to the head (`head`, -1
## for none).
static func spine(skeleton: Skeleton3D, segment_bones: Array[int], head: int) -> Array[PackedInt32Array]:
	var chains: Array[PackedInt32Array] = []
	var tail := -1
	if not segment_bones.is_empty():
		tail = segment_bones.back()
		while not skeleton.get_bone_children(tail).is_empty():
			var longest := -1
			for child in skeleton.get_bone_children(tail):
				if longest < 0 or _descendants(skeleton, child) > _descendants(skeleton, longest):
					longest = child
			tail = longest
	for end in [tail, head]:
		var chain := PackedInt32Array()
		var bone: int = end
		while bone >= 0:
			chain.insert(0, bone)
			bone = skeleton.get_bone_parent(bone)
		if chain.size() > 1:
			chains.append(chain)
	return chains


static func _descendants(skeleton: Skeleton3D, bone: int) -> int:
	var count := 0
	for child in skeleton.get_bone_children(bone):
		count += 1 + _descendants(skeleton, child)
	return count


## The local rotations that turn each bone of the `chains` (spine()), from the root end,
## toward level, from the skeleton's current poses: its direction to the next bone keeps its
## heading and loses its standing rise and fall by `slump`. A bone standing straight up takes the
## heading of the one before it in its chain, or the model's forward (-Z). A bone in two chains
## belongs to the first, even where it has no length to level there (Silicobra's body sits on
## its first segment's pivot): levelled toward the second, it would swing the first about. The root is left alone, since levelling it would lay the whole
## model over as the tip-over does. Returns {bone: Quaternion}.
static func lie_down(skeleton: Skeleton3D, chains: Array[PackedInt32Array], slump: float) -> Dictionary:
	var rotations := {}
	var standing := {}
	var globals := {}
	var levelled := {}
	for chain in chains:
		var heading := Vector3.FORWARD
		for i in chain.size() - 1:
			var bone := chain[i]
			var along := global_pose(skeleton, chain[i + 1], rotations, globals).origin - global_pose(skeleton, bone, rotations, globals).origin
			var level := Vector3(along.x, 0.0, along.z)
			if level.length_squared() > along.length_squared() * 0.01:
				heading = level.normalized()
			var parent := skeleton.get_bone_parent(bone)
			if parent < 0 or levelled.has(bone):
				continue
			levelled[bone] = true
			if along.is_zero_approx():
				continue
			# Its rise eases from its standing one to none, so no part rises on the way down.
			var was := global_pose(skeleton, chain[i + 1], {}, standing).origin - global_pose(skeleton, bone, {}, standing).origin
			var rise := (1.0 - slump) * asin(clampf(was.normalized().y, -1.0, 1.0)) if not was.is_zero_approx() else 0.0
			var target := heading * cos(rise) + Vector3.UP * sin(rise)
			var axis := along.cross(target)
			var parent_basis := global_pose(skeleton, parent, rotations, globals).basis
			if axis.is_zero_approx() or is_zero_approx(parent_basis.determinant()):
				continue
			var local_axis := (parent_basis.inverse() * axis).normalized()
			rotations[bone] = Quaternion(local_axis, along.angle_to(target)) * skeleton.get_bone_pose_rotation(bone)
			# The bones below it turned with it.
			globals.clear()
	return rotations


## A bone's pose in skeleton space from the skeleton's current poses, with the local
## `rotations` ({bone: Quaternion}) in place of theirs; cached in `globals`.
static func global_pose(skeleton: Skeleton3D, bone: int, rotations: Dictionary, globals: Dictionary) -> Transform3D:
	if not globals.has(bone):
		var turned: Quaternion = rotations.get(bone, skeleton.get_bone_pose_rotation(bone))
		var local := Transform3D(Basis(turned) * Basis.from_scale(skeleton.get_bone_pose_scale(bone)), skeleton.get_bone_pose_position(bone))
		var parent := skeleton.get_bone_parent(bone)
		globals[bone] = global_pose(skeleton, parent, rotations, globals) * local if parent >= 0 else local
	return globals[bone]
