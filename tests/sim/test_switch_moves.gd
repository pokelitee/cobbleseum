extends TestCase
## Moves that switch fighters in team battles (concepts_brief.md §9.1, M18, rules version 41):
## pivots, phazers and Healing Wish. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"other": {"name": "Other", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"uturn": {"name": "U-turn", "category": "Physical", "type": "Bug", "basePower": 70, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal", "selfSwitch": true},
	"dragontail": {"name": "Dragon Tail", "category": "Physical", "type": "Dragon", "basePower": 60, "accuracy": 90, "pp": 10, "priority": -6, "flags": {"contact": 1}, "target": "normal", "forceSwitch": true},
	"roar": {"name": "Roar", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": -6, "flags": {"sound": 1}, "target": "normal", "forceSwitch": true},
	"batonpass": {"name": "Baton Pass", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 40, "priority": 0, "flags": {}, "target": "self", "selfSwitch": "copyvolatile"},
	"healingwish": {"name": "Healing Wish", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self"},
}
const TYPES := {"normal": {"damageTaken": {}}, "bug": {"damageTaken": {}}, "dragon": {"damageTaken": {}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves: Array, team := 2) -> Battle:
	var fighters := []
	for side in 2:
		var members := []
		for i in team:
			members.append({"species": "plain" if i == 0 else "other", "moves": moves[side], "ability": "", "item": ""})
		fighters.append({"team": members})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _use(battle: Battle, index: int) -> void:
	var a := battle.fighters[0]
	a.action = Fighter.Action.WINDUP
	a.action_move = index
	a.action_ticks = 1
	battle._release(a, battle.fighters[1])


func _run(battle: Battle, seconds: float) -> void:
	for i in Rules.seconds_to_ticks(seconds) + 1:
		battle.step()


func test_u_turn_pivots_ignoring_the_switch_cooldown() -> void:
	var battle := _battle([["uturn"], ["tackle"]])
	var a := battle.fighters[0]
	assert_true(battle.switch_cooldown(0) > 0, "the leads' send-out started it")
	battle._hit(a, battle.fighters[1], a.moves[0])
	assert_true(a.pivot_ticks > 0)
	_run(battle, Rules.PIVOT_SECONDS)
	assert_eq(battle.fighters[0].slot, 1, "the bench member came in")
	assert_true(battle.switch_cooldown(0) >= Rules.seconds_to_ticks(Rules.SWITCH_COOLDOWN_SECONDS) - 2, "and restarted the cooldown")


func test_u_turn_is_a_plain_hit_one_on_one() -> void:
	var battle := _battle([["uturn"], ["tackle"]], 1)
	battle._hit(battle.fighters[0], battle.fighters[1], battle.fighters[0].moves[0])
	assert_eq(battle.fighters[0].pivot_ticks, 0)


func test_phazers_drag_the_foe_out() -> void:
	var battle := _battle([["roar", "dragontail"], ["tackle"]])
	_use(battle, 0)
	assert_eq(battle.fighters[1].slot, 1)
	battle._switch_cooldown[1] = 0
	var b := battle.fighters[1]
	battle._hit(battle.fighters[0], b, battle.fighters[0].moves[1])
	assert_eq(battle.fighters[1].slot, 0, "Dragon Tail drags the other back")
	var single := _battle([["roar"], ["tackle"]], 1)
	_use(single, 0)
	assert_true(single.events.any(func(e: Dictionary) -> bool: return e.type == "failed"))


func test_baton_pass_hands_on_stages() -> void:
	var battle := _battle([["batonpass"], ["tackle"]])
	battle.fighters[0].boosts.atk = 2
	_use(battle, 0)
	_run(battle, Rules.PIVOT_SECONDS)
	assert_eq(battle.fighters[0].slot, 1)
	assert_eq(battle.fighters[0].boosts.atk, 2)


func test_healing_wish_heals_the_next_one_out() -> void:
	var battle := _battle([["healingwish"], ["tackle"]])
	var next: Fighter = battle.teams[0][1]
	next.hp = 100
	_use(battle, 0)
	assert_true(battle.fighters[0].is_knocked_out())
	_run(battle, Rules.KNOCKOUT_LULL_SECONDS + 0.2)
	assert_true(next.hp > 100)
