class_name CobblemonRoster
extends RefCounted
## Matches Showdown species to Cobblemon models and sizes them (concepts_brief.md §8).
##
## A roster entry is a Showdown species (identified by its Showdown ID, e.g. "ninetalesalola")
## that Cobblemon implements: the base species by normalised name, a form by its form name
## ("Alola") and aspects (["alolan"]). Battle-only forms (Mega, Gmax, Primal, ...) and forms
## Showdown doesn't list as separate species (cosmetic ones) are left out.

const SPECIES_DATA := "data/cobblemon/species"
## Height band in metres; models are scaled uniformly into it.
const MIN_HEIGHT := 0.5
const MAX_HEIGHT := 3.0
## Hitbox capsule radius bounds in metres.
const MIN_RADIUS := 0.25
const MAX_RADIUS := 1.5
## Flagged in the QA report when the model's rest-pose height and its hitbox height differ
## by more than this factor (stretched-out rest poses, stray bones).
const BOUNDS_MISMATCH := 2.0


## `pokedex`: Showdown ID -> species. `cobblemon`: Cobblemon species id -> species JSON.
## `folders`: Cobblemon species id -> model folder ("0038_ninetales"). Returns entries
## {"id", "name", "num", "folder", "aspects", "base_scale", "hitbox"}, sorted by dex number
## then ID. "hitbox" is Cobblemon's {"width", "height"} in blocks before base scale, or {}.
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
			"folder": folders[cobblemon_id], "aspects": aspects, "base_scale": base_scale, "hitbox": hitbox})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.num < b.num if a.num != b.num else a.id < b.id)
	return entries


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
