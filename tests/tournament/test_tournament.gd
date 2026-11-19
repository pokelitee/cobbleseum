extends TestCase
## Tournament mode (concepts_brief.md §17, M19) on small inline data: flags, seeding, the
## bracket, deterministic play that leaves battles untouched, the cards' layout and the setup
## screen's flags.

const MOVES := {
	"tackle": {"name": "Tackle", "category": "Physical", "type": "Normal", "basePower": 60, "accuracy": 100, "pp": 35, "flags": {"contact": 1}, "target": "normal"},
	"ember": {"name": "Ember", "category": "Special", "type": "Fire", "basePower": 60, "accuracy": 100, "pp": 25, "flags": {}, "target": "normal"},
	"watergun": {"name": "Water Gun", "category": "Special", "type": "Water", "basePower": 60, "accuracy": 100, "pp": 25, "flags": {}, "target": "normal"},
}
const TYPES := {
	"normal": {"damageTaken": {"Fighting": 1}},
	"fire": {"damageTaken": {"Water": 1, "Fire": 2}},
	"water": {"damageTaken": {"Fire": 2, "Water": 2}},
}
## Species s0 (strongest by base stats) to s19, each learning every move.
const COUNT := 20


func _data() -> BattleData:
	var species := {}
	var learnsets := {}
	for i in COUNT:
		var stat := 120 - i * 4
		species["s%d" % i] = {"name": "Species %d" % i, "types": [["Normal", "Fire", "Water"][i % 3]],
			"baseStats": {"hp": stat, "atk": stat, "def": stat, "spa": stat, "spd": stat, "spe": stat}}
		learnsets["s%d" % i] = {"learnset": {"tackle": ["9L1"], "ember": ["9L1"], "watergun": ["9L1"]}}
	return BattleData.new(species, MOVES, TYPES, learnsets)


func _options(extra := {}) -> Dictionary:
	var options := Tournament.defaults()
	options.size = 4
	options.seed = 5
	options.ai = "stand_in"
	options.merge(extra, true)
	return options


func _played(extra := {}, ranking := {}) -> Dictionary:
	var data := _data()
	var created := Tournament.create(_options(extra), data, ranking)
	assert_false(created.has("error"), str(created.get("error", "")))
	var tournament: Dictionary = created.tournament
	assert_eq(Tournament.play(tournament, data), "")
	return tournament


func test_seeds_meet_as_late_as_their_order_allows() -> void:
	assert_eq(Tournament.bracket_order(4), [1, 4, 2, 3] as Array[int])
	assert_eq(Tournament.bracket_order(8), [1, 8, 4, 5, 2, 7, 3, 6] as Array[int])
	for size in [16, 32]:
		var order := Tournament.bracket_order(size)
		assert_eq(order.size(), size)
		assert_true(order.slice(0, size / 2).has(1) and order.slice(size / 2).has(2), "1 and 2 in opposite halves")
		for i in range(0, size, 2):
			assert_eq(order[i] + order[i + 1], size + 1, "each first-round pair adds up to size + 1")


func test_flags_parse_with_their_defaults_and_fail_clearly() -> void:
	var parsed := Tournament.parse(PackedStringArray(["--tournament", "--size=16", "--best-of=3", "--seed=9", "--pool=all",
		"--entrants=Mr. Mime,pikachu", "--format=both"]))
	assert_eq(parsed.options.size, 16)
	assert_eq(parsed.options.best_of, 3)
	assert_eq(parsed.options.seed, 9)
	assert_eq(parsed.options.pool, -1)
	assert_eq(parsed.options.entrants, ["mrmime", "pikachu"])
	assert_eq(parsed.rest, PackedStringArray(["--format=both"]), "other flags are left for the caller")
	assert_eq(Tournament.parse(PackedStringArray(["--doubles"])).options.team_size, Tournament.DEFAULT_DOUBLES_TEAM,
		"doubles defaults to teams of two")
	assert_true(Tournament.parse(PackedStringArray([])).options.seed >= 0, "a missing seed is drawn")
	for bad in ["--size=6", "--best-of=2", "--team-size=7", "--seed=x", "--pool=0", "--weather=hail", "--size"]:
		assert_true(Tournament.parse(PackedStringArray([bad])).has("error"), bad)
	assert_true(Tournament.parse(PackedStringArray(["--doubles", "--team-size=1"])).has("error"), "doubles needs two a side")


