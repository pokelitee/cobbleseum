class_name CobblemonRoster
extends RefCounted
## Matches Showdown species to Cobblemon models and sizes them (concepts_brief.md §8).
##
## A roster entry is a Showdown species (identified by its Showdown ID, e.g. "ninetalesalola")
## that Cobblemon implements: the base species by normalised name, a form by its form name
## ("Alola") and aspects (["alolan"]). Battle-only forms (Mega, Gmax, Primal, ...) are left out.
## Forms Showdown doesn't list as separate species (East Sea Gastrodon, Vivillon's patterns,
## female models) don't change battle data, so they become cosmetic forms of an entry instead.

const SPECIES_DATA := "data/cobblemon/species"
## Height band in metres; models are scaled uniformly into it.
const MIN_HEIGHT := 0.5
const MAX_HEIGHT := 3.0
## Hitbox capsule radius bounds in metres.
const MIN_RADIUS := 0.25
const MAX_RADIUS := 1.5
## Flagged in the QA report when the model's height in its idle pose and its hitbox height
## differ by more than this factor (a mis-posed model, or one far bigger than its hitbox).
const POSE_MISMATCH := 2.0
## Cosmetic form ids for form names that normalise to nothing, as Showdown names them.
const SYMBOL_FORM_IDS := {"!": "exclamation", "?": "question"}
const FEMALE := "female"


