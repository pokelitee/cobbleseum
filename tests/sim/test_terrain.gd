extends TestCase
## Battle terrain (concepts_brief.md §9.8): generation, climbing, blocked shots and the
## height limits on melee and area moves.

const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
	"birdy": {"name": "Birdy", "types": ["Normal", "Flying"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"kick": {"name": "Kick", "category": "Physical", "type": "Fighting", "basePower": 60, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
}


class Scripted extends RefCounted:
	var intents: Array

	func _init(steps: Array) -> void:
		intents = steps

	func decide(battle: Battle, _side: int) -> Dictionary:
		return intents[battle.tick] if battle.tick < intents.size() else {}


func _battle(script_a: Array, species_a := "squirt") -> Battle:
	var spec := {"seed": 1, "arena": "stadium", "fighters": [{"species": species_a, "moves": ["jet", "kick"]}, {"species": "squirt", "moves": ["jet"]}]}
	var created := Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), [Scripted.new(script_a), Scripted.new([])])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.battle


## A block of `height` over the cells from `from` to `to` (inclusive, cell coordinates).
func _raise(terrain: Terrain, from: Vector2i, to: Vector2i, height: float) -> void:
	for i in range(from.x, to.x + 1):
		for j in range(from.y, to.y + 1):
			terrain._put(Vector2(i + 0.5, j + 0.5), height)
	terrain._summarise()


func test_generation_is_repeatable_and_keeps_the_starts_clear() -> void:
	for field: String in Terrain.FIELDS:
		var first := Terrain.generate(field, SimRandom.new(5))
		var second := Terrain.generate(field, SimRandom.new(5))
		assert_eq(first._heights, second._heights, field)
		for start in Terrain.starts():
			var level := first.height_at(start)
			for cell in first.cells():
				if cell.distance_to(start) < Terrain.START_CLEAR:
					assert_eq(first.height_at(cell), level, "%s start level at %s" % [field, cell])
					assert_eq(first.kind_at(cell), Terrain.Kind.GROUND, "%s start open at %s" % [field, cell])
		assert_true(first.starts_connected(), "%s: the starts can walk to each other" % field)
		for cell in first.cells():
			assert_eq(fmod(first.height_at(cell), Terrain.STEP), 0.0, "heights come in steps")
	assert_eq(Terrain.generate("paved", SimRandom.new(5)).highest(), 0.0, "paving is flat")
	assert_true(Terrain.generate("cave", SimRandom.new(5)).highest() >= 3.0, "caves have tall pillars")


func test_the_battle_takes_its_field_from_the_arena() -> void:
	assert_eq(_battle([]).arena, "stadium")
	assert_eq(_battle([]).terrain.field, "paved")
	var spec := {"seed": 2, "arena": "garden_coliseum", "fighters": [{"species": "squirt", "moves": ["jet"]}, {"species": "squirt", "moves": ["jet"]}]}
	var battle: Battle = Battle.create(spec, BattleData.new(SPECIES, MOVES, {}), [Scripted.new([]), Scripted.new([])]).battle
	assert_eq(battle.terrain.field, "grassland")
	assert_true(battle.terrain.enclosed)


func test_fighters_climb_small_steps_but_not_walls() -> void:
	var battle := _battle(_walk(Vector2(1, 0), 90))
	var fighter := battle.fighters[0]
	fighter.position = Vector2(-3, -5)
	# A half-metre step at x 0, then a wall at x 3.
	_raise(battle.terrain, Vector2i(0, -8), Vector2i(2, -2), Rules.CLIMB)
	_raise(battle.terrain, Vector2i(3, -8), Vector2i(4, -2), 3.0)
	for i in 90:
		battle.step()
	assert_eq(fighter.ground, Rules.CLIMB, "up the step")
	assert_true(fighter.position.x < 3.0 - fighter.radius + 1e-3, "stopped by the wall: %s" % fighter.position)


