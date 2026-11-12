extends TestCase
## Ranking maths (concepts_brief.md §13) on synthetic results.


## Records from a known strength order: in each battle the stronger side wins `bias` of the
## time (deterministically), the rest go the other way, and one battle in `draw_every` draws.
func _records(strengths: Dictionary, battles_per_matchup := 20, bias := 0.75, draw_every := 10) -> Array:
	var ids := strengths.keys()
	var records: Array = []
	var random := SimRandom.new(3)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			for g in battles_per_matchup:
				var a: String = ids[i] if g % 2 == 0 else ids[j]
				var b: String = ids[j] if g % 2 == 0 else ids[i]
				var result := "D"
				if g % draw_every != 0:
					var a_stronger: bool = strengths[a] > strengths[b]
					var favourite_wins := random.chance(bias)
					result = "A" if a_stronger == favourite_wins else "B"
				records.append({"a": a, "b": b, "result": result})
	return records


func test_bradley_terry_recovers_the_strength_order() -> void:
	var strengths := {"ace": 4, "good": 3, "fair": 2, "weak": 1}
	var ratings := Ranking.bradley_terry(_records(strengths, 60))
	assert_eq(Ranking.order(ratings), ["ace", "good", "fair", "weak"])
	var mean := 0.0
	for id in ratings:
		mean += ratings[id].rating
	assert_almost_eq(mean / ratings.size(), Ranking.RATING_MEAN, 1.0, "centred on the average rating")


func test_draws_count_half_and_even_results_rate_equal() -> void:
	var records := [{"a": "x", "b": "y", "result": "D"}, {"a": "y", "b": "x", "result": "D"},
		{"a": "x", "b": "y", "result": "A"}, {"a": "y", "b": "x", "result": "A"}]
	var ratings := Ranking.bradley_terry(records)
	assert_eq(ratings.x.score, 2.0)
	assert_almost_eq(ratings.x.rating, ratings.y.rating, 1e-6)
	assert_eq(ratings.x.battles, 4)


func test_an_unbeaten_species_still_gets_a_finite_rating() -> void:
	var records := [{"a": "x", "b": "y", "result": "A"}, {"a": "y", "b": "x", "result": "B"}]
	var ratings := Ranking.bradley_terry(records)
	assert_true(is_finite(ratings.x.rating) and ratings.x.rating > ratings.y.rating)


func test_schedule_is_seeded_and_unique() -> void:
	var pool := ["a", "b", "c", "d", "e", "f", "g", "h"]
	var first := Ranking.schedule(pool, 3, 1)
	assert_eq(first, Ranking.schedule(pool, 3, 1), "same seed, same schedule")
	assert_true(first != Ranking.schedule(pool, 3, 2))
	var seen := {}
	for matchup in first:
		assert_true(matchup.a < matchup.b)
		var key: String = matchup.a + matchup.b
		assert_false(seen.has(key), "no matchup twice")
		seen[key] = true
	for id in pool:
		assert_true(first.filter(func(p: Dictionary) -> bool: return p.a == id or p.b == id).size() >= 3, id)
	assert_eq(Ranking.round_robin(["c", "a", "b"], 1).map(func(p: Dictionary) -> String: return p.a + p.b), ["ab", "ac", "bc"])
	var repeated := Ranking.round_robin(["a", "b"], 1, 3)
	assert_eq(repeated.size(), 3)
	assert_eq(repeated[0].seed, Ranking.schedule(["a", "b"], 1, 1)[0].seed, "the first repeat reuses the schedule's seed")
	assert_true(repeated[1].seed != repeated[0].seed and repeated[2].seed != repeated[1].seed)


func test_spearman() -> void:
	assert_almost_eq(Ranking.spearman(["a", "b", "c", "d"], ["a", "b", "c", "d"]), 1.0, 1e-9)
	assert_almost_eq(Ranking.spearman(["a", "b", "c", "d"], ["d", "c", "b", "a"]), -1.0, 1e-9)
	assert_almost_eq(Ranking.spearman(["a", "b", "c"], ["b", "a", "x", "c"]), 0.5, 1e-9, "over shared species only")


func test_matchups_are_head_to_head_shares() -> void:
	var records := [{"a": "x", "b": "y", "result": "A"}, {"a": "y", "b": "x", "result": "D"}, {"a": "x", "b": "z", "result": "A"}]
	var rates := Ranking.matchups(records, ["x", "y"])
	assert_almost_eq(rates["x|y"], 0.75, 1e-9)
	assert_almost_eq(rates["y|x"], 0.25, 1e-9)
	assert_false(rates.has("x|z"), "only species in the matrix")


func test_resuming_after_a_partial_line_starts_a_new_one() -> void:
	var path := TestFiles.fresh_dir("rank_resume").path_join("shard0.jsonl")
	TestFiles.write_text(path, '{"a":"x","b":"y","seed":1,"result":"A"}
{"a":"x","b"')
	var file := preload("res://tools/rank.gd").open_for_append(path)
	file.store_line('{"a":"x","b":"z","seed":2,"result":"B"}')
	file.close()
	var lines := FileAccess.get_file_as_string(path).split("
", false)
	assert_eq(lines.size(), 3)
	assert_eq(JSON.parse_string(lines[2]).b, "z", "the new record is whole")
	file = preload("res://tools/rank.gd").open_for_append(path)
	file.store_line("{}")
	file.close()
	assert_eq(FileAccess.get_file_as_string(path).split("
", false).size(), 4, "no blank line added after a complete one")
