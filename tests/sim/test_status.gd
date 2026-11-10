extends TestCase
## Stat stages, status conditions, secondary effects, drain, recoil and the self-buff,
## debuff, heal and status kinds (concepts_brief.md §9.3, §9.5).

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"ember": {"name": "Ember", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"swordsdance": {"name": "Swords Dance", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "self", "boosts": {"atk": 2}},
	"willowisp": {"name": "Will-O-Wisp", "category": "Status", "type": "Fire", "basePower": 0, "accuracy": 85, "pp": 15, "priority": 0, "flags": {}, "target": "normal", "status": "brn"},
	"growl": {"name": "Growl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 40, "priority": 0, "flags": {"sound": 1}, "target": "allAdjacentFoes", "boosts": {"atk": -1}},
	"recover": {"name": "Recover", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "heal": [1, 2]},
	"synthesis": {"name": "Synthesis", "category": "Status", "type": "Grass", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self"},
	"clangoroussoul": {"name": "Clangorous Soul", "category": "Status", "type": "Dragon", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "boosts": {"atk": 1, "def": 1, "spa": 1, "spd": 1, "spe": 1}},
	"confuseray": {"name": "Confuse Ray", "category": "Status", "type": "Ghost", "basePower": 0, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "confusion"},
	"scald": {"name": "Scald", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal", "secondary": {"chance": 100, "status": "brn"}},
	"closecombat": {"name": "Close Combat", "category": "Physical", "type": "Fighting", "basePower": 120, "accuracy": 100, "pp": 5, "priority": 0, "flags": {"contact": 1}, "target": "normal", "self": {"boosts": {"def": -1, "spd": -1}}},
	"gigadrain": {"name": "Giga Drain", "category": "Special", "type": "Grass", "basePower": 75, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "drain": [1, 2]},
	"bravebird": {"name": "Brave Bird", "category": "Physical", "type": "Flying", "basePower": 120, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "any", "recoil": [33, 100]},
}


class Scripted extends RefCounted:
	var intents: Array

	func _init(steps: Array) -> void:
		intents = steps

	func decide(battle: Battle, _side: int) -> Dictionary:
		return intents[battle.tick] if battle.tick < intents.size() else {}


func _battle(moves_a: Array, moves_b: Array, script_a := [], species_b := "squirt") -> Battle:
	var spec := {"seed": 7, "fighters": [{"species": "squirt", "moves": moves_a}, {"species": species_b, "moves": moves_b}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), [Scripted.new(script_a), Scripted.new([])])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _move(id: String) -> BattleMove:
	return BattleMove.from_showdown(id, MOVES[id]).get("move")


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _run_ticks(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func test_stage_multipliers_match_the_main_series() -> void:
	assert_eq(Rules.stage_multiplier(0), 1.0)
	assert_eq(Rules.stage_multiplier(2), 2.0)
	assert_eq(Rules.stage_multiplier(6), 4.0)
	assert_almost_eq(Rules.stage_multiplier(-1), 2.0 / 3.0, 1e-6)
	assert_eq(Rules.stage_multiplier(-6), 0.25)
	assert_eq(Rules.stage_multiplier(9), 4.0, "clamped to +6")


func test_status_moves_are_classified() -> void:
	assert_eq(_move("swordsdance").kind, BattleMove.Kind.SELF_BUFF)
	assert_eq(_move("swordsdance").boosts, {"atk": 2})
	assert_eq(_move("willowisp").kind, BattleMove.Kind.STATUS)
	assert_eq(_move("willowisp").status, "brn")
	assert_eq(_move("growl").kind, BattleMove.Kind.DEBUFF, "every adjacent foe is just the one opponent")
	assert_eq(_move("recover").kind, BattleMove.Kind.HEAL)
	assert_eq(_move("recover").heal_share, 0.5)
	assert_eq(_move("synthesis").heal_share, 0.5, "heal amount from the override table")
	assert_true(_move("confuseray").confuses)
	assert_true(BattleMove.from_showdown("clangoroussoul", MOVES.clangoroussoul).has("error"), "needs code Showdown's data lacks")


func test_damaging_move_effects_are_read() -> void:
	assert_eq(_move("scald").secondaries, [{"chance": 100, "status": "brn"}] as Array[Dictionary])
	assert_eq(_move("closecombat").self_boosts, {"def": -1, "spd": -1})
	assert_eq(_move("gigadrain").drain_share, 0.5)
	assert_almost_eq(_move("bravebird").recoil_share, 0.33, 1e-6)


func test_stat_stages_scale_damage() -> void:
	var battle := _battle(["kick"], ["kick"])
	var attacker := battle.fighters[0]
	var defender := battle.fighters[1]
	var plain := Battle.damage(attacker, defender, _move("kick"), BattleData.new(SPECIES, MOVES, {}), SimRandom.new(1))
	attacker.boosts.atk = 2
	var boosted := Battle.damage(attacker, defender, _move("kick"), BattleData.new(SPECIES, MOVES, {}), SimRandom.new(1))
	assert_true(boosted.damage > plain.damage * 1.8, "+2 Attack: %d vs %d" % [boosted.damage, plain.damage])
	attacker.boosts.atk = 0
	attacker.status = "brn"
	var burned := Battle.damage(attacker, defender, _move("kick"), BattleData.new(SPECIES, MOVES, {}), SimRandom.new(1))
	assert_true(burned.damage < plain.damage * 0.6, "burn halves physical damage: %d vs %d" % [burned.damage, plain.damage])


func test_self_buff_raises_stages_up_to_six() -> void:
	var battle := _battle(["swordsdance"], ["jet"], [{"use": 0}])
	_run_ticks(battle, 20)
	assert_eq(battle.fighters[0].boosts.atk, 2)
	assert_eq(_events(battle, "boost")[0].boosts, {"atk": 2})
	battle.fighters[0].boosts.atk = 5
	battle._boost(battle.fighters[0], {"atk": 2}, "swordsdance")
	assert_eq(battle.fighters[0].boosts.atk, 6)
	assert_eq(_events(battle, "boost")[-1].boosts, {"atk": 1}, "reports the change that took effect")


func test_burn_deals_damage_over_time_then_wears_off() -> void:
	var battle := _battle(["jet"], ["jet"])
	var target := battle.fighters[1]
	battle._inflict(target, "brn")
	assert_eq(target.status, "brn")
	_run_ticks(battle, Rules.seconds_to_ticks(Rules.STATUS_SECONDS) + 2)
	var ticks := _events(battle, "status_damage").filter(func(e: Dictionary) -> bool: return e.side == 1)
	assert_eq(ticks.size(), roundi(Rules.STATUS_SECONDS))
	assert_eq(target.status, "", "burn wears off")
	assert_eq(target.hp, target.max_hp - ticks.size() * roundi(target.max_hp * Rules.BURN_DAMAGE))


func test_types_resist_their_status() -> void:
	var battle := _battle(["jet"], ["jet"], [], "ember")
	battle._inflict(battle.fighters[1], "brn")
	assert_eq(battle.fighters[1].status, "", "Fire types can't be burned")
	battle._inflict(battle.fighters[1], "par")
	assert_eq(battle.fighters[1].status, "par")
	battle._inflict(battle.fighters[1], "slp")
	assert_eq(battle.fighters[1].status, "par", "only one major status at a time")


func test_paralysis_slows_walking() -> void:
	var battle := _battle(["jet"], ["jet"])
	var fighter := battle.fighters[0]
	var normal := fighter.current_move_speed()
	fighter.status = "par"
	assert_almost_eq(fighter.current_move_speed(), normal * Rules.PARALYSIS_SPEED_FACTOR, 1e-6)


func test_sleep_stops_acting_until_hit() -> void:
	var battle := _battle(["jet"], ["jet"], [{}, {"use": 0}])
	var sleeper := battle.fighters[0]
	battle._inflict(sleeper, "slp")
	sleeper.status_ticks = 1000
	_run_ticks(battle, 3)
	assert_eq(_events(battle, "windup").size(), 0, "asleep, so it can't use a move")
	battle._hit(battle.fighters[1], sleeper, _move("jet"))
	assert_eq(sleeper.status, "", "a hit wakes it")


func test_confusion_sometimes_turns_a_move_into_a_self_hit() -> void:
	var self_hits := 0
	var windups := 0
	for seed in 20:
		var script := []
		for i in 400:
			script.append({"use": 0})
		var battle := _battle(["jet"], ["jet"], script)
		battle._random = SimRandom.new(seed)
		for i in 400:
			battle.fighters[0].confusion_ticks = 100
			battle.step()
		self_hits += _events(battle, "confusion_hit").size()
		windups += _events(battle, "windup").filter(func(e: Dictionary) -> bool: return e.side == 0).size()
	assert_true(self_hits > 0 and windups > self_hits, "%d self-hits, %d moves" % [self_hits, windups])


func test_status_projectile_lands_and_inflicts() -> void:
	var battle := _battle(["willowisp"], ["jet"], [{"use": 0}])
	_run_ticks(battle, 60)
	assert_eq(_events(battle, "landed").size(), 1)
	assert_eq(battle.fighters[1].status, "brn")
	assert_eq(_events(battle, "hit").size(), 0, "it deals no damage")


func test_heal_drain_and_recoil() -> void:
	var battle := _battle(["recover"], ["jet"], [{"use": 0}])
	var fighter := battle.fighters[0]
	fighter.hp = fighter.max_hp / 4
	_run_ticks(battle, 20)
	assert_eq(fighter.hp, fighter.max_hp / 4 + roundi(fighter.max_hp * 0.5))
	fighter.hp = fighter.max_hp - 5
	battle._heal(fighter, 100, "recover")
	assert_eq(fighter.hp, fighter.max_hp, "never above max")

	battle = _battle(["gigadrain"], ["jet"])
	battle.fighters[0].hp = 100
	battle._hit(battle.fighters[0], battle.fighters[1], _move("gigadrain"))
	var dealt: int = _events(battle, "hit")[0].damage
	assert_eq(battle.fighters[0].hp, 100 + roundi(dealt * 0.5), "drain heals half the damage")

	battle = _battle(["bravebird"], ["jet"])
	battle._hit(battle.fighters[0], battle.fighters[1], _move("bravebird"))
	dealt = _events(battle, "hit")[0].damage
	assert_eq(battle.fighters[0].hp, battle.fighters[0].max_hp - roundi(dealt * 0.33), "recoil costs a third")


func test_secondary_and_self_stat_changes_apply_on_hit() -> void:
	var battle := _battle(["scald", "closecombat"], ["jet"])
	battle._hit(battle.fighters[0], battle.fighters[1], _move("scald"))
	assert_eq(battle.fighters[1].status, "brn", "a 100% secondary always lands")
	battle._hit(battle.fighters[0], battle.fighters[1], _move("closecombat"))
	assert_eq(battle.fighters[0].boosts.def, -1)
	assert_eq(battle.fighters[0].boosts.spd, -1)


func test_status_damage_can_knock_out() -> void:
	var battle := _battle(["jet"], ["jet"])
	var target := battle.fighters[1]
	battle._inflict(target, "psn")
	target.hp = 1
	_run_ticks(battle, Rules.TICK_RATE + 1)
	assert_true(target.is_fainted())
	assert_eq(_events(battle, "faint").size(), 1)
	assert_eq(battle.result, Battle.Result.WIN_A)


func test_ai_scores_support_moves_by_situation() -> void:
	var battle := _battle(["recover", "willowisp", "swordsdance"], ["jet"])
	var me := battle.fighters[0]
	var foe := battle.fighters[1]
	assert_eq(SimpleAI.move_score(me, foe, _move("recover")), 0.0, "no heal at full HP")
	me.hp = me.max_hp / 4
	assert_true(SimpleAI.move_score(me, foe, _move("recover")) > 100.0, "heals when hurt")
	assert_true(SimpleAI.move_score(me, foe, _move("willowisp")) > 0.0)
	foe.status = "par"
	assert_eq(SimpleAI.move_score(me, foe, _move("willowisp")), 0.0, "no status on a foe that has one")
	me.boosts.atk = 2
	assert_eq(SimpleAI.move_score(me, foe, _move("swordsdance")), 0.0, "stops buffing at +2")


func test_ai_discounts_moves_that_lower_its_attacking_stat() -> void:
	var overheat: BattleMove = BattleMove.from_showdown("overheat", {"name": "Overheat", "category": "Special", "type": "Fire", "basePower": 130,
		"accuracy": 90, "pp": 5, "flags": {}, "target": "normal", "self": {"boosts": {"spa": -2}}}).move
	var battle := _battle(["jet"], ["jet"])
	var me := battle.fighters[0]
	var foe := battle.fighters[1]
	var jet := _move("jet")
	assert_true(SimpleAI.move_score(me, foe, overheat) < 130.0 * 0.6, "pays for the -2 it causes")
	me.boosts.spa = -2
	assert_almost_eq(SimpleAI.move_score(me, foe, jet), 80.0 * 0.5, 1e-4, "attacks weigh the current stage")
