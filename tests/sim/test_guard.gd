extends TestCase
## Guarding (concepts_brief.md §9.2): a short parry that blocks hits from the front, staggers a
## parried melee attacker, whiffs into a recovery, and how the AIs use and bait it. Small inline
## data, so CI needs no asset cache.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"jabs": {"name": "Jabs", "category": "Physical", "type": "Fighting", "basePower": 20, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal", "multihit": 3},
}
const TYPES := {
	"fire": {"damageTaken": {"Water": 1, "Fire": 2}},
	"water": {"damageTaken": {"Fire": 2, "Water": 2}},
}
## Kick's wind-up is 8 ticks; a guard raised on this tick is up when it lands.
const GUARD_TICK := 3


## Plays one intent on its tick and nothing otherwise.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _battle(controllers: Array, moves_a := ["kick", "jet"], moves_b := ["jet"]) -> Battle:
	var spec := {"seed": 1, "arena": "stadium", "fighters": [{"species": "squirt", "moves": moves_a}, {"species": "blaze", "moves": moves_b}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	var battle: Battle = created.battle
	_place(battle, 1.0)
	return battle


func _place(battle: Battle, gap: float) -> void:
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.position = Vector2(0, -(gap + a.radius + b.radius) / 2.0)
	b.position = Vector2(0, (gap + a.radius + b.radius) / 2.0)


func _scripted(plan: Dictionary) -> Scripted:
	var scripted := Scripted.new()
	scripted.plan = plan
	return scripted


func _profile(guard_chance: float, dodge_chance := 1.0, feint_chance := 0.0) -> AIProfile:
	var profile := Controllers.load_profile("ranked").duplicate() as AIProfile
	profile.guard_chance = guard_chance
	profile.dodge_chance = dodge_chance
	profile.feint_chance = feint_chance
	profile.mistake_chance = 0.0
	return profile


func _types(battle: Battle) -> Array:
	return battle.events.map(func(e: Dictionary) -> String: return e.type)


func _of_type(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func test_a_guard_parries_a_melee_strike_from_the_front() -> void:
	var battle := _battle([_scripted({0: {"use": 0}}), _scripted({GUARD_TICK: {"guard": true}})])
	var attacker := battle.fighters[0]
	var guard := battle.fighters[1]
	var hp := guard.hp
	_run(battle, GUARD_TICK + 1)
	assert_eq(guard.action, Fighter.Action.GUARD)
	assert_true(guard.is_guarding())
	assert_eq(guard.guard_cooldown, Rules.seconds_to_ticks(Rules.GUARD_COOLDOWN))
	_run(battle, attacker.moves[0].windup_ticks - GUARD_TICK)
	assert_eq(guard.hp, hp, "no damage")
	var parried := _of_type(battle, "guarded")
	assert_eq(parried.size(), 1)
	assert_true(parried[0].parry, "a melee strike is parried")
	assert_eq(attacker.action, Fighter.Action.RECOVERY)
	assert_true(attacker.action_ticks >= Rules.seconds_to_ticks(Rules.PARRY_STAGGER) - 1, "staggered: %d ticks" % attacker.action_ticks)
	_run(battle, Rules.seconds_to_ticks(Rules.GUARD_SECONDS) - (attacker.moves[0].windup_ticks - GUARD_TICK))
	assert_eq(guard.action, Fighter.Action.READY, "a guard that blocked skips its recovery")
	assert_eq(attacker.action, Fighter.Action.RECOVERY, "the attacker is still staggered: a window to punish")
	assert_true(_of_type(battle, "guard_end")[0].blocked)


func test_a_guard_does_not_stop_a_hit_from_behind() -> void:
	var battle := _battle([_scripted({0: {"use": 0}}), _scripted({GUARD_TICK: {"guard": true}})])
	var guard := battle.fighters[1]
	var hp := guard.hp
	_run(battle, GUARD_TICK + 1)
	# Facing away, and too slow to turn round before the kick lands.
	guard.facing = Vector2(0, 1)
	guard.agility = 0.01
	_run(battle, battle.fighters[0].moves[0].windup_ticks - GUARD_TICK)
	assert_true(guard.hp < hp, "hit from behind")
	assert_false("guarded" in _types(battle))


func test_a_guard_that_blocks_nothing_whiffs_into_a_recovery() -> void:
	var battle := _battle([_scripted({}), _scripted({0: {"guard": true}})])
	var guard := battle.fighters[1]
	_run(battle, Rules.seconds_to_ticks(Rules.GUARD_SECONDS) + 1)
	assert_eq(guard.action, Fighter.Action.GUARD, "recovering")
	assert_false(guard.is_guarding(), "the guard is down")
	assert_false(guard.can_dodge(), "can't dodge out of a whiff")
	assert_false(_of_type(battle, "guard_end")[0].blocked)
	_run(battle, Rules.seconds_to_ticks(Rules.GUARD_RECOVERY))
	assert_eq(guard.action, Fighter.Action.READY)


func test_a_guard_blocks_a_projectile_without_a_parry() -> void:
	var battle := _battle([_scripted({0: {"use": 1}}), _scripted({GUARD_TICK: {"guard": true}})])
	var guard := battle.fighters[1]
	var hp := guard.hp
	_run(battle, 20)
	assert_eq(guard.hp, hp)
	var blocked := _of_type(battle, "guarded")
	assert_eq(blocked.size(), 1)
	assert_false(blocked[0].parry, "only melee strikes are parried")
	assert_true(battle.projectiles.is_empty(), "the shot stops at the guard")
	assert_true(battle.fighters[0].action_ticks < Rules.seconds_to_ticks(Rules.PARRY_STAGGER), "a shooter isn't staggered")


func test_a_parry_drops_the_remaining_strikes_of_a_multi_hit_move() -> void:
	var battle := _battle([_scripted({0: {"use": 0}}), _scripted({GUARD_TICK: {"guard": true}})], ["jabs"])
	var guard := battle.fighters[1]
	var hp := guard.hp
	_run(battle, 40)
	assert_eq(guard.hp, hp, "no strike gets through")
	assert_eq(_of_type(battle, "guarded").size(), 1, "one parry ends the flurry")
	assert_true(battle.fighters[0].followups.is_empty())


func test_the_guard_has_a_cooldown_and_it_is_in_the_checksum() -> void:
	var battle := _battle([_scripted({}), _scripted({0: {"guard": true}, 25: {"guard": true}})])
	var guard := battle.fighters[1]
	_run(battle, 26)
	assert_eq(guard.action, Fighter.Action.READY, "still cooling down")
	assert_false(guard.can_guard())
	var plain := _battle([Scripted.new(), Scripted.new()])
	var cooling := _battle([Scripted.new(), Scripted.new()])
	cooling.fighters[0].guard_cooldown = 50
	for each: Battle in [plain, cooling]:
		each.step()
		each.fighters[1].hp = 0
		each.step()
	assert_true(plain.checksum() != cooling.checksum())


func test_guards_survive_the_log_format() -> void:
	var intent := {"move": Vector2(0.5, 0), "guard": true}
	assert_eq(Battle.intent_from_log(Battle.intent_to_log(intent)), intent)
	assert_eq(Battle.intent_from_log([0.0, 0.0, -1, 0.0, 0.0, -1]), {"move": Vector2.ZERO}, "an older six-field entry")


func test_a_feint_baits_a_guard() -> void:
	var battle := _battle([_scripted({0: {"feint": 0}}), _scripted({GUARD_TICK: {"guard": true}})])
	_run(battle, 20)
	var ended := _of_type(battle, "guard_end")
	assert_eq(ended.size(), 1)
	assert_false(ended[0].blocked, "the feint never lands, so the guard whiffs")


func test_the_ai_guards_a_melee_strike_when_out_of_dodges() -> void:
	# Hard's reaction delay and decision interval: ranked sees a kick from 1 m too late to answer.
	var profile := _profile(1.0)
	profile.reaction_delay_ticks = 4
	profile.decision_interval_ticks = 2
	var battle := _battle([_scripted({0: {"use": 0}}), UtilityAI.new(profile, SimRandom.new(1))])
	battle.fighters[1].dodge_charges = 0
	battle.fighters[1].dodge_recharge_ticks = -999
	var hp := battle.fighters[1].hp
	_run(battle, 15)
	assert_true("guard" in _types(battle), str(_types(battle)))
	assert_eq(battle.fighters[1].hp, hp, "it parries the kick")


func test_the_ai_never_guards_without_a_guard_chance() -> void:
	assert_eq(Controllers.load_profile("easy").guard_chance, 0.0)
	assert_true(Controllers.load_profile("hard").guard_chance > Controllers.load_profile("ranked").guard_chance)
	var battle := _battle([_scripted({0: {"use": 0}}), UtilityAI.new(_profile(0.0), SimRandom.new(1))])
	battle.fighters[1].dodge_charges = 0
	battle.fighters[1].dodge_recharge_ticks = -999
	_run(battle, 15)
	assert_false("guard" in _types(battle))


func test_the_ai_waits_out_a_guard_before_striking() -> void:
	var ai := UtilityAI.new(_profile(0.0), SimRandom.new(1))
	var battle := _battle([ai, Scripted.new()], ["kick"])
	var me := battle.fighters[0]
	var kick := me.moves[0]
	var delay := ai.profile.reaction_delay_ticks
	var recovery := Rules.seconds_to_ticks(Rules.GUARD_RECOVERY)
	var seen := {"position": battle.fighters[1].position, "action": Fighter.Action.GUARD,
		"action_ticks": recovery + delay + kick.windup_ticks + 4, "action_move": -1}
	assert_true(ai._guarded_when_landing(me, seen, 1.0, kick), "a kick now would land on the guard")
	seen.action_ticks = recovery + delay + kick.windup_ticks - 2
	assert_false(ai._guarded_when_landing(me, seen, 1.0, kick), "a kick now lands after the guard drops")


func test_feint_openings_include_a_foe_with_only_its_guard_left() -> void:
	var ai := UtilityAI.new(_profile(0.0, 1.0, 1.0), SimRandom.new(1))
	var battle := _battle([ai, Scripted.new()])
	battle.fighters[1].dodge_charges = 0
	assert_eq(ai.decide(battle, 0).get("feint", -1), 0, "draws the guard")
	ai = UtilityAI.new(_profile(0.0, 1.0, 1.0), SimRandom.new(1))
	battle = _battle([ai, Scripted.new()], ["kick"])
	battle.fighters[1].dodge_charges = 0
	battle.fighters[1].guard_cooldown = 60
	assert_eq(ai.decide(battle, 0).get("use", -1), 0, "nothing left to bait: strikes for real")
