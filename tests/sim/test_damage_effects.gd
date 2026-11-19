extends TestCase
## Proportional and returned damage, delayed hits, HP costs and on-hit effects (concepts_brief.md
## §9.3, M18, rules version 38). Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"swift": {"name": "Swift", "category": "Special", "type": "Normal", "basePower": 60, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"superfang": {"name": "Super Fang", "category": "Physical", "type": "Normal", "basePower": 0, "accuracy": 90, "pp": 10, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"endeavor": {"name": "Endeavor", "category": "Physical", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 5, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"finalgambit": {"name": "Final Gambit", "category": "Special", "type": "Fighting", "basePower": 0, "accuracy": 100, "pp": 5, "priority": 0, "flags": {}, "target": "normal"},
	"counter": {"name": "Counter", "category": "Physical", "type": "Fighting", "basePower": 0, "accuracy": 100, "pp": 20, "priority": -5, "flags": {"contact": 1}, "target": "scripted"},
	"mirrorcoat": {"name": "Mirror Coat", "category": "Special", "type": "Psychic", "basePower": 0, "accuracy": 100, "pp": 20, "priority": -5, "flags": {}, "target": "scripted"},
	"steelbeam": {"name": "Steel Beam", "category": "Special", "type": "Steel", "basePower": 140, "accuracy": 95, "pp": 5, "priority": 0, "flags": {}, "target": "normal"},
	"highjumpkick": {"name": "High Jump Kick", "category": "Physical", "type": "Fighting", "basePower": 130, "accuracy": 90, "pp": 10, "priority": 0, "flags": {"contact": 1}, "target": "normal", "hasCrashDamage": true},
	"futuresight": {"name": "Future Sight", "category": "Special", "type": "Psychic", "basePower": 120, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"bugbite": {"name": "Bug Bite", "category": "Physical", "type": "Bug", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"clearsmog": {"name": "Clear Smog", "category": "Special", "type": "Poison", "basePower": 50, "accuracy": true, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"stoneaxe": {"name": "Stone Axe", "category": "Physical", "type": "Rock", "basePower": 65, "accuracy": 90, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
}
const TYPES := {"normal": {"damageTaken": {}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["tackle"], ["tackle"]], items := ["", ""]) -> Battle:
	var fighters := []
	for side in 2:
		fighters.append({"species": "plain", "moves": moves[side], "ability": "", "item": items[side]})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func test_proportional_damage_reads_as_a_per_hit_share() -> void:
	var battle := _battle()
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_eq(MoveEffects.rule_damage(a, b, _move("superfang")), floori(b.hp * 0.5 / 6.0))
	assert_false(MoveEffects.usable(a, b, _move("endeavor")), "not while ahead")
	a.hp = 600
	assert_eq(MoveEffects.rule_damage(a, b, _move("endeavor")), floori((b.hp - 600) / 6.0))
	assert_eq(MoveEffects.rule_damage(a, b, _move("finalgambit")), 100)
	assert_true(_move("finalgambit").self_destructs)


func test_counter_pays_back_recent_hits_of_its_kind() -> void:
	var battle := _battle([["counter", "mirrorcoat"], ["tackle", "swift"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_eq(_move("counter").kind, BattleMove.Kind.MELEE)
	assert_false(MoveEffects.usable(a, b, a.moves[0]), "nothing to pay back")
	var hp := a.hp
	battle._hit(b, a, b.moves[0])
	var took := hp - a.hp
	assert_eq(MoveEffects.rule_damage(a, b, a.moves[0]), took * 2)
	assert_false(MoveEffects.usable(a, b, a.moves[1]), "a physical hit isn't Mirror Coat's")
	for i in Rules.seconds_to_ticks(Rules.RETURN_SECONDS) + 1:
		battle.step()
	assert_false(MoveEffects.usable(a, b, a.moves[0]), "too long ago")


func test_hp_costs_and_crashes() -> void:
	var battle := _battle([["steelbeam", "highjumpkick"], ["tackle"]])
	var a := battle.fighters[0]
	assert_almost_eq(a.moves[0].cost_share, 0.5 / 6.0, 1e-6)
	var hp := a.hp
	a.position = Vector2(0, -10)
	battle._strike(a, battle.fighters[1], 1)
	assert_eq(hp - a.hp, roundi(a.max_hp * 0.5 / 6.0), "a whiffed High Jump Kick crashes")


func test_future_sight_lands_later() -> void:
	var battle := _battle([["futuresight"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.action = Fighter.Action.WINDUP
	a.action_move = 0
	a.action_ticks = 1
	battle._release(a, b)
	assert_false(a.foresight.is_empty())
	assert_false(MoveEffects.usable(a, b, a.moves[0]), "one at a time")
	var hp := b.hp
	for i in Rules.seconds_to_ticks(Rules.DELAYED_SECONDS) + 1:
		battle.step()
	assert_true(b.hp < hp)
	assert_true(a.foresight.is_empty())


func test_on_hit_effects() -> void:
	var battle := _battle([["bugbite", "clearsmog", "stoneaxe"], ["tackle"]], ["", "sitrusberry"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.hp = a.max_hp / 2
	var hp := a.hp
	battle._hit(a, b, a.moves[0])
	assert_true(b.item_used, "the berry is eaten")
	assert_true(a.hp > hp, "by the attacker")
	b.boosts.atk = 2
	battle._hit(a, b, a.moves[1])
	assert_eq(b.boosts.atk, 0)
	battle._hit(a, b, a.moves[2])
	assert_eq(battle.conditions.hazards[1].get("stealthrock", 0), 1)
