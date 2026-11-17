extends TestCase
## Weather (concepts_brief.md §9.11): weather moves, their effects on damage, stats and HP, the
## abilities and items that work with them, starting weather, and how movesets and the AIs value
## them. Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}
const FAST := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 120}
const SPECIES := {
	"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": STATS, "abilities": {"0": "Swift Swim"}},
	"blaze": {"name": "Blaze", "types": ["Fire"], "baseStats": FAST, "abilities": {"0": "Drought"}},
	"rocky": {"name": "Rocky", "types": ["Rock"], "baseStats": STATS, "abilities": {"0": "Sand Stream"}},
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"frosty": {"name": "Frosty", "types": ["Ice"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
}
const MOVES := {
	"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"rockthrow": {"name": "Rock Throw", "category": "Physical", "type": "Rock", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"},
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"thunder": {"name": "Thunder", "category": "Special", "type": "Electric", "basePower": 110, "accuracy": 70, "pp": 10, "priority": 0, "flags": {}, "target": "normal"},
	"solarbeam": {"name": "Solar Beam", "category": "Special", "type": "Grass", "basePower": 120, "accuracy": 100, "pp": 10, "priority": 0, "flags": {"charge": 1}, "target": "normal"},
	"morningsun": {"name": "Morning Sun", "category": "Status", "type": "Normal", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "self", "heal": [1, 2]},
	"raindance": {"name": "Rain Dance", "category": "Status", "type": "Water", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "all", "weather": "RainDance"},
	"sunnyday": {"name": "Sunny Day", "category": "Status", "type": "Fire", "basePower": 0, "accuracy": true, "pp": 5, "priority": 0, "flags": {}, "target": "all", "weather": "sunnyday"},
	"sandstorm": {"name": "Sandstorm", "category": "Status", "type": "Rock", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "weather": "Sandstorm"},
	"chillyreception": {"name": "Chilly Reception", "category": "Status", "type": "Ice", "basePower": 0, "accuracy": true, "pp": 10, "priority": 0, "flags": {}, "target": "all", "weather": "snowscape", "selfSwitch": true},
	"freeze": {"name": "Freeze", "category": "Status", "type": "Ice", "basePower": 0, "accuracy": 100, "pp": 20, "priority": 0, "flags": {}, "target": "normal", "status": "frz"},
}
const TYPES := {
	"fire": {"damageTaken": {}},
	"water": {"damageTaken": {}},
	"normal": {"damageTaken": {}},
	"rock": {"damageTaken": {}},
	"ice": {"damageTaken": {}},
	"electric": {"damageTaken": {}},
	"grass": {"damageTaken": {}},
}


## Plays one intent on its tick and nothing otherwise.
class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


## A battle between `species` with `moves`, no abilities or items unless given, side A following
## `plan_a`.
func _battle(species := ["squirt", "blaze"], moves := [["jet"], ["ember"]], plan_a := {}, extra := [{}, {}], spec_extra := {}) -> Battle:
	var fighters := []
	for side in 2:
		var entry := {"species": species[side], "moves": moves[side], "ability": "", "item": ""}
		entry.merge(extra[side], true)
		fighters.append(entry)
	var spec := {"seed": 1, "arena": "stadium", "fighters": fighters}
	spec.merge(spec_extra, true)
	var scripted := Scripted.new()
	scripted.plan = plan_a
	var created := Battle.create(spec, _data(), [scripted, Scripted.new()])
	assert_false(created.has("error"), str(created.get("error", "")))
	return created.get("battle")


func _run(battle: Battle, ticks: int) -> void:
	for i in ticks:
		battle.step()


func _events(battle: Battle, type: String) -> Array:
	return battle.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _move(id: String) -> BattleMove:
	return _data().convert_move(id).move


