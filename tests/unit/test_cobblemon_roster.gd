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
	assert_eq(BattleData.to_id("Mr. Mime"), "mrmime")
	assert_eq(BattleData.to_id("Paldea-Combat"), "paldeacombat")


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
			"texture": "cobblemon:textures/pokemon/0038_ninetales/ninetales_alolan.png",
			"layers": [{"name": "glow", "emissive": true, "texture": "cobblemon:textures/pokemon/0038_ninetales/glow.png"}]}]}))
	for model in ["ninetales.geo.json", "ninetales_alolan.geo.json"]:
		TestFiles.write_text(bedrock.path_join("models/0038_ninetales").path_join(model), "{}")
	var base := CobblemonSpecies.files(root, "0038_ninetales")
	assert_eq(base.geo.get_file(), "ninetales.geo.json")
	assert_eq(base.texture.get_file(), "ninetales.png", "shiny variations don't apply")
	var alola := CobblemonSpecies.files(root, "0038_ninetales", ["alolan"])
	assert_eq(alola.geo.get_file(), "ninetales_alolan.geo.json")
	assert_eq(alola.texture.get_file(), "ninetales_alolan.png")
	assert_eq(alola.poser, "ninetales", "fields the form doesn't set come from the base")
	assert_eq(alola.layers.size(), 1)
	assert_true(alola.layers[0].emissive and alola.layers[0].texture.ends_with("glow.png"), str(alola.layers))
	assert_eq(base.layers, [], "the base variation has none")
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


func test_layer_emissive_flag_may_be_a_string() -> void:
	var root := TestFiles.fresh_dir("cobblemon_layers")
	var bedrock := root.path_join(CobblemonSpecies.BEDROCK)
	TestFiles.write_text(bedrock.path_join("resolvers/0001_mon/0_mon_base.json"), JSON.stringify({"order": 0,
		"variations": [{"aspects": [], "model": "cobblemon:mon.geo", "texture": "cobblemon:textures/pokemon/mon.png",
			"layers": [{"name": "glow", "emissive": "true", "texture": "cobblemon:textures/pokemon/glow.png"},
				{"name": "wings", "texture": "cobblemon:textures/pokemon/wings.png"}]}]}))
	TestFiles.write_text(bedrock.path_join("models/0001_mon/mon.geo.json"), "{}")
	var files := CobblemonSpecies.files(root, "0001_mon")
	assert_eq(files.layers.map(func(l: Dictionary) -> bool: return l.emissive), [true, false])


func test_cosmetic_forms_are_those_showdown_lists_as_no_species_of_their_own() -> void:
	var pokedex := {
		"gastrodon": {"num": 423, "name": "Gastrodon"},
		"gastrodoneast": {"name": "Gastrodon-East", "baseSpecies": "Gastrodon", "forme": "East", "isCosmeticForme": true},
		"minior": {"num": 774, "name": "Minior", "gender": "N"},
		"miniormeteor": {"num": 774, "name": "Minior-Meteor", "baseSpecies": "Minior", "forme": "Meteor"},
		"unown": {"num": 201, "name": "Unown", "gender": "N"},
	}
	var gastrodon := CobblemonRoster.cosmetic_forms("gastrodon", pokedex,
		{"forms": [{"name": "East", "aspects": ["east-sea"]}, {"name": "Gmax", "aspects": ["gmax"], "battleOnly": true}]}, [])
	assert_eq(gastrodon, [{"id": "east", "name": "East", "aspects": ["east-sea"]},
		{"id": "female", "name": "Female", "aspects": ["female"], "chance": 0.5}],
		"a cosmetic forme, but no battle-only form; either gender by default")
	var minior := CobblemonRoster.cosmetic_forms("minior", pokedex,
		{"forms": [{"name": "Meteor", "aspects": ["meteor-form"]}, {"name": "Blue", "aspects": ["blue-core"]}]}, [])
	assert_eq(minior.map(func(f: Dictionary) -> String: return f.id), ["blue"],
		"a form Showdown lists as a species of its own isn't cosmetic; a genderless species has no female")
	var unown := CobblemonRoster.cosmetic_forms("unown", pokedex, {"forms": [{"name": "!", "aspects": ["character-!"]}]}, [])
	assert_eq(unown.map(func(f: Dictionary) -> String: return f.id), ["exclamation"], "named as Showdown names it")


func test_female_models_follow_showdowns_gender_ratio() -> void:
	var pokedex := {
		"ninetales": {"num": 38, "name": "Ninetales", "genderRatio": {"M": 0.25, "F": 0.75}},
		"ninetalesalola": {"num": 38, "name": "Ninetales-Alola", "baseSpecies": "Ninetales", "forme": "Alola",
			"genderRatio": {"M": 0.25, "F": 0.75}},
		"indeedee": {"num": 876, "name": "Indeedee", "gender": "M"},
		"salazzle": {"num": 758, "name": "Salazzle", "gender": "F"},
	}
	var data := {"forms": [{"name": "Alola", "aspects": ["alolan"]}]}
	assert_eq(CobblemonRoster.cosmetic_forms("ninetalesalola", pokedex, data, ["alolan"]),
		[{"id": "female", "name": "Female", "aspects": ["alolan", "female"], "chance": 0.75}],
		"a form gets only the female model, on its own aspects")
	assert_eq(CobblemonRoster.cosmetic_forms("ninetales", pokedex, data, []).map(func(f: Dictionary) -> String: return f.id),
		["female"], "a form that is a species of its own isn't cosmetic")
	assert_eq(CobblemonRoster.cosmetic_forms("indeedee", pokedex, {}, []), [], "an all-male species")
	assert_eq(CobblemonRoster.cosmetic_forms("salazzle", pokedex, {}, [])[0].chance, 1.0, "an all-female species")


