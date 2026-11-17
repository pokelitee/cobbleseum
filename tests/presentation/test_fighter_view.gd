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