func test_weather_moves_are_arena_moves() -> void:
	for case: Array in [["raindance", "rain"], ["sunnyday", "sun"], ["sandstorm", "sand"], ["chillyreception", "snow"]]:
		var move := _move(case[0])
		assert_eq(move.kind, BattleMove.Kind.ARENA, case[0])
		assert_eq(move.weather, case[1], case[0])
		assert_true(move.is_self(), "applied on release without reaching the foe")
		assert_false(move.can_feint())
		assert_eq(move.cooldown_ticks, Rules.seconds_to_ticks(Rules.ARENA_MOVE_COOLDOWN), "longer than the weather lasts")


func test_a_weather_move_sets_the_weather_for_its_time() -> void:
	var battle := _battle(["squirt", "plain"], [["raindance"], ["tackle"]], {0: {"use": 0}})
	_run(battle, 30)
	assert_eq(battle.conditions.weather, "rain")
	var started: Dictionary = _events(battle, "weather")[0]
	assert_eq(started.weather, "rain")
	assert_eq(started.move, "raindance")
	assert_almost_eq(float(started.seconds), Rules.WEATHER_SECONDS, 1e-6)
	_run(battle, Rules.seconds_to_ticks(Rules.WEATHER_SECONDS))
	assert_eq(battle.conditions.weather, "", "it ends")
	assert_eq(_events(battle, "weather_end").size(), 1)
	var rock := _battle(["squirt", "plain"], [["raindance"], ["tackle"]], {0: {"use": 0}}, [{"item": "damprock"}, {}])
	_run(rock, 30)
	assert_almost_eq(float(_events(rock, "weather")[0].seconds), Rules.WEATHER_EXTENDED_SECONDS, 1e-6, "Damp Rock lengthens it")


func test_a_new_weather_replaces_the_old() -> void:
	var battle := _battle(["squirt", "blaze"], [["raindance", "sunnyday"], ["ember"]], {0: {"use": 0}, 30: {"use": 1}})
	_run(battle, 60)
	assert_eq(battle.conditions.weather, "sun")


func test_rain_and_sun_power_water_and_fire() -> void:
	var battle := _battle()
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var water: float = Battle.damage_parts(a, b, _move("jet"), _data()).factor
	var fire: float = Battle.damage_parts(b, a, _move("ember"), _data()).factor
	battle.conditions.set_weather("rain", 100)
	assert_almost_eq(Battle.damage_parts(a, b, _move("jet"), _data()).factor / water, 1.5, 1e-6)
	assert_almost_eq(Battle.damage_parts(b, a, _move("ember"), _data()).factor / fire, 0.5, 1e-6)
	battle.conditions.set_weather("sun", 100)
	assert_almost_eq(Battle.damage_parts(a, b, _move("jet"), _data()).factor / water, 0.5, 1e-6)
	assert_almost_eq(Battle.damage_parts(b, a, _move("ember"), _data()).factor / fire, 1.5, 1e-6)
	a.set_item("utilityumbrella")
	assert_almost_eq(Battle.damage_parts(a, b, _move("jet"), _data()).factor / water, 1.0, 1e-6, "an umbrella keeps sun off its holder's moves")
	assert_almost_eq(Battle.damage_parts(b, a, _move("ember"), _data()).factor / fire, 1.0, 1e-6, "and off hits it takes")


func test_sand_chips_all_but_sandproof_fighters_and_shields_rock() -> void:
	var battle := _battle(["plain", "rocky"], [["tackle"], ["rockthrow"]], {}, [{}, {}], {"weather": "sand"})
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var spd := b.stat("spd")
	_run(battle, Rules.TICK_RATE * 4)
	assert_eq(a.max_hp - a.hp, 4 * roundi(a.max_hp * ArenaConditions.SAND_DAMAGE), "1/80 a second")
	assert_eq(b.hp, b.max_hp, "Rock types are sandproof")
	assert_almost_eq(spd, b.stats.spd * 1.5, 1e-6, "Rock types' Sp. Def x1.5")
	var proof := _battle(["plain", "rocky"], [["tackle"], ["rockthrow"]], {}, [{"ability": "sandforce"}, {}], {"weather": "sand"})
	_run(proof, Rules.TICK_RATE * 4)
	assert_eq(proof.fighters[0].hp, proof.fighters[0].max_hp, "Sand Force keeps sand off")