## A fixture species, "0001_mon": its own look, a shiny that only changes the texture, an
## "east-sea" form whose shiny has a model of its own, and a "west" form whose shiny texture
## is missing.
func _variant_fixture() -> String:
	var root := TestFiles.fresh_dir("cobblemon_looks")
	var bedrock := root.path_join(CobblemonSpecies.BEDROCK)
	var textures := "cobblemon:textures/pokemon/0001_mon/"
	TestFiles.write_text(bedrock.path_join("resolvers/0001_mon/0_mon_base.json"), JSON.stringify({"order": 0, "variations": [
		{"aspects": [], "model": "cobblemon:mon.geo", "texture": textures + "mon.png",
			"layers": [{"name": "glow", "emissive": true, "texture": textures + "glow.png"}]},
		{"aspects": ["shiny"], "texture": textures + "mon_shiny.png"},
		{"aspects": ["east-sea"], "texture": textures + "mon_east.png"},
		{"aspects": ["east-sea", "shiny"], "model": "cobblemon:mon_east_shiny.geo", "texture": textures + "mon_east_shiny.png"},
		{"aspects": ["west"], "texture": textures + "mon_west.png"},
		{"aspects": ["west", "shiny"], "texture": textures + "mon_west_shiny.png"},
	]}))
	var geo := {"format_version": "1.12.0", "minecraft:geometry": [{
		"description": {"identifier": "geometry.mon", "texture_width": 16, "texture_height": 16},
		"bones": [{"name": "body", "pivot": [0, 0, 0], "cubes": [{"origin": [-2, 0, -2], "size": [4, 4, 4], "uv": [0, 0]}]}]}]}
	for model in ["mon.geo.json", "mon_east_shiny.geo.json"]:
		TestFiles.write_text(bedrock.path_join("models/0001_mon").path_join(model), JSON.stringify(geo))
	var texture_dir := root.path_join("assets/cobblemon/textures/pokemon/0001_mon")
	DirAccess.make_dir_recursive_absolute(texture_dir)
	for texture in ["mon", "glow", "mon_shiny", "mon_east", "mon_east_shiny", "mon_west"]:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color(texture.length() / 20.0, 0.5, 0.5))
		image.save_png(texture_dir.path_join(texture + ".png"))
	return root


func test_each_look_gets_its_shiny_as_a_skin_or_a_scene_of_its_own() -> void:
	var build: GDScript = load("res://tools/sources/cobblemon.gd")
	var root := _variant_fixture()
	var models := TestFiles.fresh_dir("cobblemon_looks_out")
	var base: Dictionary = build._look("mon", root, "0001_mon", [], "key", models, "")
	assert_false(base.has("error"), str(base.get("error", "")))
	assert_eq(base.model, "mon.scn")
	assert_eq(base.shiny, "mon~shiny.res", "a shiny that only changes textures is a skin")
	assert_eq(base.converted, 2)
	var skin: StandardMaterial3D = load(models.path_join("mon~shiny.res"))
	assert_true(skin.albedo_texture != null, "the skin carries the shiny texture")
	assert_true(skin.next_pass is StandardMaterial3D, "and the look's layers")
	var east: Dictionary = build._look("mon@east", root, "0001_mon", ["east-sea"], "key", models, "")
	assert_eq(east.shiny, "mon@east~shiny.scn", "a shiny with its own model is a scene of its own")
	assert_true(FileAccess.file_exists(models.path_join("mon@east~shiny.scn")))
	var west: Dictionary = build._look("mon@west", root, "0001_mon", ["west"], "key", models, "")
	assert_eq(west.shiny, "", "a missing shiny texture leaves the look without a shiny")
	assert_true(str(west.shiny_error).contains("missing"), str(west.get("shiny_error")))
	assert_eq(build._look("mon", root, "0001_mon", [], "key", models, "").converted, 0, "unchanged looks are reused")
	assert_eq(build._look("mon", root, "0001_mon", [], "changed", models, "").converted, 2, "until the converter changes")
	var keep := {}
	for look: Dictionary in [base, east, west]:
		keep.merge(look.written)
	TestFiles.write_text(models.path_join("gone@old.scn"), "stale")
	build._prune(models, keep)
	assert_false(FileAccess.file_exists(models.path_join("gone@old.scn")), "files of forms no longer there are removed")
	assert_true(FileAccess.file_exists(models.path_join("mon@east~shiny.json")), "kept files stay")


func test_looks_compare_by_what_they_draw() -> void:
	var build: GDScript = load("res://tools/sources/cobblemon.gd")
	var root := _variant_fixture()
	var base := CobblemonSpecies.files(root, "0001_mon")
	assert_true(build.same_look(base, CobblemonSpecies.files(root, "0001_mon", ["region-bias-alola"])),
		"a marker form that changes nothing draws the same")
	assert_false(build.same_look(base, CobblemonSpecies.files(root, "0001_mon", ["east-sea"])))
