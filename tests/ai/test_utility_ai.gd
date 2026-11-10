extends TestCase
## The utility AI (concepts_brief.md §11): unit tests for its scoring and scenario tests
## for its behaviour, on small inline data.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"leaf": {"name": "Leaf", "category": "Special", "type": "Grass", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"recover": {"name": "Recover", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "heal": [1, 2]},
}
const TYPES := {
	"fire": {"damageTaken": {"Water": 1, "Grass": 2, "Fire": 2}},
	"water": {"damageTaken": {"Grass": 1, "Fire": 2, "Water": 2}},
}


class Idle extends RefCounted:
	func decide(_battle: Battle, _side: int) -> Dictionary:
		return {}


func _battle(ai: Object, moves: Array, foe: Object = null, foe_moves := ["jet"], seed := 1, foe_species := "blaze") -> Battle:
	var spec := {"seed": seed, "fighters": [{"species": "squirt", "moves": moves}, {"species": foe_species, "moves": foe_moves}]}
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
			"velocity": toward * (16.0 / Rules.TICK_RATE), "travelled": 0.0})
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
				"velocity": toward * (16.0 / Rules.TICK_RATE), "travelled": 0.0})
			for i in 30:
				battle.step()
			if battle.events.any(func(e: Dictionary) -> bool: return e.type == "dodge"):
				dodged[name] += 1
	assert_true(dodged.hard > dodged.easy, str(dodged))


func test_controllers_come_from_the_spec() -> void:
	var made := Controllers.for_spec({"seed": 1, "fighters": [{"species": "a"}, {"species": "b", "ai": "simple"}]})
	assert_true(made.controllers[0] is UtilityAI, "ranked by default")
	assert_eq((made.controllers[0] as UtilityAI).profile.resource_path, Controllers.PROFILES_DIR.path_join("ranked.tres"))
	assert_true(made.controllers[1] is SimpleAI)
	assert_true(Controllers.for_spec({"seed": 1, "fighters": [{"ai": "genius"}, {}]}).error.contains("unknown AI"))
	for profile in ["easy", "normal", "hard", "ranked"]:
		assert_true(Controllers.load_profile(profile) != null, profile)