func test_fliers_climb_higher() -> void:
	var battle := _battle(_walk(Vector2(1, 0), 90), "birdy")
	var fighter := battle.fighters[0]
	fighter.position = Vector2(-3, -5)
	_raise(battle.terrain, Vector2i(0, -8), Vector2i(2, -2), Rules.FLY_CLIMB)
	var highest := 0.0
	for i in 90:
		battle.step()
		highest = maxf(highest, fighter.ground)
	assert_eq(highest, Rules.FLY_CLIMB, "up onto ground a walker couldn't reach")


func test_a_pillar_blocks_a_projectile() -> void:
	var battle := _battle([{"use": 0}])
	battle.fighters[0].position = Vector2(0, -4)
	battle.fighters[1].position = Vector2(0, 4)
	_raise(battle.terrain, Vector2i(-1, -1), Vector2i(0, 0), 2.5)
	assert_false(battle.can_see(battle.fighters[0], battle.fighters[1]))
	for i in 60:
		battle.step()
	assert_eq(battle.events.filter(func(e: Dictionary) -> bool: return e.type == "blocked").size(), 1)
	assert_eq(battle.fighters[1].hp, battle.fighters[1].max_hp)


func test_melee_needs_a_small_height_difference() -> void:
	var battle := _battle([])
	var attacker := battle.fighters[0]
	var defender := battle.fighters[1]
	attacker.position = Vector2(0, 0)
	defender.position = Vector2(0, attacker.radius + defender.radius + 0.5)
	var kick: BattleMove = attacker.moves[1]
	defender.ground = Rules.MELEE_HEIGHT + 0.5
	assert_false(battle.can_reach(attacker, defender, kick))
	battle._strike(attacker, defender, 1)
	assert_eq(defender.hp, defender.max_hp, "too high to kick")
	defender.ground = Rules.MELEE_HEIGHT
	assert_true(battle.can_reach(attacker, defender, kick))


func test_steering_goes_around_a_pillar() -> void:
	var terrain := Terrain.flat("cave")
	_raise(terrain, Vector2i(1, -1), Vector2i(1, 0), 3.0)
	var direction := terrain.steer(Vector2(0.5, 0.0), 0.4, 0.0, Rules.CLIMB, Vector2(1, 0))
	assert_true(direction.normalized().dot(Vector2(1, 0)) < 0.99, "turned aside: %s" % direction)
	assert_eq(terrain.steer(Vector2(0.5, 0.0), 0.4, 0.0, Rules.CLIMB, Vector2(-1, 0)), Vector2(-1, 0), "open ground is left alone")


func _walk(direction: Vector2, ticks: int) -> Array:
	var steps := []
	for i in ticks:
		steps.append({"move": direction})
	return steps


func test_the_ai_finds_cover_and_a_clear_shot() -> void:
	var battle := _battle([])
	var me := battle.fighters[0]
	me.position = Vector2(0, -2)
	battle.fighters[1].position = Vector2(0, 4)
	var foe_eye := Vector3(0, Rules.CHEST_HEIGHT, 4)
	# A wall of pillars two cells to the right of the line between them.
	_raise(battle.terrain, Vector2i(1, 0), Vector2i(2, 1), 3.0)
	var hidden := UtilityAI.find_spot(battle, me, foe_eye, false)
	assert_true(hidden != Vector2.INF, "somewhere to hide")
	var chest := Vector3(hidden.x, Rules.CHEST_HEIGHT, hidden.y)
	assert_false(battle.terrain.clear_line(foe_eye, chest), "out of sight: %s" % hidden)
	me.position = Vector2(1.5, -2)
	var clear := UtilityAI.find_spot(battle, me, foe_eye, true)
	assert_true(battle.terrain.clear_line(foe_eye, Vector3(clear.x, Rules.CHEST_HEIGHT, clear.y)), "in sight: %s" % clear)

