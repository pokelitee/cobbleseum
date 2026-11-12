extends TestCase

const TABLE := {"flamethrower": "stream", "highjumpkick": "kick", "thunderpunch": "beam"}


func test_table_wins_over_flags() -> void:
	assert_eq(MoveStyle.of("flamethrower", {"flags": {}}, TABLE), "stream")
	assert_eq(MoveStyle.of("highjumpkick", {"flags": {"contact": 1}}, TABLE), "kick")


func test_flags_pick_the_style_otherwise() -> void:
	assert_eq(MoveStyle.of("crunch", {"flags": {"contact": 1, "bite": 1}}, TABLE), "bite")
	assert_eq(MoveStyle.of("nightslash", {"flags": {"contact": 1, "slicing": 1}}, TABLE), "slash")
	assert_eq(MoveStyle.of("shadowball", {"flags": {"bullet": 1}}, TABLE), "bullet")
	assert_eq(MoveStyle.of("bugbuzz", {"flags": {"sound": 1}}, TABLE), "sound")


func test_defaults_follow_contact() -> void:
	assert_eq(MoveStyle.of("slam", {"flags": {"contact": 1}}, TABLE), "strike")
	assert_eq(MoveStyle.of("moonblast", {"flags": {}}, TABLE), "orb")


func test_a_table_style_of_the_wrong_kind_is_ignored() -> void:
	assert_eq(MoveStyle.of("thunderpunch", {"flags": {"contact": 1, "punch": 1}}, TABLE), "punch",
		"a ranged style can't apply to a contact move")


func test_committed_table_is_valid() -> void:
	var table := MoveStyle.committed_table()
	assert_true(table.size() > 200, "the table loaded (%d moves)" % table.size())
	assert_eq(table.get("flamethrower"), "stream")
	assert_eq(table.get("icebeam"), "beam")
	assert_eq(table.get("thunderbolt"), "bolt")


func test_parse_table_rejects_duplicates_and_unknown_styles() -> void:
	assert_true(MoveStyle.parse_table('{"beam": ["a"], "orb": ["a"]}').get("error", "").contains("both beam and orb"))
	assert_true(MoveStyle.parse_table('{"laser": ["a"]}').get("error", "").contains("unknown style"))
	assert_eq(MoveStyle.parse_table('{"_comment": "x", "beam": ["a"]}'), {"table": {"a": "beam"}})


func test_projectiles_still_in_flight_end_with_the_battle() -> void:
	var species := {"squirt": {"name": "Squirt", "types": ["Water"], "baseStats": {"hp": 80, "atk": 80, "def": 100, "spa": 85, "spd": 100, "spe": 80}}}
	var moves := {"jet": {"name": "Jet", "category": "Special", "type": "Water", "basePower": 80, "accuracy": 100, "pp": 15, "priority": 0, "flags": {}, "target": "normal"}}
	var spec := {"seed": 1, "arena": "stadium", "fighters": [{"species": "squirt", "moves": ["jet"]}, {"species": "squirt", "moves": ["jet"]}]}
	var battle: Battle = Battle.create(spec, BattleData.new(species, moves, {}), [Idle.new(), Idle.new()]).battle
	battle.projectiles.append({"id": 0, "owner": 0, "move": 0, "position": Vector2(0, -2), "velocity": Vector2(0, 0.5), "height": 1.0})
	var fx := MoveFX.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(fx)
	fx.sync_projectiles(battle)
	assert_eq(fx._projectiles.size(), 1, "a projectile in flight is drawn")
	battle.result = Battle.Result.WIN_A
	fx.sync_projectiles(battle)
	assert_eq(fx._projectiles.size(), 0, "and ends when the battle does, though the simulation still lists it")
	fx.free()


class Idle extends RefCounted:
	func decide(_battle: Battle, _side: int) -> Dictionary:
		return {}