func test_snow_shields_ice_types() -> void:
	var battle := _battle(["frosty", "plain"], [["tackle"], ["tackle"]], {}, [{}, {}], {"weather": "snow"})
	assert_almost_eq(battle.fighters[0].stat("def"), battle.fighters[0].stats.def * 1.5, 1e-6)
	assert_almost_eq(battle.fighters[1].stat("def"), battle.fighters[1].stats.def, 1e-6)


func test_a_starting_weather_lasts_the_battle() -> void:
	var battle := _battle(["squirt", "plain"], [["jet"], ["tackle"]], {}, [{}, {}], {"weather": "rain"})
	_run(battle, Rules.seconds_to_ticks(Rules.WEATHER_EXTENDED_SECONDS) + 30)
	assert_eq(battle.conditions.weather, "rain")
	assert_eq(_events(battle, "weather")[0].seconds, -1)
	var spec := {"seed": 1, "arena": "stadium", "weather": "hail", "fighters": [{"species": "plain", "moves": ["tackle"]}, {"species": "plain", "moves": ["tackle"]}]}
	assert_true(Battle.create(spec, _data(), [Scripted.new(), Scripted.new()]).has("error"), "an unknown weather is an error")
	var drought := _battle(["blaze", "plain"], [["ember"], ["tackle"]], {}, [{"ability": "drought"}, {}], {"weather": "sun"})
	_run(drought, Rules.seconds_to_ticks(Rules.WEATHER_EXTENDED_SECONDS) + 30)
	assert_eq(drought.conditions.weather, "sun", "a setter renewing a battle-long weather doesn't shorten it")


func test_setting_abilities_start_the_battle_and_the_slower_wins() -> void:
	var battle := _battle(["squirt", "blaze"], [["jet"], ["ember"]], {}, [{"ability": "drizzle"}, {"ability": "drought"}])
	_run(battle, 1)
	var started := _events(battle, "weather")
	assert_eq(started.size(), 2)
	assert_eq(started[0].weather, "sun", "the faster setter goes first")
	assert_eq(battle.conditions.weather, "rain", "so the slower one's weather wins")
	assert_eq(started[1].ability, "drizzle")


func test_weather_abilities() -> void:
	var battle := _battle(["squirt", "blaze"], [["jet"], ["ember"]], {}, [{"ability": "swiftswim"}, {"ability": "solarpower"}])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var walk := a.current_move_speed()
	var spa := b.stat("spa")
	battle.conditions.set_weather("rain", 100)
	assert_almost_eq(a.current_move_speed(), walk * 2.0, 1e-6, "Swift Swim")
	battle.conditions.set_weather("sun", -1)
	assert_almost_eq(b.stat("spa"), spa * 1.5, 1e-6, "Solar Power")
	_run(battle, Rules.TICK_RATE * 2)
	assert_true(b.hp < b.max_hp, "Solar Power costs HP in sun")


func test_leaf_guard_and_sun_block_status() -> void:
	var battle := _battle(["plain", "frosty"], [["freeze"], ["tackle"]], {}, [{}, {}], {"weather": "sun"})
	var plain := battle.fighters[0]
	battle._inflict(plain, "frz")
	assert_eq(plain.status, "", "nobody freezes in sun")
	plain.set_ability("leafguard")
	battle._inflict(plain, "par")
	assert_eq(plain.status, "", "Leaf Guard in sun")
	battle.conditions.set_weather("rain", 100)
	battle._inflict(plain, "par")
	assert_eq(plain.status, "par")


