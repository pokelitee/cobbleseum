extends TestCase
## Doubles' ally moves (concepts_brief.md §9.11, §17 M17): Helping Hand, ally boosts, Dragon Cheer,
## team heals, Follow Me and Rage Powder, and Wide Guard.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"leaf": {"name": "Leaf", "types": ["Grass"], "baseStats": {"hp": 60, "atk": 70, "def": 70, "spa": 70, "spd": 70, "spe": 70}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"slide": {"name": "Slide", "category": "Physical", "type": "Rock", "basePower": 75, "accuracy": 90, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacentFoes"},
	"helpinghand": {"name": "Helping Hand", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 5, "flags": {}, "target": "adjacentAlly", "volatileStatus": "helpinghand"},
	"coaching": {"name": "Coaching", "category": "Status", "type": "Fighting", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "adjacentAlly", "boosts": {"atk": 1, "def": 1}},
	"howl": {"name": "Howl", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 40, "priority": 0, "flags": {"sound": 1}, "target": "allies", "boosts": {"atk": 1}},
	"lifedew": {"name": "Life Dew", "category": "Status", "type": "Water", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {"heal": 1}, "target": "allies", "heal": [1, 4]},
	"followme": {"name": "Follow Me", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 20, "priority": 2, "flags": {}, "target": "self", "volatileStatus": "followme"},
	"ragepowder": {"name": "Rage Powder", "category": "Status", "type": "Bug", "basePower": 0, "accuracy": true, "pp": 20, "priority": 2, "flags": {"powder": 1}, "target": "self", "volatileStatus": "ragepowder"},
	"wideguard": {"name": "Wide Guard", "category": "Status", "type": "Rock", "basePower": 0, "accuracy": true, "pp": 10, "priority": 3, "flags": {}, "target": "allySide", "sideCondition": "wideguard"},
}
const TYPES := {
	"water": {"damageTaken": {"Water": 2, "Rock": 0, "Normal": 0}},
	"grass": {"damageTaken": {"Water": 2, "Rock": 0, "Normal": 0}},
}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _index: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves_a: Array, controllers: Array, doubles := true, species_b := "squirt", ally_moves := ["jet"]) -> Battle:
	var team_a := [{"species": "squirt", "moves": moves_a}, {"species": "squirt", "moves": ally_moves}]
	var team_b := [{"species": species_b, "moves": ["jet", "slide"]}, {"species": "squirt", "moves": ["jet"]}]
	var spec := {"seed": 2, "arena": "stadium", "fighters": [{"team": team_a}, {"team": team_b}]}
	if doubles:
		spec.doubles = true
	var created := Battle.create(spec, _data(), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _scripted(count := 4) -> Array:
	var list := []
	for i in count:
		list.append(Scripted.new())
	return list


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func test_ally_moves_convert_and_stay_out_of_standard_movesets() -> void:
	var data := _data()
	for id in ["helpinghand", "coaching", "howl", "lifedew", "followme", "ragepowder", "wideguard"]:
		var converted := data.convert_move(id)
		assert_false(converted.has("error"), id)
		assert_true((converted.move as BattleMove).is_ally_move(), id)
		assert_true((converted.move as BattleMove).is_self(), id)
	assert_eq(data.convert_move("followme").move.cooldown_ticks, Rules.seconds_to_ticks(Rules.REDIRECT_COOLDOWN))
	assert_eq(data.convert_move("wideguard").move.cooldown_ticks, Rules.seconds_to_ticks(Rules.WIDE_GUARD_COOLDOWN))


func test_helping_hand_boosts_the_allys_next_move() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 1}}
	var battle := _battle(["jet", "helpinghand"], controllers)
	_run(battle, 20)
	var ally := battle.fighters[2]
	battle.fighters[3].position = Vector2(2.5, -1.0)
	assert_true(ally.helping_ticks > 0)
	assert_eq(_events(battle, "support").size(), 1)
	var plain: float = Battle.damage_parts(ally, battle.fighters[3], ally.moves[0], battle.data()).factor
	controllers[2].plan = {battle.tick: {"use": 0}}
	battle.step()
	assert_true(ally.helped)
	assert_eq(ally.helping_ticks, 0, "spent on the wind-up")
	assert_almost_eq(Battle.damage_parts(ally, battle.fighters[3], ally.moves[0], battle.data()).factor,
		plain * Rules.HELPING_HAND_FACTOR, 1e-6)


func test_ally_boosts_reach_the_ally_and_howl_the_user_too() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}, 30: {"use": 1}}
	var battle := _battle(["coaching", "howl"], controllers)
	_run(battle, 60)
	assert_eq(battle.fighters[2].boosts.atk, 2, "Coaching then Howl")
	assert_eq(battle.fighters[2].boosts.def, 1)
	assert_eq(battle.fighters[0].boosts.atk, 1, "Howl raises the user's too")
	assert_eq(battle.fighters[0].boosts.def, 0, "Coaching is only the ally's")


func test_a_team_heal_heals_both() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}}
	var battle := _battle(["lifedew"], controllers)
	for index in [0, 2]:
		battle.fighters[index].hp = battle.fighters[index].max_hp / 2
	_run(battle, Rules.seconds_to_ticks(Rules.HEAL_WINDUP) + 2)
	for index in [0, 2]:
		assert_true(battle.fighters[index].hp > battle.fighters[index].max_hp / 2, "fighter %d healed" % index)


func test_follow_me_draws_every_foes_attacks() -> void:
	var controllers := _scripted()
	controllers[2].plan = {0: {"use": 0}}
	var battle := _battle(["jet"], controllers, true, "squirt", ["followme"])
	_run(battle, 20)
	assert_eq(_events(battle, "redirect").size(), 1)
	assert_eq(battle.target_of(battle.fighters[1]), battle.fighters[2], "the foe across from A's first now goes for the user")
	assert_eq(battle.target_of(battle.fighters[3]), battle.fighters[2])
	_run(battle, Rules.seconds_to_ticks(Rules.REDIRECT_SECONDS))
	assert_eq(battle.target_of(battle.fighters[1]), battle.fighters[0], "back to its own lock")


func test_rage_powder_does_not_draw_grass_types() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}}
	var battle := _battle(["ragepowder"], controllers, true, "leaf")
	_run(battle, 20)
	assert_eq(battle.target_of(battle.fighters[1]), battle.fighters[0], "the Grass type keeps its own lock")
	assert_eq(battle.target_of(battle.fighters[3]), battle.fighters[0], "the Water type is drawn")


func test_wide_guard_blocks_spread_moves_on_the_side() -> void:
	var controllers := _scripted()
	controllers[0].plan = {0: {"use": 0}}
	controllers[1].plan = {2: {"use": 1}}
	var battle := _battle(["wideguard"], controllers)
	battle.fighters[1].position = Vector2(-2.5, -3.0)
	_run(battle, 30)
	assert_true(_events(battle, "wide_guarded").size() >= 1)
	assert_eq(_events(battle, "hit").filter(func(e: Dictionary) -> bool: return e.target_side == 0).size(), 0)


func test_ally_moves_fail_in_singles() -> void:
	var controllers := _scripted(2)
	controllers[0].plan = {0: {"use": 1}}
	var battle := _battle(["jet", "helpinghand"], controllers, false)
	_run(battle, 20)
	assert_eq(_events(battle, "failed").size(), 1)
