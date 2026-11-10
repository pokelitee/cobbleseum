extends TestCase


func _advance(motion: ProceduralMotion, frames: int, time_scale := 1.0) -> void:
	for i in frames:
		motion.next_frame(time_scale)


func test_at_rest_there_is_no_offset() -> void:
	var motion := ProceduralMotion.new(2.0, false)
	_advance(motion, 10)
	assert_eq(motion.transform(), Transform3D.IDENTITY)


func test_lunge_goes_forward_and_comes_back() -> void:
	var motion := ProceduralMotion.new(2.0, false)
	motion.start("lunge")
	_advance(motion, ProceduralMotion.ACTION_FRAMES.lunge / 2)
	assert_true(motion.transform().origin.z < -0.5, "forward is -Z: %s" % motion.transform().origin)
	_advance(motion, ProceduralMotion.ACTION_FRAMES.lunge)
	assert_true(motion.transform().is_equal_approx(Transform3D.IDENTITY), "back to rest when done")


func test_hitstop_freezes_actions() -> void:
	var motion := ProceduralMotion.new(2.0, false)
	motion.start("tilt")
	_advance(motion, 3)
	var held := motion.transform()
	_advance(motion, 20, 0.0)
	assert_eq(motion.transform(), held)


func test_hops_only_while_moving_and_flyers_hover() -> void:
	var walker := ProceduralMotion.new(1.0, false)
	walker.moving = true
	_advance(walker, 3)
	assert_true(walker.transform().origin.y > 0.0)
	var flyer := ProceduralMotion.new(1.0, true)
	_advance(flyer, 1)
	assert_almost_eq(flyer.transform().origin.y, ProceduralMotion.HOVER_HEIGHT, ProceduralMotion.HOVER_BOB + 1e-6)


func test_squash_and_stretch_keeps_volume_roughly() -> void:
	var motion := ProceduralMotion.new(1.0, false)
	motion.start("rear")
	_advance(motion, ProceduralMotion.ACTION_FRAMES.rear / 4)
	var scale := motion.transform().basis.get_scale()
	assert_true(scale.y > 1.0 and scale.x < 1.0, str(scale))
	assert_almost_eq(scale.x * scale.y * scale.z, 1.0, 0.02)


func test_faint_tips_over_sinks_and_stays() -> void:
	var motion := ProceduralMotion.new(2.0, true)
	motion.faint()
	_advance(motion, ProceduralMotion.FAINT_FRAMES * 3)
	var settled := motion.transform()
	assert_almost_eq(settled.basis.get_euler().z, ProceduralMotion.FAINT_ANGLE, 1e-3)
	assert_almost_eq(settled.origin.y, -2.0 * ProceduralMotion.FAINT_SINK, 1e-4, "a flyer drops too")
	motion.start("lunge")
	_advance(motion, 2)
	assert_true(motion.transform().is_equal_approx(settled), "no actions after fainting")