func test_weather_changes_moves() -> void:
	var battle := _battle(["plain", "plain"], [["solarbeam", "thunder", "morningsun"], ["tackle"]])
	var a := battle.fighters[0]
	var beam := _move("solarbeam")
	var thunder := _move("thunder")
	var sun := _move("morningsun")
	var charged := a.windup_ticks(beam)
	var heal := battle.conditions.heal_share(a, sun)
	battle.conditions.set_weather("sun", 100)
	assert_eq(a.windup_ticks(beam), charged - Rules.seconds_to_ticks(Rules.CHARGE_EXTRA), "Solar Beam skips its charge in sun")
	assert_true(battle.conditions.heal_share(a, sun) > heal, "Morning Sun heals more in sun")
	battle.conditions.set_weather("rain", 100)
	assert_true(battle.conditions.heal_share(a, sun) < heal, "and less in other weather")
	assert_almost_eq(battle.conditions.projectile_speed(a, thunder), Rules.projectile_speed(100), 1e-6, "Thunder is sure in rain")
	assert_true(thunder.projectile_speed < Rules.projectile_speed(100))


func test_setters_hold_their_rock() -> void:
	var data := _data()
	var moves: Array = [_move("jet")]
	assert_eq(Items.standard(SPECIES.squirt, moves, data, "drizzle"), "damprock")
	assert_eq(Items.standard(SPECIES.rocky, [_move("rockthrow"), _move("sandstorm")], data), "smoothrock", "a weather move in the moveset")
	assert_eq(Items.weather_rock("snow"), "icyrock")


func test_movesets_value_a_weather_that_suits_the_species() -> void:
	var rain := _move("raindance")
	var sun := _move("sunnyday")
	var water: Array[BattleMove] = [_move("jet"), _move("jet"), _move("tackle")]
	assert_true(Movesets.arena_value(rain, ["Water"], "swiftswim", water) > Movesets.arena_value(rain, ["Water"], "", water), "Swift Swim adds to rain")
	assert_true(Movesets.arena_value(sun, ["Water"], "", water) <= 0.0, "sun only hurts a Water attacker")
	var rock: Array[BattleMove] = [_move("rockthrow")]
	assert_true(Movesets.arena_value(_move("sandstorm"), ["Rock"], "", rock) > Movesets.arena_value(_move("sandstorm"), ["Normal"], "", rock))


func test_the_ais_set_a_weather_that_helps_and_leave_one_with_time_left() -> void:
	var battle := _battle(["squirt", "blaze"], [["jet", "raindance"], ["ember"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	var rain := a.moves[1]
	assert_true(StandInAI.arena_score(a, b, rain) > 0.0, "rain helps Water against Fire")
	battle.conditions.set_weather("sun", 300)
	assert_true(StandInAI.arena_score(a, b, rain) > 0.0, "replacing the foe's sun is worth it")
	battle.conditions.set_weather("rain", Rules.seconds_to_ticks(Rules.WEATHER_SECONDS))
	assert_eq(StandInAI.arena_score(a, b, rain), 0.0, "rain with plenty of time left isn't renewed")
	battle.conditions.set_weather("rain", 30)
	assert_true(StandInAI.arena_score(a, b, rain) > 0.0, "nearly over, it is")
	var fire := _battle(["blaze", "squirt"], [["ember", "raindance"], ["jet"]])
	assert_eq(StandInAI.arena_score(fire.fighters[0], fire.fighters[1], fire.fighters[0].moves[1]), 0.0, "rain never helps Fire against Water")


func test_weather_is_part_of_the_checksum() -> void:
	var clear := _battle(["plain", "plain"], [["tackle"], ["tackle"]])
	var rainy := _battle(["plain", "plain"], [["tackle"], ["tackle"]], {}, [{}, {}], {"weather": "rain"})
	clear.run()
	rainy.run()
	assert_true(clear.checksum() != rainy.checksum())