func test_seeding_reads_the_ranking_else_base_stats() -> void:
	var data := _data()
	assert_eq(Tournament.seeding_order(data, {}).slice(0, 3), ["s0", "s1", "s2"], "base stat total without a ranking")
	var ratings := {"s5": 1700.0, "s9": 1650.0}
	assert_eq(Tournament.seeding_order(data, ratings).slice(0, 3), ["s5", "s9", "s0"], "ranked first, then the rest by stats")
	var top := Tournament.create(_options({"pool": 4}), data, {"path": "r.json", "rules": 1, "battles": 10, "ratings": ratings})
	assert_eq(top.tournament.entrants.map(func(e: Dictionary) -> String: return e.members[0].species), ["s5", "s9", "s0", "s1"],
		"a pool the size of the field takes the top seeds in order")
	assert_eq(top.tournament.seeding.source, "ranking")
	assert_eq(Tournament.create(_options(), data, {}).tournament.seeding.source, "base stat total")


func test_the_field_is_drawn_from_the_pool_by_the_seed() -> void:
	var data := _data()
	var species := func(created: Dictionary) -> Array:
		return created.tournament.entrants.map(func(e: Dictionary) -> String: return e.members[0].species)
	var first: Array = species.call(Tournament.create(_options(), data, {}))
	assert_eq(first, species.call(Tournament.create(_options(), data, {})), "same seed, same field")
	for id: String in first:
		assert_true(int(id.trim_prefix("s")) < 4 * Tournament.POOL_FACTOR, "drawn from the top %d" % (4 * Tournament.POOL_FACTOR))
	var fields := {}
	for seed in 6:
		fields[str(species.call(Tournament.create(_options({"seed": seed}), data, {})))] = true
	assert_true(fields.size() > 1, "seeds draw different fields")
	var seeds: Array = Tournament.create(_options(), data, {}).tournament.entrants.map(func(e: Dictionary) -> int:
		return int(e.members[0].species.trim_prefix("s")))
	var sorted := seeds.duplicate()
	sorted.sort()
	assert_eq(seeds, sorted, "the drawn field is seeded strongest first")


func test_entrants_name_the_field_and_teams_are_dealt_by_tier() -> void:
	var data := _data()
	assert_true(Tournament.create(_options({"entrants": ["s1", "s2"]}), data, {}).has("error"), "too few")
	assert_true(Tournament.create(_options({"entrants": ["s1", "s1", "s2", "s3"]}), data, {}).has("error"), "twice")
	assert_true(Tournament.create(_options({"entrants": ["s1", "s2", "s3", "nope"]}), data, {}).has("error"), "unknown")
	var teams: Dictionary = Tournament.create(_options({"team_size": 2, "pool": 8}), data, {}).tournament
	assert_eq(teams.entrants.map(func(e: Dictionary) -> Array: return e.members.map(func(m: Dictionary) -> String: return m.species)),
		[["s0", "s4"], ["s1", "s5"], ["s2", "s6"], ["s3", "s7"]], "entrant i brings the i-th of each tier")
	assert_eq(teams.entrants[0].name, "Team Species 0")
	for entrant: Dictionary in teams.entrants:
		assert_true(entrant.members[0].has("form") and entrant.members[0].has("shiny"), "looks are rolled once")


