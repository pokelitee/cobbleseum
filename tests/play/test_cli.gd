extends TestCase
## The command line's shared help (Cli): nearest-match suggestions, unknown options, name checks,
## lists and the resolved battle.

const SPECIES := {
	"squirtle": {"name": "Squirtle", "types": ["Water"], "baseStats": {"hp": 44, "atk": 48, "def": 65, "spa": 50, "spd": 64, "spe": 43}},
	"charmander": {"name": "Charmander", "types": ["Fire"], "baseStats": {"hp": 39, "atk": 52, "def": 43, "spa": 60, "spd": 50, "spe": 65}},
}
const MOVES := {
	"watergun": {"name": "Water Gun", "category": "Special", "type": "Water", "basePower": 40, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 40, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
	"scratch": {"name": "Scratch", "category": "Physical", "type": "Normal", "basePower": 40, "accuracy": 100, "pp": 35, "priority": 0, "flags": {"contact": 1}, "target": "normal"},
	"breakneckblitz": {"name": "Breakneck Blitz", "category": "Physical", "type": "Normal", "basePower": 1, "accuracy": true, "pp": 1, "priority": 0, "flags": {}, "isZ": "normaliumz", "target": "normal"},
}


func _data() -> BattleData:
	return BattleData.new(SPECIES, MOVES, {})


func _spec(fighter_a := {}, fighter_b := {}) -> Dictionary:
	var a := {"species": "squirtle", "moves": ["watergun"]}
	a.merge(fighter_a, true)
	var b := {"species": "charmander", "moves": ["ember"]}
	b.merge(fighter_b, true)
	return {"seed": 3, "fighters": [a, b]}


func test_edit_distance_counts_typos() -> void:
	assert_eq(Cli.edit_distance("garchomp", "garchomp"), 0)
	assert_eq(Cli.edit_distance("garchom", "garchomp"), 1, "a missing letter")
	assert_eq(Cli.edit_distance("garhcomp", "garchomp"), 1, "swapped neighbours")
	assert_eq(Cli.edit_distance("", "abc"), 3)
	assert_eq(Cli.edit_distance("kitten", "sitting"), 3)


func test_nearest_suggests_close_names_first() -> void:
	var names := ["garchomp", "gabite", "gible", "blastoise", "garchompmega"]
	assert_eq(Cli.nearest("garchom", names), ["garchomp", "garchompmega"])
	assert_eq(Cli.nearest("blastois", names), ["blastoise"])
	assert_eq(Cli.nearest("pikachu", names), [], "nothing plausible")
	assert_eq(Cli.nearest("", names), [])
	assert_eq(Cli.nearest("gar", names).size(), 2, "a prefix suggests what it starts")


func test_unknown_options_fail_with_the_nearest_ones() -> void:
	assert_eq(Cli.unknown_option(PackedStringArray(["spec.json", "--seeds=3"]), ["seeds"]), "")
	var error := Cli.unknown_option(PackedStringArray(["--seed=3", "--vss=blastoise"]), ["seeds"])
	assert_true(error.contains("unknown option --vss=blastoise"), error)
	assert_true(error.contains("--vs"), "suggests --vs: " + error)
	assert_true(Cli.unknown_option(PackedStringArray(["--formt=both"]), ["format"]).contains("--format"))
	assert_true(Cli.unknown_option(PackedStringArray(["--watch"]), []).contains("needs a value"))
	assert_true(Cli.unknown_option(PackedStringArray(["--watch=x"]), [], false).contains("unknown option"),
		"battle flags only where a tool takes them")


func test_check_spec_names_the_nearest_matches() -> void:
	var data := _data()
	assert_eq(Cli.check_spec(_spec(), data), "")
	var error := Cli.check_spec(_spec({"species": "squirtel"}), data)
	assert_true(error.contains("unknown species 'squirtel'") and error.contains("squirtle"), error)
	error = Cli.check_spec(_spec({}, {"moves": ["embr"]}), data)
	assert_true(error.contains("unknown move 'embr'") and error.contains("ember"), error)
	error = Cli.check_spec(_spec({"ai": "hardd"}), data)
	assert_true(error.contains("unknown AI profile") and error.contains("hard"), error)
	error = Cli.check_spec(_spec({"ability": "torent"}), data)
	assert_true(error.contains("unknown ability") and error.contains("torrent"), error)
	error = Cli.check_spec(_spec({"item": "lifeorbb"}), data)
	assert_true(error.contains("unknown item") and error.contains("lifeorb"), error)
	var spec := _spec()
	spec.arena = "volcanoo"
	error = Cli.check_spec(spec, data)
	assert_true(error.contains("unknown arena") and error.contains("volcano"), error)
	spec = _spec()
	spec.weather = "rian"
	assert_true(Cli.check_spec(spec, data).contains("rain"))


func test_check_spec_accepts_what_battles_accept() -> void:
	var data := _data()
	assert_eq(Cli.check_spec(_spec({"ability": "", "item": "", "ai": "stand_in"}, {"ai": "player"}), data), "", "none and other AIs")
	assert_eq(Cli.check_spec(_spec({"ability": "torrent", "item": "lifeorb"}), data), "")
	assert_eq(Cli.check_spec(_spec({"ai": "nonsense", "intents": []}), data), "", "a replayed side has no AI")


func test_only_roster_species_count_when_there_is_a_roster() -> void:
	var data := _data()
	data.roster = {"squirtle": {}}
	assert_eq(Cli.species_ids(data), ["squirtle"])
	assert_true(Cli.check_spec(_spec(), data).contains("charmander"))


func test_lists() -> void:
	var data := _data()
	var species: PackedStringArray = Cli.list("species", data).lines
	assert_eq(Array(species), ["charmander  Charmander", "squirtle  Squirtle"])
	var moves: PackedStringArray = Cli.list("moves", data).lines
	assert_eq(moves.size(), 3, "no Z-moves")
	assert_eq(moves[0], "ember  Ember (Fire, Special, power 40)")
	assert_true(Array(Cli.list("profiles", null).lines).has("hard"))
	assert_true(Array(Cli.list("arenas", null).lines).any(func(line: String) -> bool: return line.begins_with("volcano  Volcano")))
	assert_true(Cli.list("abilities", null).lines.size() > 10)
	assert_true(Cli.list("items", null).lines.size() > 10)
	var error: String = Cli.list("specis", null).get("error", "")
	assert_true(error.contains("species"), error)


func test_profiles_are_the_profile_files() -> void:
	assert_eq(Cli.profiles(), ["easy", "hard", "normal", "ranked"])


func test_describe_prints_what_repeats_the_battle() -> void:
	var data := _data()
	var spec := SpecFlags.to_spec({"watch": "squirtle", "vs": "charmander", "moves": "watergun", "vs-moves": "ember",
		"ability": "none", "vs-item": "none", "seed": "11", "shiny": "a", "form": "base", "vs-form": "base"})
	var created := Battle.create(spec, data, Controllers.for_spec(spec).controllers)
	var lines := Cli.describe(spec, created.battle, true)
	assert_true(lines[0].begins_with("battle: seed 11, arena "), lines[0])
	assert_true(lines[1].contains("Squirtle (ranked), ability none") and lines[1].contains("moves watergun") and lines[1].ends_with("own look, shiny"), lines[1])
	var repeat := lines[3].trim_prefix("  repeat with: ")
	var again := SpecFlags.to_spec(SpecFlags.parse(repeat.split(" ")).flags)
	assert_eq(again.arena, created.battle.arena, "the arena the seed picked is pinned")
	var replayed := Battle.create(again, data, Controllers.for_spec(again).controllers)
	assert_eq(replayed.battle.arena, created.battle.arena)
	assert_eq(replayed.battle.run(), created.battle.run())
	assert_eq(replayed.battle.checksum(), created.battle.checksum(), "the flags repeat the battle")
	assert_eq(Cli.describe(spec, created.battle, false).size(), 3, "a spec file repeats itself")


func test_info_handles_only_help_and_list() -> void:
	assert_eq(Cli.info(PackedStringArray(["--watch=garchomp"]), "help"), -1)
	assert_eq(Cli.info(PackedStringArray(["--list=profiles"]), "help"), 0)
	assert_eq(Cli.info(PackedStringArray(["--help"]), "help"), 0)
