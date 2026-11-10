extends TestCase


func test_rows_show_action_score_and_considerations() -> void:
	var row := AIOverlay.describe({"action": "move:earthquake", "score": 0.6,
		"considerations": {"in_range": 1.0, "damage": 0.72, "safe_to_commit": 0.5}})
	assert_true(row.begins_with("earthquake"), row)
	assert_true(row.contains("██████····"), "a ten-step bar: " + row)
	assert_true(row.contains("0.60"), row)
	assert_true(row.contains("range 1.00 · dmg 0.72 · safe 0.50"), row)


func test_overlay_asks_utility_ais_to_keep_scores() -> void:
	var ai := UtilityAI.new(Controllers.load_profile("ranked"), SimRandom.new(1))
	var overlay := AIOverlay.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(overlay)
	overlay.setup([ai, SimpleAI.new(SimRandom.new(2))], ["A", "B"], Vector2(1920, 1080), Vector2(170, 80))
	assert_true(ai.keep_scores)
	assert_eq(AIOverlay.describe_controller(ai), "AI ranked")
	assert_eq(AIOverlay.describe_controller(SimpleAI.new(SimRandom.new(3))), "AI simple")
	overlay.refresh()
	overlay.free()


func test_keeping_scores_never_changes_a_battle() -> void:
	var data := BattleData.new(
		{"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}}},
		{"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
			"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"}}, {})
	var spec := {"seed": 4, "fighters": [{"species": "squirt", "moves": ["jet", "kick"]}, {"species": "squirt", "moves": ["jet", "kick"]}]}
	var checksums: Array[String] = []
	for keep in [false, true]:
		var controllers: Array = Controllers.for_spec(spec).controllers
		for controller in controllers:
			controller.keep_scores = keep
		var battle: Battle = Battle.create(spec, data, controllers).battle
		for fighter in battle.fighters:
			fighter.max_hp = 500
			fighter.hp = 500
		battle.run()
		checksums.append(battle.checksum())
	assert_eq(checksums[0], checksums[1])