func test_play_is_deterministic_and_leaves_every_battle_as_it_is() -> void:
	var first := _played({"ai": "ranked"})
	var again := _played({"ai": "ranked"})
	assert_eq(JSON.stringify(first.matches), JSON.stringify(again.matches), "same seed, same tournament")
	assert_eq(first.matches.size(), 3)
	assert_eq(first.matches.back().round, 1)
	var data := _data()
	for bout: Dictionary in first.matches:
		for game: Dictionary in bout.games:
			# The same battle as a plain spec (no looks, versions or tournament), as the ranking plays it.
			var plain := {"seed": game.seed, "fighters": game.sides.map(func(i: int) -> Dictionary:
				return {"species": first.entrants[i].members[0].species, "ai": "ranked"})}
			var battle: Battle = Battle.create(plain, data, Controllers.for_spec(plain).controllers).battle
			battle.run()
			assert_eq(battle.checksum(), game.checksum, "a tournament game is the plain battle")
	var other := _played({"ai": "ranked", "seed": 6})
	assert_true(JSON.stringify(other.matches) != JSON.stringify(first.matches), "another seed, another tournament")


func test_a_series_is_won_by_the_majority_with_sides_swapping() -> void:
	var tournament := _played({"best_of": 3})
	for bout: Dictionary in tournament.matches:
		var games: Array = bout.games
		assert_true(bout.wins.max() == 2 or bout.by_seeding, "first to two")
		assert_eq(bout.winner, bout.entrants[bout.wins.find(bout.wins.max())] if not bout.by_seeding else bout.entrants[0])
		assert_true(games.size() <= 3 + Tournament.MAX_DRAWS)
		for g in games.size():
			var expected: Array = [bout.entrants[1], bout.entrants[0]] if g % 2 == 1 else bout.entrants
			assert_eq(games[g].sides, expected, "sides swap every game")
	assert_eq(tournament.champion, tournament.matches.back().winner)


func test_the_reel_shows_a_card_before_each_match() -> void:
	var tournament := _played({"best_of": 3})
	var reel := Tournament.reel(tournament)
	assert_eq(reel[0], {"card": 0})
	assert_eq(reel.back(), {"champion": true})
	var games := reel.filter(func(step: Dictionary) -> bool: return step.has("game"))
	assert_eq(games.size(), tournament.matches.reduce(func(sum: int, bout: Dictionary) -> int: return sum + bout.games.size(), 0))
	assert_eq(Tournament.game_title(tournament, 2, 1), "Final · Game 2")
	var spec := Tournament.spec_of(tournament, 0, 0)
	assert_eq(spec.rules_version, Rules.RULES_VERSION)
	assert_eq(spec.seed, tournament.matches[0].games[0].seed)


func test_a_saved_tournament_reads_back_the_same() -> void:
	var tournament := _played()
	var read := Tournament.from_json(JSON.stringify(tournament))
	assert_eq(read.options.size, 4)
	assert_eq(read.champion, tournament.champion)
	assert_eq(read.matches[0].entrants, Array(tournament.matches[0].entrants))
	assert_eq(Tournament.from_json("[]"), {})


