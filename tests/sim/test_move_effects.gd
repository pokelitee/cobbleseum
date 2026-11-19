extends TestCase
## Moves whose type, power or timing follows the weather and surge (concepts_brief.md §9.3, M18,
## rules version 36): Weather Ball, Terrain Pulse, Rising Voltage, Expanding Force, Psyblade,
## Misty Explosion, Solar Beam, Grassy Glide, Electro Shot, Hydro Steam, Steel Roller and Ice
## Spinner. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"bird": {"name": "Bird", "types": ["Flying"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"rainy": {"name": "Rainy", "types": ["Water"], "baseStats": STATS, "abilities": {"0": "Drizzle"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"weatherball": {"name": "Weather Ball", "category": "Special", "type": "Normal", "basePower": 50, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"bullet": 1}, "target": "normal"},
	"terrainpulse": {"name": "Terrain Pulse", "category": "Special", "type": "Normal", "basePower": 50, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"pulse": 1}, "target": "normal"},
	"risingvoltage": {"name": "Rising Voltage", "category": "Special", "type": "Electric", "basePower": 70, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"expandingforce": {"name": "Expanding Force", "category": "Special", "type": "Psychic", "basePower": 80, "accuracy": 100, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"solarbeam": {"name": "Solar Beam", "category": "Special", "type": "Grass", "basePower": 120, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"charge": 1}, "target": "normal"},
	"grassyglide": {"name": "Grassy Glide", "category": "Physical", "type": "Grass", "basePower": 55, "accuracy": 100, "pp": 20, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"electroshot": {"name": "Electro Shot", "category": "Special", "type": "Electric", "basePower": 130, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"charge": 1}, "target": "normal"},
	"hydrosteam": {"name": "Hydro Steam", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"steelroller": {"name": "Steel Roller", "category": "Physical", "type": "Steel", "basePower": 130, "accuracy": 100, "pp": 5, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"icespinner": {"name": "Ice Spinner", "category": "Physical", "type": "Ice", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"raindance": {"name": "Rain Dance", "category": "Status", "type": "Water", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "all", "weather": "RainDance"},
}
const TYPES := {"normal": {"damageTaken": {}}, "flying": {"damageTaken": {}}, "water": {"damageTaken": {}}}


class Idle extends RefCounted:
	func decide(_battle: Battle, _index: int) -> Dictionary:
		return {}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES, {"rainy": {"learnset": {"weatherball": ["9L1"], "tackle": ["9L1"]}}})


func _battle(moves := [["weatherball"], ["tackle"]], species := ["plain", "plain"]) -> Battle:
	var fighters := []
	for side in 2:
		fighters.append({"species": species[side], "moves": moves[side], "ability": "", "item": ""})
	var created := Battle.create({"seed": 1, "arena": "stadium", "fighters": fighters}, _data(), [Idle.new(), Idle.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func _adapted(battle: Battle, id: String) -> BattleMove:
	return MoveEffects.adapt(battle.fighters[0], battle.fighters[1], _move(id))


func test_weather_ball_takes_the_weathers_type_at_double_power() -> void:
	var battle := _battle()
	var ball_move := battle.fighters[0].moves[0]
	assert_true(is_same(MoveEffects.adapt(battle.fighters[0], battle.fighters[1], ball_move), ball_move), "plain without weather")
	for weather: String in MoveEffects.WEATHER_TYPES:
		battle.conditions.set_weather(weather, 100)
		var ball := _adapted(battle, "weatherball")
		assert_eq(ball.type, MoveEffects.WEATHER_TYPES[weather], weather)
		assert_eq(ball.power, 100)
		assert_eq(ball.id, "weatherball")
	assert_true(MoveEffects.adapt(battle.fighters[0], battle.fighters[1], _adapted(battle, "weatherball")).power == 100,
		"a variant isn't adapted twice")


func test_terrain_pulse_and_surge_powered_moves() -> void:
	var battle := _battle([["terrainpulse"], ["tackle"]], ["plain", "bird"])
	battle.conditions.set_surge("electric", 100)
	var pulse := _adapted(battle, "terrainpulse")
	assert_eq(pulse.type, "Electric")
	assert_eq(pulse.power, 100)
	assert_eq(_adapted(battle, "risingvoltage").power, 70, "the flier isn't on the ground")
	battle.fighters[1].types = ["Normal"]
	assert_eq(_adapted(battle, "risingvoltage").power, 140)
	battle.conditions.set_surge("psychic", 100)
	assert_eq(_adapted(battle, "expandingforce").power, 120)
	battle.fighters[0].types = ["Flying"]
	assert_eq(_adapted(battle, "expandingforce").power, 80, "an airborne user gets no boost")
	assert_eq(_adapted(battle, "terrainpulse").type, "Normal")


func test_solar_beam_dims_in_other_weather_and_charges_skip() -> void:
	var battle := _battle([["solarbeam", "electroshot", "grassyglide"], ["tackle"]])
	var a := battle.fighters[0]
	battle.conditions.set_weather("rain", 100)
	assert_eq(_adapted(battle, "solarbeam").power, 60)
	assert_eq(a.windup_ticks(a.moves[1]), a.moves[1].windup_ticks - Rules.seconds_to_ticks(Rules.CHARGE_EXTRA), "Electro Shot in rain")
	assert_eq(a.windup_ticks(a.moves[2]), a.moves[2].windup_ticks)
	battle.conditions.set_surge("grassy", 100)
	assert_true(a.windup_ticks(a.moves[2]) < a.moves[2].windup_ticks, "Grassy Glide on grass")


func test_hydro_steam_is_powered_up_in_sun() -> void:
	var battle := _battle([["hydrosteam"], ["tackle"]])
	var steam := _move("hydrosteam")
	battle.conditions.set_weather("sun", 100)
	assert_almost_eq(battle.conditions.damage_factor(battle.fighters[0], battle.fighters[1], steam), ArenaConditions.BOOST, 1e-6)


func test_steel_roller_needs_a_surge_and_ends_it() -> void:
	var battle := _battle([["steelroller", "icespinner"], ["tackle"]])
	var a := battle.fighters[0]
	assert_false(a.move_ready(0))
	battle.conditions.set_surge("misty", 100)
	assert_true(a.move_ready(0))
	battle._hit(a, battle.fighters[1], a.moves[1])
	assert_eq(battle.conditions.surge, "", "Ice Spinner ends it")
	assert_eq(battle.events.filter(func(e: Dictionary) -> bool: return e.type == "surge_end").size(), 1)


func test_hits_and_estimates_use_the_adapted_move() -> void:
	var battle := _battle()
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var plain: float = Battle.damage_parts(a, b, a.moves[0], _data()).base
	battle.conditions.set_weather("sun", 100)
	assert_true(Battle.damage_parts(a, b, a.moves[0], _data()).base > plain, "double power")
	battle._hit(a, b, a.moves[0])
	var hit: Dictionary = battle.events.filter(func(e: Dictionary) -> bool: return e.type == "hit")[0]
	assert_eq(hit.move_type, "Fire", "the event names the type it played as")
	assert_true(StandInAI.move_score(a, b, a.moves[0]) > StandInAI.move_score(a, b, _move("tackle")))


func test_weather_values_and_movesets_count_weather_ball() -> void:
	var rainy := _battle([["weatherball", "raindance"], ["tackle"]], ["rainy", "plain"])
	var ball_only: Array[BattleMove] = [_move("weatherball")]
	assert_true(ArenaConditions.weather_gain(["Water"], {}, {}, ball_only, "rain", 20.0) > ArenaConditions.weather_gain(["Water"], {}, {}, [_move("tackle")], "rain", 20.0))
	assert_true(StandInAI.arena_score(rainy.fighters[0], rainy.fighters[1], rainy.fighters[0].moves[1]) > 0.0)
	var moves: Array = Movesets.generate("rainy", _data()).moves
	assert_eq(moves[0], "weatherball", "a rain setter takes Weather Ball as a Water attack")


func test_movesets_skip_steel_roller_without_a_surge_of_their_own() -> void:
	var data := BattleData.new(SPECIES, MOVES, TYPES, {"plain": {"learnset": {"steelroller": ["9L1"], "tackle": ["9L1"]}}})
	assert_eq(Movesets.generate("plain", data).moves, ["tackle"])
