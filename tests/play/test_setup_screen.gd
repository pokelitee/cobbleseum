extends TestCase
## The setup screen builds battles through the same flags as the command line (SetupScreen).

const SPECIES := {
	"squirtle": {"name": "Squirtle", "types": ["Water"], "baseStats": {"hp": 44, "atk": 48, "def": 65, "spa": 50, "spd": 64, "spe": 43}},
	"charmander": {"name": "Charmander", "types": ["Fire"], "baseStats": {"hp": 39, "atk": 52, "def": 43, "spa": 60, "spd": 50, "spe": 65}},
}
const MOVES := {
	"watergun": {"name": "Water Gun", "category": "Special", "type": "Water", "basePower": 40, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 40, "accuracy": 100, "pp": 25, "priority": 0, "flags": {}, "target": "normal"},
}


func _member(species: String, extra := {}) -> Dictionary:
	var member := SetupSide.DEFAULT_MEMBER.duplicate()
	member.species = species
	member.merge(extra, true)
	return member


func _setup(mode: String, a := {}, b := {}, battle := {}) -> Dictionary:
	var setup := {"mode": mode, "sides": [_member("squirtle", a), _member("charmander", b)], "arena": "", "weather": "", "seed": ""}
	setup.merge(battle, true)
	return setup


func test_defaults_build_the_plain_flags() -> void:
	assert_eq(SetupScreen.flags_for(_setup("watch")), {"watch": "squirtle", "vs": "charmander", "ai": "ranked", "vs-ai": "ranked"})
	assert_eq(SetupScreen.flags_for(_setup("play", {}, {"ai": "hard"})), {"play": "squirtle", "vs": "charmander", "ai": "hard"},
		"in play, --ai is the foe's")
	assert_eq(SetupScreen.flags_for(_setup("record", {"ai": "easy"})).get("ai"), "easy", "record is an AI battle")


func test_every_choice_reaches_the_spec() -> void:
	var setup := _setup("watch", {"ai": "hard", "form": "base", "shiny": "yes", "ability": "torrent", "item": "none", "moves": "Water Gun"},
		{"ai": "easy", "moves": "ember", "ability": "none"}, {"arena": "volcano", "weather": "rain", "seed": "42"})
	var spec := SpecFlags.to_spec(SetupScreen.flags_for(setup))
	assert_eq(spec, {"seed": 42, "arena": "volcano", "weather": "rain", "fighters": [
		{"species": "squirtle", "ai": "hard", "form": "", "shiny": true, "ability": "torrent", "item": "", "moves": ["watergun"]},
		{"species": "charmander", "ai": "easy", "shiny": false, "ability": "", "moves": ["ember"]},
	]})


func test_shiny_left_to_the_seed_on_both_sides_stays_rolled() -> void:
	assert_false(SetupScreen.flags_for(_setup("watch")).has("shiny"))
	assert_eq(SetupScreen.flags_for(_setup("watch", {}, {"shiny": "yes"})).shiny, "b")
	assert_eq(SetupScreen.flags_for(_setup("watch", {"shiny": "no"}, {"shiny": "no"})).shiny, "none")


func test_problems_are_the_command_line_s() -> void:
	var data := BattleData.new(SPECIES, MOVES, {})
	assert_eq(SetupScreen.problem_for(SetupScreen.flags_for(_setup("watch")), data), "")
	var problem := SetupScreen.problem_for(SetupScreen.flags_for(_setup("watch", {"moves": "watergn"})), data)
	assert_true(problem.contains("did you mean watergun"), problem)
	assert_true(SetupScreen.problem_for(SetupScreen.flags_for(_setup("watch", {}, {}, {"seed": "x"})), data).contains("--seed"))


func test_the_command_line_shown_runs_the_same_battle() -> void:
	var args := SpecFlags.to_args(SetupScreen.flags_for(_setup("watch", {"moves": "water gun"}, {}, {"seed": "3"})))
	assert_eq(SetupScreen.command_line(args, false),
		"godot --path . -- --watch=squirtle --vs=charmander --ai=ranked --vs-ai=ranked --seed=3 \"--moves=water gun\"")
	assert_true(SetupScreen.command_line(args, true).begins_with("godot --headless --path . --script res://tools/record.gd -- --watch="))
	assert_eq(SpecFlags.parse(args).flags, SetupScreen.flags_for(_setup("watch", {"moves": "water gun"}, {}, {"seed": "3"})),
		"the arguments the battle view gets parse back to the same flags")
