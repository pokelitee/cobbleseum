extends TestCase
## Coded status moves (concepts_brief.md §9.5, M18, rules version 39): odd self-buffs, HP and
## stage trades, Substitute. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 100, "def": 80, "spa": 60, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"thundershock": {"name": "Thunder Shock", "category": "Special", "type": "Electric", "basePower": 40, "accuracy": 100, "pp": 30, "priority": 0, "flags": {}, "target": "normal"},
	"hypervoice": {"name": "Hyper Voice", "category": "Special", "type": "Normal", "basePower": 90, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"sound": 1}, "target": "allAdjacentFoes"},
	"shellsmash": {"name": "Shell Smash", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 15, "priority": 0, "flags": {}, "target": "self", "boosts": {"def": -1, "spd": -1, "atk": 2, "spa": 2, "spe": 2}},
	"filletaway": {"name": "Fillet Away", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self", "boosts": {"atk": 2, "spa": 2, "spe": 2}},
	"bellydrum": {"name": "Belly Drum", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self"},
	"rest": {"name": "Rest", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self"},
	"substitute": {"name": "Substitute", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self", "volatileStatus": "substitute"},
	"painsplit": {"name": "Pain Split", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"charge": {"name": "Charge", "category": "Status", "type": "Electric", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "self", "boosts": {"spd": 1}, "volatileStatus": "charge"},
	"stockpile": {"name": "Stockpile", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "self", "volatileStatus": "stockpile"},
	"swallow": {"name": "Swallow", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self"},
	"wish": {"name": "Wish", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self"},
	"powersplit": {"name": "Power Split", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"swagger": {"name": "Swagger", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 85, "pp": 15, "priority": 0, "flags": {}, "target": "normal", "boosts": {"atk": 2}, "volatileStatus": "confusion"},
	"memento": {"name": "Memento", "category": "Status", "type": "Dark", "basePower": 0, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "boosts": {"atk": -2, "spa": -2}},
}
const TYPES := {"normal": {"damageTaken": {}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["tackle"], ["tackle"]]) -> Battle:
	var fighters := []
	for side in 2:
		fighters.append({"species": "plain", "moves": moves[side], "ability": "", "item": ""})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func _use(battle: Battle, index: int) -> void:
	var a := battle.fighters[0]
	a.action = Fighter.Action.WINDUP
	a.action_move = index
	a.action_ticks = 1
	battle._release(a, battle.fighters[1])


func test_classification() -> void:
	assert_eq(_move("shellsmash").kind, BattleMove.Kind.SELF_BUFF)
	assert_eq(_move("shellsmash").boosts.def, -1)
	assert_eq(_move("bellydrum").kind, BattleMove.Kind.CODED)
	assert_true(_move("rest").channels)
	assert_eq(_move("swagger").kind, BattleMove.Kind.STATUS)
	assert_eq(_move("swagger").boosts, {"atk": 2})
	assert_true(_move("memento").self_destructs)


func test_hp_costs_are_main_series_shares() -> void:
	var battle := _battle([["bellydrum", "filletaway"], ["tackle"]])
	var a := battle.fighters[0]
	var hp := a.hp
	_use(battle, 0)
	assert_eq(a.boosts.atk, Rules.MAX_STAGE)
	assert_eq(hp - a.hp, roundi(a.max_hp * 0.5))
	assert_false(MoveEffects.usable(a, battle.fighters[1], a.moves[1]), "can't pay half again")


func test_rest_heals_then_sleeps() -> void:
	var battle := _battle([["rest"], ["tackle"]])
	var a := battle.fighters[0]
	a.hp = 100
	a.status = "brn"
	_use(battle, 0)
	assert_eq(a.status, "slp")
	assert_eq(a.status_ticks, Rules.seconds_to_ticks(StatusMoves.REST_SLEEP_SECONDS))
	assert_true(a.hp > a.max_hp * 0.4)


func test_substitute_takes_hits_but_not_sound() -> void:
	var battle := _battle([["substitute"], ["tackle", "hypervoice"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	_use(battle, 0)
	assert_eq(a.substitute_hp, roundi(a.max_hp * 0.25))
	var hp := a.hp
	battle._hit(b, a, b.moves[0])
	assert_eq(a.hp, hp, "the decoy takes it")
	assert_true(a.substitute_hp < roundi(a.max_hp * 0.25))
	battle._hit(b, a, b.moves[1])
	assert_true(a.hp < hp, "sound gets through")


func test_pain_split_and_power_split() -> void:
	var battle := _battle([["painsplit", "powersplit"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.hp = 600
	var foe_hp := b.hp
	_use(battle, 0)
	assert_true(a.hp > 600 and b.hp < foe_hp)
	assert_eq(a.hp - 600, roundi((foe_hp - 600) / 2.0 * Rules.HP_SHARE_READING))
	b.stats.atk = 200
	var own: int = a.stats.atk
	_use(battle, 1)
	assert_eq(a.stats.atk, b.stats.atk)
	assert_true(a.stats.atk > own)
	for i in Rules.seconds_to_ticks(Abilities.ABILITY_SECONDS) + 1:
		battle.step()
	assert_eq(a.stats.atk, own, "it wears off")


func test_charge_stockpile_and_wish() -> void:
	var battle := _battle([["charge", "stockpile", "swallow", "wish", "thundershock"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var plain := MoveEffects.adapt(a, b, a.moves[4]).power
	_use(battle, 0)
	assert_eq(MoveEffects.adapt(a, b, a.moves[4]).power, plain * 2)
	battle._hit(a, b, a.moves[4])
	assert_eq(a.charged_ticks, 0, "spent on the hit")
	assert_false(MoveEffects.usable(a, b, a.moves[2]), "nothing to swallow")
	_use(battle, 1)
	_use(battle, 1)
	assert_eq(a.stockpile, 2)
	assert_eq(a.boosts.def, 2)
	a.hp = 200
	_use(battle, 2)
	assert_eq(a.stockpile, 0)
	assert_eq(a.boosts.def, 0)
	assert_true(a.hp > 200)
	var hp := a.hp
	_use(battle, 3)
	for i in Rules.seconds_to_ticks(Rules.DELAYED_SECONDS) + 1:
		battle.step()
	assert_true(a.hp > hp, "the wish came true")


func test_ais_and_movesets() -> void:
	var battle := _battle([["swagger", "bellydrum", "memento"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_eq(StandInAI.move_score(a, b, a.moves[0]), 0.0, "never Swagger a physical attacker")
	assert_true(StandInAI.move_score(a, b, a.moves[1]) > 0.0, "Belly Drum at full HP")
	assert_eq(StandInAI.move_score(a, b, a.moves[2]), 0.0, "no Memento at full HP")
	assert_true(Movesets.utility_value(_move("shellsmash"), true) > Movesets.utility_value(_move("filletaway"), true))
	assert_eq(Movesets.utility_value(_move("memento"), true), 0.0)
