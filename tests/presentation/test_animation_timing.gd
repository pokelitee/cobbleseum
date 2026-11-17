extends TestCase


## An attack that winds up slowly, swings hard at `strike` seconds, then recovers slowly.
func _attack(strike: float) -> Animation:
	var animation := Animation.new()
	animation.length = 3.0
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, "Skeleton:arm")
	animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track, strike - 0.1, Quaternion(Vector3.RIGHT, -0.4))
	animation.rotation_track_insert_key(track, strike, Quaternion(Vector3.RIGHT, 1.2))
	animation.rotation_track_insert_key(track, 3.0, Quaternion.IDENTITY)
	return animation


func test_the_strike_is_where_the_bones_turn_fastest() -> void:
	assert_almost_eq(AnimationTiming.strike_time(_attack(1.2)), 1.2, 0.05)
	assert_almost_eq(AnimationTiming.strike_time(_attack(0.8)), 0.8, 0.05)


func test_held_poses_are_still_and_breathing_is_not() -> void:
	var held := Animation.new()
	held.length = 1.0 / 60.0
	var track := held.add_track(Animation.TYPE_ROTATION_3D)
	held.track_set_path(track, "Skeleton:body")
	held.rotation_track_insert_key(track, 0.0, Quaternion(Vector3.UP, 0.3))
	held.rotation_track_insert_key(track, held.length, Quaternion(Vector3.UP, 0.3))
	assert_true(AnimationTiming.is_still(held))
	var breathing := Animation.new()
	breathing.length = 3.0
	track = breathing.add_track(Animation.TYPE_ROTATION_3D)
	breathing.track_set_path(track, "Skeleton:body")
	breathing.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	breathing.rotation_track_insert_key(track, 1.5, Quaternion(Vector3.RIGHT, 0.05))
	breathing.rotation_track_insert_key(track, 3.0, Quaternion.IDENTITY)
	assert_false(AnimationTiming.is_still(breathing))
