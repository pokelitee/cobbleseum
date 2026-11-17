extends TestCase


func _step(smooth: SmoothMotion, node: Node3D, to: Vector3) -> void:
	smooth.restore()
	node.position = to
	smooth.capture()


func test_shows_nodes_between_steps() -> void:
	var smooth := SmoothMotion.new()
	var node := Node3D.new()
	smooth.track(node)
	_step(smooth, node, Vector3(1, 0, 0))
	_step(smooth, node, Vector3(3, 0, 0))
	smooth.show(0.5)
	assert_eq(node.position, Vector3(2, 0, 0))
	assert_eq(smooth.offset_of(node), Vector3(-1, 0, 0), "drawn a step's half behind where the step left it")
	node.free()


func test_steps_see_where_the_last_step_left_nodes() -> void:
	var smooth := SmoothMotion.new()
	var node := Node3D.new()
	smooth.track(node)
	_step(smooth, node, Vector3(0, 0, 2))
	_step(smooth, node, Vector3(0, 0, 4))
	smooth.show(0.25)
	smooth.restore()
	assert_eq(node.position, Vector3(0, 0, 4))
	node.free()


func test_new_and_snapped_nodes_do_not_slide() -> void:
	var smooth := SmoothMotion.new()
	var node := Node3D.new()
	_step(smooth, node, Vector3(5, 0, 0))
	smooth.track(node)
	_step(smooth, node, Vector3(6, 0, 0))
	smooth.show(0.0)
	assert_eq(node.position, Vector3(6, 0, 0), "a node added in a step starts where it was put")
	smooth.restore()
	node.position = Vector3(20, 0, 0)
	smooth.snap(node)
	smooth.capture()
	smooth.show(0.5)
	assert_eq(node.position, Vector3(20, 0, 0), "a snapped node jumps")
	node.free()


func test_camera_field_of_view_is_smoothed_and_snaps() -> void:
	var smooth := SmoothMotion.new()
	var camera := Camera3D.new()
	camera.fov = 40.0
	smooth.track_camera(camera)
	smooth.capture()
	smooth.restore()
	camera.fov = 50.0
	smooth.capture()
	smooth.show(0.5)
	assert_almost_eq(camera.fov, 45.0, 1e-4)
	smooth.restore()
	camera.fov = 30.0
	smooth.snap_all()
	smooth.capture()
	smooth.show(0.5)
	assert_almost_eq(camera.fov, 30.0, 1e-4)
	camera.free()


func test_freed_nodes_are_dropped() -> void:
	var smooth := SmoothMotion.new()
	var node := Node3D.new()
	smooth.track(node)
	smooth.capture()
	node.free()
	smooth.capture()
	smooth.show(0.5)
	smooth.restore()
	assert_true(true, "no errors from a freed node")
