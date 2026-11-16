extends TestCase
## Feints (concepts_brief.md §9.2): a melee or area wind-up that breaks off unreleased, and how
## the AIs make and answer them. Small inline data, so CI needs no asset cache.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
}
const TYPES := {
	"fire": {"damageTaken": {"Water": 1, "Fire": 2}},
	"water": {"damageTaken": {"Fire": 2, "Water": 2}},
}


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


func _profile(feint_chance: float, dodge_chance := 1.0) -> AIProfile:
	var profile := Controllers.load_profile("ranked").duplicate() as AIProfile
	profile.feint_chance = feint_chance
	profile.dodge_chance = dodge_chance
	profile.mistake_chance = 0.0
	return profile


func test_a_feint_breaks_off_without_spending_the_move() -> void:
	var feinter := Scripted.new()
	feinter.plan = {0: {"feint": 0}}
	var battle := _battle([feinter, Scripted.new()])
	var me := battle.fighters[0]
	var kick := me.moves[0]
	var hp := battle.fighters[1].hp
	battle.step()
	assert_eq(me.action, Fighter.Action.WINDUP, "a feint looks like a wind-up")
	assert_eq(me.action_move, 0)
	assert_eq(me.cooldowns[0], 0, "the move's cooldown isn't spent")
	assert_eq(me.feint_cooldown, Rules.seconds_to_ticks(Rules.FEINT_COOLDOWN))
	for i in kick.windup_ticks - Rules.FEINT_BREAK_TICKS - 1:
		battle.step()
		assert_eq(me.action, Fighter.Action.WINDUP, "still winding up on tick %d" % battle.tick)
	battle.step()
	assert_eq(me.action, Fighter.Action.READY, "breaks off with %d ticks left" % Rules.FEINT_BREAK_TICKS)
	assert_false(me.feinting)
	for i in 30:
		battle.step()
	assert_eq(battle.fighters[1].hp, hp, "no damage")
	var types := battle.events.map(func(e: Dictionary) -> String: return e.type)
	assert_true("feint" in types and "feint_end" in types, str(types))
	assert_false("windup" in types, "a feint isn't a move use")


func test_only_ready_melee_and_area_moves_off_cooldown_can_be_feinted() -> void:
	var battle := _battle([Scripted.new(), Scripted.new()], ["kick", "jet", "quake"])
	var me := battle.fighters[0]
	assert_true(me.can_feint(0), "melee")
	assert_false(me.can_feint(1), "a projectile's wind-up draws nothing")
	assert_true(me.can_feint(2), "area")
	me.cooldowns[0] = 5
	assert_false(me.can_feint(0), "a move on cooldown")
	me.feint_cooldown = 5
	assert_false(me.can_feint(2), "feints on cooldown")


func test_a_feint_needs_the_move_in_reach() -> void:
	var feinter := Scripted.new()
	feinter.plan = {0: {"feint": 0}}
	var battle := _battle([feinter, Scripted.new()])
	_place(battle, 6.0)
	battle.step()
	assert_eq(battle.fighters[0].action, Fighter.Action.READY)
	assert_eq(battle.fighters[0].feint_cooldown, 0)


func test_the_feint_cooldown_is_in_the_checksum() -> void:
	var plain := _battle([Scripted.new(), Scripted.new()])
	var cooling := _battle([Scripted.new(), Scripted.new()])
	cooling.fighters[0].feint_cooldown = 50
	for battle in [plain, cooling]:
		battle.step()
		battle.fighters[1].hp = 0
		battle.step()
	assert_true(plain.checksum() != cooling.checksum())


func test_feints_survive_the_log_format() -> void:
	var intent := {"move": Vector2(0.5, 0), "feint": 1}
	assert_eq(Battle.intent_from_log(Battle.intent_to_log(intent)), intent)
	assert_eq(Battle.intent_from_log([0.0, 0.0, -1, 0.0, 0.0]), {"move": Vector2.ZERO}, "an older five-field entry")


func test_the_stand_in_dodges_a_feint() -> void:
	var feinter := Scripted.new()
	feinter.plan = {0: {"feint": 0}}
	var drawn := 0
	for seed in 20:
		var stand_in := StandInAI.new(SimRandom.new(seed))
		var battle := _battle([feinter, stand_in])
		battle.fighters[1].cooldowns[0] = 999  # free to dodge, not busy attacking
		for i in 12:
			battle.step()
		if battle.events.any(func(e: Dictionary) -> bool: return e.type == "dodge" and e.side == 1):
			drawn += 1
	assert_true(drawn > 0, "the stand-in takes a feint for a strike, sometimes")


func test_the_utility_ai_dodges_a_feint() -> void:
	var feinter := Scripted.new()
	feinter.plan = {0: {"feint": 0}}
	var battle := _battle([feinter, UtilityAI.new(_profile(0.0), SimRandom.new(1))])
	for i in 15:
		battle.step()
	assert_true(battle.events.any(func(e: Dictionary) -> bool: return e.type == "dodge" and e.side == 1),
		"it can't tell a feint from a strike")


func test_feints_when_the_foe_is_on_its_last_dodge() -> void:
	var ai := UtilityAI.new(_profile(1.0), SimRandom.new(1))
	var battle := _battle([ai, Scripted.new()])
	battle.fighters[1].dodge_charges = 1
	assert_eq(ai.decide(battle, 0).get("feint", -1), 0, "fakes the kick to draw the last dodge")


func test_does_not_feint_while_the_foe_has_both_dodges() -> void:
	var ai := UtilityAI.new(_profile(1.0), SimRandom.new(1))
	var battle := _battle([ai, Scripted.new()], ["kick"])
	var intent := ai.decide(battle, 0)
	assert_eq(intent.get("feint", -1), -1)
	assert_eq(intent.get("use", -1), 0, "kicks for real")


func test_profiles_without_a_feint_chance_never_feint() -> void:
	for name in ["easy", "normal"]:
		assert_eq(Controllers.load_profile(name).feint_chance, 0.0, name)
		var ai := UtilityAI.new(Controllers.load_profile(name), SimRandom.new(1))
		var battle := _battle([ai, Scripted.new()])
		battle.fighters[1].dodge_charges = 1
		for i in 10:
			assert_eq(ai.decide(battle, 0).get("feint", -1), -1, name)
			battle.tick += 1
	assert_true(Controllers.load_profile("hard").feint_chance > Controllers.load_profile("ranked").feint_chance)
	assert_true(Controllers.load_profile("ranked").feint_chance > 0.0)


func test_the_chance_is_rolled_once_per_opening() -> void:
	var feints := 0
	for seed in 40:
		var ai := UtilityAI.new(_profile(0.5), SimRandom.new(seed))
		var battle := _battle([ai, Scripted.new()])
		battle.fighters[1].dodge_charges = 1
		var first: int = ai.decide(battle, 0).get("feint", -1)
		for i in 5:
			battle.tick += 1
			assert_eq(ai.decide(battle, 0).get("feint", -1), first, "the same answer while the opening lasts")
		if first >= 0:
			feints += 1
	assert_true(feints > 5 and feints < 35, "about half the openings: %d of 40" % feints)