func test_the_newest_ranking_not_past_these_rules_is_found() -> void:
	var root := ProjectSettings.globalize_path("user://test_tournament_results")
	for version in [30, 33, 40]:
		var dir := root.path_join("rank/v%d/ranked" % version)
		DirAccess.make_dir_recursive_absolute(dir)
		var file := FileAccess.open(dir.path_join("ranking.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"rules": version, "battles": 100, "ranking": [{"species": "s3", "rating": 1600.0}]}))
		file.close()
	var found := Tournament.find_ranking(root, "ranked", 34)
	assert_eq(found.rules, 33)
	assert_eq(found.ratings, {"s3": 1600.0})
	assert_eq(Tournament.find_ranking(root, "hard", 34), {}, "none for another profile")
	assert_eq(Tournament.find_ranking(root.path_join("missing"), "ranked", 34), {})
	assert_true(Tournament.load_ranking(root.path_join("nope.json")).has("error"))
	for version in [30, 33, 40]:
		var dir := root.path_join("rank/v%d/ranked" % version)
		DirAccess.remove_absolute(dir.path_join("ranking.json"))
		DirAccess.remove_absolute(dir)
		DirAccess.remove_absolute(dir.get_base_dir())
	DirAccess.remove_absolute(root.path_join("rank"))
	DirAccess.remove_absolute(root)


func test_the_bracket_card_lays_slots_out_between_their_feeders() -> void:
	for portrait in [false, true]:
		var area := Rect2(40, 300, 1000, 1400) if portrait else Rect2(40, 250, 1840, 750)
		for size in [4, 8, 16, 32]:
			var rects := TournamentCard.layout(size, portrait, area)
			var rounds := Tournament.rounds(size)
			assert_eq(rects.size(), 2 * size - 1)
			var champion: Rect2 = rects[Vector2i(rounds, 0)]
			assert_true(champion.get_center().distance_to(area.get_center()) < 1.0, "the champion's slot is in the middle")
			var keys := rects.keys()
			for a in keys.size():
				assert_true(area.encloses(rects[keys[a]]), "inside the area")
				for b in range(a + 1, keys.size()):
					assert_false(rects[keys[a]].intersects(rects[keys[b]]), "%s and %s overlap" % [keys[a], keys[b]])
			var across := 0 if portrait else 1
			for key: Vector2i in keys:
				if key.x == 0 or key.x == rounds:
					continue
				var middle: float = (rects[Vector2i(key.x - 1, key.y * 2)].get_center()[across]
					+ rects[Vector2i(key.x - 1, key.y * 2 + 1)].get_center()[across]) * 0.5
				assert_almost_eq(rects[key].get_center()[across], middle, 0.01, "between the two it's fed by")


func test_slots_show_who_has_got_that_far() -> void:
	var tournament := _played({"size": 8})
	var order := Tournament.bracket_order(8)
	assert_eq(TournamentCard.occupant(tournament, [], 0, 1), order[1] - 1)
	assert_eq(TournamentCard.occupant(tournament, [], 1, 0), -1, "undecided")
	assert_eq(TournamentCard.occupant(tournament, tournament.matches, 1, 0), tournament.matches[0].winner)


func test_the_setup_screen_builds_tournament_flags() -> void:
	var chosen := SetupTournament.DEFAULT.duplicate()
	var setup := {"mode": "tournament", "tournament": chosen, "doubles": false, "arena": "", "weather": "", "seed": "", "format": "vertical", "seconds": 10}
	assert_eq(SetupScreen.tournament_args(setup), PackedStringArray(["--tournament"]), "defaults are left out")
	chosen.merge({"size": "16", "best_of": "3", "ai": "hard", "pool": "top", "record": true}, true)
	setup.merge({"doubles": true, "seed": "42", "arena": "volcano", "format": "both", "seconds": 8}, true)
	assert_eq(SetupScreen.tournament_args(setup), PackedStringArray(["--record", "--doubles", "--size=16", "--best-of=3", "--ai=hard",
		"--seed=42", "--pool=32", "--arena=volcano", "--format=both", "--seconds=8"]), "the top seeds of 16 doubles teams of two")
	assert_eq(SetupScreen.tournament_problem(setup), "")
	var parsed := Tournament.parse(SetupScreen.tournament_args(setup))
	assert_eq([parsed.options.size, parsed.options.best_of, parsed.options.team_size, parsed.options.pool], [16, 3, 2, 32])


func test_the_battle_view_takes_a_round_and_no_credits() -> void:
	var options := BattleView.parse_args(PackedStringArray(["game.json", "--no-credits", "--title=Final · Game 2"]))
	assert_false(options.has("error"), str(options.get("error", "")))
	assert_true(options.no_credits)
	assert_eq(options.title, "Final · Game 2")
	assert_false(BattleView.parse_args(PackedStringArray(["game.json"])).no_credits)
