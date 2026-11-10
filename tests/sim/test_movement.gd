extends TestCase
## Movement, dashing melee and dodging (concepts_brief.md §9.1–§9.3), with scripted
## controllers so each rule is checked in isolation.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"pulse": {"name": "Pulse", "category": "Special", "type": "Dark", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"pulse": 1}, "target": "any"},
}


## Replays a fixed intent per tick, then idles.
class Scripted extends RefCounted:
	var intents: Array

	func _init(steps: Array) -> void:
		intents = steps

	func decide(battle: Battle, _side: int) -> Dictionary:
		return intents[battle.tick] if battle.tick < intents.size() else {}


## Walks straight at the foe, then uses move `use` once the gap is below `start_gap`.
class Charger extends RefCounted:
	var use: int
	var start_gap: float
	var started := false

	func _init(move_index: int, gap: float) -> void:
		use = move_index
		start_gap = gap

	func decide(battle: Battle, side: int) -> Dictionary:
		var me := battle.fighters[side]
		var foe := battle.fighters[1 - side]
		if not started and Battle._gap(me, foe) <= start_gap:
			started = true
			return {"use": use}
		return {"move": (foe.position - me.position).normalized() if not started else Vector2.ZERO}


## Stands still and dodges sideways once a projectile is within `trigger` metres.
class LateDodger extends RefCounted:
	var trigger: float

	func _init(distance: float) -> void:
		trigger = distance

	func decide(battle: Battle, side: int) -> Dictionary:
		var me := battle.fighters[side]
		for projectile in battle.projectiles:
			if (projectile.position as Vector2).distance_to(me.position) <= trigger:
				return {"dodge": Vector2(1, 0)}
		return {}


func _battle(script_a: Variant, script_b: Variant, moves := ["jet", "kick"]) -> Battle:
	var spec := {"seed": 1, "fighters": [{"species": "squirt", "moves": moves}, {"species": "squirt", "moves": moves}]}
	var controllers := []
	for script: Variant in [script_a, script_b]:
		controllers.append(Scripted.new(script) if script is Array else script)
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _repeat(intent: Dictionary, count: int) -> Array:
	var steps := []
	for i in count:
		steps.append(intent)
	return steps


func test_single_target_variants_are_playable() -> void:
	assert_eq(BattleMove.from_showdown("pulse", MOVES.pulse).move.kind, BattleMove.Kind.PROJECTILE)


func test_moves_only_start_within_reach() -> void:
	# Fighters start 8 m apart: too far for melee (dash range 3 m), close enough for a projectile.
	var battle := _battle([{"use": 1}], [])
	battle.step()
	assert_eq(_events(battle, "windup").size(), 0, "melee out of reach doesn't start")
	battle = _battle([{"use": 0}], [])
	battle.step()
	assert_eq(_events(battle, "windup").size(), 1)


func test_melee_dashes_in_during_the_windup() -> void:
	var battle := _battle(Charger.new(1, 2.8), [])
	while _events(battle, "windup").is_empty() and battle.tick < 200:
		battle.step()
	var gap_at_start := Battle._gap(battle.fighters[0], battle.fighters[1])
	assert_true(gap_at_start > Rules.MELEE_REACH, "starts outside reach: %.2f" % gap_at_start)
	while _events(battle, "hit").is_empty() and battle.tick < 250:
		battle.step()
	assert_eq(_events(battle, "hit").size(), 1, "the dash closes the gap and the strike lands")


func test_dodging_passes_through_a_projectile_and_spends_a_charge() -> void:
	var battle := _battle([{"use": 0}], LateDodger.new(1.5))
	while battle.tick < 40:
		battle.step()
	var defender := battle.fighters[1]
	assert_eq(_events(battle, "dodge").size(), 1)
	assert_eq(_events(battle, "dodged").size(), 1, "the projectile reached the dodging fighter")
	assert_eq(_events(battle, "hit").size(), 0)
	assert_eq(defender.hp, defender.max_hp)
	assert_true(defender.position.x > 2.0, "the dodge moved it sideways: %s" % defender.position)
	assert_eq(defender.dodge_charges, Rules.DODGE_CHARGES - 1)
	while battle.tick < 40 + defender.dodge_recharge_total:
		battle.step()
	assert_eq(defender.dodge_charges, Rules.DODGE_CHARGES, "the charge comes back")


func test_without_charges_there_is_no_dodge() -> void:
	var dodge := {"dodge": Vector2(1, 0)}
	var battle := _battle([], [dodge] + _repeat({}, 6) + [dodge] + _repeat({}, 6) + [dodge])
	while battle.tick < 20:
		battle.step()
	assert_eq(_events(battle, "dodge").size(), Rules.DODGE_CHARGES)


func test_fighters_never_overlap_or_leave_the_arena() -> void:
	var charge := {"move": Vector2(0, 1)}
	var battle := _battle(_repeat(charge, 200), _repeat({"move": Vector2(1, 0)}, 200))
	for i in 200:
		battle.step()
		var a := battle.fighters[0]
		var b := battle.fighters[1]
		assert_true(Battle._gap(a, b) >= -1e-4, "overlap at tick %d" % battle.tick)
		for fighter in [a, b]:
			assert_true(fighter.position.length() <= Rules.ARENA_RADIUS - fighter.radius + 1e-4, "outside the wall at tick %d" % battle.tick)


func test_ai_sees_an_incoming_projectile() -> void:
	var battle := _battle([{"use": 0}], [])
	for i in 12:
		battle.step()
	assert_false(battle.projectiles.is_empty())
	var threat := SimpleAI.incoming_threat(battle, 1)
	if battle.projectiles[0].position.distance_to(battle.fighters[1].position) < 5.0:
		assert_false(threat.is_empty(), "a projectile on course is a threat")
	assert_true(SimpleAI.incoming_threat(battle, 0).is_empty(), "your own projectile isn't")


func test_ai_dodges_some_but_not_all_projectiles() -> void:
	var dodges := 0
	var hits := 0
	for seed in 30:
		var spec := {"seed": seed, "fighters": [{"species": "squirt", "moves": ["jet"]}, {"species": "squirt", "moves": ["jet"]}]}
		var battle: Battle = Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), SimpleAI.pair(seed)).battle
		for i in 300:
			battle.step()
		dodges += _events(battle, "dodge").size()
		hits += _events(battle, "hit").size()
	assert_true(dodges > 0 and hits > dodges, "%d dodges, %d hits" % [dodges, hits])
