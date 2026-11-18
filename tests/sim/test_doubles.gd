extends TestCase
## Doubles (concepts_brief.md §17 M17): two of each side's team out at once, each locked onto a
## foe; spread moves hit everyone in reach at ×0.75, the ally too for "all adjacent" moves; a
## knockout refills only its own place while the others fight on.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 115, "def": 75, "spa": 65, "spd": 75, "spe": 120}},
	"leaf": {"name": "Leaf", "types": ["Grass"], "baseStats": {"hp": 60, "atk": 70, "def": 70, "spa": 70, "spd": 70, "spe": 70}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"slide": {"name": "Slide", "category": "Physical", "type": "Rock", "basePower": 75, "accuracy": 90, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacentFoes"},
	"growl": {"name": "Growl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 40, "priority": 0, "flags": {}, "target": "allAdjacentFoes", "boosts": {"atk": -1}},
}
const TYPES := {
	"water": {"damageTaken": {"Fire": 2, "Water": 2, "Grass": 1, "Fighting": 0, "Ground": 0, "Rock": 0, "Normal": 0}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2, "Fighting": 0, "Ground": 1, "Rock": 1, "Normal": 0}},
	"grass": {"damageTaken": {"Water": 2, "Fire": 1, "Fighting": 0, "Ground": 2, "Rock": 0, "Normal": 0}},
}


## Plays the intents planned for its fighter, by tick.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _index: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _member(species: String, moves: Array) -> Dictionary:
	return {"species": species, "moves": moves}


func _spec(seed: int, team_a: Array, team_b: Array) -> Dictionary:
	return {"seed": seed, "doubles": true, "arena": "stadium", "fighters": [{"team": team_a}, {"team": team_b}]}


func _scripted() -> Array:
	return [Scripted.new(), Scripted.new(), Scripted.new(), Scripted.new()]


func _create(spec: Dictionary, controllers := []) -> Battle:
	if controllers.is_empty():
		controllers = Controllers.for_spec(spec).controllers
	var created := Battle.create(spec, _data(), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _four() -> Array:
	return [_member("squirt", ["jet", "kick", "quake", "slide"]), _member("leaf", ["kick", "growl"])]


func test_doubles_puts_two_out_a_side_across_from_each_other() -> void:
	var battle := _create(_spec(3, _four(), [_member("blaze", ["kick"]), _member("leaf", ["kick"])]), _scripted())
	assert_true(battle.doubles)
	assert_eq(battle.fighters.size(), 4)
	for index in 4:
		var fighter := battle.fighters[index]
		assert_eq(Battle.index_of(fighter), index)
		assert_eq(fighter.place, index / 2)
		assert_eq(fighter.target_place, fighter.place)
		assert_almost_eq(absf(fighter.position.x), Rules.DOUBLES_SPREAD, 1e-6)
	# Each faces the foe in the same place, straight across.
	assert_eq(battle.target_of(battle.fighters[0]), battle.fighters[1])
	assert_eq(battle.target_of(battle.fighters[3]), battle.fighters[2])
	assert_eq(battle.ally_of(battle.fighters[0]), battle.fighters[2])
	assert_eq(battle.out(1), [battle.fighters[1], battle.fighters[3]])


func test_doubles_needs_two_a_side_and_a_controller_each() -> void:
	var too_few := _spec(1, [_member("squirt", ["jet"])], [_member("blaze", ["kick"]), _member("leaf", ["kick"])])
	assert_true(Battle.create(too_few, _data(), _scripted()).has("error"))
	var spec := _spec(1, _four(), _four())
	assert_true(Battle.create(spec, _data(), [Scripted.new(), Scripted.new()]).has("error"))
	assert_eq(Controllers.for_spec(_spec(1, _four(), _four())).controllers.size(), 4)


func test_a_fighter_can_lock_onto_the_other_foe() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"target": 1}}
	var battle := _create(_spec(2, _four(), _four()), controllers)
	battle.step()
	assert_eq(battle.fighters[0].target_place, 1)
	assert_eq(battle.target_of(battle.fighters[0]), battle.fighters[3])
	assert_eq(_events(battle, "target").size(), 1)


