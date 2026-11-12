extends TestCase
## Play mode's pieces (concepts_brief.md §9.1, §10): the player controller, intent logging and
## replays, and the player camera.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
}


func _data() -> BattleData:
	var data := BattleData.new(SPECIES, MOVES, {})
	data.versions = {"showdown": "a".repeat(64), "cobblemon": "b".repeat(64)}
	return data


func _spec(seed := 5) -> Dictionary:
	return {"seed": seed, "fighters": [{"species": "squirt", "moves": ["jet", "kick"], "ai": "player"},
		{"species": "squirt", "moves": ["jet", "kick"], "ai": "hard"}]}


func test_player_movement_is_camera_relative() -> void:
	var player := PlayerController.new()
	player.camera_forward = Vector2(1, 0)
	assert_eq(player.to_world(Vector2(0, 1)), Vector2(1, 0), "stick forward goes where the camera looks")
	assert_eq(player.to_world(Vector2(1, 0)), Vector2(0, 1), "stick right goes to the camera's right")
	assert_eq(player.to_world(Vector2(0.123456, 0)), Vector2(0, 0.12), "rounded to short, exact steps")


func test_presses_are_latched_until_the_next_tick() -> void:
	var created := Battle.create(_spec(), _data(), Controllers.for_spec(_spec()).controllers)
	var battle: Battle = created.battle
	var player: PlayerController = Controllers.for_spec(_spec()).controllers[0]
	player.pending_use = 1
	player.pending_dodge = true
	var intent := player.decide(battle, 0)
	assert_eq(intent.use, 1)
	assert_true(intent.has("dodge"), "a dodge with the stick centred goes sideways")
	assert_false(player.decide(battle, 0).has("use"), "used once, then cleared")


func test_intents_survive_the_log_format() -> void:
	var intent := {"move": Vector2(0.5, -0.25), "use": 2, "dodge": Vector2(1, 0)}
	assert_eq(Battle.intent_from_log(Battle.intent_to_log(intent)), intent)
	assert_eq(Battle.intent_from_log(Battle.intent_to_log({})), {"move": Vector2.ZERO})


## A battle with a scripted "player", a fixed pattern of presses standing in for real input,
## and its saved spec round-tripped through JSON the way the file in recordings/specs/ is.
func _logged_battle(seed: int) -> Dictionary:
	var spec := _spec(seed)
	var controllers: Array = Controllers.for_spec(spec).controllers
	var player: PlayerController = controllers[0]
	var battle: Battle = Battle.create(spec, _data(), controllers).battle
	battle.record_intents = true
	for fighter in battle.fighters:
		fighter.max_hp = 600
		fighter.hp = 600
	while not battle.is_over():
		player.stick = Vector2(sin(battle.tick * 0.05), 1.0).limit_length(1.0)
		if battle.tick % 20 == 0:
			player.pending_use = (battle.tick / 20) % 2
		if battle.tick % 47 == 0:
			player.pending_dodge = true
		battle.step()
	return {"battle": battle, "saved": JSON.parse_string(JSON.stringify(battle.saved_spec(), "", false, true))}


func test_a_logged_battle_replays_exactly() -> void:
	var logged := _logged_battle(9)
	var battle: Battle = logged.battle
	var saved: Dictionary = logged.saved
	assert_eq(saved.checksum, battle.checksum())
	var replayed_controllers: Array = Controllers.for_spec(saved).controllers
	assert_true(replayed_controllers[0] is ReplayController and replayed_controllers[1] is ReplayController)
	var created := Battle.create(saved, _data(), replayed_controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	var replayed: Battle = created.battle
	for fighter in replayed.fighters:
		fighter.max_hp = 600
		fighter.hp = 600
	replayed.run()
	assert_eq(replayed.checksum(), saved.checksum)


func test_a_saved_spec_records_the_rules_and_data_versions() -> void:
	var saved: Dictionary = _logged_battle(9).saved
	assert_eq(int(saved.rules_version), Rules.RULES_VERSION)
	assert_eq(saved.data_versions, _data().versions)
	assert_false(saved.fighters[0].has("ai") or saved.fighters[1].has("ai"), "the intents replace the AI")


func test_a_saved_spec_wont_replay_under_other_versions() -> void:
	var saved: Dictionary = _logged_battle(9).saved
	var other_rules: Dictionary = saved.duplicate(true)
	other_rules.rules_version = Rules.RULES_VERSION - 1
	var error: String = Battle.create(other_rules, _data(), Controllers.for_spec(other_rules).controllers).get("error", "")
	assert_true(error.contains("rules version %d, not the current %d" % [Rules.RULES_VERSION - 1, Rules.RULES_VERSION]), error)
	var other_data := _data()
	other_data.versions.showdown = "c".repeat(64)
	error = Battle.create(saved, other_data, Controllers.for_spec(saved).controllers).get("error", "")
	assert_true(error.contains("showdown data %s, not the loaded %s" % ["a".repeat(12), "c".repeat(12)]), error)


func test_player_camera_looks_past_the_player_at_the_foe() -> void:
	var pose := PlayerCamera.pose(Vector3(0, 0, 0), Vector3(0, 0, 6), 1.0, 1.0)
	assert_true(pose.eye.z < 0.0, "behind the player: %s" % pose.eye)
	assert_true(pose.eye.y > 1.0, "above it")
	assert_true(pose.target.z > 0.0 and pose.target.z < 6.0, "looking between the two")


func test_every_move_kind_has_a_wind_up_animation() -> void:
	for id: String in MOVES:
		var move: BattleMove = BattleMove.from_showdown(id, MOVES[id]).move
		assert_true(BattleView.wind_up_role(move) in ["physical", "special", "status"])
	var quake: BattleMove = BattleMove.from_showdown("quake", {"name": "Quake", "category": "Physical", "type": "Ground",
		"basePower": 100, "accuracy": 100, "pp": 10, "flags": {}, "target": "allAdjacent"}).move
	assert_eq(BattleView.wind_up_role(quake), "physical", "area moves too")
