extends TestCase
## Trainers (concepts_brief.md §12.7, M15): named by the spec or flags, rolled from the seed for
## team battles, drawn from the cache only, and never read by the simulation.


func test_team_battles_get_a_generic_trainer_from_the_seed() -> void:
	var spec := SpecFlags.to_spec({"watch": "", "team": "pikachu,charizard", "vs": "garchomp", "seed": "5"})
	Appearance.roll_missing(spec, {})
	assert_true(spec.fighters[0].trainer in TrainerView.GENERIC)
	assert_false(spec.fighters[1].has("trainer"), "a side of one gets none")
	var again := SpecFlags.to_spec({"watch": "", "team": "pikachu,charizard", "vs": "garchomp", "seed": "5"})
	Appearance.roll_missing(again, {})
	assert_eq(again.fighters[0].trainer, spec.fighters[0].trainer, "the same seed, the same trainer")


func test_flags_name_trainers_and_round_trip() -> void:
	var spec := SpecFlags.to_spec({"watch": "pikachu", "trainer": "Ash", "vs-trainer": "none", "seed": "1"})
	assert_eq(spec.fighters[0].trainer, "ash")
	assert_eq(Appearance.trainer_of(spec.fighters[1]), "", "none")
	assert_eq(SpecFlags.to_spec(SpecFlags.parse(SpecFlags.from_spec(spec)).flags), spec)
	var problem := Cli.check_spec({"fighters": [{"species": "x", "trainer": "ahs"}, {"species": "x"}]}, BattleData.new({}, {}, {}))
	assert_true(problem.contains("unknown trainer 'ahs'") and problem.contains("ash"), problem)


func test_every_trainer_is_pinned_in_the_sources() -> void:
	var sources: Dictionary = AssetPipeline.load_manifest("res://sources.json").sources
	for id in TrainerView.ALL:
		assert_true(sources.has("trainer_" + id), id)
	for id in TrainerView.GENERIC:
		assert_true(id in TrainerView.ALL, id)


func test_a_trainer_missing_from_the_cache_is_not_drawn() -> void:
	assert_eq(TrainerView.create("nobody-at-all"), null)


func test_the_credits_name_the_trainer_sprites_only_with_trainers() -> void:
	var script: GDScript = load("res://tools/record.gd")
	assert_false(script.credits(false, false).contains(Hud.TRAINER_CREDIT))
	assert_true(script.credits(false, true).contains(Hud.TRAINER_CREDIT))
