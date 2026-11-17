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


func test_weather_flag_is_kept_and_passed_on() -> void:
	var spec := SpecFlags.to_spec({"watch": "garchomp", "weather": "rain", "seed": "2"})
	assert_eq(spec.weather, "rain")
	assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags), spec)
	var clear := SpecFlags.to_spec({"watch": "garchomp", "weather": "none", "seed": "2"})
	assert_eq(clear.weather, "", "none clears an arena's starting weather")
	assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(clear)).flags), clear)



func test_look_flags_set_shiny_and_forms() -> void:
	var spec := SpecFlags.to_spec({"watch": "gastrodon", "vs": "vivillon", "shiny": "b", "form": "east", "vs-form": "base", "seed": "4"})
	assert_eq(spec.fighters[0].shiny, false)
	assert_eq(spec.fighters[1].shiny, true)
	assert_eq(spec.fighters[0].form, "east")
	assert_eq(spec.fighters[1].form, "", "base is the species' own look")
	assert_false(SpecFlags.to_spec({"watch": "gastrodon"}).fighters[0].has("shiny"), "left out, it's rolled later")
	assert_true(SpecFlags.to_spec({"watch": "gastrodon", "shiny": "yes"}).has("error"))
	for flags: Dictionary in [{"watch": "gastrodon", "shiny": "both", "form": "east", "seed": "4"},
			{"play": "gastrodon", "vs": "vivillon", "shiny": "none", "vs-form": "marine", "seed": "4"}]:
		spec = SpecFlags.to_spec(flags)
		var again := SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags)
		for side in 2:
			assert_eq(again.fighters[side].get("shiny"), spec.fighters[side].get("shiny"), "shiny round-trips")
			assert_eq(again.fighters[side].get("form", ""), spec.fighters[side].get("form", ""), "forms round-trip")


func test_moves_abilities_and_items_per_side() -> void:
	var spec := SpecFlags.to_spec({"watch": "Garchomp", "vs": "Mr. Mime", "moves": "Earthquake, dragonclaw,", "vs-moves": "psychic",
		"ability": "Rough Skin", "vs-ability": "none", "item": "none", "vs-item": "Life Orb", "seed": "5"})
	assert_eq(spec.fighters[0], {"species": "garchomp", "ai": Controllers.DEFAULT_AI, "moves": ["earthquake", "dragonclaw"],
		"ability": "roughskin", "item": ""}, "names become IDs; none is none")
	assert_eq(spec.fighters[1], {"species": "mrmime", "ai": Controllers.DEFAULT_AI, "moves": ["psychic"], "ability": "", "item": "lifeorb"})
	assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags), spec, "they round-trip")
	assert_false(SpecFlags.to_spec({"watch": "garchomp"}).fighters[0].has("moves"), "left out: the standard ones")
	assert_true(SpecFlags.to_spec({"watch": "garchomp", "moves": ","}).has("error"))


func test_a_seed_must_be_a_number() -> void:
	assert_true(SpecFlags.to_spec({"watch": "garchomp", "seed": "abc"}).has("error"))


func test_flags_without_a_seed_stay_without_one() -> void:
	var flags := {"watch": "garchomp", "vs": "hydreigon", "ai": "hard", "vs-ai": "easy", "arena": "cave"}
	var spec := SpecFlags.to_spec(flags)
	spec.erase("seed")
	assert_eq(SpecFlags.to_flags(spec), flags, "so each battle from them gets a new seed")
	assert_eq(Array(SpecFlags.to_args(flags)), ["--watch=garchomp", "--vs=hydreigon", "--ai=hard", "--vs-ai=easy", "--arena=cave"])
