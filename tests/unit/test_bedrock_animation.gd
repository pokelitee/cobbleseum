extends TestCase
## Uses small hand-written clips, never Cobblemon files.


func _keys(raw: Variant) -> Array:
	return BedrockAnimation._compile_channel(raw, {})


func _at(raw: Variant, t: float) -> Vector3:
	return BedrockAnimation.sample(_keys(raw), t, RandomNumberGenerator.new())


func test_constant_channels() -> void:
	assert_eq(_at([1, 2, 3], 5.0), Vector3(1, 2, 3))
	assert_eq(_at(2, 0.0), Vector3(2, 2, 2), "a single number applies to every axis")


func test_linear_between_plain_keys() -> void:
	var channel := {"0.0": [0, 0, 0], "1.0": [10, 20, -10]}
	assert_true(_at(channel, 0.5).is_equal_approx(Vector3(5, 10, -5)))
	assert_eq(_at(channel, -1.0), Vector3.ZERO)
	assert_eq(_at(channel, 2.0), Vector3(10, 20, -10))


func test_pre_and_post_make_a_jump() -> void:
	var channel := {"0.0": [0, 0, 0], "1.0": {"pre": [10, 0, 0], "post": [100, 0, 0]}, "2.0": [100, 0, 0]}
	assert_true(_at(channel, 0.5).is_equal_approx(Vector3(5, 0, 0)))
	assert_true(_at(channel, 1.0).is_equal_approx(Vector3(100, 0, 0)))


func test_catmull_rom_passes_through_keys_and_smooths() -> void:
	var smooth := {"lerp_mode": "catmullrom"}
	var channel := {
		"0.0": smooth.merged({"post": [0, 0, 0]}),
		"1.0": smooth.merged({"post": [10, 0, 0]}),
		"2.0": smooth.merged({"post": [10, 0, 0]}),
	}
	assert_true(_at(channel, 1.0).is_equal_approx(Vector3(10, 0, 0)))
	var midpoint := _at(channel, 1.5)
	assert_true(midpoint.x > 10.0, "overshoots like a spline, got %s" % midpoint)


func test_molang_keys_use_animation_time() -> void:
	assert_true(_at(["math.sin(q.anim_time * 90)", 0, 0], 1.0).is_equal_approx(Vector3(1, 0, 0)))


func _skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("arm")
	skeleton.set_bone_rest(0, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)))
	return skeleton


func test_build_adds_rest_rotation_and_position() -> void:
	var skeleton := _skeleton()
	var clip := {"animation_length": 1.0, "loop": true, "bones": {"arm": {
		"rotation": {"0.0": [0, 0, 0], "1.0": [0, 0, 90]},
		"position": [16, 0, 0],
	}, "ghost": {"rotation": [1, 0, 0]}}}
	var report := {}
	var animation := BedrockAnimation.build(clip, "test.clip", skeleton, {"arm": [0, 0, 0]}, "Skeleton", report)
	assert_eq(animation.loop_mode, Animation.LOOP_LINEAR)
	assert_almost_eq(animation.length, 1.0, 1e-9)
	assert_eq(report.get("unknown_bones", {}).keys(), ["ghost"])
	var rotation_track := animation.find_track("Skeleton:arm", Animation.TYPE_ROTATION_3D)
	var end: Quaternion = animation.rotation_track_interpolate(rotation_track, 1.0)
	assert_true(end.is_equal_approx(Basis(Vector3(0, 0, 1), deg_to_rad(90)).get_rotation_quaternion()))
	var position_track := animation.find_track("Skeleton:arm", Animation.TYPE_POSITION_3D)
	# Positions are offsets in pixels with X mirrored, added to the rest position.
	assert_true(animation.position_track_interpolate(position_track, 0.5).is_equal_approx(Vector3(-1, 1, 0)))
	skeleton.free()


func test_hold_on_last_frame_does_not_loop() -> void:
	var skeleton := _skeleton()
	var clip := {"loop": "hold_on_last_frame", "bones": {"arm": {"rotation": {"0.0": [0, 0, 0], "0.5": [10, 0, 0]}}}}
	var animation := BedrockAnimation.build(clip, "test.clip", skeleton, {}, "Skeleton", {})
	assert_eq(animation.loop_mode, Animation.LOOP_NONE)
	assert_almost_eq(animation.length, 0.5, 1e-9, "length falls back to the last key")
	skeleton.free()


