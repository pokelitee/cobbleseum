extends TestCase
## The utility AI (concepts_brief.md §11): unit tests for its scoring and scenario tests
## for its behaviour, on small inline data.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	# One special, one physical, typeless for STAB, to set a moveset's melee lean by stats alone.
	"caster": {"name": "Caster", "types": ["Normal"], "baseStats": {"hp": 80, "atk": 50, "def": 100, "spa": 130, "spd": 100, "spe": 80}},
	"bruiser": {"name": "Bruiser", "types": ["Normal"], "baseStats": {"hp": 80, "atk": 130, "def": 100, "spa": 50, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"leaf": {"name": "Leaf", "category": "Special", "type": "Grass", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"meteor": {"name": "Meteor", "category": "Special", "type": "Water", "basePower": 130, "accuracy": 100, "pp": 5, "priority": 0, "flags": {}, "target": "normal", "self": {"boosts": {"spa": -2}}},
	"recover": {"name": "Recover", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "heal": [1, 2]},
}
const TYPES := {
	"fire": {"damageTaken": {"Water": 1, "Grass": 2, "Fire": 2}},
	"water": {"damageTaken": {"Grass": 1, "Fire": 2, "Water": 2}},
}


class Idle extends RefCounted:
	func decide(_battle: Battle, _side: int) -> Dictionary:
		return {}


func _battle(ai: Object, moves: Array, foe: Object = null, foe_moves := ["jet"], seed := 1, foe_species := "blaze",
		species := "squirt") -> Battle:
	var spec := {"seed": seed, "arena": "stadium", "fighters": [{"species": species, "moves": moves}, {"species": foe_species, "moves": foe_moves}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), [ai, foe if foe != null else Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _ai(profile := "ranked", seed := 1) -> UtilityAI:
	return UtilityAI.new(Controllers.load_profile(profile), SimRandom.new(seed))


func _place(battle: Battle, gap: float) -> void:
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.position = Vector2(0, -(gap + a.radius + b.radius) / 2.0)
	b.position = Vector2(0, (gap + a.radius + b.radius) / 2.0)


func test_combine_compensates_for_more_considerations() -> void:
	assert_eq(UtilityAI.combine([]), 0.0)
	assert_almost_eq(UtilityAI.combine([0.5]), 0.5, 1e-6, "one consideration is used as is")
	var two := UtilityAI.combine([0.5, 0.5])
	assert_true(two > 0.25 and two < 0.5, "two halves score above their raw product: %f" % two)
	assert_eq(UtilityAI.combine([1.0, 0.0, 1.0]), 0.0, "a zero vetoes")


func test_curves_rise_with_their_input() -> void:
	for name in ["damage", "finisher", "charges", "danger", "too_far", "too_close"]:
		var c := UtilityAI.curve(name)
		assert_true(c.sample(c.max_domain) > c.sample(c.min_domain), name)


func test_does_not_use_a_melee_move_out_of_range() -> void:
	var ai := _ai()
	var battle := _battle(ai, ["kick"])
	_place(battle, 6.0)
	for i in 10:
		var intent := ai.decide(battle, 0)
		assert_eq(intent.get("use", -1), -1, "kick from 6 m")
		battle.tick += 1
	assert_true((ai.decide(battle, 0).get("move", Vector2.ZERO) as Vector2).y > 0.0, "it closes in instead")


## Where the AI walks from a 4.5 m gap, out of melee reach (the foe straight ahead, in +y):
## above 0.5 is approaching, near 0 circling, below 0 backing off; -1 if it doesn't walk.
func _heading(ai: UtilityAI, battle: Battle) -> float:
	_place(battle, 4.5)
	var intent := ai.decide(battle, 0)
	assert_eq(intent.get("use", -1), -1, "nothing in reach to use")
	return (intent.move as Vector2).y if intent.has("move") else -1.0


func _lean(species: String, moves: Array) -> float:
	var battle := _battle(Idle.new(), moves, null, ["jet"], 1, "blaze", species)
	return UtilityAI.melee_lean(battle.fighters[0], battle.fighters[1], battle.data())


func test_melee_lean_weighs_the_whole_moveset_and_stats() -> void:
	var caster := _lean("caster", ["jet", "kick"])
	var bruiser := _lean("bruiser", ["jet", "kick"])
	assert_true(caster < UtilityAI.KITER_LEAN, "a special attacker with one kick leans ranged: %f" % caster)
	assert_true(bruiser > UtilityAI.KITER_LEAN, "a physical one with the same moves leans melee: %f" % bruiser)
	assert_eq(_lean("squirt", ["kick"]), 1.0)
	assert_eq(_lean("squirt", ["jet", "recover"]), 0.0, "a heal doesn't count")
	assert_eq(_lean("squirt", ["recover"]), UtilityAI.NEUTRAL_LEAN)


func test_melee_lean_follows_stat_stages() -> void:
	var battle := _battle(Idle.new(), ["jet", "kick"], null, ["jet"], 1, "blaze", "caster")
	var me := battle.fighters[0]
	var before := UtilityAI.melee_lean(me, battle.fighters[1], battle.data())
	me.boosts.atk = 6
	me.boosts.spa = -2
	var after := UtilityAI.melee_lean(me, battle.fighters[1], battle.data())
	assert_true(before < UtilityAI.KITER_LEAN and after > UtilityAI.KITER_LEAN,
		"boosted Attack turns it into a brawler: %f -> %f" % [before, after])


func test_a_kiter_keeps_its_range_with_a_melee_move_ready() -> void:
	for seed in 5:
		var ai := _ai("ranked", seed)
		var battle := _battle(ai, ["jet", "kick"], null, ["jet"], seed, "blaze", "caster")
		battle.fighters[0].cooldowns[0] = 200
		assert_true(_heading(ai, battle) < 0.5, "seed %d: doesn't walk in for the kick" % seed)


## The band each keeps with the same moves, by readiness: {"melee", "ranged", "waiting"}.
func _bands(species: String) -> Dictionary:
	var ai := _ai()
	var battle := _battle(ai, ["jet", "kick"], null, ["jet"], 1, "blaze", species)
	var me := battle.fighters[0]
	var foe := battle.fighters[1]
	var seen := {"position": foe.position, "action": Fighter.Action.READY, "action_ticks": 0}
	var bands := {"melee": ai._band(battle, me, foe, seen)}
	me.cooldowns[1] = 200
	bands.ranged = ai._band(battle, me, foe, seen)
	me.cooldowns[0] = 200
	bands.waiting = ai._band(battle, me, foe, seen)
	return bands


func test_a_brawler_keeps_closer_than_a_kiter() -> void:
	var brawler := _bands("bruiser")
	var kiter := _bands("caster")
	assert_eq(brawler.melee, UtilityAI.MELEE_GAP, "a ready kick brings the brawler in")
	assert_true(kiter.melee.x > UtilityAI.MELEE_GAP.y, "but not the kiter: %s" % kiter.melee)
	for readiness in ["ranged", "waiting"]:
		assert_true(brawler[readiness].x < kiter[readiness].x and brawler[readiness].y < kiter[readiness].y,
			"%s: brawler %s inside kiter %s" % [readiness, brawler[readiness], kiter[readiness]])


func test_everyone_closes_in_for_melee_in_overtime() -> void:
	var ai := _ai()
	var battle := _battle(ai, ["jet", "kick"], null, ["jet"], 1, "blaze", "caster")
	var foe := battle.fighters[1]
	var seen := {"position": foe.position, "action": Fighter.Action.READY, "action_ticks": 0}
	battle.tick = Rules.seconds_to_ticks(Rules.OVERTIME_SECONDS)
	assert_eq(ai._band(battle, battle.fighters[0], foe, seen), UtilityAI.MELEE_GAP)


func test_a_kiter_dashes_in_on_an_opening() -> void:
	for opening in ["asleep", "out of dodges and guard", "recovering", "about to be feinted"]:
		var profile := Controllers.load_profile("ranked").duplicate() as AIProfile
		profile.mistake_chance = 0.0
		profile.feint_chance = 1.0 if opening == "about to be feinted" else 0.0
		var ai := UtilityAI.new(profile, SimRandom.new(1))
		var battle := _battle(ai, ["jet", "kick"], null, ["jet"], 1, "blaze", "caster")
		battle.fighters[0].cooldowns[0] = 200
		var foe := battle.fighters[1]
		match opening:
			"asleep":
				foe.status = "slp"
			"out of dodges and guard":
				foe.dodge_charges = 0
				foe.guard_cooldown = 60
			"recovering":
				foe.action = Fighter.Action.RECOVERY
				foe.action_ticks = 30
			"about to be feinted":
				foe.dodge_charges = 1
		assert_true(_heading(ai, battle) > 0.5, "goes in for the kick: the foe is %s" % opening)


func test_heals_when_low() -> void:
	var ai := _ai()
	var battle := _battle(ai, ["jet", "recover"])
	_place(battle, 4.0)
	assert_eq(ai.decide(battle, 0).get("use", -1), 0, "attacks at full HP")
	var low := _ai()
	battle = _battle(low, ["jet", "recover"])
	_place(battle, 4.0)
	battle.fighters[0].hp = battle.fighters[0].max_hp / 5
	battle.fighters[1].cooldowns[0] = 90
	assert_eq(low.decide(battle, 0).get("use", -1), 1, "recovers at 20% HP while the foe can't hit back")


func test_does_not_heal_when_the_foe_could_cancel_it() -> void:
	var ai := _ai()
	var battle := _battle(ai, ["recover"])
	_place(battle, 4.0)
	var me := battle.fighters[0]
	var foe := battle.fighters[1]
	var channel := Rules.seconds_to_ticks(Rules.HEAL_WINDUP)
	var seen := {"position": foe.position, "action": Fighter.Action.READY, "action_ticks": 0}
	assert_eq(UtilityAI.heal_cover(me, foe, seen, {}, channel), UtilityAI.EXPOSED, "the foe's Jet would land first")
	foe.cooldowns[0] = 90
	assert_eq(UtilityAI.heal_cover(me, foe, seen, {}, channel), 1.0, "safe while its only attack recharges")
	assert_eq(UtilityAI.heal_cover(me, foe, seen, {"ticks": 5}, channel), UtilityAI.EXPOSED, "an attack already incoming")
	foe.cooldowns[0] = 0
	seen = {"position": foe.position, "action": Fighter.Action.RECOVERY, "action_ticks": 60}
	assert_eq(UtilityAI.heal_cover(me, foe, seen, {}, channel), 1.0, "safe while the foe recovers")


func test_self_lowering_moves_are_vetoed_and_charged() -> void:
	var ai := _ai()
	ai.keep_scores = true
	var battle := _battle(ai, ["meteor", "jet"])
	_place(battle, 4.0)
	var me := battle.fighters[0]
	assert_eq(UtilityAI.stage_cost(me, me.moves[0]), 0.5, "-2 halves the other special attack")
	me.boosts.spa = 2
	assert_eq(UtilityAI.stage_cost(me, me.moves[0]), 0.5, "throwing away +2 costs as much")
	me.boosts.spa = -1
	me.cooldowns[1] = 90
	assert_eq(ai.decide(battle, 0).get("use", -1), -1, "won't sink to -3 even with nothing else ready")
	var meteor: Dictionary = ai.last_scores.filter(func(c: Dictionary) -> bool: return c.action == "move:meteor")[0]
	assert_eq(meteor.score, 0.0)


func test_prefers_a_super_effective_move() -> void:
	var ai := _ai()
	var battle := _battle(ai, ["leaf", "jet"])
	_place(battle, 4.0)
	assert_eq(ai.decide(battle, 0).get("use", -1), 1, "Water over Grass against a Fire type")


func test_sees_the_opponent_after_its_reaction_delay() -> void:
	var ai := _ai("easy")
	var battle := _battle(ai, ["jet"])
	var foe := battle.fighters[1]
	var start := foe.position
	ai.decide(battle, 0)
	foe.position += Vector2(3, 0)
	for i in ai.profile.reaction_delay_ticks:
		ai._remember(foe)
	assert_eq(ai._perceived(foe).position, start, "still sees where it was")
	ai._remember(foe)
	assert_eq(ai._perceived(foe).position, foe.position, "catches up after the delay")


func test_dodges_a_telegraphed_projectile() -> void:
	# A free-to-act AI that always tries to dodge, with a shot coming from 6 m away; it
	# notices the shot after its reaction delay and dodges before it lands.
	var profile: AIProfile = Controllers.load_profile("hard").duplicate()
	profile.dodge_chance = 1.0
	profile.mistake_chance = 0.0
	for seed in 6:
		var ai := UtilityAI.new(profile, SimRandom.new(seed))
		var battle := _battle(ai, ["recover"], null, ["jet"], seed)
		_place(battle, 6.0)
		var me := battle.fighters[0]
		var foe := battle.fighters[1]
		var toward := (me.position - foe.position).normalized()
		battle.projectiles.append({"id": 99, "owner": 1, "move": 0, "position": foe.position + toward * foe.radius,
			"velocity": toward * (16.0 / Rules.TICK_RATE), "travelled": 0.0, "height": Rules.CHEST_HEIGHT, "rise": 0.0})
		for i in 30:
			battle.step()
		var mine := battle.events.filter(func(e: Dictionary) -> bool: return e.side == 0 and e.type == "dodge")
		var taken := battle.events.filter(func(e: Dictionary) -> bool: return e.side == 1 and e.type == "hit")
		assert_eq([mine.size(), taken.size()], [1, 0], "seed %d: one dodge, no hit" % seed)


func test_easy_misses_more_dodges_than_hard() -> void:
	var dodged := {}
	for name in ["easy", "hard"]:
		dodged[name] = 0
		for seed in 20:
			var ai := UtilityAI.new(Controllers.load_profile(name), SimRandom.new(seed))
			var battle := _battle(ai, ["recover"], null, ["jet"], seed)
			_place(battle, 6.0)
			var me := battle.fighters[0]
			var foe := battle.fighters[1]
			var toward := (me.position - foe.position).normalized()
			battle.projectiles.append({"id": 99, "owner": 1, "move": 0, "position": foe.position + toward * foe.radius,
				"velocity": toward * (16.0 / Rules.TICK_RATE), "travelled": 0.0, "height": Rules.CHEST_HEIGHT, "rise": 0.0})
			for i in 30:
				battle.step()
			if battle.events.any(func(e: Dictionary) -> bool: return e.type == "dodge"):
				dodged[name] += 1
	assert_true(dodged.hard > dodged.easy, str(dodged))


func test_controllers_come_from_the_spec() -> void:
	var made := Controllers.for_spec({"seed": 1, "fighters": [{"species": "a"}, {"species": "b", "ai": "stand_in"}]})
	assert_true(made.controllers[0] is UtilityAI, "ranked by default")
	assert_eq((made.controllers[0] as UtilityAI).profile.resource_path, Controllers.PROFILES_DIR.path_join("ranked.tres"))
	assert_true(made.controllers[1] is StandInAI)
	assert_true(Controllers.for_spec({"seed": 1, "fighters": [{"ai": "genius"}, {}]}).error.contains("unknown AI"))
	for profile in ["easy", "normal", "hard", "ranked"]:
		assert_true(Controllers.load_profile(profile) != null, profile)
