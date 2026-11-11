class_name HeadTurn
extends SkeletonModifier3D
## Turns one bone (the head) about the model's up axis by `yaw` radians, on top of whatever
## clip is playing. FighterView sets `yaw` each frame so the head follows the foe.

var bone := -1
var yaw := 0.0


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or bone < 0 or is_zero_approx(yaw):
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var up := (parent_basis.inverse() * Vector3.UP).normalized()
	skeleton.set_bone_pose_rotation(bone, Quaternion(up, yaw) * skeleton.get_bone_pose_rotation(bone))
