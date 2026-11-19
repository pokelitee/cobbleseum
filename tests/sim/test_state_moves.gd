extends TestCase
## Moves whose power or use follows HP and the battle's state (concepts_brief.md §9.3, M18, rules
## version 37). Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}, "weightkg": 50},
	"heavy": {"name": "Heavy", "types": ["Water"], "baseStats": STATS, "abilities": {"0": "Run Away"}, "weightkg": 300},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"swift": {"name": "Swift", "category": "Special", "type": "Normal", "basePower": 60, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"eruption": {"name": "Eruption", "category": "Special", "type": "Fire", "basePower": 150, "accuracy": 100, "pp": 5, "priority": 0, "flags": {}, "target": "allAdjacentFoes"},
	"reversal": {"name": "Reversal", "category": "Physical", "type": "Fighting", "basePower": 0, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"hex": {"name": "Hex", "category": "Special", "type": "Ghost", "basePower": 65, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"facade": {"name": "Facade", "category": "Physical", "type": "Normal", "basePower": 70, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"storedpower": {"name": "Stored Power", "category": "Special", "type": "Psychic", "basePower": 20, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"lowkick": {"name": "Low Kick", "category": "Physical", "type": "Fighting", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"heavyslam": {"name": "Heavy Slam", "category": "Physical", "type": "Steel", "basePower": 0, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"payback": {"name": "Payback", "category": "Physical", "type": "Dark", "basePower": 50, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"knockoff": {"name": "Knock Off", "category": "Physical", "type": "Dark", "basePower": 65, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"furycutter": {"name": "Fury Cutter", "category": "Physical", "type": "Bug", "basePower": 40, "accuracy": 95, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"freezedry": {"name": "Freeze-Dry", "category": "Special", "type": "Ice", "basePower": 70, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"falseswipe": {"name": "False Swipe", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 40, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"suckerpunch": {"name": "Sucker Punch", "category": "Physical", "type": "Dark", "basePower": 70, "accuracy": 100, "pp": 5, "priority": 1, "flags": {"contact": 1}, "target": "normal"},
	"fakeout": {"name": "Fake Out", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 10, "priority": 3, "flags": {"contact": 1}, "target": "normal"},
	"dreameater": {"name": "Dream Eater", "category": "Special", "type": "Psychic", "basePower": 100, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal", "drain": [1, 2]},
	"lastresort": {"name": "Last Resort", "category": "Physical", "type": "Normal", "basePower": 140, "accuracy": 100, "pp": 5, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"focuspunch": {"name": "Focus Punch", "category": "Physical", "type": "Fighting", "basePower": 150, "accuracy": 100, "pp": 20, "priority": -3, "flags": {"contact": 1}, "target": "normal"},
	"tripleaxel": {"name": "Triple Axel", "category": "Physical", "type": "Ice", "basePower": 20, "accuracy": 90, "pp": 10, "priority": 0, "flags": {"contact": 1}, "target": "normal", "multihit": 3},
}
const TYPES := {"normal": {"damageTaken": {}}, "water": {"damageTaken": {"Ice": 2}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["tackle"], ["tackle"]], species := ["plain", "plain"], items := ["", ""]) -> Battle:
	var fighters := []
	for side in 2:
		fighters.append({"species": species[side], "moves": moves[side], "ability": "", "item": items[side]})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func _power(battle: Battle, id: String) -> int:
	return MoveEffects.adapt(battle.fighters[0], battle.fighters[1], _data().convert_move(id).move).power


func test_hp_scaled_power() -> void:
	var battle := _battle()
	var a := battle.fighters[0]
	assert_eq(_power(battle, "eruption"), 150)
	a.hp = a.max_hp / 2
	assert_eq(_power(battle, "eruption"), 75)
	assert_eq(_power(battle, "reversal"), 40)
	a.hp = 1
	assert_eq(_power(battle, "reversal"), 200)


func test_status_stages_and_weight() -> void:
	var battle := _battle([["tackle"], ["tackle"]], ["plain", "heavy"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_eq(_power(battle, "hex"), 65)
	b.status = "par"
	assert_eq(_power(battle, "hex"), 130)
	a.status = "brn"
	assert_eq(_power(battle, "facade"), 140)
	a.boosts.spa = 2
	a.boosts.def = -1
	assert_eq(_power(battle, "storedpower"), 60, "only raised stages count")
	assert_eq(_power(battle, "lowkick"), 120, "a 300 kg target")
	assert_eq(_power(battle, "heavyslam"), 40, "a light user")


func test_recent_events_double_power() -> void:
	var battle := _battle([["tackle"], ["tackle"]])
	var a := battle.fighters[0]
	assert_eq(_power(battle, "payback"), 50)
	battle._hit(battle.fighters[1], a, a.moves[0])
	assert_eq(_power(battle, "payback"), 100, "hit just now")
	for i in Rules.seconds_to_ticks(Rules.RECENT_SECONDS) + 1:
		battle.step()
	assert_eq(_power(battle, "payback"), 50, "it wears off")
	assert_eq(a.times_hit, 1)


func test_knock_off_takes_the_item_and_effectiveness_quirks() -> void:
	var battle := _battle([["knockoff"], ["tackle"]], ["plain", "heavy"], ["", "leftovers"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_eq(_power(battle, "knockoff"), 98)
	battle._hit(a, b, a.moves[0])
	assert_eq(b.item, "")
	assert_eq(_power(battle, "knockoff"), 65)
	var freezedry := _move("freezedry")
	assert_eq(Battle.damage_parts(a, b, freezedry, _data()).effectiveness, Rules.compressed_effectiveness(2.0))


func test_fury_cutter_grows_with_repeated_use() -> void:
	var battle := _battle([["furycutter"], ["tackle"]])
	var a := battle.fighters[0]
	a.combo = {"move": "furycutter", "count": 2, "ticks": 10}
	assert_eq(_power(battle, "furycutter"), 160)
	a.combo = {}
	assert_eq(_power(battle, "furycutter"), 40)


func test_false_swipe_never_knocks_out() -> void:
	var battle := _battle([["falseswipe"], ["tackle"]])
	var b := battle.fighters[1]
	b.hp = 1
	battle._hit(battle.fighters[0], b, battle.fighters[0].moves[0])
	assert_eq(b.hp, 1)


func test_conditional_moves() -> void:
	var battle := _battle([["suckerpunch", "fakeout", "dreameater", "lastresort"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_false(MoveEffects.usable(a, b, a.moves[0]), "no attack coming")
	b.action = Fighter.Action.WINDUP
	b.action_move = 0
	assert_true(MoveEffects.usable(a, b, a.moves[0]))
	assert_true(MoveEffects.usable(a, b, a.moves[1]), "just out")
	a.out_ticks = Rules.seconds_to_ticks(Rules.FIRST_SECONDS)
	assert_false(MoveEffects.usable(a, b, a.moves[1]))
	assert_false(MoveEffects.usable(a, b, a.moves[2]))
	b.status = "slp"
	assert_true(MoveEffects.usable(a, b, a.moves[2]))
	assert_false(MoveEffects.usable(a, b, a.moves[3]))
	a.used_moves = {"suckerpunch": true, "fakeout": true, "dreameater": true}
	assert_true(MoveEffects.usable(a, b, a.moves[3]))


func test_focus_punch_is_a_channel_any_hit_breaks() -> void:
	var move := _move("focuspunch")
	assert_true(move.channels)
	assert_eq(move.windup_ticks, Rules.seconds_to_ticks(Rules.HEAL_WINDUP))
	var battle := _battle([["focuspunch"], ["tackle"]])
	var a := battle.fighters[0]
	a.action = Fighter.Action.WINDUP
	a.action_move = 0
	a.action_ticks = 10
	battle._hit(battle.fighters[1], a, battle.fighters[1].moves[0])
	assert_eq(a.action, Fighter.Action.READY)


func test_triple_axel_hits_harder_each_time() -> void:
	var battle := _battle([["tripleaxel"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	b.position = a.position + Vector2(0, a.radius + b.radius + 0.5)
	var hp := b.hp
	battle._strike(a, b, 0, 0)
	var first := hp - b.hp
	hp = b.hp
	battle._strike(a, b, 0, 2)
	assert_true(hp - b.hp > first * 2, "the third hit is about three times the first")


func test_movesets_value_conditional_moves_lower() -> void:
	var sucker := _move("suckerpunch")
	var payback := _move("payback")
	assert_true(Movesets.attack_value(sucker, {}, true) < Movesets.attack_value(payback, {}, true))
