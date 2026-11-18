extends TestCase
## Team battles (concepts_brief.md §9.1, §17 M15): a side brings 1-6 Pokémon, one out at a
## time; after a knockout the next is sent out, and the battle ends when a side has no one left.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 115, "def": 75, "spa": 65, "spd": 75, "spe": 120}},
	"leaf": {"name": "Leaf", "types": ["Grass"], "baseStats": {"hp": 60, "atk": 70, "def": 70, "spa": 70, "spd": 70, "spe": 70}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 60, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
}
const TYPES := {
	"water": {"damageTaken": {"Fire": 2, "Water": 2, "Grass": 1, "Fighting": 0}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2, "Fighting": 0}},
	"grass": {"damageTaken": {"Water": 2, "Fire": 1, "Fighting": 0}},
}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _member(species: String, moves: Array) -> Dictionary:
	return {"species": species, "moves": moves}


func _team_spec(seed: int, team_a: Array, team_b: Array) -> Dictionary:
	return {"seed": seed, "fighters": [{"team": team_a}, {"team": team_b}]}


func _create(spec: Dictionary, controllers := []) -> Battle:
	var created := Battle.create(spec, _data(), controllers if not controllers.is_empty() else StandInAI.pair(spec.seed))
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_a_side_wins_once_the_other_has_no_one_left() -> void:
	var spec := _team_spec(4, [_member("squirt", ["jet", "kick"]), _member("leaf", ["kick"])],
		[_member("blaze", ["ember", "kick"]), _member("leaf", ["kick"]), _member("squirt", ["jet"])])
	var battle := _create(spec)
	battle.run()
	assert_true(battle.result != Battle.Result.ONGOING)
	var loser := 1 if battle.result == Battle.Result.WIN_A else 0
	if battle.result != Battle.Result.DRAW:
		assert_true(battle.healthy(loser).is_empty(), "the losing side has no one left")
		assert_eq(_events(battle, "knockout").filter(func(e: Dictionary) -> bool: return e.side == loser).size(),
			battle.teams[loser].size())
	# Every send-out brings the next member in team order, after a knockout with more to come.
	for side in 2:
		var slots := _events(battle, "send_out").filter(func(e: Dictionary) -> bool: return e.side == side) \
			.map(func(e: Dictionary) -> int: return e.slot)
		for i in slots.size():
			assert_eq(slots[i], i + 1)


func test_team_battles_replay_exactly() -> void:
	var spec := _team_spec(9, [_member("squirt", ["jet", "kick"]), _member("blaze", ["ember"])],
		[_member("leaf", ["kick"]), _member("blaze", ["ember", "kick"])])
	var first := _create(spec)
	first.run()
	var second := _create(spec.duplicate(true))
	second.run()
	assert_eq(first.checksum(), second.checksum())
	assert_eq(first.events.size(), second.events.size())


func test_a_team_of_one_plays_exactly_like_a_single_fighter() -> void:
	var single := {"seed": 7, "fighters": [_member("squirt", ["jet", "kick"]), _member("blaze", ["ember", "kick"])]}
	var team := _team_spec(7, [_member("squirt", ["jet", "kick"])], [_member("blaze", ["ember", "kick"])])
	var a := _create(single)
	a.run()
	var b := _create(team)
	b.run()
	assert_eq(a.checksum(), b.checksum())
	assert_eq(a.overtime_tick, Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS))


func test_after_a_knockout_the_next_lands_shielded_at_its_start_spot() -> void:
	var b := Scripted.new()
	var spec := _team_spec(1, [_member("squirt", ["jet", "kick"])], [_member("blaze", ["ember"]), _member("leaf", ["kick"])])
	var battle := _create(spec, [Scripted.new(), b])
	battle.fighters[0].position = Vector2(3, 3)
	battle.step()
	battle._hurt(battle.fighters[1], 10000, "status_damage", {"status": "psn"})
	var knockout: Dictionary = _events(battle, "knockout")[0]
	assert_eq(knockout.left, 1)
	assert_true(battle.is_waiting(1))
	var lull := Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS)
	for i in lull:
		battle.step()
	var sent: Array = _events(battle, "send_out")
	assert_eq(sent.size(), 1)
	assert_eq(sent[0].slot, 1)
	# The knockout came between steps (stamped with the next tick), so that step is the lull's first.
	assert_eq(int(sent[0].tick) - int(knockout.tick), lull - 1)
	var leaf := battle.fighters[1]
	assert_eq(leaf.species_id, "leaf")
	assert_eq(leaf.position, Vector2(0, 0.5 * Rules.START_DISTANCE))
	assert_true(leaf.is_invulnerable(), "shielded while it lands")
	assert_false(battle.is_over())
	for i in Rules.seconds_to_ticks(Rules.SEND_OUT_SECONDS):
		battle.step()
	assert_false(leaf.is_invulnerable())
	assert_false(battle.is_waiting(1))
	assert_eq(_events(battle, "landed_out").size(), 1)


func test_the_fighter_left_standing_only_walks_while_the_foe_is_between_pokemon() -> void:
	var a := Scripted.new()
	var spec := _team_spec(1, [_member("squirt", ["jet", "kick"])], [_member("blaze", ["ember"]), _member("leaf", ["kick"])])
	var battle := _create(spec, [a, Scripted.new()])
	battle.step()
	battle._hurt(battle.fighters[1], 10000, "status_damage", {"status": "psn"})
	a.plan[battle.tick] = {"use": 0, "move": Vector2.RIGHT}
	a.plan[battle.tick + 1] = {"dodge": Vector2.RIGHT}
	var before := battle.fighters[0].position
	battle.step()
	battle.step()
	assert_eq(battle.fighters[0].action, Fighter.Action.READY)
	assert_eq(battle.fighters[0].dodge_charges, Rules.DODGE_CHARGES)
	assert_true(battle.fighters[0].position.x > before.x, "it walked")
	assert_true(_events(battle, "windup").is_empty())


func test_team_sizes_are_checked() -> void:
	var seven := []
	for i in 7:
		seven.append(_member("leaf", ["kick"]))
	var error: String = Battle.create(_team_spec(1, seven, [_member("blaze", ["ember"])]), _data(), StandInAI.pair(1)).get("error", "")
	assert_true(error.contains("1-6"), error)
	error = Battle.create(_team_spec(1, [], [_member("blaze", ["ember"])]), _data(), StandInAI.pair(1)).get("error", "")
	assert_true(error.contains("1-6"), error)


func test_overtime_and_the_time_cap_scale_with_the_larger_team() -> void:
	var battle := _create(_team_spec(1, [_member("squirt", ["jet"]), _member("leaf", ["kick"]), _member("blaze", ["ember"])],
		[_member("blaze", ["ember"])]))
	assert_eq(battle.overtime_tick, Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS * 3))


func test_hits_name_both_fighters_by_side_and_slot() -> void:
	var spec := _team_spec(3, [_member("squirt", ["jet", "kick"]), _member("leaf", ["kick"])],
		[_member("blaze", ["ember", "kick"]), _member("leaf", ["kick"])])
	var battle := _create(spec)
	battle.run()
	for hit: Dictionary in _events(battle, "hit"):
		assert_eq(int(hit.target_side), 1 - int(hit.side))
		assert_true(int(hit.slot) < battle.teams[hit.side].size())
		assert_true(int(hit.target_slot) < battle.teams[hit.target_side].size())
	assert_eq(battle.team_max_hp()[1].size(), 2)
