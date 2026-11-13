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
