extends TestCase
## Switching in team battles (concepts_brief.md §9.1): a "switch" intent recalls the fighter for
## a bench member, which lands where it stood, open to hits; a side-wide cooldown follows every
## send-out; a knockout's pick chooses who comes out next.

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


func _battle(a: Scripted, b: Scripted) -> Battle:
	var spec := {"seed": 1, "fighters": [
		{"team": [{"species": "squirt", "moves": ["jet", "kick"]}, {"species": "leaf", "moves": ["kick"]}, {"species": "blaze", "moves": ["ember"]}]},
		{"team": [{"species": "blaze", "moves": ["ember", "kick"]}, {"species": "leaf", "moves": ["kick"]}]}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), [a, b])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_a_switch_sends_the_bench_member_out_where_the_fighter_stood() -> void:
	var a := Scripted.new()
	var battle := _battle(a, Scripted.new())
	var squirt := battle.fighters[0]
	squirt.position = Vector2(2, -3)
	squirt.boosts.atk = 2
	squirt.confusion_ticks = 40
	squirt.status = "brn"
	squirt.status_ticks = 100
	squirt.hp -= 50
	squirt.cooldowns[0] = 20
	a.plan[0] = {"switch": 2}
	battle.step()
	var blaze := battle.fighters[0]
	assert_eq(blaze.slot, 2)
	assert_eq(blaze.position, Vector2(2, -3))
	assert_eq(blaze.action, Fighter.Action.SEND_OUT)
	assert_false(blaze.is_invulnerable(), "open to hits while it lands")
	assert_eq(_events(battle, "recall").size(), 1)
	assert_true(_events(battle, "send_out")[0].switch)
	# Stages and confusion clear on the way out; HP, status and cooldowns stay, frozen.
	assert_eq(squirt.boosts.atk, 0)
	assert_eq(squirt.confusion_ticks, 0)
	# The tick it switched on still counted down its timers; from then on they're frozen.
	assert_eq(squirt.status, "brn")
	assert_eq(squirt.status_ticks, 99)
	assert_eq(squirt.hp, squirt.max_hp - 50)
	for i in 30:
		battle.step()
	assert_eq(squirt.status_ticks, 99, "frozen on the bench")
	assert_eq(squirt.cooldowns[0], 19)
	assert_eq(blaze.action, Fighter.Action.READY, "landed")


func test_the_switch_cooldown_follows_every_send_out() -> void:
	var a := Scripted.new()
	var battle := _battle(a, Scripted.new())
	a.plan[0] = {"switch": 1}
	battle.step()
	assert_false(battle.can_switch(0, 0), "landing, then on cooldown")
	for i in Rules.seconds_to_ticks(Rules.SWITCH_SECONDS) + 1:
		battle.step()
	assert_true(battle.switch_cooldown(0) > 0)
	assert_false(battle.can_switch(0, 0))
	a.plan[battle.tick] = {"switch": 0}
	battle.step()
	assert_eq(battle.fighters[0].slot, 1, "a switch on cooldown does nothing")
	while battle.switch_cooldown(0) > 0:
		battle.step()
	assert_true(battle.can_switch(0, 0))
	assert_false(battle.can_switch(0, 1), "not to the fighter already out")


func test_after_a_knockout_the_side_sends_out_its_pick() -> void:
	var a := Scripted.new()
	var battle := _battle(a, Scripted.new())
	battle.step()
	battle._hurt(battle.fighters[0], 10000, "status_damage", {"status": "psn"})
	for i in Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS):
		a.plan[battle.tick] = {"switch": 2}
		battle.step()
	assert_eq(battle.fighters[0].slot, 2, "its pick, not the next in order")
	assert_true(battle.fighters[0].shielded)
	assert_true(battle.switch_cooldown(0) > 0)


func test_switches_replay_from_the_intent_log() -> void:
	var intent := {"move": Vector2(0.5, 0), "switch": 3}
	assert_eq(Battle.intent_from_log(Battle.intent_to_log(intent)), intent)
	assert_false(Battle.intent_from_log([0.0, 0.0, -1, 0.0, 0.0, -1, 0]).has("switch"), "logs from before switching")


func test_the_player_cycles_the_bench_and_switches() -> void:
	var player := PlayerController.new()
	var battle := _battle(Scripted.new(), Scripted.new())
	assert_eq(PlayerController.bench_slots(battle, 0), [1, 2])
	assert_false(player.decide(battle, 0).has("switch"))
	assert_eq(player.bench_choice, 1)
	player.pending_cycle = 1
	player.pending_switch = true
	assert_eq(player.decide(battle, 0).switch, 2)
	player.pending_cycle = 1
	player.decide(battle, 0)
	assert_eq(player.bench_choice, 1, "wraps around")
