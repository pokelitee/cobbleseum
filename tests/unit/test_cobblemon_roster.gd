extends TestCase
## Small inline data shaped like Showdown's pokedex and Cobblemon's species files.

const POKEDEX := {
	"ninetales": {"num": 38, "name": "Ninetales", "heightm": 1.1},
	"ninetalesalola": {"num": 38, "name": "Ninetales-Alola", "baseSpecies": "Ninetales", "forme": "Alola"},
	"charizardmegax": {"num": 6, "name": "Charizard-Mega-X", "baseSpecies": "Charizard", "forme": "Mega-X"},
	"charizard": {"num": 6, "name": "Charizard"},
	"mrmime": {"num": 122, "name": "Mr. Mime"},
	"missingno": {"num": 0, "name": "MissingNo."},
	"pecharunt": {"num": 1025, "name": "Pecharunt"},
}
const COBBLEMON := {
	"ninetales": {"name": "Ninetales", "implemented": true, "baseScale": 0.7, "hitbox": {"width": 1, "height": 2},
		"forms": [{"name": "Alola", "aspects": ["alolan"], "baseScale": 0.65, "hitbox": {"width": 1.2, "height": 2}}]},
	"charizard": {"name": "Charizard", "implemented": true, "baseScale": 1.0,
		"forms": [{"name": "Mega-X", "aspects": ["mega_x"], "battleOnly": true}]},
	"mrmime": {"name": "Mr. Mime", "implemented": true},
	"pecharunt": {"name": "Pecharunt"},
}
const FOLDERS := {"ninetales": "0038_ninetales", "charizard": "0006_charizard", "mrmime": "0122_mrmime", "pecharunt": "1025_pecharunt"}


func test_matches_species_and_forms() -> void:
	var entries := CobblemonRoster.match_species(POKEDEX, COBBLEMON, FOLDERS)
	assert_eq(entries.map(func(e: Dictionary) -> String: return e.id), ["charizard", "ninetales", "ninetalesalola", "mrmime"],
		"sorted by dex number; no battle-only forms, unimplemented species or dex 0")
	var alola: Dictionary = entries[2]
	assert_eq(alola.folder, "0038_ninetales")
	assert_eq(alola.aspects, ["alolan"])
	assert_eq(alola.base_scale, 0.65, "a form's own base scale wins")
	assert_eq(alola.hitbox.width, 1.2, "and its own hitbox")
	assert_eq(entries[1].aspects, [])
	assert_eq(entries[1].base_scale, 0.7)
	assert_eq(entries[1].hitbox.width, 1)
	assert_eq(entries[0].hitbox, {})


func test_normalise_drops_punctuation() -> void:
	assert_eq(CobblemonRoster.normalise("Mr. Mime"), "mrmime")
	assert_eq(CobblemonRoster.normalise("Paldea-Combat"), "paldeacombat")


func test_size_uses_the_hitbox_scaled_into_the_height_band() -> void:
	var stretched := Vector3(1.0, 12.0, 1.0)  # a rest pose that says nothing about real size
	var normal := CobblemonRoster.size({"width": 1.0, "height": 2.0}, stretched, 0.75)
	assert_almost_eq(normal.height, 1.5, 1e-6)
	assert_almost_eq(normal.scale, 0.75, 1e-6)
	assert_almost_eq(normal.radius, 0.375, 1e-6, "half the hitbox width, scaled")
	var giant := CobblemonRoster.size({"width": 3.0, "height": 8.0}, stretched, 1.0)
	assert_almost_eq(giant.height, CobblemonRoster.MAX_HEIGHT, 1e-6)
	assert_almost_eq(giant.scale, CobblemonRoster.MAX_HEIGHT / 8.0, 1e-6)
	assert_almost_eq(giant.radius, 1.5 * CobblemonRoster.MAX_HEIGHT / 8.0, 1e-6, "shrinks with the model")
	var tiny := CobblemonRoster.size({"width": 0.2, "height": 0.2}, stretched, 1.0)
	assert_almost_eq(tiny.height, CobblemonRoster.MIN_HEIGHT, 1e-6)
	assert_almost_eq(tiny.radius, CobblemonRoster.MIN_RADIUS, 1e-6)


func test_size_falls_back_to_model_bounds_without_a_hitbox() -> void:
	var sized := CobblemonRoster.size({}, Vector3(2.0, 2.0, 2.0), 0.5)
	assert_almost_eq(sized.height, 1.0, 1e-6)
	assert_almost_eq(sized.radius, 0.5, 1e-6, "half the mean horizontal extent, scaled")


func test_form_files_layer_over_the_base_variation() -> void:
	var root := TestFiles.fresh_dir("cobblemon_species")
	var bedrock := root.path_join(CobblemonSpecies.BEDROCK)
	TestFiles.write_text(bedrock.path_join("resolvers/0038_ninetales/0_ninetales_base.json"), JSON.stringify({"order": 0,
		"variations": [{"aspects": [], "model": "cobblemon:ninetales.geo", "poser": "cobblemon:ninetales",
			"texture": "cobblemon:textures/pokemon/0038_ninetales/ninetales.png"},
			{"aspects": ["shiny"], "texture": "cobblemon:textures/pokemon/0038_ninetales/ninetales_shiny.png"}]}))
	TestFiles.write_text(bedrock.path_join("resolvers/0038_ninetales/1_ninetales_alolan.json"), JSON.stringify({"order": 1,
		"variations": [{"aspects": ["alolan"], "model": "cobblemon:ninetales_alolan.geo",
			"texture": "cobblemon:textures/pokemon/0038_ninetales/ninetales_alolan.png"}]}))
	for model in ["ninetales.geo.json", "ninetales_alolan.geo.json"]:
		TestFiles.write_text(bedrock.path_join("models/0038_ninetales").path_join(model), "{}")
	var base := CobblemonSpecies.files(root, "0038_ninetales")
	assert_eq(base.geo.get_file(), "ninetales.geo.json")
	assert_eq(base.texture.get_file(), "ninetales.png", "shiny variations don't apply")
	var alola := CobblemonSpecies.files(root, "0038_ninetales", ["alolan"])
	assert_eq(alola.geo.get_file(), "ninetales_alolan.geo.json")
	assert_eq(alola.texture.get_file(), "ninetales_alolan.png")
	assert_eq(alola.poser, "ninetales", "fields the form doesn't set come from the base")
	assert_true(CobblemonSpecies.files(root, "0038_ninetales", ["galarian"]).geo.ends_with("ninetales.geo.json"),
		"unknown aspects fall back to the base")


func test_cached_models_are_reused_only_with_a_matching_key() -> void:
	var build: GDScript = load("res://tools/sources/cobblemon.gd")
	var dir := TestFiles.fresh_dir("cobblemon_cache")
	var models := dir.path_join("staging/models")
	var previous := dir.path_join("previous/models")
	TestFiles.write_text(previous.path_join("blastoise.scn"), "scene")
	TestFiles.write_text(previous.path_join("blastoise.json"), JSON.stringify({"key": "abc", "report": {}}))
	DirAccess.make_dir_recursive_absolute(models)
	assert_eq(build._cached("blastoise", "changed", models, previous), {}, "a different key means converting again")
	assert_eq(build._cached("blastoise", "abc", models, previous).key, "abc")
	assert_true(FileAccess.file_exists(models.path_join("blastoise.scn")), "the reused model moves into the new build")
	assert_eq(build._cached("blastoise", "abc", models, previous).key, "abc", "found again in staging, e.g. after an interrupted build")
