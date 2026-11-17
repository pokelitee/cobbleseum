extends TestCase
## Screens (concepts_brief.md §9.11): Reflect, Light Screen and Aurora Veil on the user's side,
## what gets through them, the moves that shatter them, and how movesets and the AIs value them.
## Small inline data, so CI needs no asset cache.

const STATS := {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}
const SPECIES := {
	"plain": {"name": "Plain", "types": ["Normal"], "baseStats": STATS, "abilities": {"0": "Run Away"}},
	"frosty": {"name": "Frosty", "types": ["Ice"], "baseStats": STATS, "abilities": {"0": "Snow Warning"}},
}
const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"swift": {"name": "Swift", "category": "Special", "type": "Normal", "basePower": 60, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "normal"},
	"brickbreak": {"name": "Brick Break", "category": "Physical", "type": "Normal", "basePower": 75, "accuracy": 100, "pp": 15, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"reflect": {"name": "Reflect", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "reflect"},
	"lightscreen": {"name": "Light Screen", "category": "Status", "type": "Psychic", "basePower": 0, "accuracy": true, "pp": 30, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "lightscreen"},
	"auroraveil": {"name": "Aurora Veil", "category": "Status", "type": "Ice", "basePower": 0, "accuracy": true, "pp": 20, "priority": 0, "flags": {}, "target": "allySide", "sideCondition": "auroraveil"},
}
const TYPES := {"normal": {"damageTaken": {}}, "ice": {"damageTaken": {}}}


class Scripted extends RefCounted:
	var plan := {}

	func decide(battle: Battle, _side: int) -> Dictionary:
		return plan.get(battle.tick, {})


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, TYPES)


func _battle(moves := [["reflect"], ["tackle", "swift"]], plan_a := {}, extra := [{}, {}], species := ["plain", "plain"]) -> Battle:
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


func _screen(battle: Battle, move_id: String) -> float:
	return Battle.damage_parts(battle.fighters[1], battle.fighters[0], _move(move_id), _data()).screen


func test_screen_moves_are_arena_moves() -> void:
	for id in ["reflect", "lightscreen", "auroraveil"]:
		var move := _move(id)
		assert_eq(move.kind, BattleMove.Kind.ARENA, id)
		assert_eq(move.screen, id)
		assert_eq(move.cooldown_ticks, Rules.seconds_to_ticks(Rules.SCREEN_COOLDOWN))


func test_a_screen_softens_its_kind_of_hit_on_its_side_for_a_while() -> void:
	var battle := _battle([["reflect"], ["tackle", "swift"]], {0: {"use": 0}})
	_run(battle, 30)
	assert_true(battle.conditions.screens[0].has("reflect"))
	assert_true(battle.conditions.screens[1].is_empty(), "only the user's side")
	assert_almost_eq(_screen(battle, "tackle"), ArenaConditions.SCREEN_FACTOR, 1e-6)
	assert_almost_eq(_screen(battle, "swift"), 1.0, 1e-6, "Reflect lets special hits through")
	_run(battle, Rules.seconds_to_ticks(Rules.SCREEN_SECONDS))
	assert_true(battle.conditions.screens[0].is_empty(), "it wears off")
	assert_eq(battle.events.filter(func(e: Dictionary) -> bool: return e.type == "screen_end").size(), 1)
	var clay := _battle([["reflect"], ["tackle"]], {0: {"use": 0}}, [{"item": "lightclay"}, {}])
	_run(clay, 30)
	assert_true(clay.conditions.screens[0].reflect > Rules.seconds_to_ticks(Rules.SCREEN_SECONDS), "Light Clay lengthens it")


func test_infiltrator_and_critical_hits_get_through() -> void:
	var battle := _battle()
	battle.conditions.set_screen(0, "lightscreen", 100)
	assert_almost_eq(_screen(battle, "swift"), ArenaConditions.SCREEN_FACTOR, 1e-6)
	battle.fighters[1].set_ability("infiltrator")
	assert_almost_eq(_screen(battle, "swift"), 1.0, 1e-6)
	var crit := Battle.damage(battle.fighters[0], battle.fighters[1], _move("tackle"), _data(), SimRandom.stream(1, 0))
	assert_true(crit.damage > 0)


func test_brick_break_shatters_screens() -> void:
	var battle := _battle([["tackle"], ["brickbreak"]])
	battle.conditions.set_screen(0, "reflect", 100)
	battle.conditions.set_screen(0, "lightscreen", 100)
	battle._hit(battle.fighters[1], battle.fighters[0], _move("brickbreak"))
	assert_true(battle.conditions.screens[0].is_empty())
	var shattered := battle.events.filter(func(e: Dictionary) -> bool: return e.type == "screen_end" and e.get("shattered", false))
	assert_eq(shattered.size(), 2)


func test_aurora_veil_needs_snow() -> void:
	var battle := _battle([["auroraveil"], ["tackle"]])
	assert_false(battle.fighters[0].move_ready(0))
	battle.conditions.set_weather("snow", 100)
	assert_true(battle.fighters[0].move_ready(0))
	battle.conditions.set_screen(0, "auroraveil", 100)
	assert_almost_eq(_screen(battle, "tackle"), ArenaConditions.SCREEN_FACTOR, 1e-6, "the veil softens both kinds")


func test_movesets_and_ais_value_screens() -> void:
	assert_true(Movesets.arena_value(_move("auroraveil"), ["Ice"], "snowwarning", []) > Movesets.arena_value(_move("reflect"), ["Normal"], "", []))
	assert_eq(Movesets.arena_value(_move("auroraveil"), ["Ice"], "", []), 0.0, "no veil without snow of its own")
	var battle := _battle([["reflect", "lightscreen"], ["tackle"]])
	var a := battle.fighters[0]
	var b := battle.fighters[1]
	assert_true(StandInAI.arena_score(a, b, a.moves[0]) > 0.0, "Reflect against a physical attacker")
	assert_eq(StandInAI.arena_score(a, b, a.moves[1]), 0.0, "Light Screen against one is no use")
	battle.conditions.set_screen(0, "reflect", 100)
	assert_eq(StandInAI.arena_score(a, b, a.moves[0]), 0.0, "not while it's up")
	assert_eq(Items.standard(SPECIES.plain, [_move("tackle"), _move("reflect")], _data()), "lightclay")