func test_choose_clips_prefers_poser_then_names() -> void:
	var poser := {
		"poses": {"battle-standing": {"isBattle": true, "poseTypes": ["STAND"],
			"animations": ["q.look('head')", "q.bedrock('mon', 'fight_idle')"],
			"namedAnimations": {"cry": "q.bedrock_primary('mon', 'battle_cry', q.curve('one'))"}}},
		"animations": {"physical": "q.bedrock_primary('mon', 'punch', q.curve('one'))", "special": "q.bedrock('mon', 'missing')"},
	}
	var available := ["mon.fight_idle", "mon.battle_cry", "mon.punch", "mon.special", "mon.ground_walk", "mon.battle_idle"]
	var roles := CobblemonModel.choose_clips(poser, available, ["mon"] as Array[String])
	assert_eq(roles.idle, "mon.fight_idle")
	assert_eq(roles.cry, "mon.battle_cry")
	assert_eq(roles.physical, "mon.punch")
	assert_eq(roles.special, "mon.special", "falls back to the name when the poser's clip is missing")
	assert_eq(roles.walk, "mon.ground_walk")
	assert_false(roles.has("faint"))


func test_choose_clips_without_poser_uses_names() -> void:
	var roles := CobblemonModel.choose_clips({}, ["mon.ground_idle", "mon.hurt"], ["mon"] as Array[String])
	assert_eq(roles, {"idle": "mon.ground_idle", "recoil": "mon.hurt"})


func test_choose_clips_falls_back_across_animation_groups() -> void:
	# A form's poser (mon_large) whose clips live in the species' group (mon).
	var standing := {"poses": {"standing": {"poseTypes": ["STAND"], "animations": ["q.bedrock('mon', 'ground_idle')"]}}}
	var roles := CobblemonModel.choose_clips(standing, ["mon.ground_idle", "mon.cry"], ["mon_large", "mon"] as Array[String])
	assert_eq(roles.idle, "mon.ground_idle", "a non-battle standing pose counts when there's no battle pose")
	assert_eq(roles.cry, "mon.cry", "fallback names are searched in the species' group too")
	var floating := CobblemonModel.choose_clips({}, ["bug.air_idle", "bug.blink"], ["other"] as Array[String])
	assert_eq(floating.idle, "bug.air_idle", "air idles count, in any group the files hold")


const BIRD := {"poses": {
	"standing": {"poseTypes": ["STAND", "NONE"], "animations": ["q.bedrock('bird', 'ground_idle')"],
		"transformedParts": [{"part": "wing_open", "isVisible": false}, {"part": "wing_closed", "isVisible": true}]},
	"hover": {"poseTypes": ["HOVER", "FLOAT"], "animations": ["q.pitch_tilt('body')", "q.bedrock('bird', 'air_idle')"],
		"transformedParts": [{"part": "wing_open", "isVisible": true}, {"part": "wing_closed", "isVisible": false}, {"part": "ghost", "isVisible": false}]},
	"fly": {"poseTypes": ["FLY", "SWIM"], "animations": ["q.bedrock('bird', 'air_fly')"],
		"transformedParts": [{"part": "wing_open", "isVisible": true}, {"part": "wing_closed", "isVisible": false}]},
}}


func test_air_roles_come_from_hover_and_fly_poses() -> void:
	var roles := CobblemonModel.choose_clips(BIRD, ["bird.ground_idle", "bird.air_idle", "bird.air_fly"], ["bird"] as Array[String])
	assert_eq(roles.idle, "bird.ground_idle")
	assert_eq(roles.air_idle, "bird.air_idle")
	assert_eq(roles.air_fly, "bird.air_fly")
	var grounded := CobblemonModel.choose_clips({}, ["mon.ground_idle"], ["mon"] as Array[String])
	assert_false(grounded.has("air_idle"), "only species with air clips get air roles")


func test_part_sets_follow_the_standing_and_hover_poses() -> void:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("wing_open")
	skeleton.add_bone("wing_closed")
	var sets := CobblemonModel.part_sets(BIRD, skeleton)
	assert_eq(sets.ground, {"wing_open": false, "wing_closed": true})
	assert_eq(sets.air, {"wing_open": true, "wing_closed": false}, "bones the model lacks are left out")
	assert_eq(CobblemonModel.part_sets({}, skeleton), {}, "no poser, nothing swaps")
	skeleton.free()

