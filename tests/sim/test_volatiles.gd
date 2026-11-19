extends TestCase
## Lingering effects (concepts_brief.md §9.5, M18, rules version 40): Taunt, Encore, Disable,
## Leech Seed, Yawn, binding, Curse, Destiny Bond, Perish Song, Magnet Rise, type and ability
## changes. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 100, "def": 80, "spa": 60, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"spooky": {"name": "Spooky", "types": ["Ghost"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"earthquake": {"name": "Earthquake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"swordsdance": {"name": "Swords Dance", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "self", "boosts": {"atk": 2}},
	"taunt": {"name": "Taunt", "category": "Status", "type": "Dark", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "taunt"},
	"encore": {"name": "Encore", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 5, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "encore"},
	"leechseed": {"name": "Leech Seed", "category": "Status", "type": "Grass", "basePower": 0, "accuracy": 90, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "leechseed"},
	"yawn": {"name": "Yawn", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "yawn"},
	"bind": {"name": "Bind", "category": "Physical", "type": "Normal", "basePower": 15, "accuracy": 85, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal", "volatileStatus": "partiallytrapped"},
	"curse": {"name": "Curse", "category": "Status", "type": "Ghost", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "curse"},
	"destinybond": {"name": "Destiny Bond", "category": "Status", "type": "Ghost", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "volatileStatus": "destinybond"},
	"perishsong": {"name": "Perish Song", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {"sound": 1}, "target": "all"},
	"magnetrise": {"name": "Magnet Rise", "category": "Status", "type": "Electric", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "self", "volatileStatus": "magnetrise"},
	"soak": {"name": "Soak", "category": "Status", "type": "Water", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"gastroacid": {"name": "Gastro Acid", "category": "Status", "type": "Poison", "basePower": 0, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "volatileStatus": "gastroacid"},
}
const TYPES := {"normal": {"damageTaken": {"Ghost": 3}}, "ghost": {"damageTaken": {"Normal": 3}}, "water": {"damageTaken": {}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["tackle"], ["tackle"]], species := ["plain", "plain"], abilities := ["", ""]) -> Battle:
	var fighters := []
	for side in 2:
		fighters.append({"species": species[side], "moves": moves[side], "ability": abilities[side], "item": ""})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _land(battle: Battle, index: int) -> void:
	var a := battle.fighters[0]
	battle._land(a, battle.fighters[1], a.moves[index])


func _use(battle: Battle, index: int) -> void:
	var a := battle.fighters[0]
	a.action = Fighter.Action.WINDUP
	a.action_move = index
	a.action_ticks = 1
	battle._release(a, battle.fighters[1])


func _run(battle: Battle, seconds: float) -> void:
	for i in Rules.seconds_to_ticks(seconds) + 1:
		battle.step()


func test_taunt_and_encore_limit_moves() -> void:
	var battle := _battle([["taunt", "encore"], ["tackle", "swordsdance"]])
	var b := battle.fighters[1]
	_land(battle, 0)
	assert_false(MoveEffects.usable(b, battle.fighters[0], b.moves[1]), "no status moves")
	assert_true(MoveEffects.usable(b, battle.fighters[0], b.moves[0]))
	b.last_move = "tackle"
	_land(battle, 1)
	assert_eq(b.volatile_data.encore, "tackle")
	_run(battle, Abilities.ABILITY_SECONDS)
	assert_true(b.volatiles.is_empty(), "both wear off")
	assert_true(MoveEffects.usable(b, battle.fighters[0], b.moves[1]))


func test_leech_seed_and_bind_drain() -> void:
	var battle := _battle([["leechseed", "bind"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	a.hp = 1000
	_land(battle, 0)
	battle._hit(a, b, a.moves[1])
	assert_true(b.volatiles.has("leechseed") and b.volatiles.has("bound"))
	assert_true(Volatiles.trapped(b))
	var hp := b.hp
	_run(battle, 2.0)
	assert_true(b.hp < hp)
	assert_true(a.hp > 1000, "the seed feeds the user")


func test_yawn_puts_to_sleep_a_turn_later() -> void:
	var battle := _battle([["yawn"], ["tackle"]])
	var b := battle.fighters[1]
	_land(battle, 0)
	assert_eq(b.status, "")
	_run(battle, Volatiles.TURN_SECONDS)
	assert_eq(b.status, "slp")


func test_curse_destiny_bond_and_perish_song() -> void:
	var battle := _battle([["curse", "destinybond", "perishsong"], ["tackle"]], ["spooky", "plain"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var hp := a.hp
	_use(battle, 0)
	assert_eq(hp - a.hp, roundi(a.max_hp * 0.5), "a Ghost pays half")
	assert_true(b.volatiles.has("curse"))
	_use(battle, 1)
	a.hp = 1
	battle._hit(b, a, _data().convert_move("earthquake").move)
	assert_true(b.is_knocked_out(), "taken down with it")
	var song := _battle([["perishsong"], ["tackle"]])
	_use(song, 0)
	assert_true(song.fighters[1].volatiles.has("perish") and song.fighters[0].volatiles.has("perish"))
	_run(song, Abilities.ABILITY_SECONDS)
	assert_true(song.fighters[0].is_knocked_out() and song.fighters[1].is_knocked_out())


func test_non_ghost_curse_is_a_buff() -> void:
	var battle := _battle([["curse"], ["tackle"]])
	_use(battle, 0)
	assert_eq(battle.fighters[0].boosts, {"atk": 1, "def": 1, "spa": 0, "spd": 0, "spe": -1})


func test_magnet_rise_and_type_and_ability_changes() -> void:
	var battle := _battle([["magnetrise", "soak", "gastroacid"], ["earthquake"]], ["plain", "plain"], ["", "intimidate"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	_use(battle, 0)
	assert_eq(Battle.damage_parts(b, a, b.moves[0], _data()).effectiveness, Rules.compressed_effectiveness(0.0))
	assert_false(ArenaConditions.grounded(a))
	_land(battle, 1)
	assert_eq(b.types, ["Water"])
	_land(battle, 2)
	assert_eq(b.ability, "")
	_run(battle, Abilities.ABILITY_SECONDS)
	assert_eq(b.types, ["Normal"], "types come back")
	assert_eq(b.ability, "intimidate", "and the ability")


func test_ais_and_movesets() -> void:
	var battle := _battle([["taunt", "leechseed", "soak", "tackle"], ["tackle", "swordsdance"]], ["plain", "spooky"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_true(StandInAI.move_score(a, b, a.moves[0]) > 0.0, "taunt a foe with a status move")
	assert_true(StandInAI.move_score(a, b, a.moves[1]) > 0.0)
	assert_true(UtilityAI.change_value(battle, a, b, a.moves[2]) > 0.0, "Soak lets Tackle hit the Ghost")
	assert_true(Movesets.utility_value(_data().convert_move("leechseed").move, true) >= Movesets.UTILITY_THRESHOLD)
