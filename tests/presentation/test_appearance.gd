extends TestCase
## How fighters look (Appearance, concepts_brief.md §12.8): shinies and cosmetic forms.

const ROSTER := {
	"gastrodon": {"name": "Gastrodon", "model": "gastrodon.scn", "shiny": "gastrodon~shiny.res", "forms": {
		"east": {"name": "East", "model": "gastrodon@east.scn", "shiny": "gastrodon@east~shiny.scn"},
		"female": {"name": "Female", "model": "gastrodon@female.scn", "chance": 0.25},
	}},
	"plain": {"name": "Plain", "model": "plain.scn", "shiny": "plain~shiny.res"},
	"dull": {"name": "Dull", "model": "dull.scn"},
}


func _spec(seed: int, a := "gastrodon", b := "plain") -> Dictionary:
	return {"seed": seed, "fighters": [{"species": a}, {"species": b}]}


## A seed whose roll makes side A shiny, found by searching.
func _shiny_seed(species: String) -> int:
	for seed in 100000:
		var spec := _spec(seed, species)
		Appearance.roll_missing(spec, ROSTER)
		if spec.fighters[0].shiny:
			return seed
	return -1


func test_rolls_repeat_for_a_seed_and_fill_only_what_is_missing() -> void:
	var first := _spec(5)
	var second := _spec(5)
	Appearance.roll_missing(first, ROSTER)
	Appearance.roll_missing(second, ROSTER)
	assert_eq(first, second)
	for fighter: Dictionary in first.fighters:
		assert_true(fighter.has("shiny") and fighter.has("form"), str(fighter))
	var set := {"seed": 5, "fighters": [{"species": "gastrodon", "shiny": true, "form": "east"}, {"species": "plain", "form": ""}]}
	Appearance.roll_missing(set, ROSTER)
	assert_eq(set.fighters[0], {"species": "gastrodon", "shiny": true, "form": "east"}, "a spec's own choices stay")
	assert_eq(set.fighters[1].form, "")
	assert_eq(set.fighters[1].shiny, first.fighters[1].shiny, "and only what's missing is rolled")


func test_one_sides_species_never_changes_the_others_roll() -> void:
	for seed in 50:
		var with_forms := _spec(seed, "gastrodon", "gastrodon")
		var without := _spec(seed, "dull", "gastrodon")
		Appearance.roll_missing(with_forms, ROSTER)
		Appearance.roll_missing(without, ROSTER)
		assert_eq(with_forms.fighters[1], without.fighters[1], "seed %d" % seed)


func test_forms_are_as_likely_as_the_own_look_and_females_follow_their_chance() -> void:
	var counts := {"": 0, "east": 0, "female": 0}
	var tries := 3000
	for seed in tries:
		var spec := _spec(seed)
		Appearance.roll_missing(spec, ROSTER)
		counts[spec.fighters[0].form] += 1
	assert_almost_eq(counts.east / float(tries), 0.5, 0.04, "east and the own look are even")
	assert_almost_eq(counts.female / float(tries), 0.5 * 0.25, 0.03, "the own look is female at its chance")
	assert_almost_eq(counts[""] / float(tries), 0.5 * 0.75, 0.04)


func test_shinies_are_rare_and_only_for_looks_that_have_one() -> void:
	var shinies := 0
	var tries := 40000
	for seed in tries:
		var spec := _spec(seed, "plain")
		Appearance.roll_missing(spec, ROSTER)
		shinies += int(spec.fighters[0].shiny)
	assert_true(shinies > 0 and shinies < 30, "about one in 4096: %d in %d" % [shinies, tries])
	var seed := _shiny_seed("plain")
	assert_true(seed >= 0)
	var dull := _spec(seed, "dull")
	Appearance.roll_missing(dull, ROSTER)
	assert_false(dull.fighters[0].shiny, "a species without shiny colours isn't rolled shiny")


func test_unknown_forms_are_errors() -> void:
	assert_eq(Appearance.check({"fighters": [{"species": "gastrodon", "form": "east"}, {"species": "plain"}]}, ROSTER), "")
	var problem := Appearance.check({"fighters": [{"species": "gastrodon", "form": "west"}, {"species": "plain"}]}, ROSTER)
	assert_true(problem.contains("west") and problem.contains("east, female"), problem)
	assert_true(Appearance.check({"fighters": [{"species": "plain", "form": "east"}]}, ROSTER).contains("it has none"))


func test_resolves_models_skins_and_fallbacks() -> void:
	assert_eq(Appearance.resolve(ROSTER.gastrodon, {"species": "gastrodon"}),
		{"model": "gastrodon.scn", "skin": "", "shiny": false, "warning": ""}, "a spec without looks shows the species as before")
	assert_eq(Appearance.resolve(ROSTER.gastrodon, {"species": "gastrodon", "shiny": true}),
		{"model": "gastrodon.scn", "skin": "gastrodon~shiny.res", "shiny": true, "warning": ""}, "a shiny skin")
	assert_eq(Appearance.resolve(ROSTER.gastrodon, {"species": "gastrodon", "shiny": true, "form": "east"}),
		{"model": "gastrodon@east~shiny.scn", "skin": "", "shiny": true, "warning": ""}, "a shiny scene of its own")
	var female := Appearance.resolve(ROSTER.gastrodon, {"species": "gastrodon", "shiny": true, "form": "female"})
	assert_eq([female.model, female.skin, female.shiny], ["gastrodon@female.scn", "", false], "no shiny: normal colours")
	assert_true(female.warning.contains("no shiny"), female.warning)


func test_files_missing_from_the_cache_fall_back_to_the_own_look() -> void:
	var dir := TestFiles.fresh_dir("variants_models")
	TestFiles.write_text(dir.path_join("gastrodon.scn"), "")
	var shown := Appearance.resolve(ROSTER.gastrodon, {"species": "gastrodon", "shiny": true, "form": "east"}, dir)
	assert_eq([shown.model, shown.skin, shown.shiny], ["gastrodon.scn", "", false])
	assert_false(shown.warning.is_empty())