## `pokedex`: Showdown ID -> species. `cobblemon`: Cobblemon species id -> species JSON.
## `folders`: Cobblemon species id -> model folder ("0038_ninetales"). Returns entries
## {"id", "name", "num", "folder", "aspects", "base_scale", "hitbox", "forms"}, sorted by dex
## number then ID. "hitbox" is Cobblemon's {"width", "height"} in blocks before base scale, or {}.
## "forms" are the entry's candidate cosmetic forms (cosmetic_forms()).
static func match_species(pokedex: Dictionary, cobblemon: Dictionary, folders: Dictionary) -> Array:
	var by_name := {}
	for cobblemon_id: String in cobblemon:
		var data: Dictionary = cobblemon[cobblemon_id]
		if data.get("implemented", false) and folders.has(cobblemon_id):
			by_name[BattleData.to_id(str(data.get("name", cobblemon_id)))] = cobblemon_id
	var entries: Array = []
	for id: String in pokedex:
		var dex: Dictionary = pokedex[id]
		if int(dex.get("num", 0)) <= 0:
			continue
		var cobblemon_id: Variant = by_name.get(BattleData.to_id(str(dex.get("baseSpecies", dex.get("name", "")))))
		if cobblemon_id == null:
			continue
		var data: Dictionary = cobblemon[cobblemon_id]
		var aspects: Array = []
		var base_scale := float(data.get("baseScale", 1.0))
		var hitbox: Dictionary = data.get("hitbox", {})
		var forme := BattleData.to_id(str(dex.get("forme", "")))
		if not forme.is_empty():
			var form := _form(data, forme)
			if form.is_empty():
				continue
			aspects = form.get("aspects", [])
			base_scale = float(form.get("baseScale", base_scale))
			hitbox = form.get("hitbox", hitbox)
		entries.append({"id": id, "name": dex.get("name", id), "num": int(dex.num),
			"folder": folders[cobblemon_id], "aspects": aspects, "base_scale": base_scale, "hitbox": hitbox,
			"forms": cosmetic_forms(id, pokedex, data, aspects)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.num < b.num if a.num != b.num else a.id < b.id)
	return entries


## The cosmetic forms the entry `id` (Cobblemon species `data`, drawn with `aspects`) may
## appear in: [{"id", "name", "aspects"}], plus "chance" for the female model. A base species
## gets each Cobblemon form that isn't battle-only and that Showdown lists as no species of its
## own, or only as a cosmetic forme. Any entry gets a female model when Showdown says the
## species can be female; "chance" is its share of females. Candidates only: a form whose
## files turn out the same as the entry's (a marker form such as "Alola-Bias") shows nothing new.
static func cosmetic_forms(id: String, pokedex: Dictionary, data: Dictionary, aspects: Array) -> Array:
	var dex: Dictionary = pokedex[id]
	var forms: Array = []
	if str(dex.get("forme", "")).is_empty():
		for form: Dictionary in data.get("forms", []):
			var form_aspects: Array = form.get("aspects", [])
			var shown_as := BattleData.to_id(str(dex.get("name", id)) + str(form.get("name", "")))
			var listed: Variant = pokedex.get(shown_as)
			if form.get("battleOnly", false) or form_aspects.is_empty():
				continue
			if listed is Dictionary and shown_as != id and not listed.get("isCosmeticForme", false):
				continue
			var name := str(form.get("name", ""))
			var form_id: String = SYMBOL_FORM_IDS.get(name, BattleData.to_id(name))
			if not form_id.is_empty() and form_id != FEMALE:
				forms.append({"id": form_id, "name": name, "aspects": aspects + form_aspects})
	var gender := str(dex.get("gender", ""))
	if gender != "M" and gender != "N":
		var chance := 1.0 if gender == "F" else float((dex.get("genderRatio", {}) as Dictionary).get("F", 0.5))
		forms.append({"id": FEMALE, "name": "Female", "aspects": aspects + [FEMALE], "chance": chance})
	return forms


## Scale, height and hitbox radius. Cobblemon draws a model at `base_scale` and gives it a
## curated gameplay hitbox ({"width", "height"} in blocks, i.e. metres, before base scale).
## Rest-pose bounds are unreliable for coiled or stretched-out models, so they're used only
## when there's no hitbox (radius from half the mean horizontal extent). Everything is then
## scaled uniformly so the height falls within [MIN_HEIGHT, MAX_HEIGHT].
static func size(hitbox: Dictionary, bounds: Vector3, base_scale: float) -> Dictionary:
	var natural_height := float(hitbox.get("height", bounds.y)) * base_scale
	var natural_width := float(hitbox.get("width", (bounds.x + bounds.z) * 0.5)) * base_scale
	if natural_height <= 0.0:
		return {"scale": base_scale, "height": MIN_HEIGHT, "radius": MIN_RADIUS}
	var height := clampf(natural_height, MIN_HEIGHT, MAX_HEIGHT)
	var factor := height / natural_height
	return {"scale": base_scale * factor, "height": height,
		"radius": clampf(natural_width * 0.5 * factor, MIN_RADIUS, MAX_RADIUS)}


## Cobblemon species JSON by id ("ninetales") from every generation folder.
static func load_cobblemon(source_root: String) -> Dictionary:
	var species := {}
	var root := source_root.path_join(SPECIES_DATA)
	for generation in DirAccess.get_directories_at(root):
		for file in DirAccess.get_files_at(root.path_join(generation)):
			if file.ends_with(".json"):
				var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join(generation).path_join(file)))
				if data is Dictionary:
					species[file.get_basename()] = data
	return species


## Model folder by Cobblemon species id, read from each resolver's "species" field.
static func load_folders(source_root: String) -> Dictionary:
	var folders := {}
	var resolvers := source_root.path_join(CobblemonSpecies.BEDROCK).path_join("resolvers")
	for folder in DirAccess.get_directories_at(resolvers):
		for file in DirAccess.get_files_at(resolvers.path_join(folder)):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(resolvers.path_join(folder).path_join(file)))
			if data is Dictionary and data.get("species") is String:
				folders[(data.species as String).get_slice(":", 1)] = folder
				break
	return folders


static func _form(data: Dictionary, forme: String) -> Dictionary:
	for form: Dictionary in data.get("forms", []):
		if BattleData.to_id(str(form.get("name", ""))) == forme and not form.get("battleOnly", false):
			return form
	return {}
