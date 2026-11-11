class_name PartSwap
extends SkeletonModifier3D
## Shows the parts a Cobblemon poser shows in the current stance and hides the rest, such as
## folded wings on the ground and open wings in the air. Parts are bones; a hidden bone is
## scaled to zero after the clip has posed it, so any clip can play in either stance.

## Set by FighterView: true shows the "air" parts, false the "ground" ones.
var air := false
## Bone index -> visible, per stance.
var _ground := {}
var _air := {}


## `parts` is the model's "parts" metadata: {"ground": {bone: visible}, "air": {...}}.
## A stance the poser doesn't describe uses the other one's parts.
func setup(skeleton: Skeleton3D, parts: Dictionary) -> void:
	for stance: String in ["ground", "air"]:
		var visible: Dictionary = _ground if stance == "ground" else _air
		for bone_name: String in parts.get(stance, {}):
			var bone := skeleton.find_bone(bone_name)
			if bone >= 0:
				visible[bone] = bool(parts[stance][bone_name])


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var visible := _air if (air and not _air.is_empty()) or _ground.is_empty() else _ground
	for bone: int in visible:
		if not visible[bone]:
			skeleton.set_bone_pose_scale(bone, Vector3.ZERO)
