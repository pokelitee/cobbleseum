extends TestCase

const SPECIES := {"mon": {"name": "Mon", "types": ["Normal"], "baseStats": {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}}}
const MOVES := {"hit": {"name": "Hit", "category": "Physical", "type": "Normal", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"}}


func _battle() -> Battle:
	var spec := {"seed": 3, "arena": "stadium", "fighters": [{"species": "mon", "moves": ["hit"]}, {"species": "mon", "moves": ["hit"]}]}
	return Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), SimpleAI.pair(3)).battle


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
