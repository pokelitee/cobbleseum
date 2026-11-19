extends TestCase
## Serpents' body wave (concepts_brief.md §7.4).


func _serpent() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	for bone in ["body", "segment2", "segment", "segment1", "tail", "neck"]:
		skeleton.add_bone(bone)
	# body > segment > segment1 > segment2 > tail, and body > neck, added out of order.
	skeleton.set_bone_parent(2, 0)
	skeleton.set_bone_parent(3, 2)
	skeleton.set_bone_parent(1, 3)
	skeleton.set_bone_parent(4, 1)
	skeleton.set_bone_parent(5, 0)
	return skeleton


func test_finds_segments_from_the_head_end_to_the_tail() -> void:
	var skeleton := _serpent()
	var names := BodyWave.find_segments(skeleton).map(func(bone: int) -> String: return skeleton.get_bone_name(bone))
	assert_eq(names, ["segment", "segment1", "segment2"])
	skeleton.free()


func test_only_still_bodies_count_as_unanimated() -> void:
	var skeleton := _serpent()
	var held := Animation.new()
	var track := held.add_track(Animation.TYPE_ROTATION_3D)
	held.track_set_path(track, "Skeleton:segment1")
	held.rotation_track_insert_key(track, 0.0, Quaternion(Vector3.UP, 0.3))
	held.rotation_track_insert_key(track, 1.0, Quaternion(Vector3.UP, 0.3))
	var segments := BodyWave.find_segments(skeleton)
	assert_false(BodyWave.animated([held], skeleton, segments), "a held pose")
	var swimming := held.duplicate()
	swimming.rotation_track_insert_key(track, 0.5, Quaternion(Vector3.UP, -0.3))
	assert_true(BodyWave.animated([held, swimming], skeleton, segments), "an animation that moves them")
	skeleton.free()


## A rearing serpent: root > body > neck > head going up from the body, and body > segment >
## segment1 > segment2 > tail lying along +Z then curling up. One unit per bone.
func _rearing() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	var bones := {"root": -1, "body": 0, "neck": 1, "head": 2, "segment": 1, "segment1": 4, "segment2": 5, "tail": 6}
	for bone: String in bones:
		skeleton.add_bone(bone)
		skeleton.set_bone_parent(skeleton.get_bone_count() - 1, bones[bone])
	skeleton.set_bone_pose_position(1, Vector3(0, 1, 0))
	# The neck turns up where the body begins, as Rayquaza's does.
	skeleton.set_bone_pose_position(skeleton.find_bone("head"), Vector3.UP)
	# The segments run back along +Z, the last turned to point up.
	for bone in ["segment", "segment1", "segment2"]:
		skeleton.set_bone_pose_position(skeleton.find_bone(bone), Vector3.BACK)
	skeleton.set_bone_pose_rotation(skeleton.find_bone("segment2"), Quaternion(Vector3.RIGHT, -PI / 2))
	skeleton.set_bone_pose_position(skeleton.find_bone("tail"), Vector3.BACK)
	return skeleton


func _heights(skeleton: Skeleton3D, rotations: Dictionary) -> Dictionary:
	var globals := {}
	var heights := {}
	for bone in skeleton.get_bone_count():
		heights[skeleton.get_bone_name(bone)] = BodyWave.global_pose(skeleton, bone, rotations, globals).origin.y
	return heights


func test_the_spine_runs_down_the_segments_to_the_tail_and_up_to_the_head() -> void:
	var skeleton := _rearing()
	var chains := BodyWave.spine(skeleton, BodyWave.find_segments(skeleton), skeleton.find_bone("head"))
	var names := chains.map(func(chain: PackedInt32Array) -> Array:
		return Array(chain).map(func(bone: int) -> String: return skeleton.get_bone_name(bone)))
	assert_eq(names, [["root", "body", "segment", "segment1", "segment2", "tail"], ["root", "body", "neck", "head"]])
	skeleton.free()


func test_a_slump_lays_the_neck_and_tail_level_and_none_rises_on_the_way() -> void:
	var skeleton := _rearing()
	var chains := BodyWave.spine(skeleton, BodyWave.find_segments(skeleton), skeleton.find_bone("head"))
	var standing := _heights(skeleton, {})
	assert_almost_eq(standing.head, 2.0, 1e-4)
	assert_almost_eq(standing.tail, 2.0, 1e-4)
	var previous := standing
	for slump in [0.25, 0.5, 0.75]:
		var heights := _heights(skeleton, BodyWave.lie_down(skeleton, chains, slump))
		for bone: String in heights:
			assert_true(heights[bone] <= previous[bone] + 1e-4, "%s doesn't rise at %s" % [bone, slump])
		previous = heights
	var flat := _heights(skeleton, BodyWave.lie_down(skeleton, chains, 1.0))
	for bone: String in flat:
		if bone != "root":
			assert_almost_eq(flat[bone], 1.0, 1e-4, "%s level with the body" % bone)
	var unslumped := _heights(skeleton, BodyWave.lie_down(skeleton, chains, 0.0))
	for bone: String in standing:
		assert_almost_eq(unslumped[bone], standing[bone], 1e-4, "%s as it stands" % bone)
	skeleton.free()
