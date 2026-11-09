extends TestCase
## Uses small hand-written geometry, never Cobblemon files.


func _geo(bones: Array, texture := 64) -> Dictionary:
	return {"format_version": "1.12.0", "minecraft:geometry": [{
		"description": {"identifier": "geometry.test", "texture_width": texture, "texture_height": texture},
		"bones": bones,
	}]}


func _build(bones: Array) -> Node3D:
	var result := BedrockGeometry.build(_geo(bones), null, "Test")
	assert_false(result.has("error"), str(result.get("error", "")))
	return result.get("scene")


func _vertices(scene: Node3D) -> PackedVector3Array:
	var mesh: ArrayMesh = scene.get_node("Skeleton/Mesh").mesh
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func test_cube_position_mirrors_x_and_uses_sixteen_pixels_per_metre() -> void:
	var scene := _build([{"name": "body", "pivot": [0, 0, 0], "cubes": [{"origin": [2, 0, -4], "size": [4, 8, 2], "uv": [0, 0]}]}])
	var box := _bounds(_vertices(scene))
	assert_almost_eq(box.position.x, -6.0 / 16.0, 1e-6)
	assert_almost_eq(box.end.x, -2.0 / 16.0, 1e-6)
	assert_almost_eq(box.position.y, 0.0, 1e-6)
	assert_almost_eq(box.end.y, 0.5, 1e-6)
	assert_almost_eq(box.position.z, -0.25, 1e-6)
	assert_almost_eq(box.end.z, -0.125, 1e-6)
	assert_eq(_vertices(scene).size(), 36, "six faces of two triangles")
	scene.free()


func test_inflate_grows_every_side() -> void:
	var scene := _build([{"name": "b", "cubes": [{"origin": [0, 0, 0], "size": [16, 16, 16], "uv": [0, 0], "inflate": 1}]}])
	var box := _bounds(_vertices(scene))
	assert_almost_eq(box.size.x, 18.0 / 16.0, 1e-6)
	assert_almost_eq(box.position.y, -1.0 / 16.0, 1e-6)
	scene.free()


func test_zero_thickness_cube_keeps_two_faces() -> void:
	var scene := _build([{"name": "b", "cubes": [{"origin": [0, 0, 0], "size": [2, 2, 0], "uv": [0, 0]}]}])
	assert_eq(_vertices(scene).size(), 12)
	scene.free()


func test_bone_hierarchy_and_rest_transforms() -> void:
	var scene := _build([
		{"name": "head", "parent": "body", "pivot": [0, 24, -2]},
		{"name": "body", "pivot": [4, 12, 0], "rotation": [0, 0, 30]},
	])
	var skeleton: Skeleton3D = scene.get_node("Skeleton")
	assert_eq(skeleton.get_bone_name(0), "body", "parents are ordered first")
	var head := skeleton.find_bone("head")
	assert_eq(skeleton.get_bone_parent(head), 0)
	var head_rest := skeleton.get_bone_rest(head)
	assert_true(head_rest.origin.is_equal_approx(Vector3(4, 12, -2) / 16.0), str(head_rest.origin))
	var body_rest := skeleton.get_bone_rest(0)
	assert_true(body_rest.origin.is_equal_approx(Vector3(-4, 12, 0) / 16.0))
	# Z rotation keeps its sign: +30 degrees about +Z.
	assert_true(body_rest.basis.is_equal_approx(Basis(Vector3(0, 0, 1), deg_to_rad(30))))
	scene.free()


func test_rotation_basis_negates_x_and_y() -> void:
	var basis := BedrockGeometry.rotation_basis([90, 0, 0])
	assert_true(basis.is_equal_approx(Basis(Vector3(1, 0, 0), deg_to_rad(-90))))
	basis = BedrockGeometry.rotation_basis([0, 90, 0])
	assert_true(basis.is_equal_approx(Basis(Vector3(0, 1, 0), deg_to_rad(-90))))


func test_rotated_parent_moves_child_cube_but_skin_undoes_rest() -> void:
	var scene := _build([
		{"name": "arm", "pivot": [0, 16, 0], "rotation": [0, 0, 90],
			"cubes": [{"origin": [0, 16, 0], "size": [8, 1, 1], "uv": [0, 0]}]},
	])
	var box := _bounds(_vertices(scene))
	# The arm points along -X in Godot; rotating +90 about Z swings it to point down.
	assert_almost_eq(box.end.y, 1.0, 1e-5)
	assert_almost_eq(box.position.y, 0.5, 1e-5)
	var mesh_instance: MeshInstance3D = scene.get_node("Skeleton/Mesh")
	var bind := mesh_instance.skin.get_bind_pose(0)
	var skeleton: Skeleton3D = scene.get_node("Skeleton")
	assert_true((skeleton.get_bone_global_rest(0) * bind).is_equal_approx(Transform3D.IDENTITY))
	scene.free()


func test_box_uv_layout() -> void:
	var uv := BedrockGeometry.box_uv(Vector2(10, 20), Vector3(4, 8, 2), false)
	assert_eq(uv.east, [Vector2(10, 22), Vector2(2, 8)])
	assert_eq(uv.north, [Vector2(12, 22), Vector2(4, 8)])
	assert_eq(uv.west, [Vector2(16, 22), Vector2(2, 8)])
	assert_eq(uv.south, [Vector2(18, 22), Vector2(4, 8)])
	assert_eq(uv.up, [Vector2(16, 22), Vector2(-4, -2)])
	assert_eq(uv.down, [Vector2(20, 20), Vector2(-4, 2)])


func test_mirror_swaps_east_and_west_and_flips() -> void:
	var uv := BedrockGeometry.box_uv(Vector2.ZERO, Vector3(4, 8, 2), true)
	assert_eq(uv.east, [Vector2(8, 2), Vector2(-2, 8)])
	assert_eq(uv.west, [Vector2(2, 2), Vector2(-2, 8)])
	assert_eq(uv.north, [Vector2(6, 2), Vector2(-4, 8)])


func test_locators_are_relative_to_their_bone() -> void:
	var scene := _build([{"name": "head", "pivot": [0, 20, 0], "locators": {"target": [0, 20, -16]}}])
	var locators: Dictionary = scene.get_meta("locators")
	assert_eq(locators.target.bone, "head")
	assert_true((locators.target.position as Vector3).is_equal_approx(Vector3(0, 0, -1)))
	scene.free()


func test_reports_bad_hierarchies() -> void:
	assert_true(BedrockGeometry.build(_geo([{"name": "a", "parent": "missing"}]), null, "T").error.contains("unknown parent"))
	assert_true(BedrockGeometry.build(_geo([{"name": "a"}, {"name": "a"}]), null, "T").error.contains("duplicate"))
	assert_true(BedrockGeometry.build(_geo([{"name": "a", "parent": "b"}, {"name": "b", "parent": "a"}]), null, "T").error.contains("cycle"))
	assert_true(BedrockGeometry.build({}, null, "T").error.contains("no minecraft:geometry"))
