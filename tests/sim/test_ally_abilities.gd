extends TestCase
## Abilities in doubles (concepts_brief.md §9.9, §17 M17): Intimidate reaches both foes,
## Lightning Rod and Storm Drain draw single-target moves of their type, Friend Guard softens hits
## on the ally, and Telepathy keeps the ally's spread moves off.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80},
		"abilities": {"0": "Telepathy", "1": "Torrent"}},
	"volt": {"name": "Volt", "types": ["Electric"], "baseStats": {"hp": 70, "atk": 80, "def": 70, "spa": 100, "spd": 80, "spe": 100}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"zap": {"name": "Zap", "category": "Special", "type": "Electric", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
}
const TYPES := {
	"water": {"damageTaken": {"Water": 2, "Electric": 1, "Ground": 0}},
	"electric": {"damageTaken": {"Water": 0, "Electric": 2, "Ground": 1}},
}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _index: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _battle(team_a: Array, team_b: Array, controllers: Array) -> Battle:
	var spec := {"seed": 3, "doubles": true, "arena": "stadium", "fighters": [{"team": team_a}, {"team": team_b}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _scripted() -> Array:
	return [Scripted.new(), Scripted.new(), Scripted.new(), Scripted.new()]


func _member(species: String, moves: Array, ability := "") -> Dictionary:
	return {"species": species, "moves": moves, "ability": ability}


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_doubles_only_abilities_are_never_standard() -> void:
	assert_eq(Abilities.standard(SPECIES.squirt), "torrent")


func test_intimidate_lowers_both_foes() -> void:
	var battle := _battle([_member("squirt", ["jet"], "intimidate"), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], _scripted())
	battle.step()
	assert_eq(battle.fighters[1].boosts.atk, -1)
	assert_eq(battle.fighters[3].boosts.atk, -1)
	assert_eq(battle.fighters[2].boosts.atk, 0, "not the ally")


func test_lightning_rod_draws_single_target_electric_moves() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}}
	var battle := _battle([_member("volt", ["zap"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"], "lightningrod")], controllers)
	battle.fighters[1].position = Vector2(-2.5, 0)
	battle.fighters[3].position = Vector2(2.5, 0)
	assert_eq(battle.drawn_to(battle.fighters[0], battle.fighters[1], battle.fighters[0].moves[0]), battle.fighters[3])
	for i in 60:
		battle.step()
	var hits := _events(battle, "hit")
	assert_true(not hits.is_empty())
	assert_eq([hits[0].target_side, hits[0].target_slot], [1, 1], "the rod took it")


func test_friend_guard_softens_hits_on_the_ally() -> void:
	var plain := _battle([_member("volt", ["zap"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], _scripted())
	var guarded := _battle([_member("volt", ["zap"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"], "friendguard")], _scripted())
	var a: float = Battle.damage_parts(plain.fighters[0], plain.fighters[1], plain.fighters[0].moves[0], plain.data()).factor
	var b: float = Battle.damage_parts(guarded.fighters[0], guarded.fighters[1], guarded.fighters[0].moves[0], guarded.data()).factor
	assert_almost_eq(b, a * 0.75, 1e-6)


func test_telepathy_keeps_the_allys_spread_move_off() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}}
	var battle := _battle([_member("volt", ["quake"]), _member("squirt", ["jet"], "telepathy")],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], controllers)
	battle.fighters[0].position = Vector2(0, 0)
	battle.fighters[2].position = Vector2(-1.5, 0)
	battle.fighters[1].position = Vector2(0, 1.5)
	battle.fighters[3].position = Vector2(8, 8)
	for i in 30:
		battle.step()
	var hits := _events(battle, "hit")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].target_side, 1)