func test_the_lock_passes_to_the_other_foe_while_its_target_is_down() -> void:
	var battle := _create(_spec(2, _four(), _four()), _scripted())
	var a := battle.fighters[0]
	battle.fighters[1].hp = 0
	assert_eq(battle.target_of(a), battle.fighters[3])
	battle.fighters[1].hp = 1
	assert_eq(battle.target_of(a), battle.fighters[1])


func _area_hits(spread_both: bool, move: int) -> Array:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": move}}
	var battle := _create(_spec(6, _four(), _four()), controllers)
	var user := battle.fighters[0]
	user.position = Vector2(0, 0)
	battle.fighters[1].position = Vector2(0, 1.5)
	battle.fighters[3].position = Vector2(1.5, 0.8) if spread_both else Vector2(8, 8)
	battle.fighters[2].position = Vector2(-1.5, 0.5)
	for i in 30:
		battle.step()
	return _events(battle, "hit")


func test_a_spread_move_hits_every_foe_in_reach_at_three_quarters() -> void:
	var alone := _area_hits(false, 3)
	var both := _area_hits(true, 3)
	assert_eq(alone.size(), 1)
	assert_eq(both.size(), 2)
	assert_eq(both.map(func(e: Dictionary) -> int: return e.target_side), [1, 1])
	# The same draws, so the first foe's hit is the lone hit at ×0.75.
	assert_eq(both[0].damage, maxi(1, floori(alone[0].damage * Rules.SPREAD_FACTOR)))


func test_an_all_adjacent_move_hits_the_ally_too() -> void:
	var hits := _area_hits(true, 2)
	assert_eq(hits.size(), 3)
	assert_eq(hits.filter(func(e: Dictionary) -> bool: return e.target_side == 0).size(), 1, "the ally is hit")


func test_a_spread_status_move_fires_at_both_foes() -> void:
	var controllers := _scripted()
	controllers[2].plan = {0: {"use": 1}}
	var battle := _create(_spec(6, _four(), _four()), controllers)
	battle.fighters[1].position = Vector2(-2.5, 1)
	battle.fighters[3].position = Vector2(2.5, 1)
	battle.fighters[2].position = Vector2(2.5, -2)
	for i in Rules.seconds_to_ticks(Rules.STATUS_MOVE_WINDUP) + 2:
		battle.step()
	var fired := _events(battle, "fire")
	assert_eq(fired.size(), 2)
	var targets := battle.projectiles.map(func(p: Dictionary) -> int: return p.target)
	targets.sort()
	assert_eq(targets, [1, 3])


func test_allies_cannot_pass_through_each_other() -> void:
	var controllers := _scripted()
	var plan := {}
	for t in 90:
		plan[t] = {"move": Vector2(1, 0)}
	controllers[0].plan = plan
	var battle := _create(_spec(2, _four(), _four()), controllers)
	for i in 90:
		battle.step()
	var a := battle.fighters[0]
	var ally := battle.fighters[2]
	assert_true(a.position.distance_to(ally.position) >= a.radius + ally.radius - 1e-4)


func test_a_knockout_refills_its_place_while_the_rest_fight_on() -> void:
	var controllers := _scripted()
	var battle := _create(_spec(4, _four(), [_member("blaze", ["kick"]), _member("leaf", ["kick"]), _member("squirt", ["jet"])]),
		controllers)
	var down := battle.fighters[3]
	battle.fighters[3].hp = 1
	battle._hurt(down, 5, "status_damage", {})
	assert_true(battle.is_waiting(3))
	assert_false(battle.frozen(battle.fighters[0]), "nobody is frozen in doubles")
	for i in Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS) + 1:
		battle.step()
	var newcomer := battle.fighters[3]
	assert_eq(newcomer.slot, 2)
	assert_eq(newcomer.place, 1)
	assert_eq(battle.fighters[1].slot, 0, "the other place keeps its fighter")
	assert_almost_eq(newcomer.position.x, Rules.DOUBLES_SPREAD, 0.6)


