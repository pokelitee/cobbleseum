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
