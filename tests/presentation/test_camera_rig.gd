extends TestCase

const SPECIES := {"mon": {"name": "Mon", "types": ["Normal"], "baseStats": {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}}}
const MOVES := {"hit": {"name": "Hit", "category": "Physical", "type": "Normal", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"}}


func _battle() -> Battle:
	var spec := {"seed": 3, "arena": "stadium", "fighters": [{"species": "mon", "moves": ["hit"]}, {"species": "mon", "moves": ["hit"]}]}
	return Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), StandInAI.pair(3)).battle


func _poses(seed: int) -> Array:
	var battle := _battle()
	var rig := CameraRig.new(false, [3.0, 3.0], SimRandom.new(seed))
	var camera := Camera3D.new()
	var poses: Array = []
	for shot in Director.Shot.values():
		rig.apply(camera, {"start": 0, "end": 30, "shot": shot, "side": 0}, battle, 0.5, 0.5, 1.7, true)
		poses.append([camera.position, camera.fov])
	camera.free()
	return poses


func test_same_seed_same_camera() -> void:
	assert_eq(_poses(1), _poses(1))
	assert_true(_poses(1) != _poses(2), "the wobble follows the seed")


func test_camera_stays_out_of_fighters() -> void:
	var battle := _battle()
	battle.fighters[0].position = Vector2(0, -1)
	battle.fighters[1].position = Vector2(0, 1)
	var rig := CameraRig.new(true, [3.0, 3.0], SimRandom.new(1))
	for shot in Director.Shot.values():
		for progress in [0.0, 0.5, 1.0]:
			var pose := rig.pose_for({"start": 0, "end": 30, "shot": shot, "side": 0}, battle, progress * 2.0, progress, true)
			for fighter in battle.fighters:
				var ground := Vector2(pose.position.x, pose.position.z)
				assert_true(ground.distance_to(fighter.position) >= 3.0 * CameraRig.CLEARANCE + fighter.radius - 1e-6,
					"shot %s at %s is inside a fighter" % [Director.Shot.keys()[shot], progress])


func test_nearby_angles_blend_and_distant_ones_cut() -> void:
	var battle := _battle()
	battle.fighters[0].position = Vector2(0, -2)
	battle.fighters[1].position = Vector2(0, 2)
	var rig := CameraRig.new(false, [1.5, 1.5], SimRandom.new(1))
	var camera := Camera3D.new()
	rig.apply(camera, {"start": 0, "end": 90, "shot": Director.Shot.OVER_SHOULDER, "side": 0}, battle, 0.0, 0.0, 0.0, true)
	assert_true(rig.cut, "the first shot cuts in")
	var before := camera.position
	# The same angle from the other side's shoulder is far away: a cut.
	rig.apply(camera, {"start": 90, "end": 180, "shot": Director.Shot.OVER_SHOULDER, "side": 1}, battle, 0.0, 0.0, 0.0, true)
	assert_true(rig.cut, "a far angle cuts")
	# The low version of the same shot sits near where the camera is now: it eases over instead.
	var near := rig.pose_for({"start": 180, "end": 270, "shot": Director.Shot.OVER_SHOULDER, "side": 1}, battle, 0.0, 0.0, false)
	assert_true(near.position.distance_to(camera.position) < CameraRig.NEAR_DISTANCE)
	rig.apply(camera, {"start": 180, "end": 270, "shot": Director.Shot.OVER_SHOULDER, "side": 1, "low": true}, battle, 0.0, 0.0, 0.0, true)
	assert_false(rig.cut, "a nearby angle blends")
	assert_true(camera.position.distance_to(before) > 0.1)
	camera.free()
