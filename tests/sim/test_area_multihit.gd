extends TestCase
## Area, multi-hit, charge, recharge, fixed-damage and self-destructing moves (concepts_brief.md §9.3).

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"earthquake": {"name": "Earthquake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"bulletseed": {"name": "Bullet Seed", "category": "Physical", "type": "Grass", "basePower": 25, "accuracy": 100, "pp": 30, "priority": 0, "flags": {}, "target": "normal", "multihit": [2, 5]},
	"doublekick": {"name": "Double Kick", "category": "Physical", "type": "Fighting", "basePower": 30, "accuracy": 100, "pp": 30, "priority": 0, "flags": {"contact": 1}, "target": "normal", "multihit": 2},
	"solarbeam": {"name": "Solar Beam", "category": "Special", "type": "Grass", "basePower": 120, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"charge": 1}, "target": "normal"},
	"hyperbeam": {"name": "Hyper Beam", "category": "Special", "type": "Normal", "basePower": 150, "accuracy": 90, "pp": 5, "priority": 0, "flags": {"recharge": 1}, "target": "normal"},
	"seismictoss": {"name": "Seismic Toss", "category": "Physical", "type": "Fighting", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal", "damage": "level"},
	"explosion": {"name": "Explosion", "category": "Physical", "type": "Normal", "basePower": 250, "accuracy": 100, "pp": 5, "priority": 0, "flags": {}, "target": "allAdjacent", "selfdestruct": "always"},
	"flail": {"name": "Flail", "category": "Physical", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
}


class Scripted extends RefCounted:
	var intents: Array

	func _init(steps: Array) -> void:
		intents = steps

	func decide(battle: Battle, _side: int) -> Dictionary:
		return intents[battle.tick] if battle.tick < intents.size() else {}


func _battle(moves_a: Array, script_a := []) -> Battle:
	var spec := {"seed": 3, "fighters": [{"species": "squirt", "moves": moves_a}, {"species": "squirt", "moves": ["jet"]}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), [Scripted.new(script_a), Scripted.new([])])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _move(id: String) -> BattleMove:
	return BattleMove.from_showdown(id, MOVES[id]).get("move")


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


## Puts the fighters `gap` metres apart (between hitboxes), facing each other.
func _place(battle: Battle, gap: float) -> void:
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.position = Vector2(0, -(gap + a.radius + b.radius) / 2.0)
	b.position = Vector2(0, (gap + a.radius + b.radius) / 2.0)


func test_moves_are_classified() -> void:
	assert_eq(_move("earthquake").kind, BattleMove.Kind.AREA)
	assert_eq(_move("earthquake").reach(), Rules.AREA_RADIUS)
	assert_eq([_move("bulletseed").hits_min, _move("bulletseed").hits_max], [2, 5])
	assert_almost_eq(_move("bulletseed").expected_hits(), 3.1, 1e-6)
	assert_eq(_move("doublekick").hits_min, 2)
	assert_true(_move("solarbeam").windup_ticks > _move("jet").windup_ticks + Rules.seconds_to_ticks(Rules.CHARGE_EXTRA) - 2)
	assert_true(_move("hyperbeam").recovery_ticks >= Rules.seconds_to_ticks(Rules.PROJECTILE_RECOVERY + Rules.RECHARGE_EXTRA) - 1)
	assert_eq(_move("seismictoss").fixed_damage, Rules.LEVEL)
	assert_true(_move("explosion").self_destructs)
	assert_true(BattleMove.from_showdown("flail", MOVES.flail).has("error"), "power computed in code")


func test_hit_counts_follow_the_main_series_weights() -> void:
	var battle := _battle(["bulletseed"])
	var counts := {2: 0, 3: 0, 4: 0, 5: 0}
	for i in 2000:
		counts[battle._roll_hits(_move("bulletseed"))] += 1
	assert_true(counts[2] > 600 and counts[3] > 600 and counts[4] > 200 and counts[5] > 200, str(counts))
	assert_true(counts[2] < 800 and counts[5] < 400, str(counts))


func test_multi_hit_melee_strikes_each_time() -> void:
	var battle := _battle(["doublekick"], [{"use": 0}])
	_place(battle, 0.5)
	for i in 40:
		battle.step()
	assert_eq(_events(battle, "hit").filter(func(e: Dictionary) -> bool: return e.side == 0).size(), 2)
	assert_eq(_events(battle, "multi_hit_end").size(), 1)


func test_area_moves_hit_within_their_radius_only() -> void:
	var near := _battle(["earthquake"], [{"use": 0}])
	_place(near, Rules.AREA_RADIUS - 0.5)
	for i in 30:
		near.step()
	assert_eq(_events(near, "blast").size(), 1)
	assert_eq(_events(near, "hit").size(), 1)
	var far := _battle(["earthquake"], [{"use": 0}])
	_place(far, Rules.AREA_RADIUS - 0.5)
	far.step()  # wind-up starts in range...
	far.fighters[1].position.y += 3.0  # ...then the target steps back
	for i in 30:
		far.step()
	assert_eq(_events(far, "hit").size(), 0)
	assert_eq(_events(far, "miss").size(), 1)


func test_fixed_damage_ignores_stats() -> void:
	var battle := _battle(["seismictoss"])
	battle.fighters[1].boosts.def = 6
	var outcome := Battle.damage(battle.fighters[0], battle.fighters[1], _move("seismictoss"), BattleData.new(SPECIES, MOVES, {}), SimRandom.new(1))
	assert_eq(outcome.damage, Rules.LEVEL)


func test_self_destruct_faints_the_user() -> void:
	var battle := _battle(["explosion"], [{"use": 0}])
	_place(battle, 1.0)
	for i in 30:
		battle.step()
	assert_true(battle.fighters[0].is_fainted())
	assert_eq(_events(battle, "self_destruct").size(), 1)
	assert_true(battle.is_over())


func test_sleep_cancels_remaining_hits() -> void:
	var battle := _battle(["doublekick"], [{"use": 0}])
	_place(battle, 0.5)
	while _events(battle, "hit").is_empty() and battle.tick < 40:
		battle.step()
	assert_eq(battle.fighters[0].followups.size(), 1)
	battle._inflict(battle.fighters[0], "slp")
	assert_eq(battle.fighters[0].followups.size(), 0)


func test_ai_values_new_moves_sensibly() -> void:
	var battle := _battle(["explosion", "bulletseed", "solarbeam"])
	var me := battle.fighters[0]
	var foe := battle.fighters[1]
	assert_eq(SimpleAI.move_score(me, foe, _move("explosion")), 0.0, "no self-destruct at full HP")
	me.hp = me.max_hp / 10
	assert_true(SimpleAI.move_score(me, foe, _move("explosion")) > 200.0)
	assert_almost_eq(SimpleAI.move_score(me, foe, _move("bulletseed")), 25 * 3.1, 1e-4)
	assert_almost_eq(SimpleAI.move_score(me, foe, _move("solarbeam")), 120 * SimpleAI.CHARGE_FACTOR, 1e-4)
