extends TestCase
## Field and side conditions (concepts_brief.md §9.11, rules version 35): Tailwind, Trick Room,
## Gravity, Magic Room, Wonder Room, Safeguard, Mist, Haze and Court Change, and how the AIs and
## movesets treat them. Small inline data, so CI needs no asset cache.

const SLOW := {"hp": 80, "atk": 80, "def": 120, "spa": 80, "spd": 60, "spe": 20}
const FAST := {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 130}
const SPECIES := {
	"slow": {"name": "Slow", "types": ["Normal"], "baseStats": SLOW, "abilities": {"0": "Run Away"}, "weightkg": 50},
	"fast": {"name": "Fast", "types": ["Normal"], "baseStats": FAST, "abilities": {"0": "Run Away"}, "weightkg": 50},
	"bird": {"name": "Bird", "types": ["Normal", "Flying"], "baseStats": FAST, "abilities": {"0": "Run Away"}, "weightkg": 50},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"swift": {"name": "Swift", "category": "Special", "type": "Normal", "basePower": 60, "accuracy": 70, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"earthquake": {"name": "Earthquake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"bounce": {"name": "Bounce", "category": "Physical", "type": "Flying", "basePower": 85, "accuracy": 85, "pp": 5, "priority": 0, "flags": {"contact": 1, "charge": 1, "gravity": 1}, "target": "any"},
	"growl": {"name": "Growl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 40, "priority": 0, "flags": {}, "target": "allAdjacentFoes", "boosts": {"atk": -1}},
	"swordsdance": {"name": "Swords Dance", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "self", "boosts": {"atk": 2}},
	"toxic": {"name": "Toxic", "category": "Status", "type": "Poison", "basePower": 0, "accuracy": 90, "pp": 10, "priority": 0, "flags": {}, "target": "normal", "status": "tox"},
	"tailwind": {"name": "Tailwind", "category": "Status", "type": "Flying", "basePower": 0, "accuracy": true, "pp": 15, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "tailwind"},
	"trickroom": {"name": "Trick Room", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 5, "priority": -7, "flags": {}, "target": "all", "pseudoWeather": "trickroom"},
	"gravity": {"name": "Gravity", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "all", "pseudoWeather": "gravity"},
	"magicroom": {"name": "Magic Room", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "pseudoWeather": "magicroom"},
	"wonderroom": {"name": "Wonder Room", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "pseudoWeather": "wonderroom"},
	"safeguard": {"name": "Safeguard", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 25, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "safeguard"},
	"mist": {"name": "Mist", "category": "Status", "type": "Ice", "basePower": 0, "accuracy": true, "pp": 30, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "mist"},
	"haze": {"name": "Haze", "category": "Status", "type": "Ice", "basePower": 0, "accuracy": true, "pp": 30, "priority": 0, "flags": {}, "target": "all"},
	"courtchange": {"name": "Court Change", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "all"},
}
const TYPES := {"normal": {"damageTaken": {}}, "flying": {"damageTaken": {"Ground": 3}}, "ground": {"damageTaken": {}}}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["tailwind"], ["tackle"]], plan_a := {}, species := ["slow", "fast"], extra := [{}, {}]) -> Battle:
	var fighters := []
	for side in 2:
		var entry := {"species": species[side], "moves": moves[side], "ability": "", "item": ""}
		entry.merge(extra[side], true)
		fighters.append(entry)
	var scripted := Scripted.new()
	scripted.plan = plan_a
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [scripted, Scripted.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_field_moves_are_arena_moves() -> void:
	for id in ["tailwind", "trickroom", "gravity", "magicroom", "wonderroom", "safeguard", "mist", "haze", "courtchange"]:
		var move := _move(id)
		assert_eq(move.kind, BattleMove.Kind.ARENA, id)
		assert_eq(move.field_effect, id, id)
	assert_eq(_move("tailwind").cooldown_ticks, Rules.seconds_to_ticks(Rules.ARENA_MOVE_COOLDOWN))
	assert_eq(_move("courtchange").cooldown_ticks, Rules.seconds_to_ticks(Rules.HAZARD_COOLDOWN))
	assert_eq(_move("haze").cooldown_ticks, Rules.seconds_to_ticks(Rules.status_move_cooldown_seconds(30)))


func test_tailwind_doubles_its_sides_walking_speed_for_a_while() -> void:
	var battle := _battle([["tailwind"], ["tackle"]], {0: {"use": 0}})
	var a := battle.fighters[0]
	var walking := a.current_move_speed()
	_run(battle, 20)
	assert_true(battle.conditions.sides[0].has("tailwind"))
	assert_true(battle.conditions.sides[1].is_empty(), "only the user's side")
	assert_almost_eq(a.current_move_speed(), walking * 2.0, 1e-6)
	assert_almost_eq(a.stat("spe"), a.stats.spe * 2.0, 1e-6)
	_run(battle, Rules.seconds_to_ticks(Rules.TAILWIND_SECONDS))
	assert_false(battle.conditions.sides[0].has("tailwind"), "it dies down")
	assert_eq(_events(battle, "side_condition_end").size(), 1)


func test_trick_room_mirrors_speed_and_a_second_use_ends_it() -> void:
	var battle := _battle([["trickroom"], ["tackle"]], {0: {"use": 0}, 600: {"use": 0}})
	var slow := battle.fighters[0]
	var fast := battle.fighters[1]
	assert_true(slow.current_move_speed() < fast.current_move_speed())
	var slow_agility := slow.current_agility()
	_run(battle, 30)
	assert_true(battle.conditions.has_field("trickroom"))
	assert_true(slow.current_move_speed() > fast.current_move_speed(), "the slow one walks faster")
	assert_true(slow.current_agility() > slow_agility, "and turns quicker")
	assert_true(slow.dodge_recharge_needed() < fast.dodge_recharge_needed(), "and recharges dodges sooner")
	assert_almost_eq(Rules.mirrored_speed(Rules.SPEED_STAT_FOR_MAX), Rules.SLOWEST_SPEED_STAT, 1e-6)
	# Its cooldown outlasts the room, so a second use only comes after it ends on its own; ending
	# one early is checked directly.
	battle.conditions.field.trickroom = 100
	battle._field_move(slow, slow.moves[0])
	assert_false(battle.conditions.has_field("trickroom"), "using it again ends it")
	assert_true(slow.current_move_speed() < fast.current_move_speed())


func test_gravity_grounds_fliers() -> void:
	var battle := _battle([["earthquake", "bounce", "swift"], ["tackle"]], {}, ["slow", "bird"])
	var a := battle.fighters[0]
	var bird := battle.fighters[1]
	var quake := _move("earthquake")
	assert_eq(Battle.damage_parts(a, bird, quake, _data()).effectiveness, Rules.compressed_effectiveness(0.0))
	assert_true(a.move_ready(1))
	assert_almost_eq(bird.step_height(), Rules.FLY_CLIMB, 1e-6)
	var slow_shot := battle.conditions.projectile_speed(a, _move("swift"))
	battle.conditions.field.gravity = 100
	assert_eq(Battle.damage_parts(a, bird, quake, _data()).effectiveness, 1.0, "Ground reaches the flier")
	assert_true(ArenaConditions.grounded(bird))
	assert_false(a.move_ready(1), "no Bounce under Gravity")
	assert_almost_eq(bird.step_height(), Rules.CLIMB, 1e-6)
	assert_true(battle.conditions.projectile_speed(a, _move("swift")) > slow_shot, "shots fly true")
	bird.set_ability("levitate")
	bird.types = ["Normal"]
	assert_false(Abilities.immune(bird, quake), "Levitate is grounded too")
	battle.conditions.field.erase("gravity")
	assert_true(Abilities.immune(bird, quake))


func test_magic_room_turns_items_off_until_it_ends() -> void:
	var battle := _battle([["magicroom"], ["tackle"]], {0: {"use": 0}}, ["slow", "fast"], [{}, {"item": "lifeorb"}])
	var orb := battle.fighters[1]
	var tackle := _move("tackle")
	var with_orb: float = Battle.damage_parts(orb, battle.fighters[0], tackle, _data()).factor
	_run(battle, 20)
	assert_true(battle.conditions.has_field("magicroom"))
	assert_true(orb.item_effect.is_empty())
	assert_true(Battle.damage_parts(orb, battle.fighters[0], tackle, _data()).factor < with_orb)
	_run(battle, Rules.seconds_to_ticks(Rules.FIELD_SECONDS))
	assert_false(battle.conditions.has_field("magicroom"))
	assert_false(orb.item_effect.is_empty(), "the item works again")


func test_wonder_room_swaps_the_defences_hit() -> void:
	var battle := _battle([["tackle"], ["tackle"]])
	var slow := battle.fighters[0]
	var tackle := _move("tackle")
	var before: float = Battle.damage_parts(battle.fighters[1], slow, tackle, _data()).base
	battle.conditions.field.wonderroom = 100
	assert_true(Battle.damage_parts(battle.fighters[1], slow, tackle, _data()).base > before, "a physical hit meets the lower Sp. Def")


func test_safeguard_and_mist_shield_the_side() -> void:
	var battle := _battle([["safeguard", "mist"], ["toxic", "growl"]], {0: {"use": 0}, 30: {"use": 1}})
	_run(battle, 60)
	var a := battle.fighters[0]
	assert_true(battle.conditions.safeguarded(a) and battle.conditions.misted(a))
	battle._inflict(a, "tox", battle.fighters[1])
	assert_eq(a.status, "", "Safeguard keeps the poison off")
	battle._boost(a, {"atk": -1}, "growl", battle.fighters[1])
	assert_eq(a.boosts.atk, 0, "Mist keeps the drop off")
	assert_eq(_events(battle, "mist_blocked").size(), 1)
	battle._boost(a, {"atk": 1}, "swordsdance")
	assert_eq(a.boosts.atk, 1, "its own rises still count")
	battle._field_move(a, a.moves[0])
	assert_eq(_events(battle, "failed").size(), 1, "it fails while it's up")


func test_haze_clears_every_stage_and_court_change_swaps_sides() -> void:
	var battle := _battle([["haze", "courtchange"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	b.boosts.atk = 3
	a.boosts.def = -1
	battle._field_move(a, a.moves[0])
	assert_eq(b.boosts.atk, 0)
	assert_eq(a.boosts.def, 0)
	battle.conditions.set_screen(1, "reflect", 100)
	battle.conditions.hazards[0] = {"spikes": 2}
	battle.conditions.sides[1] = {"tailwind": 100}
	battle._field_move(a, a.moves[1])
	assert_true(battle.conditions.screens[0].has("reflect"))
	assert_eq(battle.conditions.hazards[1], {"spikes": 2})
	assert_true(battle.conditions.sides[0].has("tailwind"))


func test_ais_value_field_moves_by_the_difference_they_make() -> void:
	var battle := _battle([["trickroom", "tailwind", "gravity", "earthquake"], ["tackle"]], {}, ["slow", "bird"])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_true(StandInAI.arena_score(a, b, a.moves[0]) > 0.0, "the slower side wants Trick Room")
	assert_eq(StandInAI.arena_score(b, a, _move("trickroom")), 0.0, "the faster one doesn't")
	assert_true(StandInAI.arena_score(a, b, a.moves[1]) > 0.0, "Tailwind helps")
	assert_true(StandInAI.arena_score(a, b, a.moves[2]) > 0.0, "Gravity lets Earthquake reach the flier")
	battle.conditions.field.trickroom = 300
	assert_eq(StandInAI.arena_score(a, b, a.moves[0]), 0.0, "never ends its own helpful room")
	assert_true(StandInAI.arena_score(b, a, _move("trickroom")) > 0.0, "the foe ends it")
	assert_eq(StandInAI.arena_score(a, b, a.moves[1]), 0.0, "Tailwind slows it under Trick Room")
	var haze := _battle([["haze"], ["tackle"]])
	haze.fighters[1].boosts.atk = 2
	assert_true(StandInAI.arena_score(haze.fighters[0], haze.fighters[1], haze.fighters[0].moves[0]) > 0.0, "Haze against a boosted foe")
	assert_eq(StandInAI.arena_score(haze.fighters[1], haze.fighters[0], _move("haze")), 0.0, "not against its own boosts")


func test_standard_movesets_never_pick_field_moves() -> void:
	var learnsets := {"slow": {"learnset": {"tackle": ["9L1"], "tailwind": ["9L1"], "trickroom": ["9L1"], "haze": ["9L1"], "safeguard": ["9L1"]}}}
	var data := BattleData.new(SPECIES, MOVES, TYPES, learnsets)
	var moves: Array = Movesets.generate("slow", data).moves
	assert_eq(moves, ["tackle"])


func test_field_conditions_are_in_the_checksum() -> void:
	var plain := _battle([["tackle"], ["tackle"]])
	var roomed := _battle([["tackle"], ["tackle"]])
	roomed.conditions.field.wonderroom = 5
	_run(plain, 3)
	_run(roomed, 3)
	plain.result = Battle.Result.DRAW
	roomed.result = Battle.Result.DRAW
	assert_true(plain.checksum() != roomed.checksum())
