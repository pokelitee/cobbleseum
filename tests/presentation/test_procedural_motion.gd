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


func test_a_fainted_body_rests_on_the_ground_rather_than_through_it() -> void:
	# A body 2 m tall and 1.2 m wide, standing on its feet.
	var body := PackedVector2Array([Vector2(-0.6, 0), Vector2(0.6, 0), Vector2(0.6, 2), Vector2(-0.6, 2), Vector2(0, 1)])
	var motion := ProceduralMotion.new(2.0, false)
	motion.faint(body)
	for frame in ProceduralMotion.FAINT_FRAMES * 2:
		motion.next_frame()
		var lowest := INF
		for point in body:
			lowest = minf(lowest, (motion.transform() * Vector3(point.x, point.y, 0)).y)
		assert_true(lowest > -2.0 * ProceduralMotion.FAINT_SINK - 1e-4, "frame %d: no deeper than it settles (%f)" % [frame, lowest])
	var settled := INF
	for point in body:
		settled = minf(settled, (motion.transform() * Vector3(point.x, point.y, 0)).y)
	assert_almost_eq(settled, -2.0 * ProceduralMotion.FAINT_SINK, 1e-4, "lying on its side, just settled into the ground")


func test_a_faint_animation_drops_a_flier_and_is_lifted_out_of_the_ground() -> void:
	var motion := ProceduralMotion.new(2.0, true)
	motion.fall()
	motion.ground_lift = 0.3
	_advance(motion, ProceduralMotion.FAINT_FRAMES * 2)
	var settled := motion.transform()
	assert_almost_eq(settled.origin.y, 0.3, 1e-4, "out of the hover, raised by the lift")
	assert_almost_eq(settled.basis.get_euler().z, 0.0, 1e-4, "the animation lays it down, not a tip-over")
	motion.revive()
	assert_eq(motion.ground_lift, 0.0)


func test_leans_into_movement_and_fliers_bank_more() -> void:
	var walker := ProceduralMotion.new(2.0, false)
	walker.velocity = Vector2(0, 4)
	walker.facing = Vector2(0, 1)
	_advance(walker, 30)
	var pitch := walker.transform().basis.get_euler().x
	assert_true(pitch < -0.05, "leans forward walking forward: %f" % pitch)
	walker.velocity = Vector2.ZERO
	_advance(walker, 60)
	assert_almost_eq(walker.transform().basis.get_euler().x, 0.0, 1e-3, "and straightens up when stopped")
	var flier := ProceduralMotion.new(2.0, true)
	flier.velocity = Vector2(0, 4)
	flier.facing = Vector2(0, 1)
	_advance(flier, 30)
	assert_true(flier.transform().basis.get_euler().x < pitch, "fliers lean further")


func test_fliers_swoop_only_when_faster_than_walking() -> void:
	var flier := ProceduralMotion.new(2.0, true)
	flier.velocity = Vector2(ProceduralMotion.SWOOP_FROM, 0)
	_advance(flier, 30)
	assert_almost_eq(flier._swoop, 0.0, 1e-6, "walking pace keeps the hover")
	flier.velocity = Vector2(ProceduralMotion.SWOOP_FULL, 0)
	_advance(flier, 30)
	assert_true(flier._swoop > 0.95, "a dash dives")
	var bob := ProceduralMotion.HOVER_BOB * 2.0
	assert_true(flier.transform().origin.y < 2.0 * (ProceduralMotion.HOVER_HEIGHT * (1.0 - ProceduralMotion.SWOOP_DEPTH * 0.95)) + bob)


func test_landing_squashes_then_recovers() -> void:
	var motion := ProceduralMotion.new(2.0, false)
	motion.start("land")
	_advance(motion, ProceduralMotion.ACTION_FRAMES.land / 2)
	assert_true(motion.transform().basis.get_scale().y < 0.95)
	_advance(motion, ProceduralMotion.ACTION_FRAMES.land)
	assert_true(motion.transform().is_equal_approx(Transform3D.IDENTITY))


func test_revive_stands_a_fainted_fighter_up() -> void:
	var motion := ProceduralMotion.new(1.5, false)
	var rest := motion.transform()
	motion.faint()
	_advance(motion, 120)
	assert_false(motion.transform().is_equal_approx(rest))
	motion.revive()
	_advance(motion, 1)
	assert_true(motion.transform().is_equal_approx(rest), "back at rest")


func test_serpents_slither_rather_than_hop_and_wave_harder_when_moving() -> void:
	var serpent := ProceduralMotion.new(2.0, false)
	serpent.slithers = true
	_advance(serpent, 60)
	assert_almost_eq(serpent.wave_strength, ProceduralMotion.WAVE_REST, 1e-3, "a gentle wave at rest")
	var resting_phase := serpent.wave_phase
	serpent.moving = true
	serpent.velocity = Vector2(ProceduralMotion.LEAN_SPEED, 0)
	_advance(serpent, 60)
	assert_almost_eq(serpent.wave_strength, 1.0, 1e-3, "a full wave moving")
	assert_true(serpent.wave_phase - resting_phase > 60 * ProceduralMotion.WAVE_REST_SPEED * 2.0, "travelling faster")
	assert_almost_eq(serpent.transform().origin.y, 0.0, 1e-6, "no hop")
	var paused := serpent.wave_phase
	_advance(serpent, 10, 0.0)
	assert_eq(serpent.wave_phase, paused, "hit-stop freezes it")


func test_a_fainted_serpent_drops_without_tipping_over_and_stops_waving() -> void:
	var serpent := ProceduralMotion.new(3.0, true)
	serpent.slithers = true
	_advance(serpent, 30)
	serpent.faint(PackedVector2Array([Vector2(-1, 0), Vector2(3, 0), Vector2(0, 4)]))
	_advance(serpent, ProceduralMotion.FAINT_FRAMES * 3)
	assert_almost_eq(serpent.transform().basis.get_euler().z, 0.0, 1e-4, "its coils stay down")
	assert_almost_eq(serpent.transform().origin.y, 0.0, 1e-4, "out of the hover, on the ground")
	assert_almost_eq(serpent.wave_strength, 0.0, 1e-3)

