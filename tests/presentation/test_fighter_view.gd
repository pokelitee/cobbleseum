extends TestCase
## How fighters' converted models are shaded (concepts_brief.md §12.7).


func test_models_are_matte_with_a_rim_and_emissive_layers_bloom() -> void:
	var base := StandardMaterial3D.new()
	base.roughness = 1.0
	var emissive := StandardMaterial3D.new()
	emissive.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	base.next_pass = emissive
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, base)
	FighterView.shade(mesh)
	assert_eq(base.specular_mode, BaseMaterial3D.SPECULAR_DISABLED, "matte")
	assert_true(base.rim_enabled and base.rim > 0.0, "a rim")
	assert_true(emissive.albedo_color.r > ArenaLighting.HDR_THRESHOLD, "emissive layers bloom")
	assert_false(emissive.rim_enabled, "unshaded layers are left unlit")
	FighterView.shade(mesh)
	assert_eq(emissive.albedo_color.r, FighterView.EMISSIVE_ENERGY, "shading twice changes nothing")


func test_a_skin_is_worn_and_shaded_and_a_missing_one_is_left_off() -> void:
	var dir := TestFiles.fresh_dir("fighter_view_skin")
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	root.add_child(skeleton)
	skeleton.owner = root
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.material = StandardMaterial3D.new()
	mesh.mesh = box
	skeleton.add_child(mesh)
	mesh.owner = root
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.add_animation_library("", AnimationLibrary.new())
	root.add_child(player)
	player.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	ResourceSaver.save(scene, dir.path_join("mon.scn"))
	var skin := StandardMaterial3D.new()
	skin.roughness = 1.0
	ResourceSaver.save(skin, dir.path_join("mon~shiny.res"))
	var view := FighterView.from_model(dir.path_join("mon.scn"), 1.0, 1.0, dir.path_join("mon~shiny.res"))
	var worn := view._mesh.get_surface_override_material(0) as StandardMaterial3D
	assert_true(worn != null and worn.rim_enabled, "the skin is worn, shaded like the model's own material")
	view.free()
	expected_errors = 1
	var plain := FighterView.from_model(dir.path_join("mon.scn"), 1.0, 1.0, dir.path_join("missing.res"))
	assert_true(plain != null and plain._mesh.get_surface_override_material(0) == null, "a missing skin is left off")
	plain.free()


func _animation(tracks: Dictionary, loop := Animation.LOOP_NONE) -> Animation:
	var animation := Animation.new()
	animation.length = 1.0
	animation.loop_mode = loop
	for bone: String in tracks:
		var track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, "Skeleton:" + bone)
		animation.position_track_insert_key(track, 0.0, tracks[bone])
	return animation


func test_base_animations_put_back_bones_only_other_animations_move() -> void:
	var skeleton := Skeleton3D.new()
	for bone in ["body", "eyelid"]:
		skeleton.add_bone(bone)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	var library := AnimationLibrary.new()
	library.add_animation("idle", _animation({"body": Vector3(0, 0.1, 0)}, Animation.LOOP_LINEAR))
	library.add_animation("hurt", _animation({"body": Vector3.ZERO, "eyelid": Vector3(0, 1, -0.1)}))
	var roles := {"idle": "idle", "recoil": "hurt"}
	FighterView.pad_base_animations(library, roles, skeleton)
	var idle := library.get_animation("idle")
	var track := idle.find_track(NodePath("Skeleton:eyelid"), Animation.TYPE_POSITION_3D)
	assert_true(track >= 0, "the idle puts the eyelid back")
	assert_eq(idle.position_track_interpolate(track, 0.5), Vector3(0, 1, 0), "at its rest pose")
	assert_eq(library.get_animation("hurt").get_track_count(), 2, "one-offs are left alone")
	FighterView.pad_base_animations(library, roles, skeleton)
	assert_eq(idle.get_track_count(), 2, "padding again adds nothing")
	skeleton.free()


func test_a_species_without_an_idle_holds_its_rest_pose_and_returns_to_it() -> void:
	var skeleton := Skeleton3D.new()
	for bone in ["body", "leg"]:
		skeleton.add_bone(bone)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0)))
	var library := AnimationLibrary.new()
	library.add_animation("walk", _animation({"leg": Vector3(0, 0.5, 0.2)}, Animation.LOOP_LINEAR))
	var roles := {"walk": "walk"}
	FighterView.add_rest_idle(library, roles)
	FighterView.pad_base_animations(library, roles, skeleton)
	assert_eq(roles.idle, FighterView.REST_IDLE)
	var idle := library.get_animation(roles.idle)
	var track := idle.find_track(NodePath("Skeleton:leg"), Animation.TYPE_POSITION_3D)
	assert_true(track >= 0 and idle.position_track_interpolate(track, 0.5) == Vector3(0, 0.5, 0), "the leg stops at rest")
	assert_true(AnimationTiming.is_still(idle), "so it breathes")
	var own := {"idle": "walk"}
	FighterView.add_rest_idle(library, own)
	assert_eq(own.idle, "walk", "a species' own idle is kept")
	skeleton.free()


func test_looping_one_offs_play_once_and_a_faint_is_left_as_authored() -> void:
	var library := AnimationLibrary.new()
	library.add_animation("idle", _animation({}, Animation.LOOP_LINEAR))
	library.add_animation("angry", _animation({}, Animation.LOOP_LINEAR))
	library.add_animation("faint", _animation({}, Animation.LOOP_LINEAR))
	FighterView.play_one_offs_once(library, {"idle": "idle", "angry": "angry", "faint": "faint"})
	assert_eq(library.get_animation("angry").loop_mode, Animation.LOOP_NONE)
	assert_eq(library.get_animation("idle").loop_mode, Animation.LOOP_LINEAR)
	assert_eq(library.get_animation("faint").loop_mode, Animation.LOOP_LINEAR)


func test_head_points_are_the_head_bone_and_the_bones_under_it() -> void:
	var view := FighterView.new()
	var skeleton := Skeleton3D.new()
	view.add_child(skeleton)
	for bone: Array in [["body", -1], ["head", 0], ["ear", 1], ["tail", 0]]:
		skeleton.add_bone(bone[0])
		skeleton.set_bone_parent(skeleton.get_bone_count() - 1, bone[1])
	var vertices := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 2, 0), Vector3(1, 0, 0)])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in vertices.size():
		bones.append_array([i, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var skin := Skin.new()
	for i in skeleton.get_bone_count():
		skin.add_named_bind(skeleton.get_bone_name(i), Transform3D.IDENTITY)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.skin = skin
	skeleton.add_child(instance)
	view._mesh = instance
	assert_eq(view.posed_points().size(), 4)
	assert_eq(view.head_points(), PackedVector3Array([Vector3(0, 1, 0), Vector3(0, 2, 0)]), "the head and its ear, not the body or tail")
	skeleton.set_bone_name(1, "neck")
	assert_eq(view.head_points(), PackedVector3Array(), "none without a head bone")
	view.free()
