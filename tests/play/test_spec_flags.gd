extends TestCase
## Battle specs from command-line flags (SpecFlags): --play and --watch.


func test_flags_are_split_from_other_arguments() -> void:
	var parsed := SpecFlags.parse(PackedStringArray(["--watch=garchomp", "--clip-seconds=5", "--vs-ai=easy", "spec.json", "--ai-debug"]))
	assert_eq(parsed.flags, {"watch": "garchomp", "vs-ai": "easy"})
	assert_eq(Array(parsed.rest), ["--clip-seconds=5", "spec.json", "--ai-debug"])


func test_watch_builds_an_ai_battle() -> void:
	var spec := SpecFlags.to_spec({"watch": "garchomp", "vs": "hydreigon", "ai": "hard", "vs-ai": "easy", "seed": "7"})
	assert_eq(spec, {"seed": 7, "fighters": [{"species": "garchomp", "ai": "hard"}, {"species": "hydreigon", "ai": "easy"}]})
	spec = SpecFlags.to_spec({"watch": "garchomp", "ai": "hard"})
	assert_eq(spec.fighters[1], {"species": SpecFlags.DEFAULT_FOE, "ai": "hard"}, "the foe defaults, and shares --ai")
	assert_eq(SpecFlags.to_spec({"watch": "garchomp"}).fighters[0].ai, Controllers.DEFAULT_AI)


func test_play_keeps_its_meaning() -> void:
	var spec := SpecFlags.to_spec({"play": "cinderace", "vs": "blastoise", "ai": "normal", "seed": "3"})
	assert_eq(spec, {"seed": 3, "fighters": [{"species": "cinderace", "ai": "player"}, {"species": "blastoise", "ai": "normal"}]})


func test_no_battle_or_conflicting_flags() -> void:
	assert_eq(SpecFlags.to_spec({}), {})
	assert_eq(SpecFlags.to_spec({"vs": "blastoise"}), {}, "--vs alone names no battle")
	assert_true(SpecFlags.to_spec({"play": "a", "watch": "b"}).has("error"))
	assert_true(SpecFlags.to_spec({"play": "a", "vs-ai": "easy"}).has("error"))


func test_specs_round_trip_through_flags() -> void:
	for flags: Dictionary in [{"watch": "garchomp", "vs": "hydreigon", "ai": "hard", "vs-ai": "easy", "seed": "7"},
			{"play": "cinderace", "vs": "blastoise", "ai": "normal", "seed": "3"}]:
		var spec := SpecFlags.to_spec(flags)
		assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags), spec)


func test_arena_flag_is_kept_and_passed_on() -> void:
	var spec := SpecFlags.to_spec({"watch": "garchomp", "arena": "volcano", "seed": "2"})
	assert_eq(spec.arena, "volcano")
	assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags), spec)
	assert_false(SpecFlags.to_spec({"watch": "garchomp"}).has("arena"))

