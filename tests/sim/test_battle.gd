extends TestCase
## Uses small inline data shaped like Showdown's export, so CI needs no asset cache.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 115, "def": 75, "spa": 65, "spd": 75, "spe": 120}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 60, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"growl": {"name": "Growl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 40, "priority": 0, "flags": {}, "target": "allAdjacentFoes"},
}
const TYPES := {
	"water": {"damageTaken": {"Fire": 2, "Water": 2, "Grass": 1, "Fighting": 0}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2, "Fighting": 0}},
}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _spec(seed: int, a := "squirt", b := "blaze", moves_a := ["jet", "kick"], moves_b := ["ember", "kick"]) -> Dictionary:
	return {"seed": seed, "fighters": [{"species": a, "moves": moves_a}, {"species": b, "moves": moves_b}]}


func _run(spec: Dictionary) -> Battle:
	var created := Battle.create(spec, _data(), SimpleAI.pair(spec.seed))
	assert_false(created.has("error"), str(created.get("error", "")))
	var battle: Battle = created.battle
	battle.run()
	return battle


func test_stat_formulas_match_main_series_at_level_50() -> void:
	assert_eq(Rules.stat(100), 120)
	assert_eq(Rules.hp_stat(100), 175)


func test_effectiveness_is_compressed() -> void:
	var data := _data()
	assert_eq(data.effectiveness("Water", ["Fire"]), 2.0)
	assert_eq(Rules.compressed_effectiveness(data.effectiveness("Water", ["Fire"])), 1.3)
	assert_eq(Rules.compressed_effectiveness(0.0), 0.25, "immunity still deals some damage")


func test_damage_formula() -> void:
	var data := _data()
	var jet: BattleMove = BattleMove.from_showdown("jet", MOVES.jet).move
	var attacker := Fighter.create(0, "squirt", SPECIES.squirt, [jet], 0.5)
	var defender := Fighter.create(1, "blaze", SPECIES.blaze, [jet], 0.5)
	# Base = floor(floor(22 * 80 * SpA 105 / SpD 95) / 50) + 2 = 40; x1.5 STAB x1.3 effectiveness.
	var outcome := Battle.damage(attacker, defender, jet, data, SimRandom.new(3))
	var base := 40.0 * 1.5 * 1.3
	assert_true(outcome.damage >= floori(base * 0.85) and outcome.damage <= floori(base * Rules.CRIT_MULTIPLIER), str(outcome))
	assert_eq(outcome.effectiveness, 1.3)


func test_move_kinds_and_unsupported_moves() -> void:
	assert_eq(BattleMove.from_showdown("kick", MOVES.kick).move.kind, BattleMove.Kind.MELEE)
	assert_eq(BattleMove.from_showdown("jet", MOVES.jet).move.kind, BattleMove.Kind.PROJECTILE)
	assert_eq(BattleMove.from_showdown("quake", MOVES.quake).move.kind, BattleMove.Kind.AREA)
	var field := {"name": "Rain", "category": "Status", "type": "Water", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "all"}
	assert_true(BattleMove.from_showdown("rain", field).error.contains("not supported"))
	assert_true(BattleMove.from_showdown("growl", MOVES.growl).error.contains("status"))


func test_same_spec_same_battle() -> void:
	var first := _run(_spec(11))
	var second := _run(_spec(11))
	assert_eq(first.checksum(), second.checksum())
	assert_eq(first.events, second.events)
	assert_false(first.checksum().is_empty())


func test_different_seed_different_battle() -> void:
	assert_true(_run(_spec(11)).checksum() != _run(_spec(12)).checksum())


func test_battle_ends_within_the_time_cap() -> void:
	var battle := _run(_spec(5))
	assert_true(battle.is_over())
	assert_true(battle.tick <= Rules.seconds_to_ticks(Rules.TIME_CAP_SECONDS))
	assert_true(battle.events.any(func(e: Dictionary) -> bool: return e.type == "hit"))


func test_mirror_match_has_no_side_bias() -> void:
	var wins := [0, 0]
	for seed in 20:
		var spec := _spec(seed, "squirt", "squirt", ["jet", "kick"], ["jet", "kick"])
		var battle: Battle = Battle.create(spec, _data(), SimpleAI.pair(seed)).battle
		# Two weak moves can't get through a full HP pool before the time cap; this test is
		# about which side wins, so give both sides a smaller one.
		for fighter in battle.fighters:
			fighter.max_hp = 600
			fighter.hp = 600
		battle.run()
		if battle.result == Battle.Result.WIN_A:
			wins[0] += 1
		elif battle.result == Battle.Result.WIN_B:
			wins[1] += 1
	assert_true(wins[0] > 0 and wins[1] > 0, "wins by side: %s" % [wins])


func test_bad_specs_are_reported() -> void:
	var controllers := [SimpleAI.new(SimRandom.new(1)), SimpleAI.new(SimRandom.new(2))]
	assert_true(Battle.create(_spec(1, "nobody"), _data(), controllers).error.contains("unknown species"))
	assert_true(Battle.create(_spec(1, "squirt", "blaze", ["nothing"]), _data(), controllers).error.contains("unknown move"))
	assert_true(Battle.create({"seed": 1, "fighters": []}, _data(), controllers).error.contains("two fighters"))


func test_hitbox_radius_comes_from_the_roster() -> void:
	var data := _data()
	data.roster = {"squirt": {"radius": 0.7}, "blaze": {"radius": 1.1}}
	var created := Battle.create(_spec(1), data, SimpleAI.pair(1))
	assert_eq(created.battle.fighters[0].radius, 0.7)
	assert_eq(created.battle.fighters[1].radius, 1.1)
	var spec := _spec(1)
	spec.fighters[0].radius = 0.4
	assert_eq(Battle.create(spec, data, SimpleAI.pair(1)).battle.fighters[0].radius, 0.4, "the spec overrides the roster")


func test_species_outside_the_roster_are_rejected() -> void:
	var data := _data()
	data.roster = {"squirt": {"radius": 0.7}}
	var created := Battle.create(_spec(1), data, SimpleAI.pair(1))
	assert_true(str(created.get("error", "")).contains("not in the roster"), str(created))
