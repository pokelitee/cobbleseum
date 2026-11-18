extends TestCase
## The utility AI in doubles (concepts_brief.md §11, §17 M17): target choice with focus fire,
## spread moves weighed against harm to the ally, and keeping apart from the ally.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"stone": {"name": "Stone", "types": ["Rock"], "baseStats": {"hp": 80, "atk": 120, "def": 100, "spa": 50, "spd": 100, "spe": 60}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"quake": {"name": "Quake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"slide": {"name": "Slide", "category": "Physical", "type": "Rock", "basePower": 75, "accuracy": 90, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacentFoes"},
}
const TYPES := {
	"water": {"damageTaken": {"Water": 2, "Fire": 2, "Ground": 0, "Rock": 0}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2, "Ground": 1, "Rock": 1}},
	"rock": {"damageTaken": {"Water": 1, "Fire": 2, "Ground": 1, "Rock": 0}},
}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _battle(team_a: Array, team_b: Array, controllers: Array) -> Battle:
	var spec := {"seed": 3, "doubles": true, "arena": "stadium", "fighters": [{"team": team_a}, {"team": team_b}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, TYPES), controllers)
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


func _ai() -> UtilityAI:
	return UtilityAI.new(Controllers.load_profile("ranked"), SimRandom.new(1))


func _member(species: String, moves: Array) -> Dictionary:
	return {"species": species, "moves": moves}


func test_it_targets_the_foe_it_can_finish() -> void:
	var battle := _battle([_member("squirt", ["jet"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("blaze", ["jet"])], [Idle.new(), Idle.new(), Idle.new(), Idle.new()])
	var me := battle.fighters[0]
	assert_eq(me.target_place, 0)
	# Jet is super effective on the fire foe across, in place 1.
	assert_eq(UtilityAI.choose_target(battle, me), 1)
	battle.fighters[1].hp = 5
	assert_eq(UtilityAI.choose_target(battle, me), 0, "a foe it can finish wins")


func test_it_joins_its_allys_target() -> void:
	var battle := _battle([_member("squirt", ["jet"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], [Idle.new(), Idle.new(), Idle.new(), Idle.new()])
	var me := battle.fighters[0]
	var ally := battle.fighters[2]
	me.target_place = 1
	ally.target_place = 1
	me.position = Vector2(0, 0)
	battle.fighters[1].position = Vector2(-1, 3)
	battle.fighters[3].position = Vector2(1, 3.5)
	assert_eq(UtilityAI.choose_target(battle, me), 1, "focus and its lock outweigh half a metre")
	ally.target_place = 0
	me.target_place = 0
	assert_eq(UtilityAI.choose_target(battle, me), 0)


func test_a_spread_move_that_would_hurt_the_ally_more_is_worth_nothing() -> void:
	var battle := _battle([_member("stone", ["quake", "slide"]), _member("blaze", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], [Idle.new(), Idle.new(), Idle.new(), Idle.new()])
	var me := battle.fighters[0]
	me.position = Vector2(0, 0)
	battle.fighters[1].position = Vector2(0, 1.5)
	battle.fighters[3].position = Vector2(8, 8)
	battle.fighters[2].position = Vector2(-1.5, 0)
	# Quake barely scratches the water foe and hits the fire ally hard.
	var quake := UtilityAI.spread_value(battle, me, me.moves[0])
	assert_eq(quake.foes, 1)
	assert_true(quake.share < 0.0, "net harm: %f" % quake.share)
	# Slide spares the ally.
	assert_true(UtilityAI.spread_value(battle, me, me.moves[1]).share > 0.0)
	battle.fighters[2].position = Vector2(-8, -8)
	assert_true(UtilityAI.spread_value(battle, me, me.moves[0]).share > 0.0, "with the ally away it's worth using")


func test_the_ai_retargets_with_a_target_intent() -> void:
	var ai := _ai()
	var battle := _battle([_member("squirt", ["jet"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("blaze", ["jet"])], [ai, Idle.new(), Idle.new(), Idle.new()])
	battle.step()
	assert_eq(battle.fighters[0].target_place, 1)


func test_it_keeps_apart_from_its_ally() -> void:
	var ai := _ai()
	var battle := _battle([_member("squirt", ["jet"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("squirt", ["jet"])], [ai, Idle.new(), Idle.new(), Idle.new()])
	var me := battle.fighters[0]
	me.position = Vector2(0, -3)
	battle.fighters[2].position = Vector2(1.2, -3)
	var pushes := 0
	for i in 30:
		var intent := ai.decide(battle, 0)
		if intent.has("move") and (intent.move as Vector2).x < 0.0:
			pushes += 1
		battle.tick += 1
	assert_true(pushes > 15, "it edges away from the ally on its right: %d" % pushes)


func test_uncoordinated_it_plays_as_if_each_foe_were_alone() -> void:
	var ai := _ai()
	ai.coordinate = false
	var battle := _battle([_member("squirt", ["jet"]), _member("squirt", ["jet"])],
		[_member("squirt", ["jet"]), _member("blaze", ["jet"])], [ai, Idle.new(), Idle.new(), Idle.new()])
	battle.step()
	assert_eq(battle.fighters[0].target_place, 0)