func test_with_no_bench_left_a_side_fights_on_alone() -> void:
	var battle := _create(_spec(4, _four(), [_member("blaze", ["kick"]), _member("leaf", ["kick"])]), _scripted())
	battle._hurt(battle.fighters[3], 9999, "status_damage", {})
	assert_false(battle.is_waiting(3))
	for i in 60:
		battle.step()
	assert_eq(battle.result, Battle.Result.ONGOING)
	assert_true(battle.fighters[3].is_knocked_out())
	battle._hurt(battle.fighters[1], 9999, "status_damage", {})
	battle.step()
	assert_eq(battle.result, Battle.Result.WIN_A)


func test_the_last_bench_member_fills_only_one_of_two_empty_places() -> void:
	var battle := _create(_spec(4, _four(), [_member("blaze", ["kick"]), _member("leaf", ["kick"]), _member("squirt", ["jet"])]),
		_scripted())
	battle._hurt(battle.fighters[1], 9999, "status_damage", {})
	battle._hurt(battle.fighters[3], 9999, "status_damage", {})
	assert_true(battle.is_waiting(1))
	assert_false(battle.is_waiting(3))
	for i in Rules.seconds_to_ticks(Rules.KNOCKOUT_LULL_SECONDS) + 1:
		battle.step()
	assert_eq(battle.fighters[1].slot, 2)
	assert_true(battle.fighters[3].is_knocked_out())


func test_doubles_replay_exactly() -> void:
	var spec := _spec(9, _four(), [_member("blaze", ["kick", "slide"]), _member("leaf", ["kick"]), _member("squirt", ["jet"])])
	var first := _create(spec)
	first.run()
	var second := _create(spec.duplicate(true))
	second.run()
	assert_true(first.result != Battle.Result.ONGOING)
	assert_eq(first.checksum(), second.checksum())


func test_a_saved_doubles_battle_replays_each_fighter() -> void:
	var spec := _spec(5, _four(), [_member("blaze", ["kick", "slide"]), _member("leaf", ["kick"])])
	var played := _create(spec)
	played.record_intents = true
	played.run()
	var saved := played.saved_spec()
	assert_true(saved.fighters[0].has("ally_intents"))
	var replayed := _create(saved)
	replayed.run()
	assert_eq(replayed.checksum(), played.checksum())


func test_a_side_can_switch_either_fighter_under_one_cooldown() -> void:
	var controllers := _scripted()
	var start := Rules.seconds_to_ticks(Rules.SWITCH_COOLDOWN_SECONDS) + 1
	controllers[2].plan = {start: {"switch": 2}}
	controllers[0].plan = {start + 1: {"switch": 3}}
	var team := _four() + [_member("blaze", ["kick"]), _member("squirt", ["jet"])]
	var battle := _create(_spec(4, team, _four()), controllers)
	for i in start + 2:
		battle.step()
	assert_eq(battle.fighters[2].slot, 2, "the second fighter switched")
	assert_eq(battle.fighters[2].place, 1)
	assert_eq(battle.fighters[0].slot, 0, "the side's cooldown held the first back")
	assert_false(battle.can_switch(0, 3))


func test_doubles_hp_takes_a_team_of_twos_factor_at_any_size() -> void:
	var two := _create(_spec(1, _four(), _four()), _scripted())
	var six_team := _four() + _four() + _four()
	var six := _create(_spec(1, six_team, six_team), _scripted())
	assert_almost_eq(two.pace, Rules.team_hp_factor(2), 1e-9)
	assert_almost_eq(six.pace, Rules.team_hp_factor(2), 1e-9)
	assert_eq(six.fighters[0].max_hp, two.fighters[0].max_hp)
