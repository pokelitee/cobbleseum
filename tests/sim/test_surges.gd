extends TestCase
## Surges (concepts_brief.md §9.11): the moves Showdown calls terrains, what each does to grounded
## fighters, the abilities and item that work with them, and how movesets and the AIs value them.
## Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}
const FAST := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 120}
const SPECIES := {
	"sparky": {"name": "Sparky", "types": ["Electric"], "baseStats": STATS, "abilities": {"0": "Electric Surge"}},
	"leafy": {"name": "Leafy", "types": ["Grass"], "baseStats": FAST, "abilities": {"0": "Grassy Surge"}},
	"birdy": {"name": "Birdy", "types": ["Flying"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"drake": {"name": "Drake", "types": ["Dragon"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"zap": {"name": "Zap", "category": "Special", "type": "Electric", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"leaf": {"name": "Leaf", "category": "Special", "type": "Grass", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"dragonpulse": {"name": "Dragon Pulse", "category": "Special", "type": "Dragon", "basePower": 85, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"earthquake": {"name": "Earthquake", "category": "Physical", "type": "Ground", "basePower": 100, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "allAdjacent"},
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"quickattack": {"name": "Quick Attack", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 30, "priority": 1, "flags": {"contact": 1}, "target": "normal"},
	"electricterrain": {"name": "Electric Terrain", "category": "Status", "type": "Electric", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "terrain": "electricterrain"},
	"grassyterrain": {"name": "Grassy Terrain", "category": "Status", "type": "Grass", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "terrain": "grassyterrain"},
	"mistyterrain": {"name": "Misty Terrain", "category": "Status", "type": "Fairy", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "terrain": "mistyterrain"},
	"psychicterrain": {"name": "Psychic Terrain", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "terrain": "psychicterrain"},
	"sleep": {"name": "Sleep", "category": "Status", "type": "Grass", "basePower": 0, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal", "status": "slp"},
}
const TYPES := {
	"electric": {"damageTaken": {}},
	"grass": {"damageTaken": {}},
	"flying": {"damageTaken": {}},
	"normal": {"damageTaken": {}},
	"dragon": {"damageTaken": {}},
}


## Plays one intent on its tick and nothing otherwise.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(species := ["sparky", "plain"], moves := [["zap"], ["tackle"]], plan_a := {}, extra := [{}, {}]) -> Battle:
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


func _factor(battle: Battle, attacker: int, move_id: String) -> float:
	return Battle.damage_parts(battle.fighters[attacker], battle.fighters[1 - attacker], _move(move_id), _data()).factor


func test_surge_moves_are_arena_moves() -> void:
	for case: Array in [["electricterrain", "electric"], ["grassyterrain", "grassy"], ["mistyterrain", "misty"], ["psychicterrain", "psychic"]]:
		var move := _move(case[0])
		assert_eq(move.kind, BattleMove.Kind.ARENA, case[0])
		assert_eq(move.surge, case[1], case[0])
		assert_eq(move.weather, "")


func test_a_surge_move_sets_the_surge_for_its_time_beside_the_weather() -> void:
	var battle := _battle(["sparky", "plain"], [["electricterrain"], ["tackle"]], {0: {"use": 0}})
	battle.conditions.set_weather("rain", -1)
	_run(battle, 30)
	assert_eq(battle.conditions.surge, "electric")
	assert_eq(battle.conditions.weather, "rain", "a surge and a weather are up together")
	var started: Array = battle.events.filter(func(e: Dictionary) -> bool: return e.type == "surge")
	assert_almost_eq(float(started[0].seconds), Rules.WEATHER_SECONDS, 1e-6)
	_run(battle, Rules.seconds_to_ticks(Rules.WEATHER_SECONDS))
	assert_eq(battle.conditions.surge, "")
	assert_eq(battle.events.filter(func(e: Dictionary) -> bool: return e.type == "surge_end").size(), 1)
	var extended := _battle(["sparky", "plain"], [["electricterrain"], ["tackle"]], {0: {"use": 0}}, [{"item": "terrainextender"}, {}])
	_run(extended, 30)
	assert_true(extended.conditions.surge_ticks > Rules.seconds_to_ticks(Rules.WEATHER_SECONDS), "a Terrain Extender lengthens it")


func test_surges_power_grounded_attackers_only() -> void:
	var battle := _battle(["sparky", "birdy"], [["zap"], ["zap"]])
	var grounded := _factor(battle, 0, "zap")
	var flying := _factor(battle, 1, "zap")
	battle.conditions.set_surge("electric", 100)
	assert_almost_eq(_factor(battle, 0, "zap") / grounded, ArenaConditions.SURGE_BOOST, 1e-6)
	assert_almost_eq(_factor(battle, 1, "zap") / flying, 1.0, 1e-6, "a Flying type isn't grounded")
	battle.fighters[0].set_ability("levitate")
	assert_almost_eq(_factor(battle, 0, "zap") / grounded, 1.0, 1e-6, "nor is Levitate")


func test_grassy_and_misty_ground_soften_hits_on_grounded_fighters() -> void:
	var battle := _battle(["plain", "drake"], [["tackle"], ["earthquake", "dragonpulse"]])
	var quake := _factor(battle, 1, "earthquake")
	var pulse := _factor(battle, 1, "dragonpulse")
	battle.conditions.set_surge("grassy", 100)
	assert_almost_eq(_factor(battle, 1, "earthquake") / quake, ArenaConditions.SOFTENED, 1e-6)
	battle.conditions.set_surge("misty", 100)
	assert_almost_eq(_factor(battle, 1, "dragonpulse") / pulse, ArenaConditions.SOFTENED, 1e-6)


func test_grassy_ground_heals_grounded_fighters() -> void:
	var battle := _battle(["plain", "birdy"], [["tackle"], ["tackle"]])
	battle.conditions.set_surge("grassy", 300)
	for fighter in battle.fighters:
		fighter.hp = fighter.max_hp / 2
	_run(battle, Rules.TICK_RATE * 3)
	assert_eq(battle.fighters[0].hp, battle.fighters[0].max_hp / 2 + 3 * roundi(battle.fighters[0].max_hp * ArenaConditions.GRASSY_HEAL))
	assert_eq(battle.fighters[1].hp, battle.fighters[1].max_hp / 2, "the flier isn't on the grass")


func test_electric_and_misty_ground_block_statuses() -> void:
	var battle := _battle(["plain", "birdy"], [["sleep"], ["tackle"]])
	var plain := battle.fighters[0]
	battle.conditions.set_surge("electric", 100)
	battle._inflict(plain, "slp")
	assert_eq(plain.status, "", "no sleep on electric ground")
	battle._inflict(plain, "par")
	assert_eq(plain.status, "par")
	battle._end_status(plain)
	battle.conditions.set_surge("misty", 100)
	battle._inflict(plain, "brn")
	assert_eq(plain.status, "", "no status on misty ground")
	battle._apply_effect(battle.fighters[1], plain, {"confuses": true}, "test")
	assert_eq(plain.confusion_ticks, 0, "nor confusion")
	battle._inflict(battle.fighters[1], "brn")
	assert_eq(battle.fighters[1].status, "brn", "a flier isn't protected")
	assert_eq(StandInAI.move_score(battle.fighters[1], plain, _move("sleep")), 0.0, "the AI doesn't throw a status it blocks")


func test_psychic_ground_slows_priority_moves_at_grounded_foes() -> void:
	var battle := _battle(["plain", "plain"], [["quickattack"], ["tackle"]], {0: {"use": 0}})
	battle.conditions.set_surge("psychic", 100)
	var quick := _move("quickattack")
	battle.fighters[0].position = Vector2(0, -1.0)
	battle.fighters[1].position = Vector2(0, 1.0)
	battle.step()
	assert_eq(battle.fighters[0].action_ticks, roundi(quick.windup_ticks / Rules.PRIORITY_WINDUP_FACTOR))


func test_setting_abilities_and_surge_abilities() -> void:
	var battle := _battle(["sparky", "leafy"], [["zap"], ["leaf"]], {}, [{"ability": "electricsurge"}, {"ability": "grassysurge"}])
	_run(battle, 1)
	assert_eq(battle.conditions.surge, "electric", "the slower setter's surge wins")
	var surfer := _battle(["sparky", "plain"], [["zap"], ["tackle"]], {}, [{"ability": "surgesurfer"}, {"ability": "grasspelt"}])
	var walk := surfer.fighters[0].current_move_speed()
	var def := surfer.fighters[1].stat("def")
	surfer.conditions.set_surge("electric", 100)
	assert_almost_eq(surfer.fighters[0].current_move_speed(), walk * 2.0, 1e-6, "Surge Surfer")
	surfer.conditions.set_surge("grassy", 100)
	assert_almost_eq(surfer.fighters[1].stat("def"), def * 1.5, 1e-6, "Grass Pelt")


func test_setters_hold_a_terrain_extender() -> void:
	var data := _data()
	assert_eq(Items.standard(SPECIES.sparky, [_move("zap")], data, "electricsurge"), "terrainextender")
	assert_eq(Items.standard(SPECIES.plain, [_move("tackle"), _move("mistyterrain")], data), "terrainextender")


func test_movesets_and_ais_value_a_surge_that_suits_them() -> void:
	var zaps: Array[BattleMove] = [_move("zap"), _move("zap"), _move("tackle")]
	assert_true(Movesets.arena_value(_move("electricterrain"), ["Electric"], "", zaps) > 0.0)
	assert_true(Movesets.arena_value(_move("electricterrain"), ["Flying"], "", zaps) <= 0.0, "a flier gains nothing from it")
	var battle := _battle(["sparky", "birdy"], [["zap", "electricterrain"], ["zap"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_true(StandInAI.arena_score(a, b, a.moves[1]) > 0.0, "grounded Electric against a flier")
	battle.conditions.set_surge("electric", Rules.seconds_to_ticks(Rules.WEATHER_SECONDS))
	assert_eq(StandInAI.arena_score(a, b, a.moves[1]), 0.0, "not renewed with plenty of time left")
	var foe := _battle(["birdy", "sparky"], [["zap", "electricterrain"], ["zap"]])
	assert_eq(StandInAI.arena_score(foe.fighters[0], foe.fighters[1], foe.fighters[0].moves[1]), 0.0, "it would only help the grounded foe")
